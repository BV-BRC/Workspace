// Package wsconfig reads the deployment INI consumed by the Perl Workspace
// service, so the Go download service and the Perl service stay on one source
// of truth.
//
// The Perl side reads this in WorkspaceImpl::new (WorkspaceImpl.pm:2125-2247)
// via Config::Simple, keyed by "$service.$param" where $service is
// $ENV{KB_SERVICE_NAME} defaulting to "Workspace". Note that the download
// service is started with KB_SERVICE_NAME=Workspace, so it reads the
// [Workspace] section too -- there is no [WorkspaceDownload] section.
package wsconfig

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// DefaultSection matches the Perl default when KB_SERVICE_NAME is unset.
const DefaultSection = "Workspace"

// DefaultDownloadLifetime is the fallback the Perl code applies when
// download-lifetime is absent or falsy (WorkspaceImpl.pm:1539-1544).
const DefaultDownloadLifetime = time.Hour

// Config holds the subset of the [Workspace] section the download service uses.
type Config struct {
	// DBPath is the on-disk root for non-Shock objects, already normalized the
	// way Perl normalizes it (see normalizeDBPath).
	DBPath string

	MongoHost     string
	MongoDatabase string
	MongoUser     string
	MongoPassword string

	// DownloadLifetime backs both the auth-cookie expiry and the cookie Max-Age.
	DownloadLifetime time.Duration

	// WSUser/WSPassword are the service account used to grant Shock read ACLs.
	WSUser     string
	WSPassword string

	ShockURL string
}

// Load reads path and extracts the given section. An empty section means
// DefaultSection.
func Load(path, section string) (*Config, error) {
	if section == "" {
		section = DefaultSection
	}

	raw, err := parseINI(path)
	if err != nil {
		return nil, err
	}
	vals := raw[section]
	if vals == nil {
		return nil, fmt.Errorf("wsconfig: no [%s] section in %s", section, path)
	}

	cfg := &Config{
		DBPath:        normalizeDBPath(vals["db-path"]),
		MongoHost:     vals["mongodb-host"],
		MongoDatabase: vals["mongodb-database"],
		MongoUser:     vals["mongodb-user"],
		MongoPassword: vals["mongodb-pwd"],
		WSUser:        vals["wsuser"],
		WSPassword:    vals["wspassword"],
		ShockURL:      vals["shock-url"],
	}

	// Perl defaults these in _validateargs (WorkspaceImpl.pm:2184-2193).
	if cfg.MongoHost == "" {
		cfg.MongoHost = "localhost"
	}
	if cfg.MongoDatabase == "" {
		cfg.MongoDatabase = "P3Workspace"
	}

	cfg.DownloadLifetime = DefaultDownloadLifetime
	if s := vals["download-lifetime"]; s != "" {
		secs, err := strconv.Atoi(s)
		if err != nil {
			return nil, fmt.Errorf("wsconfig: download-lifetime %q is not an integer: %w", s, err)
		}
		// Perl treats a falsy value (0) as absent and falls back to the default.
		if secs > 0 {
			cfg.DownloadLifetime = time.Duration(secs) * time.Second
		}
	}

	if cfg.DBPath == "" {
		return nil, fmt.Errorf("wsconfig: db-path is required in [%s] of %s", section, path)
	}
	return cfg, nil
}

// normalizeDBPath reproduces the Perl transformation exactly: append "/P3WSDB/"
// (WorkspaceImpl.pm:2182), collapse doubled slashes, then strip any trailing
// slash (:2216-2217). A configured "/mnt/workspace" becomes
// "/mnt/workspace/P3WSDB".
//
// Note Perl's s{//}{/}g is a single non-global-overlapping pass, but since the
// only doubling it can introduce is the one from the concatenation above,
// strings.ReplaceAll is equivalent for real inputs.
func normalizeDBPath(p string) string {
	if p == "" {
		return ""
	}
	p += "/P3WSDB/"
	p = strings.ReplaceAll(p, "//", "/")
	return strings.TrimRight(p, "/")
}

// parseINI reads a Config::Simple-style INI: [section] headers, key = value
// pairs, and ';' or '#' comments. It applies two Perl-side conventions:
// the literal string "null" means unset, and an empty value means unset.
func parseINI(path string) (map[string]map[string]string, error) {
	fh, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("wsconfig: %w", err)
	}
	defer fh.Close()

	out := map[string]map[string]string{}
	section := ""

	sc := bufio.NewScanner(fh)
	for lineNo := 1; sc.Scan(); lineNo++ {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.TrimSpace(line[1 : len(line)-1])
			if out[section] == nil {
				out[section] = map[string]string{}
			}
			continue
		}
		key, val, found := strings.Cut(line, "=")
		if !found {
			return nil, fmt.Errorf("wsconfig: %s:%d: expected 'key = value', got %q", path, lineNo, line)
		}
		key = strings.TrimSpace(key)
		val = strings.TrimSpace(val)
		if val == "null" {
			// Perl maps the literal "null" to undef; deploy.cfg relies on this
			// for mongodb-user/mongodb-pwd.
			val = ""
		}
		if section == "" {
			return nil, fmt.Errorf("wsconfig: %s:%d: key %q outside any section", path, lineNo, key)
		}
		out[section][key] = val
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("wsconfig: reading %s: %w", path, err)
	}
	return out, nil
}

// MongoURI builds a connection string from the discrete fields Perl keeps
// separate. Credentials are only applied when both are set, matching
// WorkspaceImpl.pm:2205-2208.
func (c *Config) MongoURI() string {
	host := c.MongoHost
	if !strings.Contains(host, ":") {
		host += ":27017"
	}
	if c.MongoUser != "" && c.MongoPassword != "" {
		return fmt.Sprintf("mongodb://%s:%s@%s/%s",
			c.MongoUser, c.MongoPassword, host, c.MongoDatabase)
	}
	return fmt.Sprintf("mongodb://%s", host)
}
