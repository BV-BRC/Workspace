// Command ws-download serves the BV-BRC Workspace download endpoints
// (/download, /view, /set-cookie-auth, /archive), replacing the Perl Twiggy
// service in lib/WorkspaceDownload.psgi.
//
// The Perl service runs a single-process event loop and performs synchronous
// Mongo and HTTP calls inside it, so one slow lookup blocks every concurrent
// download; measured at ~91% of wall-clock time stalled. Here each request is
// its own goroutine, so a slow call costs only that request.
//
// Config comes from the same deployment INI the Perl service reads, so the two
// cannot drift:
//
//	ws-download --config /kb/deployment/deployment.cfg --port 7129
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/pflag"

	"github.com/BV-BRC/Workspace/go/internal/dlservice"
	"github.com/BV-BRC/Workspace/go/internal/dlstore"
	"github.com/BV-BRC/Workspace/go/internal/wsconfig"
)

// version is stamped at build time with -X main.version=...
var version = "dev"

func main() {
	var (
		configPath = pflag.StringP("config", "c", "", "deployment INI to read (defaults to $KB_DEPLOYMENT_CONFIG)")
		section    = pflag.String("section", "", "INI section to read (defaults to $KB_SERVICE_NAME, else Workspace)")
		listen     = pflag.StringP("listen", "l", ":7129", "address to listen on")
		logLevel   = pflag.String("log-level", "info", "debug, info, warn, or error")
		skipIndex  = pflag.Bool("skip-index-creation", false, "do not create Mongo indexes at startup")
		enforceExp = pflag.Bool("enforce-download-expiry", false,
			"reject expired download keys immediately (Perl leaves this to the 120s sweep)")
		strictRange = pflag.Bool("strict-range-errors", false,
			"answer 416 for an unsatisfiable range (Perl emits a 206 with a negative Content-Length)")
		showVersion = pflag.BoolP("version", "v", false, "print the version and exit")
	)

	pflag.Usage = func() {
		fmt.Fprintf(os.Stderr, "ws-download - BV-BRC Workspace download service\n\n")
		fmt.Fprintf(os.Stderr, "Usage:\n  ws-download [options]\n\n")
		fmt.Fprintf(os.Stderr, "Examples:\n")
		fmt.Fprintf(os.Stderr, "  ws-download --config /kb/deployment/deployment.cfg\n")
		fmt.Fprintf(os.Stderr, "  ws-download -c ./test.cfg -l :7130 --log-level debug\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		pflag.PrintDefaults()
	}
	pflag.Parse()

	if *showVersion {
		fmt.Printf("ws-download %s\n", version)
		return
	}

	log := newLogger(*logLevel)

	if *configPath == "" {
		*configPath = os.Getenv("KB_DEPLOYMENT_CONFIG")
	}
	if *configPath == "" {
		fatal(log, "no config given: pass --config or set KB_DEPLOYMENT_CONFIG")
	}
	if *section == "" {
		// The Perl service is launched with KB_SERVICE_NAME=Workspace, so the
		// download service reads the [Workspace] section too.
		*section = os.Getenv("KB_SERVICE_NAME")
	}

	cfg, err := wsconfig.Load(*configPath, *section)
	if err != nil {
		fatal(log, "loading config", "err", err)
	}
	log.Info("config loaded",
		"path", *configPath,
		"db_path", cfg.DBPath,
		"mongo_host", cfg.MongoHost,
		"mongo_db", cfg.MongoDatabase,
		"download_lifetime", cfg.DownloadLifetime)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	store, err := dlstore.Open(ctx, cfg.MongoURI(), cfg.MongoDatabase, log)
	if err != nil {
		fatal(log, "connecting to mongo", "err", err)
	}
	defer func() {
		closeCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = store.Close(closeCtx)
	}()

	if !*skipIndex {
		// The Perl repo never creates these; without them every lookup is a
		// collection scan. Idempotent, so it is safe on every start.
		idxCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		err := store.EnsureIndexes(idxCtx)
		cancel()
		if err != nil {
			// Not fatal: the service still works against an unindexed
			// collection, just slowly. Better to serve than to refuse to boot.
			log.Error("could not create indexes; lookups may be slow", "err", err)
		} else {
			log.Info("mongo indexes ensured")
		}
	}

	go store.RunSweeper(ctx)

	srv := &dlservice.Server{
		Store:                 store,
		Log:                   log,
		EnforceDownloadExpiry: *enforceExp,
		StrictRangeErrors:     *strictRange,
	}

	httpSrv := &http.Server{
		Addr:    *listen,
		Handler: srv.Handler(),
		// No WriteTimeout: downloads are long-lived streams and a deadline here
		// would truncate large transfers mid-flight.
		ReadHeaderTimeout: 20 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		log.Info("listening", "addr", *listen, "version", version)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fatal(log, "serving", "err", err)
		}
	}()

	<-ctx.Done()
	log.Info("shutting down; waiting for in-flight downloads")

	// Graceful: let running transfers finish rather than truncating them.
	shutCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutCtx); err != nil {
		log.Warn("shutdown did not complete cleanly", "err", err)
	}
	log.Info("stopped")
}

func newLogger(level string) *slog.Logger {
	var l slog.Level
	switch level {
	case "debug":
		l = slog.LevelDebug
	case "warn":
		l = slog.LevelWarn
	case "error":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: l}))
}

func fatal(log *slog.Logger, msg string, args ...any) {
	log.Error(msg, args...)
	os.Exit(1)
}
