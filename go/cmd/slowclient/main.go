// Command slowclient reproduces the download-service stall by holding open a
// set of deliberately slow downloads while probing the service with cheap
// requests.
//
// Background. On 2026-09-24 the Perl WorkspaceDownload service was stalled
// ~91-93% of wall-clock time in ~9s blocks. Shock's own log shows it answered
// in <1s at p99 and was never even asked during the gaps, and ganglia shows the
// host (spruce, behind nginx) essentially idle -- CPU user ~7%, wio ~0.19%. So
// the process was blocked, not busy, and not waiting on the upstream.
//
// The leading explanation is missing backpressure on a single-threaded loop.
// The Shock streaming callback does:
//
//	on_body => sub { $writer->write($data); return 1; }
//
// Twiggy::Writer::write is push_write, which appends to an unbounded
// AnyEvent::Handle wbuf; returning 1 tells AnyEvent::HTTP to keep reading. A
// client that drains slowly therefore makes the loop buffer without limit and
// spend its time in syswrite and O(n) buffer concatenation -- per-chunk work
// that blocks every other request on the shared loop.
//
// This tool tests that against a live service:
//
//	slowclient --url <download-url> --clients 8 --rate 32768 \
//	           --probe https://host/services/WorkspaceDownload/download/BOGUS/x
//
// It starts -n clients that each read at -rate bytes/sec, and meanwhile issues
// a cheap probe every second, reporting the probe's latency distribution. If
// the hypothesis holds, probe latency climbs sharply once the slow clients are
// established and recovers when they finish.
//
// SAFETY. This applies deliberate load to a shared service. Run it against a
// test deployment, or against production only during a window where a few
// seconds of added download latency is acceptable. Start with -n 2 and work
// up: the failure mode, if present, degrades the service for everyone. The
// defaults are intentionally gentle.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/spf13/pflag"
)

func main() {
	var (
		url      = pflag.String("url", "", "download URL for the slow clients to fetch (required)")
		probeURL = pflag.String("probe", "", "cheap URL to probe with (required); a bogus download key is ideal")
		n        = pflag.IntP("clients", "n", 4, "number of slow clients")
		rate     = pflag.Int("rate", 32<<10, "bytes/sec each slow client reads")
		dur      = pflag.Duration("duration", 60*time.Second, "how long to hold the slow clients open")
		probeInt = pflag.Duration("probe-interval", 1*time.Second, "how often to probe")
		insecure = pflag.Bool("insecure", false, "skip TLS verification")
	)
	pflag.Usage = func() {
		fmt.Fprintf(os.Stderr, "slowclient - reproduce the download-service backpressure stall\n\n")
		fmt.Fprintf(os.Stderr, "Usage:\n  slowclient --url <download-url> --probe <cheap-url> [options]\n\n")
		fmt.Fprintf(os.Stderr, "Example:\n")
		fmt.Fprintf(os.Stderr, "  slowclient \\\n")
		fmt.Fprintf(os.Stderr, "    --url   https://p3.theseed.org/services/WorkspaceDownload/download/KEY/big.tsv \\\n")
		fmt.Fprintf(os.Stderr, "    --probe https://p3.theseed.org/services/WorkspaceDownload/download/BOGUS/x \\\n")
		fmt.Fprintf(os.Stderr, "    --clients 8 --rate 32768 --duration 90s\n\n")
		fmt.Fprintf(os.Stderr, "SAFETY: this loads a shared service. Start with --clients 2.\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		pflag.PrintDefaults()
	}
	pflag.Parse()

	if *url == "" || *probeURL == "" {
		pflag.Usage()
		os.Exit(1)
	}

	tr := http.DefaultTransport.(*http.Transport).Clone()
	// Each slow client needs its own connection; the default cap of 2 idle
	// conns per host would otherwise serialize them in the CLIENT and produce
	// a false positive.
	tr.MaxIdleConnsPerHost = *n + 4
	tr.MaxConnsPerHost = 0
	if *insecure {
		tr.TLSClientConfig = insecureTLS()
	}
	client := &http.Client{Transport: tr}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, *dur)
	defer cancel()

	fmt.Printf("baseline: probing %s with no load\n", *probeURL)
	base := probeN(client, *probeURL, 8, 200*time.Millisecond)
	report("baseline", base)

	fmt.Printf("\nstarting %d slow clients at %d B/s against %s\n", *n, *rate, *url)

	var active int64
	var wg sync.WaitGroup
	for i := 0; i < *n; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			atomic.AddInt64(&active, 1)
			defer atomic.AddInt64(&active, -1)
			if err := slowFetch(ctx, client, *url, *rate); err != nil && ctx.Err() == nil {
				fmt.Printf("  client %d: %v\n", id, err)
			}
		}(i)
	}

	// Let them establish before measuring.
	time.Sleep(2 * time.Second)

	loadStart := time.Now()
	var loaded []time.Duration
	ticker := time.NewTicker(*probeInt)
	defer ticker.Stop()
loop:
	for {
		select {
		case <-ctx.Done():
			break loop
		case <-ticker.C:
			d := probeOnce(client, *probeURL)
			loaded = append(loaded, d)
			marker := ""
			if d > 1*time.Second {
				marker = "   <== STALL"
			}
			fmt.Printf("  t+%-6s active=%d probe=%7.3fs%s\n",
				time.Since(loadStart).Round(time.Second),
				atomic.LoadInt64(&active), d.Seconds(), marker)
		}
	}

	cancel()
	wg.Wait()

	fmt.Println()
	report("under load", loaded)

	fmt.Printf("\nafter load:\n")
	after := probeN(client, *probeURL, 8, 200*time.Millisecond)
	report("recovered", after)

	verdict(base, loaded, after)
}

// slowFetch downloads url while reading at approximately rate bytes/sec.
func slowFetch(ctx context.Context, c *http.Client, url string, rate int) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	resp, err := c.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("status %s (is the download key valid and unexpired?)", resp.Status)
	}

	const slice = 8 << 10
	buf := make([]byte, slice)
	interval := time.Duration(float64(slice) / float64(rate) * float64(time.Second))
	for {
		n, err := resp.Body.Read(buf)
		if n > 0 {
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(interval):
			}
		}
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
	}
}

func probeOnce(c *http.Client, url string) time.Duration {
	start := time.Now()
	resp, err := c.Get(url)
	if err != nil {
		return time.Since(start)
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	resp.Body.Close()
	return time.Since(start)
}

func probeN(c *http.Client, url string, n int, gap time.Duration) []time.Duration {
	out := make([]time.Duration, 0, n)
	for i := 0; i < n; i++ {
		out = append(out, probeOnce(c, url))
		time.Sleep(gap)
	}
	return out
}

func report(label string, ds []time.Duration) {
	if len(ds) == 0 {
		fmt.Printf("  %-12s (no samples)\n", label)
		return
	}
	s := append([]time.Duration(nil), ds...)
	sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
	var sum time.Duration
	stalls := 0
	for _, d := range s {
		sum += d
		if d > time.Second {
			stalls++
		}
	}
	fmt.Printf("  %-12s n=%-3d median=%7.3fs p95=%7.3fs max=%7.3fs stalls(>1s)=%d\n",
		label, len(s),
		s[len(s)/2].Seconds(),
		s[int(float64(len(s))*0.95)%len(s)].Seconds(),
		s[len(s)-1].Seconds(),
		stalls)
}

func verdict(base, loaded, after []time.Duration) {
	fmt.Println()
	if len(base) == 0 || len(loaded) == 0 {
		fmt.Println("verdict: not enough samples")
		return
	}
	med := func(ds []time.Duration) time.Duration {
		s := append([]time.Duration(nil), ds...)
		sort.Slice(s, func(i, j int) bool { return s[i] < s[j] })
		return s[len(s)/2]
	}
	b, l := med(base), med(loaded)
	stalls := 0
	for _, d := range loaded {
		if d > time.Second {
			stalls++
		}
	}

	switch {
	case stalls > 0 && l > 5*b:
		fmt.Printf("verdict: REPRODUCED. Median probe latency went %v -> %v under slow-client load,\n", b, l)
		fmt.Printf("         with %d/%d probes over 1s. Slow clients stall unrelated requests,\n", stalls, len(loaded))
		fmt.Printf("         which is the 2026-09-24 signature.\n")
	case l > 2*b:
		fmt.Printf("verdict: DEGRADED but not stalled. Median %v -> %v. Try more clients (-n) or a\n", b, l)
		fmt.Printf("         slower rate, and confirm the -url body is large enough to keep them busy.\n")
	default:
		fmt.Printf("verdict: NOT reproduced at this load. Median %v -> %v.\n", b, l)
		fmt.Printf("         Either the hypothesis is wrong, or the load is too gentle: check that the\n")
		fmt.Printf("         slow clients actually stayed connected (a 4xx above means the key expired)\n")
		fmt.Printf("         and that the file is large relative to -rate * -duration.\n")
	}
	_ = after
}

func insecureTLS() *tls.Config {
	return &tls.Config{InsecureSkipVerify: true} // opt-in via -insecure, for test deployments with self-signed certs
}
