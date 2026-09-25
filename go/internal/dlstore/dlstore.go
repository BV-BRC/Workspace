// Package dlstore is the MongoDB layer for the download service.
//
// It only ever reads the two collections the Perl RPC service writes:
//
//	downloads    - written by Workspace.get_download_url (single files) and
//	               Workspace.get_archive_url (archives)
//	auth_cookie  - written by the /set-cookie-auth route
//
// The document shapes are fixed by the Perl writers (WorkspaceImpl.pm:3102-3171
// and :3396-3412), so the bson tags here are a contract, not a choice.
package dlstore

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// ErrNotFound is returned when no document matches. Callers map this to the
// route's 404; it must be distinguishable from a Mongo failure, which has to
// surface as a 500 rather than a silent "invalid path".
var ErrNotFound = errors.New("dlstore: not found")

// Download is a record in the `downloads` collection.
//
// Two disjoint shapes share this collection. A single-file record (from
// get_download_url) carries DownloadKey plus exactly one of FilePath or
// ShockNode. An archive record (from get_archive_url) carries
// DownloadSignature and Objects. Fields absent from a given shape stay zero.
type Download struct {
	// Common
	DownloadKey    string `bson:"download_key"`
	ExpirationTime int64  `bson:"expiration_time"`

	// Single-file records
	WorkspacePath string `bson:"workspace_path,omitempty"`
	Name          string `bson:"name,omitempty"`
	Size          int64  `bson:"size,omitempty"`
	FilePath      string `bson:"file_path,omitempty"`
	ShockNode     string `bson:"shock_node,omitempty"`
	UserToken     string `bson:"user_token,omitempty"`

	// Archive records
	DownloadSignature string   `bson:"download_signature,omitempty"`
	ArchiveName       string   `bson:"archive_name,omitempty"`
	ArchiveType       string   `bson:"archive_type,omitempty"`
	Objects           []string `bson:"objects,omitempty"`
	User              string   `bson:"user,omitempty"`
	TotalSize         int64    `bson:"total_size,omitempty"`
	FileCount         int64    `bson:"file_count,omitempty"`
}

// Expired reports whether the record is past its expiry.
//
// Note the Perl serve paths for /download and /archive do NOT consult this --
// expiry is enforced only by the 120s sweep, so a record stays usable for up to
// two minutes past nominal expiry. Whether to honor this is the caller's
// decision; see Server.EnforceDownloadExpiry.
func (d *Download) Expired(now time.Time) bool {
	return d.ExpirationTime > 0 && d.ExpirationTime < now.Unix()
}

// AuthCookie is a record in the `auth_cookie` collection
// (WorkspaceImpl.pm:1553-1557).
type AuthCookie struct {
	SessionToken   string `bson:"session_token"`
	ExpirationTime int64  `bson:"expiration_time"`
	AuthToken      string `bson:"auth_token"`
}

// Expired mirrors the strict `<` comparison at WorkspaceImpl.pm:1635, so a
// record exactly at its expiry second is still considered valid.
func (a *AuthCookie) Expired(now time.Time) bool {
	return a.ExpirationTime < now.Unix()
}

// Store owns the Mongo client and the two collections.
type Store struct {
	client     *mongo.Client
	downloads  *mongo.Collection
	authCookie *mongo.Collection
	log        *slog.Logger
}

// Open connects to Mongo and pings to fail fast on a bad URI or unreachable
// server, rather than deferring the error into the first request.
func Open(ctx context.Context, uri, database string, log *slog.Logger) (*Store, error) {
	opts := options.Client().
		ApplyURI(uri).
		// The Perl side uses a 120s timeout (WorkspaceImpl.pm:2189), which is
		// far too long: a slow query there blocks every download for two
		// minutes. Ten seconds is generous for these indexed point lookups.
		SetServerSelectionTimeout(10 * time.Second).
		SetConnectTimeout(10 * time.Second).
		SetMaxPoolSize(100)

	client, err := mongo.Connect(ctx, opts)
	if err != nil {
		return nil, fmt.Errorf("dlstore: connect: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := client.Ping(pingCtx, nil); err != nil {
		_ = client.Disconnect(context.Background())
		return nil, fmt.Errorf("dlstore: ping %s: %w", database, err)
	}

	db := client.Database(database)
	return &Store{
		client:     client,
		downloads:  db.Collection("downloads"),
		authCookie: db.Collection("auth_cookie"),
		log:        log,
	}, nil
}

// Close disconnects the client.
func (s *Store) Close(ctx context.Context) error { return s.client.Disconnect(ctx) }

// EnsureIndexes creates the indexes the lookup paths need.
//
// The Perl repo creates no indexes at all (there is no ensure_index anywhere),
// so in production every /download, /view and /archive request may be a full
// collection scan -- a prime suspect for the multi-second stalls this service
// was written to fix. Index creation is idempotent, so this is safe to run on
// every startup whether or not the indexes already exist.
//
// These are deliberately NOT TTL indexes: a TTL index would let Mongo expire
// records on its own schedule, changing the documented grace period. Expiry
// stays under our control in Sweeper.
func (s *Store) EnsureIndexes(ctx context.Context) error {
	specs := []struct {
		coll  *mongo.Collection
		name  string
		keys  bson.D
		extra *options.IndexOptions
	}{
		{s.downloads, "download_key_1", bson.D{{Key: "download_key", Value: 1}}, nil},
		{s.downloads, "download_signature_1", bson.D{{Key: "download_signature", Value: 1}}, nil},
		{s.downloads, "expiration_time_1", bson.D{{Key: "expiration_time", Value: 1}}, nil},
		{s.authCookie, "session_token_1", bson.D{{Key: "session_token", Value: 1}}, nil},
		{s.authCookie, "expiration_time_1", bson.D{{Key: "expiration_time", Value: 1}}, nil},
	}

	for _, spec := range specs {
		opts := spec.extra
		if opts == nil {
			opts = options.Index()
		}
		opts.SetName(spec.name)

		_, err := spec.coll.Indexes().CreateOne(ctx, mongo.IndexModel{
			Keys:    spec.keys,
			Options: opts,
		})
		if err != nil {
			return fmt.Errorf("dlstore: creating index %s on %s: %w",
				spec.name, spec.coll.Name(), err)
		}
		s.log.Debug("index ensured", "collection", spec.coll.Name(), "index", spec.name)
	}
	return nil
}

// FindByDownloadKey looks up a single-file download record.
// Mirrors WorkspaceImpl.pm:1836.
func (s *Store) FindByDownloadKey(ctx context.Context, key string) (*Download, error) {
	return s.findDownload(ctx, bson.D{{Key: "download_key", Value: key}})
}

// FindBySignature looks up an archive record.
// Mirrors WorkspaceImpl.pm:1674.
func (s *Store) FindBySignature(ctx context.Context, sig string) (*Download, error) {
	return s.findDownload(ctx, bson.D{{Key: "download_signature", Value: sig}})
}

func (s *Store) findDownload(ctx context.Context, filter bson.D) (*Download, error) {
	var d Download
	err := s.downloads.FindOne(ctx, filter).Decode(&d)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("dlstore: querying downloads: %w", err)
	}
	return &d, nil
}

// FindSession looks up an auth cookie by its session token.
// Mirrors WorkspaceImpl.pm:1628.
func (s *Store) FindSession(ctx context.Context, sessionToken string) (*AuthCookie, error) {
	var a AuthCookie
	err := s.authCookie.
		FindOne(ctx, bson.D{{Key: "session_token", Value: sessionToken}}).
		Decode(&a)
	if errors.Is(err, mongo.ErrNoDocuments) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("dlstore: querying auth_cookie: %w", err)
	}
	return &a, nil
}

// InsertSession writes a new auth cookie record.
// Mirrors WorkspaceImpl.pm:1558.
func (s *Store) InsertSession(ctx context.Context, a *AuthCookie) error {
	if _, err := s.authCookie.InsertOne(ctx, a); err != nil {
		return fmt.Errorf("dlstore: inserting auth_cookie: %w", err)
	}
	return nil
}

// SweepInterval matches the Perl AnyEvent timer (WorkspaceImpl.pm:1478).
const SweepInterval = 120 * time.Second

// Sweep deletes expired records from both collections, returning the counts in
// the same order the Perl loop uses (downloads first, then auth_cookie).
// Mirrors _download_cleanup (WorkspaceImpl.pm:1487-1508).
func (s *Store) Sweep(ctx context.Context) (downloads, cookies int64, err error) {
	now := time.Now().Unix()
	filter := bson.D{{Key: "expiration_time", Value: bson.D{{Key: "$lt", Value: now}}}}

	dres, err := s.downloads.DeleteMany(ctx, filter)
	if err != nil {
		return 0, 0, fmt.Errorf("dlstore: expiring downloads: %w", err)
	}
	cres, err := s.authCookie.DeleteMany(ctx, filter)
	if err != nil {
		return dres.DeletedCount, 0, fmt.Errorf("dlstore: expiring auth_cookie: %w", err)
	}
	return dres.DeletedCount, cres.DeletedCount, nil
}

// RunSweeper sweeps immediately (the Perl timer uses after => 0) and then every
// SweepInterval until ctx is cancelled. Unlike the Perl version this runs in its
// own goroutine, so a slow sweep cannot stall request handling.
func (s *Store) RunSweeper(ctx context.Context) {
	tick := time.NewTicker(SweepInterval)
	defer tick.Stop()

	for {
		dl, ck, err := s.Sweep(ctx)
		switch {
		case ctx.Err() != nil:
			return
		case err != nil:
			s.log.Error("expiry sweep failed", "err", err)
		case dl > 0 || ck > 0:
			s.log.Info("expired records removed", "downloads", dl, "auth_cookie", ck)
		}

		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}
