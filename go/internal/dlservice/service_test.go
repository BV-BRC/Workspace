package dlservice

import (
	"context"
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

// fakeStore stands in for Mongo.
type fakeStore struct {
	byKey     map[string]*dlstore.Download
	bySig     map[string]*dlstore.Download
	sessions  map[string]*dlstore.AuthCookie
	forcedErr error
}

func (f *fakeStore) FindByDownloadKey(_ context.Context, k string) (*dlstore.Download, error) {
	if f.forcedErr != nil {
		return nil, f.forcedErr
	}
	if d, ok := f.byKey[k]; ok {
		return d, nil
	}
	return nil, dlstore.ErrNotFound
}

func (f *fakeStore) FindBySignature(_ context.Context, s string) (*dlstore.Download, error) {
	if f.forcedErr != nil {
		return nil, f.forcedErr
	}
	if d, ok := f.bySig[s]; ok {
		return d, nil
	}
	return nil, dlstore.ErrNotFound
}

func (f *fakeStore) FindSession(_ context.Context, t string) (*dlstore.AuthCookie, error) {
	if f.forcedErr != nil {
		return nil, f.forcedErr
	}
	if a, ok := f.sessions[t]; ok {
		return a, nil
	}
	return nil, dlstore.ErrNotFound
}

func (f *fakeStore) InsertSession(context.Context, *dlstore.AuthCookie) error { return nil }

func quietLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// newTestServer wires a server over a temp file of the given content.
func newTestServer(t *testing.T, content string) (http.Handler, *fakeStore) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "data.txt")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	fs := &fakeStore{
		byKey: map[string]*dlstore.Download{
			"goodkey": {
				DownloadKey:    "goodkey",
				Name:           "data.txt",
				Size:           int64(len(content)),
				FilePath:       path,
				ExpirationTime: time.Now().Add(time.Hour).Unix(),
			},
			"expiredkey": {
				DownloadKey:    "expiredkey",
				Name:           "data.txt",
				Size:           int64(len(content)),
				FilePath:       path,
				ExpirationTime: time.Now().Add(-time.Hour).Unix(),
			},
			"dirkey": {
				DownloadKey: "dirkey",
				Name:        "adir",
				FilePath:    dir,
			},
			"missingfile": {
				DownloadKey: "missingfile",
				Name:        "gone.txt",
				FilePath:    filepath.Join(dir, "does-not-exist"),
			},
		},
		bySig:    map[string]*dlstore.Download{},
		sessions: map[string]*dlstore.AuthCookie{},
	}
	s := &Server{Store: fs, Log: quietLogger()}
	return s.Handler(), fs
}

func get(h http.Handler, method, target string, hdr http.Header) *httptest.ResponseRecorder {
	r := httptest.NewRequest(method, target, nil)
	for k, vs := range hdr {
		for _, v := range vs {
			r.Header.Add(k, v)
		}
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func TestDownloadHappyPath(t *testing.T) {
	const body = "hello workspace"
	h, _ := newTestServer(t, body)

	w := get(h, "GET", "/download/goodkey/data.txt", nil)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if got := w.Body.String(); got != body {
		t.Errorf("body = %q, want %q", got, body)
	}
	if got, want := w.Header().Get("Content-Disposition"), `attachment; filename="data.txt"`; got != want {
		t.Errorf("Content-Disposition = %q, want %q", got, want)
	}
	if got, want := w.Header().Get("Content-Type"), "application/octet-stream"; got != want {
		t.Errorf("Content-Type = %q, want %q", got, want)
	}
}

// All four legacy/current URL forms must reach the same handler.
func TestDownloadURLForms(t *testing.T) {
	const body = "payload"
	h, _ := newTestServer(t, body)

	for _, target := range []string{
		"/download/goodkey/data.txt", // current
		"/goodkey/data.txt",          // legacy, served by the "/" mount
	} {
		w := get(h, "GET", target, nil)
		if w.Code != http.StatusOK || w.Body.String() != body {
			t.Errorf("%s: status=%d body=%q, want 200 %q", target, w.Code, w.Body.String(), body)
		}
	}
}

// The filename in the URL is ignored; the record's name wins.
func TestDownloadIgnoresURLName(t *testing.T) {
	h, _ := newTestServer(t, "x")
	w := get(h, "GET", "/download/goodkey/completely-different.bin", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if got, want := w.Header().Get("Content-Disposition"), `attachment; filename="data.txt"`; got != want {
		t.Errorf("Content-Disposition = %q, want %q (record name, not URL name)", got, want)
	}
}

func TestDownload404Shapes(t *testing.T) {
	h, _ := newTestServer(t, "x")

	for _, tc := range []struct {
		name, target, wantBody string
	}{
		{"unknown key", "/download/nosuchkey/data.txt", bodyInvalidPath},
		{"too few segments", "/download/onlyone", bodyInvalidPath},
		{"too many segments", "/download/a/b/c", bodyInvalidPath},
		{"trailing slash", "/download/a/b/", bodyInvalidPath},
		{`literal "0" segment`, "/download/0/0", bodyInvalidPath},
		{"file missing on disk", "/download/missingfile/x", bodyInvalidPath},
		{"path is a directory", "/download/dirkey/x", bodyNotAFile},
	} {
		t.Run(tc.name, func(t *testing.T) {
			w := get(h, "GET", tc.target, nil)
			if w.Code != http.StatusNotFound {
				t.Fatalf("status = %d, want 404", w.Code)
			}
			if got := w.Body.String(); got != tc.wantBody {
				t.Errorf("body = %q, want %q", got, tc.wantBody)
			}
			if got := w.Header().Get("Content-Type"); got != "text/plain" {
				t.Errorf("Content-Type = %q, want text/plain", got)
			}
		})
	}
}

// A Mongo outage must not masquerade as a 404.
func TestDownloadStoreErrorIs500(t *testing.T) {
	h, fs := newTestServer(t, "x")
	fs.forcedErr = io.ErrUnexpectedEOF

	w := get(h, "GET", "/download/goodkey/data.txt", nil)
	if w.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want 500 (a store failure is not 'invalid path')", w.Code)
	}
}

func TestDownloadExpiryIsIgnoredByDefault(t *testing.T) {
	h, _ := newTestServer(t, "still here")

	// Bug-compatible default: expiry is enforced only by the 120s sweep.
	w := get(h, "GET", "/download/expiredkey/data.txt", nil)
	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want 200 (Perl does not check expiry on /download)", w.Code)
	}
}

func TestDownloadExpiryEnforcedWhenEnabled(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "d.txt")
	if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	fs := &fakeStore{byKey: map[string]*dlstore.Download{
		"k": {Name: "d.txt", Size: 1, FilePath: path, ExpirationTime: time.Now().Add(-time.Hour).Unix()},
	}}
	s := &Server{Store: fs, Log: quietLogger(), EnforceDownloadExpiry: true}

	w := get(s.Handler(), "GET", "/download/k/d.txt", nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want 404 when expiry enforcement is on", w.Code)
	}
}

func TestDownloadRanges(t *testing.T) {
	const body = "0123456789" // 10 bytes
	h, _ := newTestServer(t, body)

	for _, tc := range []struct {
		name, rangeHdr string
		wantStatus     int
		wantBody       string
		wantRange      string
		wantLen        string
	}{
		{"bounded", "bytes=2-4", http.StatusPartialContent, "234", "bytes 2-4/10", "3"},
		{"first byte", "bytes=0-0", http.StatusPartialContent, "0", "bytes 0-0/10", "1"},
		{"open ended", "bytes=5-", http.StatusPartialContent, "56789", "bytes 5-9/10", "5"},
		{"end past EOF clamps", "bytes=8-9999", http.StatusPartialContent, "89", "bytes 8-9/10", "2"},
		{"suffix range falls back to 200", "bytes=-3", http.StatusOK, body, "", ""},
		{"multi-range falls back to 200", "bytes=0-1,4-5", http.StatusOK, body, "", ""},
		{"no range", "", http.StatusOK, body, "", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			hdr := http.Header{}
			if tc.rangeHdr != "" {
				hdr.Set("Range", tc.rangeHdr)
			}
			w := get(h, "GET", "/download/goodkey/data.txt", hdr)

			if w.Code != tc.wantStatus {
				t.Fatalf("status = %d, want %d", w.Code, tc.wantStatus)
			}
			if got := w.Body.String(); got != tc.wantBody {
				t.Errorf("body = %q, want %q", got, tc.wantBody)
			}
			if got := w.Header().Get("Content-Range"); got != tc.wantRange {
				t.Errorf("Content-Range = %q, want %q", got, tc.wantRange)
			}
			if tc.wantLen != "" {
				if got := w.Header().Get("Content-Length"); got != tc.wantLen {
					t.Errorf("Content-Length = %q, want %q", got, tc.wantLen)
				}
			}
		})
	}
}

// Perl emits a 206 with a negative Content-Length for a start past EOF; with
// StrictRangeErrors we answer 416 instead.
func TestOutOfRangeStart(t *testing.T) {
	h, _ := newTestServer(t, "0123456789")
	hdr := http.Header{"Range": {"bytes=9999-"}}

	w := get(h, "GET", "/download/goodkey/data.txt", hdr)
	if w.Code != http.StatusPartialContent {
		t.Errorf("default: status = %d, want 206 (bug-compatible)", w.Code)
	}

	dir := t.TempDir()
	p := filepath.Join(dir, "d.txt")
	_ = os.WriteFile(p, []byte("0123456789"), 0o600)
	s := &Server{
		Store:             &fakeStore{byKey: map[string]*dlstore.Download{"k": {Name: "d.txt", Size: 10, FilePath: p}}},
		Log:               quietLogger(),
		StrictRangeErrors: true,
	}
	w = get(s.Handler(), "GET", "/download/k/d.txt", hdr)
	if w.Code != http.StatusRequestedRangeNotSatisfiable {
		t.Errorf("strict: status = %d, want 416", w.Code)
	}
	if got, want := w.Header().Get("Content-Range"), "bytes */10"; got != want {
		t.Errorf("strict: Content-Range = %q, want %q", got, want)
	}
}

func TestViewSessionHandling(t *testing.T) {
	h, fs := newTestServer(t, "x")
	fs.sessions["live"] = &dlstore.AuthCookie{
		SessionToken:   "live",
		AuthToken:      "un=u@patricbrc.org|sig=abc",
		ExpirationTime: time.Now().Add(time.Hour).Unix(),
	}
	fs.sessions["stale"] = &dlstore.AuthCookie{
		SessionToken:   "stale",
		ExpirationTime: time.Now().Add(-time.Hour).Unix(),
	}

	for _, tc := range []struct {
		name, cookie string
		wantStatus   int
	}{
		// Every session failure is 503, not 401/403 -- preserved from Perl.
		{"no cookie", "", http.StatusServiceUnavailable},
		{"unknown session", "nosuch", http.StatusServiceUnavailable},
		{"expired session", "stale", http.StatusServiceUnavailable},
		{`literal "0"`, "0", http.StatusServiceUnavailable},
		// A valid session gets past auth (the resolution step is not built yet).
		{"valid session", "live", http.StatusNotImplemented},
	} {
		t.Run(tc.name, func(t *testing.T) {
			hdr := http.Header{}
			if tc.cookie != "" {
				hdr.Set("Cookie", SessionCookieName+"="+tc.cookie)
			}
			w := get(h, "GET", "/view/u@patricbrc.org/home/x.txt", hdr)
			if w.Code != tc.wantStatus {
				t.Fatalf("status = %d, want %d", w.Code, tc.wantStatus)
			}
			if tc.wantStatus == http.StatusServiceUnavailable {
				if got := w.Body.String(); got != bodyInvalidSession {
					t.Errorf("body = %q, want %q", got, bodyInvalidSession)
				}
			}
		})
	}
}

func TestArchive404Shapes(t *testing.T) {
	h, fs := newTestServer(t, "x")
	const sig = "da39a3ee5e6b4b0d3255bfef95601890afd80709"
	const emptySig = "0000000000000000000000000000000000000000"
	fs.bySig[sig] = &dlstore.Download{DownloadSignature: sig, Objects: []string{"/u/home/a"}}
	fs.bySig[emptySig] = &dlstore.Download{DownloadSignature: emptySig}

	// Unknown signature -> "Invalid path\n"
	w := get(h, "GET", "/archive/"+strings.Repeat("a", 40), nil)
	if w.Code != http.StatusNotFound || w.Body.String() != bodyInvalidPath {
		t.Errorf("unknown sig: %d %q, want 404 %q", w.Code, w.Body.String(), bodyInvalidPath)
	}

	// Known signature but no objects -> the DIFFERENT body "Not found\n"
	w = get(h, "GET", "/archive/"+emptySig, nil)
	if w.Code != http.StatusNotFound || w.Body.String() != bodyNotFound {
		t.Errorf("empty objects: %d %q, want 404 %q", w.Code, w.Body.String(), bodyNotFound)
	}

	// Both /archive/{sig} and /download/archive/{sig} must route there.
	for _, target := range []string{"/archive/" + sig, "/download/archive/" + sig} {
		w = get(h, "GET", target, nil)
		if w.Code != http.StatusNotImplemented {
			t.Errorf("%s: status = %d, want 501 (reached the archive handler)", target, w.Code)
		}
	}
}

// The archive regex is [a-z0-9]{40}, not hex: a 40-char string with letters
// beyond 'f' still routes to the archive branch.
func TestArchiveRegexAcceptsNonHex(t *testing.T) {
	h, _ := newTestServer(t, "x")
	w := get(h, "GET", "/archive/"+strings.Repeat("z", 40), nil)
	// Routed to archive, looked up, not found.
	if w.Code != http.StatusNotFound || w.Body.String() != bodyInvalidPath {
		t.Errorf("status=%d body=%q, want 404 %q", w.Code, w.Body.String(), bodyInvalidPath)
	}
}

func TestSetCookieAuthMissingHeader(t *testing.T) {
	h, _ := newTestServer(t, "x")

	// Any method is accepted by the Perl handler.
	for _, method := range []string{"GET", "POST", "PUT"} {
		w := get(h, method, "/set-cookie-auth", nil)
		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s: status = %d, want 401", method, w.Code)
		}
		if got, want := w.Body.String(), "Authentication required"; got != want {
			t.Errorf("%s: body = %q, want %q", method, got, want)
		}
		// Perl sends no Content-Type on this branch.
		if got := w.Header().Get("Content-Type"); got != "" {
			t.Errorf("%s: Content-Type = %q, want none", method, got)
		}
	}
}
