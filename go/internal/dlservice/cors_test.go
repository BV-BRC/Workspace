package dlservice

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func corsHandler() http.Handler {
	return corsMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("app ran"))
	}))
}

// With no Origin the Perl middleware appends only Vary.
func TestCORSNoOrigin(t *testing.T) {
	w := get(corsHandler(), "GET", "/anything", nil)

	if got := w.Header().Get("Vary"); got != "Origin" {
		t.Errorf("Vary = %q, want Origin", got)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Allow-Origin = %q, want none without an Origin request header", got)
	}
	if w.Body.String() != "app ran" {
		t.Error("the app should still run")
	}
}

// Credentials are enabled, so the Origin must be echoed literally. A "*" here
// would make the credentialed fetch in viewer/File.js illegal.
func TestCORSSimpleRequestEchoesOrigin(t *testing.T) {
	const origin = "https://www.maage-brc.org"
	w := get(corsHandler(), "GET", "/x", http.Header{"Origin": {origin}})

	if got := w.Header().Get("Access-Control-Allow-Origin"); got != origin {
		t.Errorf("Allow-Origin = %q, want the echoed origin %q", got, origin)
	}
	if got := w.Header().Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Errorf("Allow-Credentials = %q, want true", got)
	}
	if got := w.Header().Get("Vary"); got != "Origin" {
		t.Errorf("Vary = %q, want Origin", got)
	}
	// Emitted with an empty value, matching the live Perl service.
	if _, ok := w.Header()["Access-Control-Expose-Headers"]; !ok {
		t.Error("Expose-Headers should be present (with an empty value)")
	}
	if w.Body.String() != "app ran" {
		t.Error("a simple request should still reach the app")
	}
}

// A preflight is answered by the middleware; the app must not run.
func TestCORSPreflight(t *testing.T) {
	const origin = "https://www.maage-brc.org"
	w := get(corsHandler(), "OPTIONS", "/services/WorkspaceDownload/set-cookie-auth", http.Header{
		"Origin":                         {origin},
		"Access-Control-Request-Method":  {"POST"},
		"Access-Control-Request-Headers": {"authorization, content-type"},
	})

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if w.Body.String() != "" {
		t.Errorf("body = %q, want empty (the app must not run on a preflight)", w.Body.String())
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != origin {
		t.Errorf("Allow-Origin = %q, want %q", got, origin)
	}
	if got := w.Header().Get("Access-Control-Allow-Methods"); got != allowedMethods {
		t.Errorf("Allow-Methods = %q, want the full Plack default list", got)
	}
	if got, want := w.Header().Get("Access-Control-Allow-Headers"), "authorization, content-type"; got != want {
		t.Errorf("Allow-Headers = %q, want the echoed request headers %q", got, want)
	}
	// Perl never sets Max-Age, so browsers re-preflight every time.
	if got := w.Header().Get("Access-Control-Max-Age"); got != "" {
		t.Errorf("Max-Age = %q, want none", got)
	}
}

// OPTIONS without Access-Control-Request-Method is NOT a preflight.
func TestCORSOptionsWithoutRequestMethodFallsThrough(t *testing.T) {
	w := get(corsHandler(), "OPTIONS", "/x", http.Header{"Origin": {"https://example.org"}})
	if w.Body.String() != "app ran" {
		t.Errorf("body = %q, want the app to run", w.Body.String())
	}
}

func TestNormalizeRequestHeaders(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"a,b", "a, b"},
		{"a,  b,c", "a, b, c"},
		{"authorization", "authorization"},
		{"", ""},
	} {
		if got := normalizeRequestHeaders(tc.in); got != tc.want {
			t.Errorf("normalizeRequestHeaders(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// The real service is reached through nginx at /services/WorkspaceDownload/...;
// confirm a preflight to that shape is still handled.
func TestCORSPreflightOnNestedPath(t *testing.T) {
	w := httptest.NewRecorder()
	r := httptest.NewRequest("OPTIONS", "/download/somekey/file.txt", nil)
	r.Header.Set("Origin", "https://www.maage-brc.org")
	r.Header.Set("Access-Control-Request-Method", "GET")
	corsHandler().ServeHTTP(w, r)

	if w.Code != http.StatusOK || w.Body.String() != "" {
		t.Errorf("status=%d body=%q, want 200 and an empty body", w.Code, w.Body.String())
	}
}
