package dlservice

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/BV-BRC/Workspace/go/internal/dlstore"
)

// capture builds a server logging JSON into a buffer so lines can be asserted on.
func capture(t *testing.T, s *Server) (http.Handler, *bytes.Buffer) {
	t.Helper()
	var buf bytes.Buffer
	s.Log = slog.New(slog.NewJSONHandler(&buf, nil))
	return s.Handler(), &buf
}

func lastLine(t *testing.T, buf *bytes.Buffer) map[string]any {
	t.Helper()
	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		var m map[string]any
		if err := json.Unmarshal([]byte(lines[i]), &m); err != nil {
			continue
		}
		if m["msg"] == "request" {
			return m
		}
	}
	t.Fatalf("no request log line found in:\n%s", buf.String())
	return nil
}

func TestAccessLogRecordsTiming(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "d.txt")
	body := strings.Repeat("x", 4096)
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}

	s := &Server{Store: &fakeStore{byKey: map[string]*dlstore.Download{
		"k": {Name: "d.txt", Size: int64(len(body)), FilePath: path},
	}}}
	h, buf := capture(t, s)

	w := get(h, "GET", "/download/k/d.txt", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d", w.Code)
	}

	m := lastLine(t, buf)
	if m["route"] != "/download" {
		t.Errorf("route = %v, want /download", m["route"])
	}
	if m["status"].(float64) != 200 {
		t.Errorf("status = %v, want 200", m["status"])
	}
	if got := m["bytes"].(float64); int(got) != len(body) {
		t.Errorf("bytes = %v, want %d", got, len(body))
	}
	// Both timings must be present and non-negative on a served response.
	for _, k := range []string{"ttfb_s", "total_s"} {
		v, ok := m[k].(float64)
		if !ok {
			t.Fatalf("%s missing or not a number: %v", k, m[k])
		}
		if v < 0 {
			t.Errorf("%s = %v, want >= 0", k, v)
		}
	}
	if m["ttfb_s"].(float64) > m["total_s"].(float64) {
		t.Errorf("ttfb (%v) must not exceed total (%v)", m["ttfb_s"], m["total_s"])
	}
}

// The ttfb/total split is the whole point: it separates a slow dependency from
// a slow client. A handler that stalls BEFORE writing must show a large ttfb.
func TestAccessLogTTFBReflectsPreWriteDelay(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, nil))

	h := accessLog(log, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(120 * time.Millisecond) // e.g. a slow upstream fetch
		_, _ = io.WriteString(w, "body")
	}))

	req := httptest.NewRequest("GET", "/download/k/x", nil)
	h.ServeHTTP(httptest.NewRecorder(), req)

	m := lastLine(t, &buf)
	ttfb := m["ttfb_s"].(float64)
	if ttfb < 0.1 {
		t.Errorf("ttfb = %v, want >= 0.1 for a handler that slept before writing", ttfb)
	}
}

// Conversely, a handler that writes immediately then dribbles must show a small
// ttfb and a large total -- the slow-client signature.
func TestAccessLogSlowBodyShowsInTotalNotTTFB(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&buf, nil))

	h := accessLog(log, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, "first")
		time.Sleep(120 * time.Millisecond)
		_, _ = io.WriteString(w, "rest")
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/download/k/x", nil))

	m := lastLine(t, &buf)
	ttfb, total := m["ttfb_s"].(float64), m["total_s"].(float64)
	if ttfb > 0.05 {
		t.Errorf("ttfb = %v, want small when the first byte is written immediately", ttfb)
	}
	if total < 0.1 {
		t.Errorf("total = %v, want >= 0.1", total)
	}
}

// Bearer secrets must never be logged.
func TestAccessLogOmitsSecrets(t *testing.T) {
	const secretKey = "SUPERSECRETDOWNLOADKEY"
	s := &Server{Store: &fakeStore{}}
	h, buf := capture(t, s)

	get(h, "GET", "/download/"+secretKey+"/f.txt", nil)
	get(h, "GET", "/view/user@bvbrc/private/path.txt",
		http.Header{"Cookie": {SessionCookieName + "=SECRETSESSION"}})

	out := buf.String()
	for _, secret := range []string{secretKey, "SECRETSESSION", "user@bvbrc", "private/path.txt"} {
		if strings.Contains(out, secret) {
			t.Errorf("log leaked %q:\n%s", secret, out)
		}
	}
}

func TestAccessLogRouteGrouping(t *testing.T) {
	s := &Server{Store: &fakeStore{bySig: map[string]*dlstore.Download{}}}
	h, buf := capture(t, s)

	for _, tc := range []struct{ path, want string }{
		{"/download/k/f.txt", "/download"},
		{"/k/f.txt", "/"},
		{"/view/u/p.txt", "/view"},
		{"/archive/" + strings.Repeat("a", 40), "/archive"},
		{"/download/archive/" + strings.Repeat("b", 40), "/archive"},
		{"/set-cookie-auth", "/set-cookie-auth"},
	} {
		buf.Reset()
		get(h, "GET", tc.path, nil)
		if m := lastLine(t, buf); m["route"] != tc.want {
			t.Errorf("%s -> route %v, want %v", tc.path, m["route"], tc.want)
		}
	}
}

func TestAccessLogRecordsRange(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "d.txt")
	_ = os.WriteFile(path, []byte("0123456789"), 0o600)

	s := &Server{Store: &fakeStore{byKey: map[string]*dlstore.Download{
		"k": {Name: "d.txt", Size: 10, FilePath: path},
	}}}
	h, buf := capture(t, s)

	get(h, "GET", "/download/k/d.txt", http.Header{"Range": {"bytes=2-4"}})

	m := lastLine(t, buf)
	if m["range"] != "bytes=2-4" {
		t.Errorf("range = %v, want bytes=2-4", m["range"])
	}
	if m["status"].(float64) != 206 {
		t.Errorf("status = %v, want 206", m["status"])
	}
	if m["bytes"].(float64) != 3 {
		t.Errorf("bytes = %v, want 3", m["bytes"])
	}
}

// A CORS preflight is answered by the middleware without reaching the app, so
// it should not appear as a request line.
func TestAccessLogSkipsPreflight(t *testing.T) {
	s := &Server{Store: &fakeStore{}}
	h, buf := capture(t, s)

	get(h, "OPTIONS", "/set-cookie-auth", http.Header{
		"Origin":                        {"https://www.maage-brc.org"},
		"Access-Control-Request-Method": {"POST"},
	})

	if strings.Contains(buf.String(), `"msg":"request"`) {
		t.Errorf("preflight should not be logged as a request:\n%s", buf.String())
	}
}
