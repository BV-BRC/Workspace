package dlservice

import (
	"regexp"
	"strconv"
)

// The Perl range regex, reproduced verbatim (WorkspaceImpl.pm:1882):
//
//	/bytes=(\d+)-(\d*)\s*$/
//
// It is deliberately unanchored at the start and anchored at the end. Two
// consequences the Go port must keep:
//
//   - Suffix ranges ("bytes=-500") do NOT match, because \d+ requires a digit
//     before the dash. Such a request is served as a normal 200.
//   - A multi-range header ("bytes=0-99,200-299") does NOT match either: the
//     literal "bytes=" has to sit directly before the digits, and the trailing
//     anchor rules out the first pair. Verified against the Perl regex. Such a
//     request is also served as a normal 200.
var rangeRE = regexp.MustCompile(`bytes=(\d+)-(\d*)\s*$`)

// byteRange is a resolved, clamped range over a known file size.
type byteRange struct {
	start int64
	end   int64 // inclusive
}

func (r byteRange) length() int64 { return r.end - r.start + 1 }

// parseRange resolves a Range header against size.
//
// ok is false when there is no usable range and the caller should serve a
// normal 200. satisfiable is false when the range parsed but starts at or past
// EOF.
//
// The Perl code has no notion of "unsatisfiable": it clamps end to size-1 and
// then computes length as end-start+1, which for start >= size yields a
// NEGATIVE Content-Length on a 206 (e.g. "bytes 99999-99/100",
// Content-Length: -99899). That is a bug, not a contract, so we surface it to
// the caller and answer 416 instead.
func parseRange(header string, size int64) (r byteRange, ok, satisfiable bool) {
	if header == "" {
		return byteRange{}, false, true
	}
	m := rangeRE.FindStringSubmatch(header)
	if m == nil {
		return byteRange{}, false, true
	}

	start, err := strconv.ParseInt(m[1], 10, 64)
	if err != nil {
		// Only reachable for absurdly long digit runs that overflow int64;
		// Perl would silently produce garbage, we decline the range instead.
		return byteRange{}, false, true
	}

	end := size - 1
	if m[2] != "" {
		parsed, err := strconv.ParseInt(m[2], 10, 64)
		if err != nil {
			return byteRange{}, false, true
		}
		// Perl clamps an over-long end down to the last byte (:1890-1893).
		if parsed < size {
			end = parsed
		}
	}

	if start > end || start >= size {
		return byteRange{start: start, end: end}, true, false
	}
	return byteRange{start: start, end: end}, true, true
}
