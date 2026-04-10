# Plan: Port Workspace Service to Go

Date: 2026-04-10

## Executive Summary

This document outlines a plan to port the Workspace service from Perl to Go. The existing BV-BRC-Go-SDK provides a solid foundation with authentication, JSON-RPC client infrastructure, and a partial Workspace client implementation. The goal is to create a standalone Go service that can serve as a drop-in replacement for the Perl implementation.

## Current State

### Perl Implementation

The current Workspace service (`lib/Bio/P3/Workspace/WorkspaceImpl.pm`) is a ~5000-line Perl module providing:

**Public API Methods** (from `Workspace.spec`):
- `create` - Create objects, directories, and upload nodes
- `get` - Retrieve objects and their data
- `ls` - List directory contents
- `copy` - Copy/move objects
- `delete` - Delete objects and directories
- `update_metadata` - Update object metadata
- `update_auto_meta` - Update auto-generated metadata (post-upload)
- `set_permissions` - Set workspace permissions
- `list_permissions` - List workspace permissions
- `get_download_url` - Generate temporary download URLs
- `get_archive_url` - Generate archive download URLs
- `du` - Compute disk usage
- `objects_exist` - Check if objects exist

**Internal Components**:
- MongoDB integration for metadata storage
- Shock/S3/Filesystem integration for file storage
- Permission system (owner, read, write, admin, global)
- Path parsing and validation
- Auto-metadata generation for various file types
- Workspace caching

### Go SDK Foundation

The `BV-BRC-Go-SDK` already provides:

| Component | Status | Notes |
|-----------|--------|-------|
| `auth/token.go` | Complete | Token parsing, validation, source chain |
| `auth/login.go` | Complete | Interactive login |
| `workspace/client.go` | Partial | Client-side operations: `Ls`, `Get`, `Create`, `Delete`, `Copy`, `Mkdir`, `Cat` |
| `appservice/client.go` | Complete | Full AppService client (reference for pattern) |
| JSON-RPC infrastructure | Complete | Request/response handling, error extraction |
| CLI commands | Partial | `p3-ls`, `p3-mkdir`, `p3-rm`, `p3-cp`, `p3-cat` |

## Architecture

### Proposed Package Structure

```
workspace-go/
├── cmd/
│   └── workspace-server/
│       └── main.go                # Server entry point
├── internal/
│   ├── server/
│   │   ├── server.go              # HTTP server, JSON-RPC dispatcher
│   │   ├── handlers.go            # RPC method handlers
│   │   └── middleware.go          # Auth, logging, metrics
│   ├── service/
│   │   ├── workspace.go           # Core business logic
│   │   ├── permissions.go         # Permission checking
│   │   ├── paths.go               # Path parsing and validation
│   │   ├── metadata.go            # Auto-metadata generation
│   │   └── errors.go              # Domain errors
│   ├── storage/
│   │   ├── storage.go             # Storage interface
│   │   ├── s3.go                  # S3 implementation
│   │   ├── filesystem.go          # Direct filesystem implementation
│   │   └── shock.go               # Legacy Shock support (read-only)
│   └── db/
│       ├── mongo.go               # MongoDB client wrapper
│       ├── objects.go             # Object collection operations
│       └── workspaces.go          # Workspace collection operations
├── pkg/
│   └── types/
│       ├── object.go              # ObjectMeta, etc.
│       └── params.go              # API parameter types
├── config/
│   └── config.go                  # Configuration loading
└── go.mod
```

### Integration with BV-BRC-Go-SDK

The new service will:
1. **Import `auth` package** from SDK for token validation
2. **Share type definitions** with SDK's `workspace` package
3. **Follow same JSON-RPC patterns** as SDK's `appservice` client

The SDK's `workspace/client.go` can be updated to point to the new Go server.

## Core Components

### 1. JSON-RPC Server

The Perl service uses JSON-RPC 1.1 over HTTP. The Go server will implement the same protocol:

```go
package server

import (
    "encoding/json"
    "net/http"
)

type RPCRequest struct {
    Method  string          `json:"method"`
    Params  json.RawMessage `json:"params"`
    Version string          `json:"version"`
    ID      string          `json:"id"`
}

type RPCResponse struct {
    Result interface{} `json:"result,omitempty"`
    Error  *RPCError   `json:"error,omitempty"`
    ID     string      `json:"id"`
}

type RPCError struct {
    Code    int         `json:"code"`
    Message string      `json:"message"`
    Error   interface{} `json:"error,omitempty"`
}

type Server struct {
    service  *service.Workspace
    handlers map[string]HandlerFunc
}

type HandlerFunc func(ctx context.Context, params json.RawMessage) (interface{}, error)

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // Parse request
    var req RPCRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeError(w, req.ID, -32700, "Parse error")
        return
    }

    // Extract auth token
    token := r.Header.Get("Authorization")
    ctx := auth.WithToken(r.Context(), token)

    // Dispatch to handler
    handler, ok := s.handlers[req.Method]
    if !ok {
        writeError(w, req.ID, -32601, "Method not found")
        return
    }

    result, err := handler(ctx, req.Params)
    if err != nil {
        writeError(w, req.ID, -32000, err.Error())
        return
    }

    writeResult(w, req.ID, result)
}
```

### 2. MongoDB Integration

Use the official MongoDB Go driver:

```go
package db

import (
    "context"
    "time"

    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
    "go.mongodb.org/mongo-driver/bson"
)

type MongoDB struct {
    client   *mongo.Client
    database *mongo.Database
    objects  *mongo.Collection
}

func New(uri, database string) (*MongoDB, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    opts := options.Client().ApplyURI(uri)
    opts.SetReadPreference(readpref.PrimaryPreferred())

    client, err := mongo.Connect(ctx, opts)
    if err != nil {
        return nil, err
    }

    db := client.Database(database)
    return &MongoDB{
        client:   client,
        database: db,
        objects:  db.Collection("objects"),
    }, nil
}

// Object represents a workspace object in MongoDB
type Object struct {
    ID             string            `bson:"uuid"`
    Name           string            `bson:"name"`
    Type           string            `bson:"type"`
    Path           string            `bson:"path"`
    Owner          string            `bson:"owner"`
    Size           int64             `bson:"size"`
    CreationTime   time.Time         `bson:"creation_date"`
    WorkspaceUUID  string            `bson:"workspace_uuid"`
    Shock          int               `bson:"shock"`
    ShockNode      string            `bson:"shocknode"`
    UserMetadata   map[string]string `bson:"metadata"`
    AutoMetadata   map[string]string `bson:"autometadata"`
}

func (m *MongoDB) GetObject(ctx context.Context, path string) (*Object, error) {
    var obj Object
    err := m.objects.FindOne(ctx, bson.M{"path": path}).Decode(&obj)
    if err == mongo.ErrNoDocuments {
        return nil, ErrNotFound
    }
    return &obj, err
}

func (m *MongoDB) ListObjects(ctx context.Context, path string, recursive bool) ([]*Object, error) {
    filter := bson.M{}
    if recursive {
        filter["path"] = bson.M{"$regex": "^" + regexp.QuoteMeta(path)}
    } else {
        filter["path"] = path
    }

    cursor, err := m.objects.Find(ctx, filter)
    if err != nil {
        return nil, err
    }
    defer cursor.Close(ctx)

    var objects []*Object
    if err := cursor.All(ctx, &objects); err != nil {
        return nil, err
    }
    return objects, nil
}
```

### 3. Storage Interface

Abstract storage backend to support multiple implementations:

```go
package storage

import (
    "context"
    "io"
)

// Store defines the interface for file storage backends
type Store interface {
    // CreateNode creates a new storage node and returns its ID
    CreateNode(ctx context.Context) (string, error)

    // Write writes data to a storage node, returning size and checksum
    Write(ctx context.Context, nodeID string, r io.Reader) (size int64, md5 string, err error)

    // Read returns a reader for the given node
    Read(ctx context.Context, nodeID string) (io.ReadCloser, error)

    // ReadRange returns a reader for a byte range
    ReadRange(ctx context.Context, nodeID string, offset, length int64) (io.ReadCloser, error)

    // Delete removes a storage node
    Delete(ctx context.Context, nodeID string) error

    // Stat returns metadata for a storage node
    Stat(ctx context.Context, nodeID string) (*NodeInfo, error)

    // Exists checks if a node exists
    Exists(ctx context.Context, nodeID string) (bool, error)
}

type NodeInfo struct {
    Size         int64
    MD5          string
    LastModified time.Time
}

// URLFromNodeRef extracts storage info from a shocknode URL
// Supports: s3://bucket/key, http://shock/node/uuid, file:///path
func ParseNodeRef(ref string) (scheme, location string, err error) {
    u, err := url.Parse(ref)
    if err != nil {
        return "", "", err
    }
    return u.Scheme, u.Host + u.Path, nil
}
```

### 4. S3 Storage Implementation

```go
package storage

import (
    "context"
    "crypto/md5"
    "encoding/hex"
    "fmt"
    "io"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "github.com/google/uuid"
)

type S3Store struct {
    client     *s3.Client
    bucket     string
    prefix     string
}

func NewS3Store(client *s3.Client, bucket, prefix string) *S3Store {
    return &S3Store{
        client: client,
        bucket: bucket,
        prefix: prefix,
    }
}

func (s *S3Store) CreateNode(ctx context.Context) (string, error) {
    return uuid.New().String(), nil
}

func (s *S3Store) key(nodeID string) string {
    // Hierarchical key: prefix/aa/bb/cc/uuid
    return fmt.Sprintf("%s/%s/%s/%s/%s",
        s.prefix,
        nodeID[0:2],
        nodeID[2:4],
        nodeID[4:6],
        nodeID,
    )
}

func (s *S3Store) Write(ctx context.Context, nodeID string, r io.Reader) (int64, string, error) {
    // For large files, use multipart upload
    // For small files, buffer and upload directly
    
    // Calculate MD5 while reading
    hash := md5.New()
    tee := io.TeeReader(r, hash)
    
    // Read all data (for simple implementation; use multipart for large files)
    data, err := io.ReadAll(tee)
    if err != nil {
        return 0, "", err
    }
    
    _, err = s.client.PutObject(ctx, &s3.PutObjectInput{
        Bucket:      aws.String(s.bucket),
        Key:         aws.String(s.key(nodeID)),
        Body:        bytes.NewReader(data),
        ContentType: aws.String("application/octet-stream"),
    })
    if err != nil {
        return 0, "", err
    }
    
    return int64(len(data)), hex.EncodeToString(hash.Sum(nil)), nil
}

func (s *S3Store) Read(ctx context.Context, nodeID string) (io.ReadCloser, error) {
    result, err := s.client.GetObject(ctx, &s3.GetObjectInput{
        Bucket: aws.String(s.bucket),
        Key:    aws.String(s.key(nodeID)),
    })
    if err != nil {
        return nil, err
    }
    return result.Body, nil
}

func (s *S3Store) ReadRange(ctx context.Context, nodeID string, offset, length int64) (io.ReadCloser, error) {
    rangeHeader := fmt.Sprintf("bytes=%d-%d", offset, offset+length-1)
    
    result, err := s.client.GetObject(ctx, &s3.GetObjectInput{
        Bucket: aws.String(s.bucket),
        Key:    aws.String(s.key(nodeID)),
        Range:  aws.String(rangeHeader),
    })
    if err != nil {
        return nil, err
    }
    return result.Body, nil
}
```

### 5. Permission System

```go
package service

import "context"

type Permission string

const (
    PermNone   Permission = "n"
    PermRead   Permission = "r"
    PermWrite  Permission = "w"
    PermAdmin  Permission = "a"
    PermOwner  Permission = "o"
    PermPublic Permission = "p"
)

// PermissionChecker validates user permissions on workspace objects
type PermissionChecker struct {
    db         *db.MongoDB
    adminUsers map[string]bool
}

func (p *PermissionChecker) CheckPermission(ctx context.Context, path string, required Permission) error {
    user := auth.UserFromContext(ctx)
    if user == "" {
        // Anonymous user
        if required == PermRead {
            return p.checkGlobalRead(ctx, path)
        }
        return ErrAuthRequired
    }

    // Admin users bypass permission checks
    if p.adminUsers[user] {
        return nil
    }

    ws, err := p.getWorkspace(ctx, path)
    if err != nil {
        return err
    }

    // Owner has full access
    if ws.Owner == user {
        return nil
    }

    // Check user-specific permissions
    if perm, ok := ws.Permissions[user]; ok {
        if p.satisfies(perm, required) {
            return nil
        }
    }

    // Check global permissions
    if p.satisfies(ws.GlobalPermission, required) {
        return nil
    }

    return ErrPermissionDenied
}

func (p *PermissionChecker) satisfies(have, need Permission) bool {
    order := map[Permission]int{
        PermNone:  0,
        PermRead:  1,
        PermWrite: 2,
        PermAdmin: 3,
        PermOwner: 4,
    }
    return order[have] >= order[need]
}
```

### 6. Path Parsing

Port the Perl `_parse_ws_path` logic:

```go
package service

import (
    "errors"
    "regexp"
    "strings"
)

var (
    ErrInvalidPath     = errors.New("invalid workspace path")
    ErrInvalidUsername = errors.New("invalid username in path")
)

// ParsedPath represents a parsed workspace path
type ParsedPath struct {
    Owner         string   // Username that owns the workspace
    Workspace     string   // Workspace name
    ObjectPath    string   // Path within workspace (e.g., "/folder/file")
    FullPath      string   // Complete path
    PathParts     []string // Individual path components
    IsWorkspace   bool     // True if path is a workspace root
}

// ParsePath parses a workspace path like "/user@domain/workspace/folder/file"
func ParsePath(path string) (*ParsedPath, error) {
    if !strings.HasPrefix(path, "/") {
        return nil, ErrInvalidPath
    }

    // Normalize path (remove trailing slash, double slashes)
    path = normalizePath(path)

    parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
    if len(parts) == 0 {
        return nil, ErrInvalidPath
    }

    result := &ParsedPath{
        FullPath:  path,
        PathParts: parts,
    }

    // First component is owner
    result.Owner = parts[0]
    if !isValidUsername(result.Owner) {
        return nil, ErrInvalidUsername
    }

    if len(parts) >= 2 {
        result.Workspace = parts[1]
        result.IsWorkspace = len(parts) == 2
    }

    if len(parts) > 2 {
        result.ObjectPath = "/" + strings.Join(parts[2:], "/")
    }

    return result, nil
}

var usernameRegex = regexp.MustCompile(`^[a-zA-Z0-9._-]+(@[a-zA-Z0-9.-]+)?$`)

func isValidUsername(username string) bool {
    return usernameRegex.MatchString(username)
}

func normalizePath(path string) string {
    // Remove double slashes
    for strings.Contains(path, "//") {
        path = strings.ReplaceAll(path, "//", "/")
    }
    // Remove trailing slash (except for root)
    if len(path) > 1 && strings.HasSuffix(path, "/") {
        path = path[:len(path)-1]
    }
    return path
}
```

### 7. Auto-Metadata Generation

The Perl implementation computes auto-metadata based on file type. Port key formats:

```go
package service

import (
    "bufio"
    "io"
    "strings"
)

type MetadataGenerator struct{}

// ComputeAutoMetadata generates automatic metadata based on file type and content
func (m *MetadataGenerator) ComputeAutoMetadata(objType string, r io.Reader) (map[string]string, error) {
    meta := make(map[string]string)

    switch objType {
    case "txt", "unspecified":
        return m.textMetadata(r)
    case "fasta", "feature_dna_fasta", "feature_protein_fasta":
        return m.fastaMetadata(r)
    case "fastq":
        return m.fastqMetadata(r)
    case "gff":
        return m.gffMetadata(r)
    case "json":
        return m.jsonMetadata(r)
    // Add other types...
    }

    return meta, nil
}

func (m *MetadataGenerator) textMetadata(r io.Reader) (map[string]string, error) {
    scanner := bufio.NewScanner(r)
    lineCount := 0
    for scanner.Scan() {
        lineCount++
    }
    return map[string]string{
        "linecount": fmt.Sprintf("%d", lineCount),
    }, scanner.Err()
}

func (m *MetadataGenerator) fastaMetadata(r io.Reader) (map[string]string, error) {
    scanner := bufio.NewScanner(r)
    seqCount := 0
    totalLength := 0
    
    for scanner.Scan() {
        line := scanner.Text()
        if strings.HasPrefix(line, ">") {
            seqCount++
        } else {
            totalLength += len(strings.TrimSpace(line))
        }
    }
    
    return map[string]string{
        "sequence_count": fmt.Sprintf("%d", seqCount),
        "total_length":   fmt.Sprintf("%d", totalLength),
    }, scanner.Err()
}
```

## API Implementation

### Method Handlers

```go
package server

import (
    "context"
    "encoding/json"
)

func (s *Server) registerHandlers() {
    s.handlers = map[string]HandlerFunc{
        "Workspace.create":           s.handleCreate,
        "Workspace.get":              s.handleGet,
        "Workspace.ls":               s.handleLs,
        "Workspace.copy":             s.handleCopy,
        "Workspace.delete":           s.handleDelete,
        "Workspace.update_metadata":  s.handleUpdateMetadata,
        "Workspace.update_auto_meta": s.handleUpdateAutoMeta,
        "Workspace.set_permissions":  s.handleSetPermissions,
        "Workspace.list_permissions": s.handleListPermissions,
        "Workspace.get_download_url": s.handleGetDownloadURL,
        "Workspace.get_archive_url":  s.handleGetArchiveURL,
        "Workspace.du":               s.handleDu,
        "Workspace.objects_exist":    s.handleObjectsExist,
    }
}

func (s *Server) handleLs(ctx context.Context, params json.RawMessage) (interface{}, error) {
    var p struct {
        Paths               []string            `json:"paths"`
        ExcludeDirectories  bool                `json:"excludeDirectories"`
        ExcludeObjects      bool                `json:"excludeObjects"`
        Recursive           bool                `json:"recursive"`
        FullHierarchical    bool                `json:"fullHierachicalOutput"`
        Query               map[string][]string `json:"query"`
        AdminMode           bool                `json:"adminmode"`
    }
    
    // Params come wrapped in array: [{...}]
    var wrapper []json.RawMessage
    if err := json.Unmarshal(params, &wrapper); err != nil {
        return nil, err
    }
    if len(wrapper) > 0 {
        if err := json.Unmarshal(wrapper[0], &p); err != nil {
            return nil, err
        }
    }

    result, err := s.service.Ls(ctx, service.LsParams{
        Paths:              p.Paths,
        ExcludeDirectories: p.ExcludeDirectories,
        ExcludeObjects:     p.ExcludeObjects,
        Recursive:          p.Recursive,
        FullHierarchical:   p.FullHierarchical,
        Query:              p.Query,
        AdminMode:          p.AdminMode,
    })
    if err != nil {
        return nil, err
    }

    // Return wrapped in array like Perl does
    return []interface{}{result}, nil
}

func (s *Server) handleCreate(ctx context.Context, params json.RawMessage) (interface{}, error) {
    var p struct {
        Objects           [][]interface{} `json:"objects"`
        Permission        string          `json:"permission"`
        CreateUploadNodes bool            `json:"createUploadNodes"`
        Overwrite         bool            `json:"overwrite"`
        AdminMode         bool            `json:"adminmode"`
        SetOwner          string          `json:"setowner"`
    }
    
    var wrapper []json.RawMessage
    if err := json.Unmarshal(params, &wrapper); err != nil {
        return nil, err
    }
    if len(wrapper) > 0 {
        if err := json.Unmarshal(wrapper[0], &p); err != nil {
            return nil, err
        }
    }

    // Parse objects array: [[path, type, metadata, data, creation_time], ...]
    objects := make([]service.CreateObject, len(p.Objects))
    for i, obj := range p.Objects {
        objects[i] = parseCreateObject(obj)
    }

    result, err := s.service.Create(ctx, service.CreateParams{
        Objects:           objects,
        Permission:        p.Permission,
        CreateUploadNodes: p.CreateUploadNodes,
        Overwrite:         p.Overwrite,
        AdminMode:         p.AdminMode,
        SetOwner:          p.SetOwner,
    })
    if err != nil {
        return nil, err
    }

    return []interface{}{result}, nil
}
```

## File Upload Handling

The current Perl implementation supports two upload modes:
1. **Inline data** in `create` call (small files)
2. **Shock upload** using returned `shockurl` (large files)

For the Go service with S3 backend:

```go
package server

import (
    "io"
    "net/http"
)

// Upload endpoint: POST /upload/{uuid}
func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
    nodeID := chi.URLParam(r, "uuid")
    
    // Validate token and get user
    token := r.Header.Get("Authorization")
    user, err := s.auth.ValidateToken(token)
    if err != nil {
        http.Error(w, "Unauthorized", http.StatusUnauthorized)
        return
    }

    // Verify user has permission to write to this node
    if err := s.service.ValidateUploadPermission(r.Context(), user, nodeID); err != nil {
        http.Error(w, "Forbidden", http.StatusForbidden)
        return
    }

    // Handle multipart upload
    file, header, err := r.FormFile("upload")
    if err != nil {
        http.Error(w, "Bad request", http.StatusBadRequest)
        return
    }
    defer file.Close()

    // Write to storage
    size, md5, err := s.storage.Write(r.Context(), nodeID, file)
    if err != nil {
        http.Error(w, "Storage error", http.StatusInternalServerError)
        return
    }

    // Update object metadata in MongoDB
    if err := s.service.UpdateObjectAfterUpload(r.Context(), nodeID, size, md5, header.Filename); err != nil {
        http.Error(w, "Database error", http.StatusInternalServerError)
        return
    }

    // Return success
    json.NewEncoder(w).Encode(map[string]interface{}{
        "status": "ok",
        "size":   size,
        "md5":    md5,
    })
}

// Download endpoint: GET /download/{uuid}
func (s *Server) handleDownload(w http.ResponseWriter, r *http.Request) {
    nodeID := chi.URLParam(r, "uuid")

    // Check permissions (may allow public read)
    if err := s.service.ValidateReadPermission(r.Context(), nodeID); err != nil {
        http.Error(w, "Forbidden", http.StatusForbidden)
        return
    }

    // Handle range requests
    rangeHeader := r.Header.Get("Range")
    if rangeHeader != "" {
        s.handleRangeDownload(w, r, nodeID, rangeHeader)
        return
    }

    // Get file info
    info, err := s.storage.Stat(r.Context(), nodeID)
    if err != nil {
        http.Error(w, "Not found", http.StatusNotFound)
        return
    }

    // Stream file
    reader, err := s.storage.Read(r.Context(), nodeID)
    if err != nil {
        http.Error(w, "Storage error", http.StatusInternalServerError)
        return
    }
    defer reader.Close()

    w.Header().Set("Content-Length", fmt.Sprintf("%d", info.Size))
    w.Header().Set("Content-Type", "application/octet-stream")
    io.Copy(w, reader)
}
```

## Configuration

```go
package config

import (
    "os"

    "github.com/kelseyhightower/envconfig"
)

type Config struct {
    // Server
    Port    int    `envconfig:"PORT" default:"7125"`
    BaseURL string `envconfig:"BASE_URL" default:"http://localhost:7125"`

    // MongoDB
    MongoURI      string `envconfig:"MONGODB_URI" required:"true"`
    MongoDatabase string `envconfig:"MONGODB_DATABASE" default:"Workspace"`

    // Storage
    StorageBackend string `envconfig:"STORAGE_BACKEND" default:"s3"` // s3, filesystem, shock

    // S3
    S3Endpoint  string `envconfig:"S3_ENDPOINT"`
    S3Bucket    string `envconfig:"S3_BUCKET"`
    S3Prefix    string `envconfig:"S3_PREFIX"`
    S3AccessKey string `envconfig:"S3_ACCESS_KEY"`
    S3SecretKey string `envconfig:"S3_SECRET_KEY"`
    S3Region    string `envconfig:"S3_REGION" default:"us-east-1"`

    // Filesystem (legacy)
    FilestorePath string `envconfig:"FILESTORE_PATH"`

    // Shock (legacy read-only)
    ShockURL   string `envconfig:"SHOCK_URL"`
    ShockToken string `envconfig:"SHOCK_TOKEN"`

    // Auth
    AdminUsers []string `envconfig:"ADMIN_USERS"`
}

func Load() (*Config, error) {
    var cfg Config
    if err := envconfig.Process("WORKSPACE", &cfg); err != nil {
        return nil, err
    }
    return &cfg, nil
}
```

## Testing Strategy

### Unit Tests

```go
package service_test

import (
    "context"
    "testing"

    "workspace-go/internal/service"
)

func TestParsePath(t *testing.T) {
    tests := []struct {
        input    string
        wantErr  bool
        owner    string
        workspace string
    }{
        {"/user@domain/ws/folder", false, "user@domain", "ws"},
        {"/user/workspace", false, "user", "workspace"},
        {"invalid", true, "", ""},
        {"", true, "", ""},
    }

    for _, tt := range tests {
        t.Run(tt.input, func(t *testing.T) {
            result, err := service.ParsePath(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("ParsePath(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
                return
            }
            if err == nil {
                if result.Owner != tt.owner {
                    t.Errorf("Owner = %q, want %q", result.Owner, tt.owner)
                }
                if result.Workspace != tt.workspace {
                    t.Errorf("Workspace = %q, want %q", result.Workspace, tt.workspace)
                }
            }
        })
    }
}
```

### Integration Tests

Use Docker Compose to run MongoDB and MinIO for integration testing:

```yaml
# docker-compose.test.yml
version: '3.8'
services:
  mongo:
    image: mongo:5.0
    ports:
      - "27017:27017"

  minio:
    image: minio/minio
    command: server /data
    ports:
      - "9000:9000"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
```

### Compatibility Tests

Run the same test suite against both Perl and Go implementations:

```go
func TestCompatibility(t *testing.T) {
    // Test against running Perl service
    perlClient := workspace.New(
        workspace.WithURL("http://localhost:7125"), // Perl
        workspace.WithToken(testToken),
    )

    // Test against running Go service
    goClient := workspace.New(
        workspace.WithURL("http://localhost:7126"), // Go
        workspace.WithToken(testToken),
    )

    // Create same object in both
    path := fmt.Sprintf("/testuser@test/compat-test/file-%d", time.Now().Unix())

    perlResult, err := perlClient.Create(...)
    goResult, err := goClient.Create(...)

    // Compare results
    assert.Equal(t, perlResult, goResult)
}
```

## Migration Strategy

### Phase 1: Parallel Deployment (2-3 weeks)

1. Deploy Go service on different port (e.g., 7126)
2. Run both services against same MongoDB and storage
3. Route test traffic to Go service
4. Compare results between services

### Phase 2: Shadow Traffic (1-2 weeks)

1. Mirror production traffic to Go service
2. Log discrepancies without affecting users
3. Fix any compatibility issues found

### Phase 3: Gradual Cutover (1-2 weeks)

1. Route percentage of traffic to Go service
2. Monitor error rates and latency
3. Increase percentage as confidence builds

### Phase 4: Full Cutover

1. Route all traffic to Go service
2. Keep Perl service on standby
3. Decommission after stability period

## Dependencies

```go
// go.mod additions
require (
    // Existing
    github.com/spf13/cobra v1.8.0
    golang.org/x/term v0.39.0

    // New
    go.mongodb.org/mongo-driver v1.13.1
    github.com/aws/aws-sdk-go-v2 v1.24.0
    github.com/aws/aws-sdk-go-v2/service/s3 v1.47.0
    github.com/go-chi/chi/v5 v5.0.11
    github.com/kelseyhightower/envconfig v1.4.0
    github.com/google/uuid v1.5.0
    github.com/stretchr/testify v1.8.4
)
```

## Benefits

1. **Performance**: Go compiles to native code, no interpreter overhead
2. **Concurrency**: Goroutines handle concurrent requests efficiently
3. **Memory**: Lower memory footprint than Perl
4. **Type Safety**: Compile-time type checking catches errors early
5. **Deployment**: Single binary, no runtime dependencies
6. **Ecosystem**: Modern MongoDB and S3 client libraries
7. **Maintainability**: Cleaner code structure, better tooling
8. **SDK Integration**: Shared types with existing Go SDK

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Behavioral differences | Extensive compatibility testing |
| MongoDB query differences | Port exact query logic, test with production data |
| Permission edge cases | Comprehensive permission test suite |
| Auto-metadata differences | Compare output for all file types |
| Performance regressions | Benchmark critical paths |
| Deployment complexity | Containerize, use existing infrastructure |

## Timeline Estimate

| Phase | Duration | Notes |
|-------|----------|-------|
| Core infrastructure | 1 week | Server, MongoDB, config |
| Storage backends | 1 week | S3, filesystem, Shock |
| API methods (core) | 2 weeks | ls, get, create, delete, copy |
| API methods (remaining) | 1 week | permissions, du, archive |
| Upload/download endpoints | 1 week | Multipart, range requests |
| Auto-metadata | 1 week | Port file type handlers |
| Testing | 2 weeks | Unit, integration, compatibility |
| Documentation | 1 week | |
| Parallel deployment | 2 weeks | |
| Cutover | 2 weeks | |
| **Total** | **~14 weeks** | |

## Appendix: API Method Mapping

| Perl Method | Go Handler | Notes |
|-------------|------------|-------|
| `create` | `handleCreate` | Object/directory creation |
| `get` | `handleGet` | Object retrieval |
| `ls` | `handleLs` | Directory listing |
| `copy` | `handleCopy` | Copy/move operations |
| `delete` | `handleDelete` | Object deletion |
| `update_metadata` | `handleUpdateMetadata` | User metadata update |
| `update_auto_meta` | `handleUpdateAutoMeta` | Post-upload metadata |
| `set_permissions` | `handleSetPermissions` | Permission management |
| `list_permissions` | `handleListPermissions` | Permission listing |
| `get_download_url` | `handleGetDownloadURL` | Temporary URL generation |
| `get_archive_url` | `handleGetArchiveURL` | Archive URL generation |
| `du` | `handleDu` | Disk usage calculation |
| `objects_exist` | `handleObjectsExist` | Existence check |
