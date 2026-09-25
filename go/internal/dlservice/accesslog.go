package dlservice

import (
	"log/slog"
	"net/http"
	"time"
)

// Per-request timing instrumentation.
//
// This is the Go counterpart of the `shock-fetch` line added to the Perl
// service (WorkspaceImpl.pm, replacing the Dumper at :1942). The 2026-09-24
// stall was diagnosable only because a leftover debug statement happened to
// record upstream response times; without equivalent instrumentation the Go
// service would be LESS observable than the Perl one it replaces, which is
// unacceptable given the trigger for that stall is still unidentified.
//
// The three numbers that matter, and why:
//
//	ttfb   time to the first byte written to the client. Covers the Mongo
//	       lookup, permission checks and (for Shock-backed objects) the
//	       upstream fetch. A large ttfb points at a dependency.
//	total  time to the last byte. total-ttfb is the body transfer, which is
//	       dominated by how fast the CLIENT drains. A large total with a
//	       small ttfb means a slow client, not a slow service.
//	bytes  what actually reached the client, which distinguishes a completed
//	       transfer from one the client abandoned.
//
// That ttfb/total split is precisely the distinction the Perl logs could not
// make, and which left the investigation unable to separate an upstream stall
// from a body-transfer stall.

// logResponseWriter wraps http.ResponseWriter to capture the status code, the
// byte count, and the moment of the first write.
type logResponseWriter struct {
	http.ResponseWriter
	status    int
	bytes     int64
	firstByte time.Time
}

func (w *logResponseWriter) WriteHeader(code int) {
	if w.status == 0 {
		w.status = code
		if w.firstByte.IsZero() {
			w.firstByte = time.Now()
		}
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *logResponseWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK // implicit 200 on first write
	}
	if w.firstByte.IsZero() {
		w.firstByte = time.Now()
	}
	n, err := w.ResponseWriter.Write(b)
	w.bytes += int64(n)
	return n, err
}

// Flush forwards to the underlying writer when it supports flushing, so
// streaming responses are not buffered by this wrapper.
func (w *logResponseWriter) Flush() {
	if f, ok := w.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// accessLog wraps a handler with one structured line per request.
//
// Deliberately omitted: the download key and session cookie. Both are bearer
// secrets — anyone holding the key can fetch the file — so they must not land
// in a log file. The route and the workspace path are logged instead, which is
// enough to correlate against Shock's log and the nginx access log.
func accessLog(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lw := &logResponseWriter{ResponseWriter: w}

		next.ServeHTTP(lw, r)

		done := time.Now()
		ttfb := time.Duration(-1)
		if !lw.firstByte.IsZero() {
			ttfb = lw.firstByte.Sub(start)
		}

		attrs := []any{
			"method", r.Method,
			"route", routeOf(r.URL.Path),
			"status", lw.status,
			"ttfb_s", round3(ttfb),
			"total_s", round3(done.Sub(start)),
			"bytes", lw.bytes,
		}
		if rng := r.Header.Get("Range"); rng != "" {
			attrs = append(attrs, "range", rng)
		}
		// A client that goes away mid-transfer is the signature of the slow-
		// client/backpressure failure mode, so call it out explicitly.
		if err := r.Context().Err(); err != nil {
			attrs = append(attrs, "client_gone", true)
		}

		log.Info("request", attrs...)
	})
}

// routeOf reduces a path to its route so the logs group usefully and no
// download key or workspace path is emitted. Keys are secrets; workspace paths
// can identify users.
func routeOf(p string) string {
	switch {
	case p == "/set-cookie-auth" || hasPrefix(p, "/set-cookie-auth/"):
		return "/set-cookie-auth"
	case hasPrefix(p, "/view"):
		return "/view"
	case hasPrefix(p, "/download/archive/"), hasPrefix(p, "/archive/"):
		return "/archive"
	case hasPrefix(p, "/download/"):
		return "/download"
	default:
		return "/" // legacy fallback mount
	}
}

func hasPrefix(s, p string) bool { return len(s) >= len(p) && s[:len(p)] == p }

// round3 renders a duration in seconds to millisecond precision, matching the
// %.3f used by the Perl shock-fetch line so the two are directly comparable.
// A negative duration means "never measured" and is passed through as -1.
func round3(d time.Duration) float64 {
	if d < 0 {
		return -1
	}
	return float64(d.Microseconds()) / 1e6
}
