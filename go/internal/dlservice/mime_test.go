package dlservice

import "testing"

func TestMimeTypeFor(t *testing.T) {
	for _, tc := range []struct{ name, want string }{
		// Overrides from %mime_overrides.
		{"structure.pdb", "text/plain"},
		{"mol.sdf", "text/plain"},
		{"seq.gb", "text/plain"},
		{"run.sh", "text/plain"},

		// The override table is case-SENSITIVE while the fallback lowercases,
		// so an uppercase extension misses the override and gets the stock
		// (wrong, but faithful) type.
		{"STRUCTURE.PDB", "application/vnd.palm"},

		// Ordinary types from the MIME::Types table.
		{"notes.txt", "text/plain"},
		{"page.html", "text/html"},
		{"data.json", "application/json"},
		{"table.tsv", "text/tab-separated-values"},
		{"img.png", "image/png"},
		{"doc.pdf", "application/pdf"},
		{"arch.zip", "application/zip"},

		// The FASTA registration in Perl is buggy, so these resolve via the
		// text/plain fallback -- which is the intended answer anyway.
		{"genome.fa", "text/plain"},
		{"genome.fasta", "text/plain"},
		{"genome.fna", "text/plain"},
		{"genome.faa", "text/plain"},

		// Unknown or absent extensions.
		{"reads.fastq", "text/plain"},
		{"aln.bam", "text/plain"},
		{"README", "text/plain"},
		{"trailing.", "text/plain"},
		{"", "text/plain"},
	} {
		if got := mimeTypeFor(tc.name); got != tc.want {
			t.Errorf("mimeTypeFor(%q) = %q, want %q", tc.name, got, tc.want)
		}
	}
}

// Go's mime.TypeByExtension would append "; charset=utf-8"; Perl never does.
func TestMimeHasNoCharsetParameter(t *testing.T) {
	for _, n := range []string{"a.txt", "a.html", "a.css"} {
		got := mimeTypeFor(n)
		for _, c := range got {
			if c == ';' {
				t.Errorf("mimeTypeFor(%q) = %q, want no parameters", n, got)
				break
			}
		}
	}
}

func TestLastExtension(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"file.txt", "txt"},
		{"archive.tar.gz", "gz"},
		{"UPPER.TXT", "TXT"}, // case preserved, matching Perl
		{"noext", ""},
		{"trailingdot.", ""},
		{"", ""},
	} {
		if got := lastExtension(tc.in); got != tc.want {
			t.Errorf("lastExtension(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
