package dlservice

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/BV-BRC/Workspace/go/internal/dlstore"
)

// slowStore simulates the pathological Mongo latency that cripples the Perl
// service: every lookup blocks for a fixed delay. Under Twiggy's single event
// loop this serializes ALL downloads (measured: n=1 and n=60 both stall ~9s,
// with all 60 releasing within 70ms of each other). Here it must not.
type slowStore struct {
	delay time.Duration
	rec   *dlstore.Download
}

func (s *slowStore) FindByDownloadKey(ctx context.Context, _ string) (*dlstore.Download, error) {
	select {
	case <-time.After(s.delay):
		return s.rec, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}
func (s *slowStore) FindBySignature(context.Context, string) (*dlstore.Download, error) {
	return nil, dlstore.ErrNotFound
}
func (s *slowStore) FindSession(context.Context, string) (*dlstore.AuthCookie, error) {
	return nil, dlstore.ErrNotFound
}
func (s *slowStore) InsertSession(context.Context, *dlstore.AuthCookie) error { return nil }

// TestConcurrentRequestsDoNotSerialize is the regression test for the bug this
// port exists to fix. With a 300ms store delay, 40 concurrent downloads must
// finish in roughly 300ms total, not 40*300ms, and no single request may take
// meaningfully longer than one delay.
func TestConcurrentRequestsDoNotSerialize(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "d.txt")
	body := make([]byte, 64*1024)
	for i := range body {
		body[i] = byte('a' + i%26)
	}
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatal(err)
	}

	const delay = 300 * time.Millisecond
	const n = 40

	s := &Server{
		Store: &slowStore{
			delay: delay,
			rec: &dlstore.Download{
				DownloadKey: "k", Name: "d.txt",
				Size: int64(len(body)), FilePath: path,
			},
		},
		Log: quietLogger(),
	}
	srv := httptest.NewServer(s.Handler())
	defer srv.Close()

	durations := make([]time.Duration, n)
	var wg sync.WaitGroup
	start := time.Now()

	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			t0 := time.Now()
			resp, err := http.Get(fmt.Sprintf("%s/download/k/d.txt", srv.URL))
			if err != nil {
				t.Errorf("request %d: %v", i, err)
				return
			}
			defer resp.Body.Close()
			nRead, err := io.Copy(io.Discard, resp.Body)
			if err != nil {
				t.Errorf("request %d body: %v", i, err)
			}
			if nRead != int64(len(body)) {
				t.Errorf("request %d: read %d bytes, want %d", i, nRead, len(body))
			}
			durations[i] = time.Since(t0)
		}(i)
	}
	wg.Wait()
	total := time.Since(start)

	// Serialized, this would be n*delay = 12s. Concurrent, ~delay.
	if total > 4*delay {
		t.Errorf("total wall clock for %d concurrent requests = %v; "+
			"want roughly one store delay (%v). Requests appear serialized.",
			n, total, delay)
	}

	var worst time.Duration
	for _, d := range durations {
		if d > worst {
			worst = d
		}
	}
	if worst > 3*delay {
		t.Errorf("slowest request = %v, want ~%v; one request should not wait on others", worst, delay)
	}
	t.Logf("%d concurrent requests: total=%v slowest=%v (store delay %v)", n, total, worst, delay)
}

// A client that disconnects mid-download must not leave the handler blocked.
func TestClientDisconnectIsPropagated(t *testing.T) {
	s := &Server{
		Store: &slowStore{delay: 5 * time.Second, rec: &dlstore.Download{Name: "x", FilePath: "/nonexistent"}},
		Log:   quietLogger(),
	}
	srv := httptest.NewServer(s.Handler())
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, "GET", srv.URL+"/download/k/x", nil)

	done := make(chan struct{})
	go func() {
		defer close(done)
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			resp.Body.Close()
		}
	}()

	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("client disconnect was not propagated; the handler is still blocked")
	}
}
