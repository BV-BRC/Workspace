package dlservice

import "testing"

func TestParseRange(t *testing.T) {
	const size = 100

	for _, tc := range []struct {
		name            string
		header          string
		wantOK          bool
		wantSatisfiable bool
		wantStart       int64
		wantEnd         int64
	}{
		{name: "absent", header: "", wantOK: false, wantSatisfiable: true},
		{name: "bounded", header: "bytes=10-19", wantOK: true, wantSatisfiable: true, wantStart: 10, wantEnd: 19},
		{name: "single byte", header: "bytes=0-0", wantOK: true, wantSatisfiable: true, wantStart: 0, wantEnd: 0},
		{name: "open ended", header: "bytes=10-", wantOK: true, wantSatisfiable: true, wantStart: 10, wantEnd: 99},
		{name: "whole file", header: "bytes=0-99", wantOK: true, wantSatisfiable: true, wantStart: 0, wantEnd: 99},

		// Perl clamps an over-long end down to size-1 (:1890).
		{name: "end past EOF clamps", header: "bytes=50-9999", wantOK: true, wantSatisfiable: true, wantStart: 50, wantEnd: 99},

		// Suffix ranges do not match the Perl regex at all -> served as a 200.
		{name: "suffix range not supported", header: "bytes=-500", wantOK: false, wantSatisfiable: true},

		// A multi-range header does NOT match: the literal "bytes=" must
		// directly precede the digits, and the trailing anchor rules out the
		// first pair. Verified against the Perl regex itself. Served as a 200.
		{name: "multi range does not match", header: "bytes=0-9,200-299", wantOK: false, wantSatisfiable: true},

		// Unanchored at the start, so a junk prefix still matches.
		{name: "junk prefix still matches", header: "xbytes=0-5", wantOK: true, wantSatisfiable: true, wantStart: 0, wantEnd: 5},

		{name: "trailing whitespace allowed", header: "bytes=0-5  ", wantOK: true, wantSatisfiable: true, wantStart: 0, wantEnd: 5},

		// Where Perl would emit a negative Content-Length, we report
		// unsatisfiable so the caller can answer 416.
		{name: "start past EOF is unsatisfiable", header: "bytes=99999-", wantOK: true, wantSatisfiable: false},
		{name: "start exactly at EOF is unsatisfiable", header: "bytes=100-", wantOK: true, wantSatisfiable: false},

		{name: "garbage", header: "chunks=1-2", wantOK: false, wantSatisfiable: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r, ok, sat := parseRange(tc.header, size)
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tc.wantOK)
			}
			if sat != tc.wantSatisfiable {
				t.Fatalf("satisfiable = %v, want %v", sat, tc.wantSatisfiable)
			}
			if !ok || !sat {
				return
			}
			if r.start != tc.wantStart || r.end != tc.wantEnd {
				t.Errorf("range = %d-%d, want %d-%d", r.start, r.end, tc.wantStart, tc.wantEnd)
			}
		})
	}
}

func TestByteRangeLength(t *testing.T) {
	if got := (byteRange{start: 0, end: 0}).length(); got != 1 {
		t.Errorf("length of 0-0 = %d, want 1", got)
	}
	if got := (byteRange{start: 10, end: 19}).length(); got != 10 {
		t.Errorf("length of 10-19 = %d, want 10", got)
	}
}

// A zero-length file cannot satisfy any range.
func TestParseRangeEmptyFile(t *testing.T) {
	if _, ok, sat := parseRange("bytes=0-", 0); !ok || sat {
		t.Errorf("on an empty file: ok=%v satisfiable=%v, want ok=true satisfiable=false", ok, sat)
	}
}
