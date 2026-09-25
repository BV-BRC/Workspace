package dlservice

import (
	"fmt"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/BV-BRC/Workspace/go/internal/dlstore"
)

// Drives the real server over a real socket with curl, so the wire bytes are
// verified rather than the recorder's view of them.
func TestLiveWithCurl(t *testing.T) {
	if _, err := exec.LookPath("curl"); err != nil {
		t.Skip("curl not available")
	}

	dir := t.TempDir()
	path := filepath.Join(dir, "data.txt")
	const body = "0123456789"
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}

	s := &Server{
		Store: &fakeStore{byKey: map[string]*dlstore.Download{
			"k": {DownloadKey: "k", Name: "data.txt", Size: int64(len(body)), FilePath: path},
		}, bySig: map[string]*dlstore.Download{}, sessions: map[string]*dlstore.AuthCookie{}},
		Log: quietLogger(),
	}
	srv := httptest.NewServer(s.Handler())
	defer srv.Close()

	curl := func(args ...string) string {
		out, err := exec.Command("curl", append([]string{"-sS"}, args...)...).CombinedOutput()
		if err != nil {
			t.Fatalf("curl %v: %v\n%s", args, err, out)
		}
		return string(out)
	}

	t.Run("full download headers", func(t *testing.T) {
		out := curl("-D-", "-o", "/dev/null", srv.URL+"/download/k/data.txt")
		for _, want := range []string{
			"HTTP/1.1 200 OK",
			`Content-Disposition: attachment; filename="data.txt"`,
			"Content-Type: application/octet-stream",
		} {
			if !strings.Contains(out, want) {
				t.Errorf("missing %q in:\n%s", want, out)
			}
		}
	})

	t.Run("body bytes", func(t *testing.T) {
		if got := curl(srv.URL + "/download/k/data.txt"); got != body {
			t.Errorf("body = %q, want %q", got, body)
		}
	})

	t.Run("range", func(t *testing.T) {
		out := curl("-D-", "-H", "Range: bytes=2-4", srv.URL+"/download/k/data.txt")
		for _, want := range []string{
			"HTTP/1.1 206 Partial Content",
			"Content-Range: bytes 2-4/10",
			"Content-Length: 3",
		} {
			if !strings.Contains(out, want) {
				t.Errorf("missing %q in:\n%s", want, out)
			}
		}
		if !strings.HasSuffix(out, "234") {
			t.Errorf("ranged body should be %q, got tail of:\n%s", "234", out)
		}
	})

	t.Run("404 bodies", func(t *testing.T) {
		for _, tc := range []struct{ url, want string }{
			{srv.URL + "/download/nope/x", "Invalid path"},
			{srv.URL + "/download/a/b/c", "Invalid path"},
		} {
			out := curl("-D-", tc.url)
			if !strings.Contains(out, "HTTP/1.1 404 Not Found") ||
				!strings.Contains(out, "Content-Type: text/plain") ||
				!strings.HasSuffix(out, tc.want+"\n") {
				t.Errorf("%s: unexpected response:\n%s", tc.url, out)
			}
		}
	})

	t.Run("cors preflight", func(t *testing.T) {
		out := curl("-D-", "-o", "/dev/null", "-X", "OPTIONS",
			"-H", "Origin: https://www.maage-brc.org",
			"-H", "Access-Control-Request-Method: POST",
			"-H", "Access-Control-Request-Headers: authorization",
			srv.URL+"/set-cookie-auth")
		for _, want := range []string{
			"HTTP/1.1 200 OK",
			"Access-Control-Allow-Origin: https://www.maage-brc.org",
			"Access-Control-Allow-Credentials: true",
			"Access-Control-Allow-Headers: authorization",
			"Vary: Origin",
		} {
			if !strings.Contains(out, want) {
				t.Errorf("missing %q in:\n%s", want, out)
			}
		}
		if strings.Contains(out, "Access-Control-Max-Age") {
			t.Errorf("Max-Age should not be set (Perl never sets it):\n%s", out)
		}
	})

	t.Run("legacy url form", func(t *testing.T) {
		if got := curl(srv.URL + "/k/data.txt"); got != body {
			t.Errorf("legacy /{key}/{name} body = %q, want %q", got, body)
		}
	})

	fmt.Fprintln(os.Stderr, "live curl checks complete")
}
