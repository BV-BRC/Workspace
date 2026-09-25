package wsconfig

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeTemp(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "deploy.cfg")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

// The real test.cfg from the repo, which exercises "null", a comment-disabled
// duplicate key, and an explicit download-lifetime.
const testCfg = `[workspace]
service-port = 7125

[Workspace]
shock-url = http://p3.theseed.org/services/shock_api
db-path = /scratch/olson/workspace
mongodb-database = WorkspaceBob
mongodb-host = localhost
mongodb-user = null
mongodb-pwd = null
wsuser = reviewer
wspassword = reviewer

download-lifetime = 10
;download-lifetime = 7200
download-url-base = http://localhost:7129
`

func TestLoadRealTestCfg(t *testing.T) {
	cfg, err := Load(writeTemp(t, testCfg), "")
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	// db-path must gain /P3WSDB and lose the trailing slash.
	if got, want := cfg.DBPath, "/scratch/olson/workspace/P3WSDB"; got != want {
		t.Errorf("DBPath = %q, want %q", got, want)
	}
	// "null" means unset, not the literal string.
	if cfg.MongoUser != "" || cfg.MongoPassword != "" {
		t.Errorf("mongo creds = %q/%q, want empty (null means unset)", cfg.MongoUser, cfg.MongoPassword)
	}
	if got, want := cfg.DownloadLifetime, 10*time.Second; got != want {
		t.Errorf("DownloadLifetime = %v, want %v", got, want)
	}
	// The ";"-commented duplicate must not win.
	if cfg.DownloadLifetime == 7200*time.Second {
		t.Error("picked up a ';'-commented line")
	}
	if got, want := cfg.MongoDatabase, "WorkspaceBob"; got != want {
		t.Errorf("MongoDatabase = %q, want %q", got, want)
	}
	// The lowercase [workspace] section must not bleed into [Workspace].
	if cfg.ShockURL != "http://p3.theseed.org/services/shock_api" {
		t.Errorf("ShockURL = %q", cfg.ShockURL)
	}
}

func TestDownloadLifetimeDefaults(t *testing.T) {
	// deploy.cfg has no download-lifetime; Perl falls back to 3600.
	cfg, err := Load(writeTemp(t, "[Workspace]\ndb-path = /mnt/ws\n"), "")
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := cfg.DownloadLifetime; got != time.Hour {
		t.Errorf("DownloadLifetime = %v, want 1h", got)
	}

	// A falsy 0 is "absent" in Perl (if (!$download_lifetime)), so it defaults too.
	cfg, err = Load(writeTemp(t, "[Workspace]\ndb-path = /mnt/ws\ndownload-lifetime = 0\n"), "")
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := cfg.DownloadLifetime; got != time.Hour {
		t.Errorf("DownloadLifetime for 0 = %v, want 1h", got)
	}
}

func TestNormalizeDBPath(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"/mnt/workspace", "/mnt/workspace/P3WSDB"},
		{"/mnt/workspace/", "/mnt/workspace/P3WSDB"},
		{"/mnt//workspace", "/mnt/workspace/P3WSDB"},
		{"", ""},
	} {
		if got := normalizeDBPath(tc.in); got != tc.want {
			t.Errorf("normalizeDBPath(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestMissingDBPathIsAnError(t *testing.T) {
	if _, err := Load(writeTemp(t, "[Workspace]\nmongodb-host = localhost\n"), ""); err == nil {
		t.Fatal("expected an error when db-path is absent")
	}
}

func TestMissingSectionIsAnError(t *testing.T) {
	if _, err := Load(writeTemp(t, "[Other]\ndb-path = /x\n"), ""); err == nil {
		t.Fatal("expected an error when the section is absent")
	}
}

func TestMongoURI(t *testing.T) {
	c := &Config{MongoHost: "localhost", MongoDatabase: "P3Workspace"}
	if got, want := c.MongoURI(), "mongodb://localhost:27017"; got != want {
		t.Errorf("MongoURI = %q, want %q", got, want)
	}

	// Credentials only when BOTH are present, matching the Perl guard.
	c.MongoUser = "u"
	if got, want := c.MongoURI(), "mongodb://localhost:27017"; got != want {
		t.Errorf("MongoURI with only a user = %q, want %q", got, want)
	}
	c.MongoPassword = "p"
	if got, want := c.MongoURI(), "mongodb://u:p@localhost:27017/P3Workspace"; got != want {
		t.Errorf("MongoURI with creds = %q, want %q", got, want)
	}
}
