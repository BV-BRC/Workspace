# p3-mount-ws

A cross-platform FUSE filesystem driver for BV-BRC Workspace, written in Go.

## Overview

This tool allows you to mount a BV-BRC Workspace path as a local filesystem using FUSE. Once mounted, you can access and modify workspace files using standard file operations (ls, cat, cp, mkdir, rm, etc.).

## Supported Platforms

- **Linux**: Requires FUSE 3
- **macOS**: Requires macFUSE
- **Windows**: Requires WinFsp

## Installation

### Prerequisites

#### Linux
```bash
# Ubuntu/Debian
sudo apt install fuse3

# RHEL/CentOS
sudo yum install fuse3
```

#### macOS
```bash
brew install macfuse
```

#### Windows
Download and install WinFsp from: https://winfsp.dev/

### Building from Source

```bash
cd go
make deps
make build
```

Or build for specific platforms:
```bash
make linux      # Linux (amd64 + arm64)
make darwin     # macOS (amd64 + arm64)
make windows    # Windows (requires mingw-w64 for cross-compilation)
make cross      # Linux + macOS
make cross-all  # All platforms
```

## Usage

### Basic Usage

```bash
# Login first
p3-login

# Create a mountpoint
mkdir -p ~/ws

# Mount your home workspace (read-write)
p3-mount-ws /myuser@patricbrc.org/home ~/ws

# Now use standard commands
ls ~/ws
cat ~/ws/myfile.txt
cp ~/ws/data.fasta /tmp/
echo "Hello" > ~/ws/newfile.txt
mkdir ~/ws/newfolder
```

### Unmounting

```bash
# Linux
fusermount -u ~/ws

# macOS
umount ~/ws

# Windows (if mounted as drive letter)
net use X: /delete
```

### Options

```
-f, --foreground    Run in foreground (don't daemonize)
-d, --debug         Enable debug output (implies foreground)
-r, --read-only     Mount as read-only filesystem
    --temp-dir      Directory for temporary write buffers
-A, --admin         Run in admin mode
    --url           Workspace service URL
    --cache-ttl     Metadata cache TTL in seconds (default: 60)
-v, --version       Show version
-h, --help          Show help
```

### Examples

```bash
# Mount read-only
p3-mount-ws -r /myuser@patricbrc.org/home ~/ws

# Mount with debug output (foreground)
p3-mount-ws -f -d /myuser@patricbrc.org/home ~/ws

# Mount entire user directory
p3-mount-ws /myuser@patricbrc.org ~/ws

# Windows: Mount as drive letter
p3-mount-ws.exe /myuser@patricbrc.org/home W:
```

### Clearing Cache

To clear the cache without unmounting (Linux/macOS only):
```bash
kill -HUP $(pgrep -f "p3-mount-ws.*$HOME/ws")
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Local Apps     │────▶│  p3-mount-ws     │────▶│  Workspace API  │
│  (any platform) │     │  (Go binary)     │     │  (HTTP/JSON-RPC)│
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                        ┌─────┴─────┐
                        │           │
                   ┌────▼───┐  ┌────▼───┐
                   │  Cache │  │  Temp  │
                   │ (LRU)  │  │  Dir   │
                   └────────┘  └────────┘
```

### Components

- **auth/token.go**: Authentication token loading from ~/.patric_token or environment
- **workspace/client.go**: Workspace API client (JSON-RPC)
- **workspace/shock.go**: Shock storage operations for large files
- **cache/cache.go**: LRU cache with TTL for metadata, directories, and content
- **fuse/fs.go**: FUSE filesystem implementation

### Cache Settings

- Metadata: 60s TTL, 10,000 entries max
- Directory listings: 30s TTL, 5,000 entries max
- File content: 300s TTL, 1,000 entries max

### Write Operations

Write operations use a full-file-replacement model:
1. On first write, existing file content is downloaded to a temp file
2. All writes go to the temp file
3. On close (flush), the temp file is uploaded back to workspace
4. Large files (>10KB) are stored in Shock storage

## Notes

- By default, the filesystem is mounted read-write. Use `-r` for read-only.
- Large files are streamed directly from Shock storage with range request support.
- Metadata and directory listings are cached for performance.
- Send SIGHUP to clear the cache without unmounting.
- Modified files require local temp space equal to the file size.

## See Also

- [p3-ls](../scripts/p3-ls.pl) - List workspace contents
- [p3-cat](../scripts/p3-cat.pl) - Display workspace file contents
- [p3-cp](../scripts/p3-cp.pl) - Copy files to/from workspace
