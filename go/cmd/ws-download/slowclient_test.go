package main

// Slow-client backpressure simulation.
//
// Hypothesis under test (from the 2026-09-24 download stall): the Perl
// service's Shock streaming path has no backpressure. on_body does
//
//     $writer->write($data); return 1;
//
// and Twiggy::Writer::write is just push_write, which appends to an unbounded
// AnyEvent::Handle wbuf. Returning 1 tells AnyEvent::HTTP to keep reading. So
// when a client drains slowly, the loop keeps pulling from Shock at full speed
// and buffers the difference in memory, while every push_write drives a
// syswrite and an O(n) string concat on a growing buffer -- per-chunk work on
// the single shared event loop that scales with how far behind the client is.
//
// Corroborating evidence: ganglia for spruce (the host running the download
// service behind nginx) shows the machine essentially IDLE during the stalls
// -- CPU user avg 6.96%, wio avg 0.19%. A blocked event loop burns no CPU. That
// is consistent with blocking on socket writes and inconsistent with the
// process being busy serializing Dumper output.
//
// These tests are run against a HARNESS, not production. They compare two
// server implementations under identical slow-client load:
//
//   - unbounded: mimics the Perl shape. A producer goroutine pushes into an
//     unbounded buffer as fast as the upstream allows; a single shared
//     "event loop" goroutine drains that buffer to clients.
//   - backpressured: what Go's io.Copy does naturally. The write blocks the
//     per-request goroutine when the client is slow, so the upstream read
//     paces itself and no unbounded buffer forms.
//
// Run:  go test -v -run TestSlowClient ./cmd/ws-download/
//
// These are simulations of an architecture, not of Twiggy's exact internals.
// They demonstrate the mechanism and its magnitude; they do not prove this was
// the trigger on 2026-09-24.

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// slowReader stands in for Shock: an upstream that can deliver quickly.
type fastUpstream struct {
	remaining int
	chunk     []byte
}

func (f *fastUpstream) Read(p []byte) (int, error) {
	if f.remaining <= 0 {
		return 0, io.EOF
	}
	n := copy(p, f.chunk)
	if n > f.remaining {
		n = f.remaining
	}
	f.remaining -= n
	return n, nil
}

// singleLoopServer models the Perl/Twiggy shape: ONE goroutine serves every
// connection, and writes go through an unbounded per-connection buffer that
// the same goroutine must drain. Upstream reads are never paced.
type singleLoopServer struct {
	mu       sync.Mutex
	queues   map[int][]byte // per-client pending bytes (the unbounded wbuf)
	peakLive int64
	peakBuf  int64
}

// TestSlowClientBackpressure is the core comparison. N clients each read at a
// throttled rate while the server streams a large body to each. With
// backpressure the server's memory stays flat and fast clients are unaffected;
// without it, buffered bytes grow without bound.
func TestSlowClientBackpressure(t *testing.T) {
	if testing.Short() {
		t.Skip("slow-client simulation takes ~15s")
	}

	const (
		bodySize   = 8 << 20 // 8 MB per response
		nSlow      = 8
		clientRate = 256 << 10 // 256 KB/s per slow client
	)

	t.Run("with backpressure (Go io.Copy)", func(t *testing.T) {
		var inFlight, peak int64

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// io.Copy blocks this goroutine when the client is slow, which
			// paces the upstream read. Nothing accumulates.
			up := &fastUpstream{remaining: bodySize, chunk: make([]byte, 32<<10)}
			cur := atomic.AddInt64(&inFlight, 1)
			for {
				p := atomic.LoadInt64(&peak)
				if cur <= p || atomic.CompareAndSwapInt64(&peak, p, cur) {
					break
				}
			}
			defer atomic.AddInt64(&inFlight, -1)
			_, _ = io.Copy(w, up)
		}))
		defer srv.Close()

		elapsed, probeLatency := runSlowClients(t, srv.URL, nSlow, clientRate, bodySize)
		t.Logf("  backpressured: %d slow clients, wall=%v, concurrent probe latency=%v",
			nSlow, elapsed.Round(time.Millisecond), probeLatency.Round(time.Millisecond))

		// The point: a fast probe issued while slow clients are streaming must
		// still be served promptly.
		if probeLatency > 2*time.Second {
			t.Errorf("probe latency %v: a fast client should not be delayed by slow ones", probeLatency)
		}
	})

	t.Run("without backpressure (unbounded buffer)", func(t *testing.T) {
		var buffered, peakBuf int64

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Mimic push_write: pull from upstream as fast as possible into a
			// buffer, regardless of how fast the client drains.
			up := &fastUpstream{remaining: bodySize, chunk: make([]byte, 32<<10)}
			var pending []byte
			buf := make([]byte, 32<<10)
			for {
				n, err := up.Read(buf)
				if n > 0 {
					pending = append(pending, buf[:n]...)
					cur := atomic.AddInt64(&buffered, int64(n))
					for {
						p := atomic.LoadInt64(&peakBuf)
						if cur <= p || atomic.CompareAndSwapInt64(&peakBuf, p, cur) {
							break
						}
					}
				}
				if err == io.EOF {
					break
				}
			}
			// Only now hand it to the (slow) client.
			_, _ = w.Write(pending)
			atomic.AddInt64(&buffered, -int64(len(pending)))
		}))
		defer srv.Close()

		elapsed, probeLatency := runSlowClients(t, srv.URL, nSlow, clientRate, bodySize)
		peak := atomic.LoadInt64(&peakBuf)
		t.Logf("  unbounded:     %d slow clients, wall=%v, concurrent probe latency=%v, peak buffered=%.1f MB",
			nSlow, elapsed.Round(time.Millisecond), probeLatency.Round(time.Millisecond),
			float64(peak)/(1<<20))

		// Every byte of every response is held in memory at once.
		wantAtLeast := int64(nSlow) * bodySize / 2
		if peak < wantAtLeast {
			t.Errorf("peak buffered %.1f MB, expected at least %.1f MB with no backpressure",
				float64(peak)/(1<<20), float64(wantAtLeast)/(1<<20))
		}

		// Honest scoping of what this sub-test does and does not show.
		//
		// Latency stays low here because Go still runs each request on its own
		// goroutine -- only the BUFFERING is unbounded, not the scheduling. So
		// this isolates the memory cost of missing backpressure.
		//
		// The latency half of the production failure requires the other
		// ingredient, a single shared serving loop, which is what
		// TestSlowClientStalledLoop demonstrates. The Perl service has BOTH:
		// unbounded push_write buffers AND one Twiggy event loop. This test
		// pair separates the two effects so neither is overclaimed.
		t.Logf("  note: latency stayed low because each request still had its own goroutine;")
		t.Logf("        this sub-test isolates the MEMORY cost. See TestSlowClientStalledLoop")
		t.Logf("        for the latency effect of a shared loop.")
	})
}

// runSlowClients starts n clients that read at rateBytesPerSec, and midway
// through fires a single fast probe to measure whether it is delayed.
func runSlowClients(t *testing.T, url string, n int, rateBytesPerSec, bodySize int) (time.Duration, time.Duration) {
	t.Helper()

	start := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			resp, err := http.Get(url)
			if err != nil {
				return
			}
			defer resp.Body.Close()
			throttledDrain(resp.Body, rateBytesPerSec)
		}()
	}

	// Let the slow clients establish and start backing up.
	time.Sleep(1500 * time.Millisecond)

	probeStart := time.Now()
	func() {
		resp, err := http.Get(url)
		if err != nil {
			return
		}
		defer resp.Body.Close()
		// Read only the first chunk: we care about time-to-service, not
		// time-to-complete.
		b := make([]byte, 32<<10)
		_, _ = resp.Body.Read(b)
	}()
	probeLatency := time.Since(probeStart)

	wg.Wait()
	return time.Since(start), probeLatency
}

// throttledDrain reads at approximately rate bytes/sec.
func throttledDrain(r io.Reader, rate int) {
	const slice = 16 << 10
	buf := make([]byte, slice)
	interval := time.Duration(float64(slice) / float64(rate) * float64(time.Second))
	for {
		n, err := r.Read(buf)
		if n > 0 {
			time.Sleep(interval)
		}
		if err != nil {
			return
		}
	}
}

// TestSlowClientStalledLoop demonstrates the specific failure observed in
// production: a single shared serving goroutine means one slow client's write
// blocks every other request, including ones that touch nothing slow.
//
// This is the closest analogue to the Twiggy behaviour -- and to the probe
// that stalled ~10s while doing nothing but an indexed Mongo lookup.
func TestSlowClientStalledLoop(t *testing.T) {
	if testing.Short() {
		t.Skip("takes ~6s")
	}

	// A listener whose accept loop serves connections one at a time, like a
	// single-threaded event loop that blocks inside a write.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			// SERIALIZED: this connection is fully handled before the next is
			// looked at. No goroutine per connection.
			func() {
				defer c.Close()
				b := make([]byte, 1024)
				_, _ = c.Read(b)
				hdr := "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n"
				_, _ = c.Write([]byte(hdr))
				// Write more than the socket buffer so a non-draining client
				// blocks this write, and therefore the whole accept loop.
				payload := make([]byte, 4<<20)
				_, _ = c.Write(payload)
			}()
		}
	}()

	addr := ln.Addr().String()

	// Client 1: connects, requests, then stops reading entirely.
	stuck, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer stuck.Close()
	fmt.Fprintf(stuck, "GET /big HTTP/1.1\r\nHost: x\r\n\r\n")
	time.Sleep(500 * time.Millisecond) // let the server block writing to it

	// Client 2: a trivial request that should be instant.
	probeStart := time.Now()
	probe, err := net.DialTimeout("tcp", addr, 3*time.Second)
	if err != nil {
		t.Fatalf("probe could not even connect: %v", err)
	}
	defer probe.Close()
	fmt.Fprintf(probe, "GET /tiny HTTP/1.1\r\nHost: x\r\n\r\n")
	_ = probe.SetReadDeadline(time.Now().Add(5 * time.Second))
	b := make([]byte, 64)
	_, readErr := probe.Read(b)
	probeLatency := time.Since(probeStart)

	t.Logf("  serialized loop + one non-draining client: probe latency=%v err=%v",
		probeLatency.Round(time.Millisecond), readErr)

	if readErr == nil && probeLatency < 400*time.Millisecond {
		t.Errorf("expected the probe to be blocked behind the stuck client; got %v", probeLatency)
	} else {
		t.Logf("  CONFIRMED: one non-draining client stalls an unrelated request on a shared loop.")
		t.Logf("  This is the production signature: a probe doing only an indexed Mongo")
		t.Logf("  lookup stalled ~10s because the loop was blocked elsewhere.")
	}
}
