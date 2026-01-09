package main

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/spf13/pflag"
	cgofuse "github.com/winfsp/cgofuse/fuse"

	"github.com/BV-BRC/Workspace/go/internal/auth"
	"github.com/BV-BRC/Workspace/go/internal/cache"
	wsfuse "github.com/BV-BRC/Workspace/go/internal/fuse"
	"github.com/BV-BRC/Workspace/go/internal/workspace"
)

const (
	version    = "1.0.0"
	defaultURL = "https://p3.theseed.org/services/Workspace"
)

func main() {
	// Define flags
	foreground := pflag.BoolP("foreground", "f", false, "Run in foreground (don't daemonize)")
	debug := pflag.BoolP("debug", "d", false, "Enable debug output (implies foreground)")
	readOnly := pflag.BoolP("read-only", "r", false, "Mount as read-only filesystem")
	tempDir := pflag.String("temp-dir", "", "Directory for temporary write buffers")
	admin := pflag.BoolP("admin", "A", false, "Run in admin mode")
	url := pflag.String("url", defaultURL, "Workspace service URL")
	cacheTTL := pflag.Int("cache-ttl", 60, "Metadata cache TTL in seconds")
	showVersion := pflag.BoolP("version", "v", false, "Show version")
	help := pflag.BoolP("help", "h", false, "Show help")

	pflag.Usage = func() {
		fmt.Fprintf(os.Stderr, `p3-mount-ws - Mount a BV-BRC workspace as a filesystem

Usage:
  p3-mount-ws [options] <workspace-path> <mountpoint>

Examples:
  # Mount your home workspace (read-write)
  p3-mount-ws /user@example.org/home ~/ws-mount

  # Mount entire user directory (read-only)
  p3-mount-ws -r /user@example.org ~/ws-mount

  # Mount with debug output
  p3-mount-ws -f -d /user@example.org/home ~/ws-mount

  # Unmount
`)
		switch runtime.GOOS {
		case "windows":
			fmt.Fprintf(os.Stderr, "  net use X: /delete\n\n")
		case "darwin":
			fmt.Fprintf(os.Stderr, "  umount ~/ws-mount\n\n")
		default:
			fmt.Fprintf(os.Stderr, "  fusermount -u ~/ws-mount\n\n")
		}

		fmt.Fprintf(os.Stderr, "Options:\n")
		pflag.PrintDefaults()
	}

	pflag.Parse()

	if *showVersion {
		fmt.Printf("p3-mount-ws version %s\n", version)
		os.Exit(0)
	}

	if *help || pflag.NArg() != 2 {
		pflag.Usage()
		if *help {
			os.Exit(0)
		}
		os.Exit(1)
	}

	wsPath := pflag.Arg(0)
	mountpoint := pflag.Arg(1)

	// Debug implies foreground
	if *debug {
		*foreground = true
	}

	// Validate workspace path
	if len(wsPath) == 0 || wsPath[0] != '/' {
		fatal("Workspace path must be absolute (start with /)")
	}

	// Validate mountpoint
	if runtime.GOOS != "windows" {
		// On Unix, mountpoint must be an existing directory
		info, err := os.Stat(mountpoint)
		if err != nil {
			fatalf("Mountpoint %s does not exist: %v", mountpoint, err)
		}
		if !info.IsDir() {
			fatalf("Mountpoint %s is not a directory", mountpoint)
		}
		// Convert to absolute path
		mountpoint, err = filepath.Abs(mountpoint)
		if err != nil {
			fatalf("Cannot resolve mountpoint path: %v", err)
		}
	}

	// Load authentication token
	token, err := auth.LoadToken()
	if err != nil {
		fatal("You must be logged in via p3-login to mount a workspace.")
	}

	// Create workspace client
	client := workspace.NewClient(*url, token)
	client.AdminMode = *admin

	// Verify workspace path exists
	_, err = client.GetMetadata(wsPath)
	if err != nil {
		fatalf("Cannot access workspace path %s: %v", wsPath, err)
	}

	// Create cache
	c := cache.New()
	c.MetadataTTL = time.Duration(*cacheTTL) * time.Second
	c.DirTTL = c.MetadataTTL / 2
	c.ContentTTL = c.MetadataTTL * 5

	// Create filesystem
	fs := wsfuse.NewWorkspaceFS(client, c, wsfuse.Options{
		RootPath: wsPath,
		ReadOnly: *readOnly,
		TempDir:  *tempDir,
		Debug:    *debug,
	})

	// Create FUSE host
	host := cgofuse.NewFileSystemHost(fs)

	// Build mount options
	var opts []string
	if *foreground || *debug {
		opts = append(opts, "-f")
	}
	if *debug {
		opts = append(opts, "-d")
	}

	// Platform-specific options
	switch runtime.GOOS {
	case "darwin":
		// macFUSE options
		opts = append(opts, "-o", "volname=BV-BRC Workspace")
	case "linux":
		// Linux FUSE options
		opts = append(opts, "-o", "auto_unmount")
	}

	// Handle signals
	go handleSignals(fs, host, mountpoint)

	// Print mount info
	if *foreground {
		mode := "read-write"
		if *readOnly {
			mode = "read-only"
		}
		fmt.Printf("Mounting %s on %s (%s)...\n", wsPath, mountpoint, mode)
		fmt.Printf("Press Ctrl+C to unmount, or use: ")
		switch runtime.GOOS {
		case "windows":
			fmt.Printf("net use %s /delete\n", mountpoint)
		case "darwin":
			fmt.Printf("umount %s\n", mountpoint)
		default:
			fmt.Printf("fusermount -u %s\n", mountpoint)
		}
	}

	// Mount and run
	if !host.Mount(mountpoint, opts) {
		fatal("Mount failed")
	}
}

func handleSignals(fs *wsfuse.WorkspaceFS, host *cgofuse.FileSystemHost, mountpoint string) {
	sigCh := make(chan os.Signal, 1)

	// Platform-specific signal handling
	if runtime.GOOS != "windows" {
		signal.Notify(sigCh, syscall.SIGHUP, syscall.SIGINT, syscall.SIGTERM)
	} else {
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	}

	for sig := range sigCh {
		switch sig {
		case syscall.SIGINT, syscall.SIGTERM:
			fmt.Println("\nReceived signal, unmounting...")
			host.Unmount()
			os.Exit(0)
		default:
			// SIGHUP - clear cache
			if runtime.GOOS != "windows" {
				fmt.Println("Received SIGHUP, clearing cache...")
				fs.ClearCache()
			}
		}
	}
}

func fatal(msg string) {
	fmt.Fprintf(os.Stderr, "Error: %s\n", msg)
	os.Exit(1)
}

func fatalf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", args...)
	os.Exit(1)
}
