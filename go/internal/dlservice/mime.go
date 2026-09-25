package dlservice

import "strings"

// mimeOverrides is %mime_overrides from WorkspaceImpl.pm:60-64, in full. These
// four exist because the stock MIME database maps them to actively wrong types
// for bioinformatics data: pdb -> application/vnd.palm,
// sdf -> application/vnd.kinar, gb -> application/x-gameboy-rom,
// sh -> application/x-sh.
//
// The Perl lookup is case-SENSITIVE against these lowercase keys, while the
// fallback MIME::Types lookup lowercases. So "X.PDB" misses the override and
// resolves to application/vnd.palm. That asymmetry is reproduced below.
var mimeOverrides = map[string]string{
	"pdb": "text/plain",
	"sdf": "text/plain",
	"gb":  "text/plain",
	"sh":  "text/plain",
}

// mimeByExt is the subset of the deployed MIME/types.db that matters here.
//
// Go's mime.TypeByExtension is deliberately NOT used: its table differs from
// Perl's (it lacks bed/sam/gb entries entirely) and it appends "; charset=utf-8"
// to text types, which Perl never does. Both differences would show up in a
// header diff against the Perl service.
//
// Entries whose stock mapping is wrong for bioinformatics (bed, sam, vcf) are
// kept as-is: they are what the Perl service actually returns today, and
// "fixing" them here would be an unrequested behavior change.
var mimeByExt = map[string]string{
	"txt":  "text/plain",
	"html": "text/html",
	"htm":  "text/html",
	"json": "application/json",
	"csv":  "text/csv",
	"tsv":  "text/tab-separated-values",
	"xml":  "application/xml",
	"png":  "image/png",
	"gif":  "image/gif",
	"jpg":  "image/jpeg",
	"jpeg": "image/jpeg",
	"svg":  "image/svg+xml",
	"pdf":  "application/pdf",
	"gz":   "application/gzip",
	"zip":  "application/zip",
	"tar":  "application/x-tar",
	"tgz":  "application/x-gtar",
	"bz2":  "application/x-bzip2",
	"xz":   "application/x-xz",
	"css":  "text/css",
	"js":   "application/javascript",
	"md":   "text/markdown",
	"conf": "text/plain",
	"log":  "text/x-log",
	"xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
	"xls":  "application/vnd.ms-excel",
	"doc":  "application/msword",
	"docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
	"gff3": "text/gff3",
	"embl": "x-chemical/x-embl-dl-nucleotide",
	"bed":  "application/vnd.realvnc.bed",
	"sam":  "application/x-amipro",
	"vcf":  "text/vcard",
	"nt":   "application/n-triples",
	"yaml": "application/vnd.oai.workflows",
	"yml":  "application/vnd.oai.workflows+yaml",

	// The stock types.db values for the four overridden extensions. These are
	// only reachable when the override table misses on case (e.g. "X.PDB"),
	// because mimeTypeFor consults mimeOverrides first for the exact-case key.
	// Faithful to Perl, wrong for the data -- which is precisely why the
	// overrides above exist.
	"pdb": "application/vnd.palm",
	"sdf": "application/vnd.kinar",
	"gb":  "application/x-gameboy-rom",
	"sh":  "application/x-sh",

	// Note there are deliberately NO fa/fasta/fna/faa entries. The Perl code
	// tries to register them at WorkspaceImpl.pm:56 but passes the extensions
	// WITH leading dots, which MIME::Types never matches on lookup. They fall
	// through to the "text/plain" default, which is the intended answer anyway.
}

// mimeTypeFor reproduces the /view content-type selection at
// WorkspaceImpl.pm:1853-1862. Everything unrecognized is text/plain.
func mimeTypeFor(name string) string {
	ext := lastExtension(name)
	if ext == "" {
		return "text/plain"
	}
	// Case-sensitive override lookup, matching Perl.
	if t, ok := mimeOverrides[ext]; ok {
		return t
	}
	// The MIME::Types fallback lowercases the filename first.
	if t, ok := mimeByExt[strings.ToLower(ext)]; ok {
		return t
	}
	return "text/plain"
}

// lastExtension is Perl's /\.([^.]+)$/ -- the final dot-segment, case
// preserved, empty when there is no dot.
func lastExtension(name string) string {
	i := strings.LastIndex(name, ".")
	if i < 0 || i == len(name)-1 {
		return ""
	}
	ext := name[i+1:]
	if strings.Contains(ext, ".") {
		return ""
	}
	return ext
}
