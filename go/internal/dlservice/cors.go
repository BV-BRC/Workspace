package dlservice

import (
	"net/http"
	"strings"
)

// allowedMethods is the default method list from Plack::Middleware::CrossOrigin
// (the PSGI wrap at WorkspaceDownload.psgi:24 sets origins/headers but not
// methods, so the module default applies). Reproduced verbatim, duplicate
// entries and WebDAV verbs included, because it is echoed literally in the
// preflight response. Confirmed against the live service.
const allowedMethods = "GET, HEAD, POST, PUT, DELETE, CONNECT, OPTIONS, TRACE, PATCH, " +
	"CANCELUPLOAD, CHECKIN, CHECKOUT, COPY, DELETE, GETLIB, LOCK, MKCOL, MOVE, OPTIONS, " +
	"PROPFIND, PROPPATCH, PUT, REPORT, UNCHECKOUT, UNLOCK, UPDATE, VERSION-CONTROL"

// corsMiddleware reproduces Plack::Middleware::CrossOrigin configured as
// origins => "*", headers => "*", credentials => 1.
//
// Two details matter for the browser client in MAAGE-Web
// (public/js/p3/util/../widget/viewer/File.js posts to /set-cookie-auth with
// credentials):
//
//   - Because credentials are enabled, the Origin is echoed back literally
//     rather than collapsed to "*". A wildcard would make the credentialed
//     fetch illegal and break the viewer.
//   - Vary: Origin is appended to every response, even when no Origin was sent.
//
// Access-Control-Expose-Headers is emitted with an EMPTY value because the Perl
// module pushes it unconditionally from an empty list. Verified on the live
// service. It is harmless, and reproduced for byte-compatibility.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Add("Vary", "Origin")

		origin := r.Header.Get("Origin")
		if origin == "" {
			// No Origin: the Perl middleware adds only the Vary header.
			next.ServeHTTP(w, r)
			return
		}

		h.Set("Access-Control-Allow-Credentials", "true")
		h.Set("Access-Control-Allow-Origin", origin)
		h.Set("Access-Control-Expose-Headers", "")

		// A preflight is answered by the middleware itself; the app never runs.
		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			h.Set("Access-Control-Allow-Methods", allowedMethods)
			// headers => "*" means the requested headers are echoed verbatim.
			h.Set("Access-Control-Allow-Headers", normalizeRequestHeaders(
				r.Header.Get("Access-Control-Request-Headers")))
			// Note: no Access-Control-Max-Age -- the Perl side never sets one,
			// so every preflight is re-issued by the browser.
			h.Set("Content-Type", "text/plain")
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// normalizeRequestHeaders mirrors the Perl `join ', ', split /,\s*/, $hdrs`.
func normalizeRequestHeaders(s string) string {
	if s == "" {
		return ""
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return strings.Join(out, ", ")
}
