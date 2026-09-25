package dlstore

import (
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/bson"
)

// Decoding must tolerate the two disjoint document shapes that share the
// `downloads` collection, exactly as the Perl writers emit them.
func TestDecodeSingleFileShockRecord(t *testing.T) {
	// As written by get_download_url for a Shock-backed object
	// (WorkspaceImpl.pm:3102-3167).
	raw, err := bson.Marshal(bson.D{
		{Key: "workspace_path", Value: "/u@patricbrc.org/home/x.txt"},
		{Key: "shock_node", Value: "http://shock/node/abc"},
		{Key: "user_token", Value: "un=u@patricbrc.org|sig=deadbeef"},
		{Key: "download_key", Value: "abcdefghijklmnopqrstuv"},
		{Key: "expiration_time", Value: int64(1790000000)},
		{Key: "name", Value: "x.txt"},
		{Key: "size", Value: int64(1234)},
	})
	if err != nil {
		t.Fatal(err)
	}

	var d Download
	if err := bson.Unmarshal(raw, &d); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if d.ShockNode != "http://shock/node/abc" {
		t.Errorf("ShockNode = %q", d.ShockNode)
	}
	if d.Size != 1234 || d.Name != "x.txt" {
		t.Errorf("Size/Name = %d/%q", d.Size, d.Name)
	}
	if d.FilePath != "" {
		t.Errorf("FilePath should be empty on a shock record, got %q", d.FilePath)
	}
}

func TestDecodeSingleFileLocalRecord(t *testing.T) {
	// A non-Shock record carries file_path and NO user_token -- the local
	// branch never needs one.
	raw, _ := bson.Marshal(bson.D{
		{Key: "workspace_path", Value: "/u@patricbrc.org/home/y.txt"},
		{Key: "file_path", Value: "/mnt/ws/P3WSDB/u@patricbrc.org/home//y.txt"},
		{Key: "download_key", Value: "key22charsxxxxxxxxxxxx"},
		{Key: "expiration_time", Value: int64(1790000000)},
		{Key: "name", Value: "y.txt"},
		{Key: "size", Value: int64(10)},
	})
	var d Download
	if err := bson.Unmarshal(raw, &d); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if d.FilePath == "" || d.ShockNode != "" || d.UserToken != "" {
		t.Errorf("unexpected shape: file=%q shock=%q token=%q", d.FilePath, d.ShockNode, d.UserToken)
	}
}

func TestDecodeArchiveRecord(t *testing.T) {
	// As written by get_archive_url (WorkspaceImpl.pm:3396-3407).
	raw, _ := bson.Marshal(bson.D{
		{Key: "user_token", Value: "un=u@patricbrc.org|sig=abc"},
		{Key: "user", Value: "u@patricbrc.org"},
		{Key: "archive_type", Value: "zip"},
		{Key: "archive_name", Value: "ws-archive-2026-09-25-00-00.zip"},
		{Key: "objects", Value: bson.A{"/u@patricbrc.org/home/a", "/u@patricbrc.org/home/b"}},
		{Key: "download_key", Value: "0123456789abcdef0123456789abcdef"},
		{Key: "download_signature", Value: "da39a3ee5e6b4b0d3255bfef95601890afd80709"},
		{Key: "expiration_time", Value: int64(1790000000)},
		{Key: "total_size", Value: int64(99)},
		{Key: "file_count", Value: int64(2)},
	})
	var d Download
	if err := bson.Unmarshal(raw, &d); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if len(d.Objects) != 2 {
		t.Fatalf("Objects = %v, want 2 entries", d.Objects)
	}
	if d.ArchiveName == "" || d.DownloadSignature == "" {
		t.Errorf("archive fields missing: %+v", d)
	}
	// An archive record has no name/size/file_path -- the serve path must not
	// assume those exist.
	if d.Name != "" || d.Size != 0 || d.FilePath != "" {
		t.Errorf("archive record should not carry single-file fields: %+v", d)
	}
}

func TestDownloadExpired(t *testing.T) {
	now := time.Unix(1000, 0)
	for _, tc := range []struct {
		name string
		exp  int64
		want bool
	}{
		{"past", 999, true},
		{"exactly now", 1000, false}, // strict < , matching the Perl comparison
		{"future", 1001, false},
		{"absent", 0, false}, // a record with no expiration_time never expires
	} {
		d := &Download{ExpirationTime: tc.exp}
		if got := d.Expired(now); got != tc.want {
			t.Errorf("%s: Expired(%d) = %v, want %v", tc.name, tc.exp, got, tc.want)
		}
	}
}

func TestAuthCookieExpired(t *testing.T) {
	now := time.Unix(1000, 0)
	// WorkspaceImpl.pm:1635 uses `<`, so exactly-at-expiry still passes.
	if (&AuthCookie{ExpirationTime: 1000}).Expired(now) {
		t.Error("a cookie exactly at its expiry second should still be valid")
	}
	if !(&AuthCookie{ExpirationTime: 999}).Expired(now) {
		t.Error("a cookie one second past expiry should be expired")
	}
}

func TestSweepIntervalMatchesPerl(t *testing.T) {
	if SweepInterval != 120*time.Second {
		t.Errorf("SweepInterval = %v, want 120s to match the Perl timer", SweepInterval)
	}
}
