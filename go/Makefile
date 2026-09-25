# Makefile for the Go components: the p3-mount-ws FUSE driver and the
# ws-download service.

VERSION := 1.0.0
BINARY := p3-mount-ws
OUTDIR := bin
GOFLAGS := -ldflags="-s -w"

# The download service is pure Go. Building it with CGO_ENABLED=0 keeps it
# independent of the FUSE/cgo toolchain the mount driver needs, so it can be
# built and cross-compiled anywhere and ships as a static binary.
SERVER_BINARY := ws-download
SERVER_PKG := ./cmd/ws-download
SERVER_FLAGS := -ldflags="-s -w -X main.version=$(VERSION)"
SERVER_PKGS := ./cmd/ws-download/... ./internal/dlservice/... ./internal/dlstore/... ./internal/wsconfig/...

.PHONY: all build clean linux darwin windows test deps help \
        server server-linux-amd64 server-linux-arm64 test-server

# Default target - build for current platform
all: build

# Build for current platform
build:
	@echo "Building for current platform..."
	go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY) ./cmd/p3-mount-ws

# --- ws-download service ----------------------------------------------------

# Build the download service for the current platform.
server:
	@echo "Building $(SERVER_BINARY)..."
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=0 go build $(SERVER_FLAGS) -o $(OUTDIR)/$(SERVER_BINARY) $(SERVER_PKG)

# Deployment targets. No CGO means these cross-compile with no toolchain setup.
server-linux-amd64:
	@echo "Building $(SERVER_BINARY) for Linux amd64..."
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(SERVER_FLAGS) -o $(OUTDIR)/$(SERVER_BINARY)-linux-amd64 $(SERVER_PKG)

server-linux-arm64:
	@echo "Building $(SERVER_BINARY) for Linux arm64..."
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(SERVER_FLAGS) -o $(OUTDIR)/$(SERVER_BINARY)-linux-arm64 $(SERVER_PKG)

# Test only the server packages. Plain `make test` runs ./... which pulls in
# internal/fuse and therefore needs FUSE headers and a C toolchain; this target
# runs anywhere.
test-server:
	@echo "Testing $(SERVER_BINARY) packages..."
	CGO_ENABLED=0 go test $(SERVER_PKGS)

# Download dependencies
deps:
	@echo "Downloading dependencies..."
	go mod download
	go mod tidy

# Run tests
test:
	@echo "Running tests..."
	go test -v ./...

# Linux builds (amd64 and arm64)
# CGO is required for cgofuse. Native builds work; cross-compilation needs target toolchain.
linux: linux-amd64 linux-arm64

linux-amd64:
	@echo "Building for Linux amd64..."
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY)-linux-amd64 ./cmd/p3-mount-ws

linux-arm64:
	@echo "Building for Linux arm64..."
	@echo "Note: Cross-compiling requires aarch64-linux-gnu-gcc toolchain"
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=1 GOOS=linux GOARCH=arm64 CC=aarch64-linux-gnu-gcc go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY)-linux-arm64 ./cmd/p3-mount-ws

# macOS builds (amd64 and arm64)
# Note: cgofuse requires CGO. Cross-compilation needs the target platform's
# FUSE headers and toolchain. These targets work best when run on macOS.
darwin: darwin-amd64 darwin-arm64

darwin-amd64:
	@echo "Building for macOS amd64..."
	@echo "Note: Cross-compiling FUSE requires target platform. Build on macOS for best results."
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY)-darwin-amd64 ./cmd/p3-mount-ws

darwin-arm64:
	@echo "Building for macOS arm64 (Apple Silicon)..."
	@echo "Note: Cross-compiling FUSE requires target platform. Build on macOS for best results."
	@mkdir -p $(OUTDIR)
	CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY)-darwin-arm64 ./cmd/p3-mount-ws

# Windows build (requires CGO for WinFsp)
# Note: Cross-compilation from Linux requires mingw-w64
windows: windows-amd64

windows-amd64:
	@echo "Building for Windows amd64..."
	@echo "Note: Windows builds require CGO. Cross-compiling from Linux needs mingw-w64."
	@mkdir -p $(OUTDIR)
ifneq ($(shell uname -s),Windows_NT)
	# Cross-compiling from Unix
	CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY)-windows-amd64.exe ./cmd/p3-mount-ws
else
	# Native Windows build
	set CGO_ENABLED=1&& set GOOS=windows&& set GOARCH=amd64&& go build $(GOFLAGS) -o $(OUTDIR)/$(BINARY)-windows-amd64.exe ./cmd/p3-mount-ws
endif

# Build all platforms (Linux and macOS only - Windows needs special setup)
cross: linux darwin
	@echo "Cross-compilation complete (Linux + macOS)"
	@echo "For Windows, run 'make windows' with mingw-w64 installed"

# Build all platforms including Windows
cross-all: linux darwin windows
	@echo "All platform builds complete"

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -rf $(OUTDIR)

# Install to GOPATH/bin
install: build
	@echo "Installing to GOPATH/bin..."
	cp $(OUTDIR)/$(BINARY) $(GOPATH)/bin/

# Show help
help:
	@echo "p3-mount-ws Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all           Build for current platform (default)"
	@echo "  build         Build for current platform"
	@echo "  deps          Download and tidy dependencies"
	@echo "  test          Run tests (needs FUSE headers; see test-server)"
	@echo ""
	@echo "  ws-download service (pure Go, no CGO):"
	@echo "  server              Build ws-download for the current platform"
	@echo "  server-linux-amd64  Build ws-download for Linux amd64"
	@echo "  server-linux-arm64  Build ws-download for Linux arm64"
	@echo "  test-server         Test only the ws-download packages"
	@echo ""
	@echo "  linux         Build for Linux (amd64 + arm64)"
	@echo "  linux-amd64   Build for Linux amd64"
	@echo "  linux-arm64   Build for Linux arm64"
	@echo "  darwin        Build for macOS (amd64 + arm64)"
	@echo "  darwin-amd64  Build for macOS amd64"
	@echo "  darwin-arm64  Build for macOS arm64 (Apple Silicon)"
	@echo "  windows       Build for Windows amd64 (requires mingw-w64)"
	@echo "  cross         Build for Linux + macOS"
	@echo "  cross-all     Build for all platforms (Linux + macOS + Windows)"
	@echo "  clean         Remove build artifacts"
	@echo "  install       Install to GOPATH/bin"
	@echo "  help          Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  Linux:   FUSE 3 (fuse3 package)"
	@echo "  macOS:   macFUSE (brew install macfuse)"
	@echo "  Windows: WinFsp (https://winfsp.dev/)"
