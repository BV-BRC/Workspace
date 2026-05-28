# Plan: Remove Shock Layer from Workspace Service

Date: 2026-04-10

## Executive Summary

This document outlines a plan to replace the Shock API integration in the Workspace service with direct filesystem access. The goal is to eliminate the Shock service as a dependency while maintaining backward compatibility with existing stored files. This change will reduce operational complexity, improve performance by removing HTTP overhead, and simplify the overall system architecture.

## Current Architecture

The Workspace service currently uses a two-tier storage architecture:

```
Client → Workspace API → Shock API → Filesystem
                      → MongoDB (metadata)
```

Files larger than 1000 bytes are stored in Shock, while smaller files are stored directly on the local filesystem. The Workspace service communicates with Shock via HTTP API calls for all file operations including creation, upload, download, and access control management.

### Proposed Architecture

The proposed architecture eliminates the Shock service layer:

```
Client → Workspace API → Filesystem (direct)
                      → MongoDB (metadata)
```

All file storage operations will be performed directly against the filesystem, using the same directory structure that Shock uses internally. This ensures that existing files remain accessible without migration if the Shock data directory is made available to the Workspace service.

## Understanding Shock Storage Internals

### Node ID Format

Shock identifies each stored file with a UUID version 4 identifier, which is a 36-character string in the format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. These UUIDs are generated using the `github.com/MG-RAST/golib/go-uuid/uuid` library.

### Directory Structure

Shock organizes files on disk using a hierarchical directory structure derived from the UUID. The first six characters of the UUID are used to create three levels of subdirectories, which helps distribute files across the filesystem and avoids having too many files in a single directory:

```
{PATH_DATA}/
  {id[0:2]}/           # First 2 characters of UUID
    {id[2:4]}/         # Characters 3-4 of UUID
      {id[4:6]}/       # Characters 5-6 of UUID
        {id}/          # Full UUID as directory name
          {id}.data    # Actual file content
          idx/         # Index files (optional, used for streaming formats)
            size.idx
            *.idx
```

For example, a node with ID `a1b2c3d4-e5f6-7890-abcd-ef1234567890` would be stored at:
- Directory: `{PATH_DATA}/a1/b2/c3/a1b2c3d4-e5f6-7890-abcd-ef1234567890/`
- Data file: `{PATH_DATA}/a1/b2/c3/a1b2c3d4-e5f6-7890-abcd-ef1234567890/a1b2c3d4-e5f6-7890-abcd-ef1234567890.data`

### File Metadata in Shock

Shock stores file metadata in MongoDB alongside the binary data on disk. The relevant fields in the Shock node document are:

```go
type File struct {
    Name      string            `bson:"name" json:"name"`
    Size      int64             `bson:"size" json:"size"`
    Checksum  map[string]string `bson:"checksum" json:"checksum"`  // e.g., {"md5": "..."}
    CreatedOn time.Time         `bson:"created_on" json:"created_on"`
    Path      string            `bson:"path" json:"-"`  // Alternative path for linked files
}
```

The Workspace service currently only uses the `size` field from this metadata, which it retrieves after a file upload completes.

## Current Workspace-Shock Integration

### Shock API Endpoints Used by Workspace

The Workspace service uses the following Shock API endpoints:

| Endpoint | HTTP Method | Purpose | Direct Replacement |
|----------|-------------|---------|--------------------|
| `/node` | POST | Create an empty node before upload | Generate UUID and create directory structure |
| `/node/{id}` | GET | Retrieve node metadata (file size, name) | Read file metadata via stat() system call |
| `/node/{id}?download` | GET | Download entire file content | Open and read file directly |
| `/node/{id}?download&seek=X&length=Y` | GET | Download a byte range of the file | Use pread() or seek()+read() |
| `/node/{id}` | PUT | Upload file content | Write file directly to filesystem |
| `/node/{id}/acl/*` | PUT/GET | Manage access control lists | Eliminate entirely (use Workspace permissions) |

### Workspace MongoDB Schema

The Workspace service stores Shock-related information in the `objects` collection:

```javascript
{
    "shock": 1,                    // Boolean flag: 1 if file is stored in Shock
    "shocknode": "http://host/services/shock_api/node/{uuid}",  // Full Shock URL
    "size": 12345,                 // File size in bytes
    // ... other workspace object fields
}
```

The `shocknode` field contains the complete URL to the Shock node, including the server address and node UUID.

### Code Locations Requiring Modification

The following functions in the Workspace codebase interact with Shock and will need to be updated:

| Function | File | Approximate Line | Purpose |
|----------|------|------------------|--------|
| `_create_shock_node()` | WorkspaceImpl.pm | ~767 | Creates an empty Shock node and sets ACLs |
| `_update_shock_node()` | WorkspaceImpl.pm | ~794 | Retrieves file size after upload completes |
| `_make_shock_node_public()` | WorkspaceImpl.pm | ~786 | Modifies ACLs for public workspace access |
| `_shockurl()` | WorkspaceImpl.pm | - | Returns the configured Shock URL |
| Download streaming | WorkspaceImpl.pm | ~1892 | Streams file content to HTTP response |
| Client upload | WorkspaceClientExt.pm | ~454 | Uploads files via multipart form data |
| Client download | WorkspaceClientExt.pm | ~341 | Downloads files with authentication |
| Go FUSE client | shock.go | - | Reads files with byte-range support |

## Implementation Plan

### Phase 1: Create the Direct Storage Module

The first step is to create a new Perl module that encapsulates all direct filesystem operations. This module will be self-contained and testable independently of the rest of the Workspace service.

**New file:** `lib/Bio/P3/Workspace/FileStore.pm`

This module will provide the following functionality:

```perl
package Bio::P3::Workspace::FileStore;

use strict;
use warnings;
use Data::UUID;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Digest::MD5;
use Fcntl qw(:seek);

sub new {
    my ($class, %args) = @_;
    my $self = {
        base_path => $args{base_path} || die "base_path required",
    };
    return bless $self, $class;
}

# Generate a new file ID and create the directory structure.
# Returns the UUID of the newly created node.
sub create_node {
    my ($self) = @_;
    my $uuid = Data::UUID->new->create_str();
    my $path = $self->uuid_to_path($uuid);
    make_path($path) or die "Failed to create directory $path: $!";
    return $uuid;
}

# Convert a UUID to its filesystem path.
# Uses the same algorithm as Shock: first 6 characters split into 3 directory levels.
sub uuid_to_path {
    my ($self, $uuid) = @_;
    return sprintf("%s/%s/%s/%s/%s",
        $self->{base_path},
        substr($uuid, 0, 2),
        substr($uuid, 2, 2),
        substr($uuid, 4, 2),
        $uuid
    );
}

# Get the full path to the data file for a given UUID.
sub data_file_path {
    my ($self, $uuid) = @_;
    return $self->uuid_to_path($uuid) . "/$uuid.data";
}

# Write data to a node, computing the MD5 checksum during the write.
# Accepts either a scalar reference or a filehandle.
# Returns a hashref with size and md5 fields.
sub write_file {
    my ($self, $uuid, $data_or_fh) = @_;
    
    my $file_path = $self->data_file_path($uuid);
    make_path(dirname($file_path));
    
    open(my $out_fh, '>', $file_path) or die "Cannot write to $file_path: $!";
    binmode($out_fh);
    
    my $md5 = Digest::MD5->new;
    my $size = 0;
    
    if (ref($data_or_fh) eq 'GLOB') {
        # Input is a filehandle
        while (my $bytes_read = read($data_or_fh, my $buffer, 65536)) {
            print $out_fh $buffer;
            $md5->add($buffer);
            $size += $bytes_read;
        }
    } elsif (ref($data_or_fh) eq 'SCALAR') {
        # Input is a scalar reference
        print $out_fh $$data_or_fh;
        $md5->add($$data_or_fh);
        $size = length($$data_or_fh);
    } else {
        die "write_file requires a filehandle or scalar reference";
    }
    
    close($out_fh);
    
    return {
        size => $size,
        md5 => $md5->hexdigest,
    };
}

# Open a file for reading and optionally seek to a position.
# Returns a filehandle.
sub open_file {
    my ($self, $uuid, $offset) = @_;
    
    my $file_path = $self->data_file_path($uuid);
    open(my $fh, '<', $file_path) or die "Cannot read $file_path: $!";
    binmode($fh);
    
    if (defined $offset && $offset > 0) {
        seek($fh, $offset, SEEK_SET) or die "Cannot seek in $file_path: $!";
    }
    
    return $fh;
}

# Read a portion of a file.
# Returns the data as a scalar.
sub read_file {
    my ($self, $uuid, $offset, $length) = @_;
    
    my $fh = $self->open_file($uuid, $offset);
    my $data;
    
    if (defined $length) {
        read($fh, $data, $length);
    } else {
        local $/;
        $data = <$fh>;
    }
    
    close($fh);
    return $data;
}

# Get file metadata (size, modification time).
# Returns a hashref with size and mtime fields.
sub stat_file {
    my ($self, $uuid) = @_;
    
    my $file_path = $self->data_file_path($uuid);
    my @stat = stat($file_path);
    
    if (!@stat) {
        return undef;  # File does not exist
    }
    
    return {
        size => $stat[7],
        mtime => $stat[9],
    };
}

# Delete a node and its directory.
sub delete_node {
    my ($self, $uuid) = @_;
    my $path = $self->uuid_to_path($uuid);
    remove_tree($path);
    return 1;
}

# Check if a node exists.
sub node_exists {
    my ($self, $uuid) = @_;
    my $file_path = $self->data_file_path($uuid);
    return -e $file_path;
}

1;
```

### Phase 2: Update WorkspaceImpl.pm

The main implementation file needs to be updated to support both Shock-based and direct storage modes. This will be done by adding a configuration toggle and creating wrapper functions that dispatch to the appropriate backend.

#### Step 2a: Add Configuration Options

Add the following configuration options to the `[Workspace]` section of `deploy.cfg`:

```ini
# Path to direct file storage (same structure as Shock PATH_DATA)
file-store-path = /mnt/workspace/filestore

# Toggle between Shock API and direct storage
# Set to 1 to use Shock API (existing behavior)
# Set to 0 to use direct filesystem access
use-shock = 0
```

#### Step 2b: Add Storage Node Creation

Replace or augment the `_create_shock_node()` function with a dual-mode version:

```perl
sub _create_storage_node {
    my ($self, $user) = @_;
    
    if ($self->_use_shock()) {
        # Use existing Shock integration
        return $self->_create_shock_node($user);
    }
    
    # Create node directly on filesystem
    my $uuid = $self->{_filestore}->create_node();
    
    # Return a URL-like identifier for compatibility with existing code.
    # The file:// prefix distinguishes direct storage from Shock URLs.
    return "file://" . $self->_file_store_path() . "/node/$uuid";
}
```

#### Step 2c: Add Storage Node Metadata Retrieval

Create a dual-mode version of `_update_shock_node()` that retrieves file metadata:

```perl
sub _update_storage_node {
    my ($self, $node_url) = @_;
    
    if ($node_url =~ /^http/) {
        # Legacy Shock node - use existing API call
        return $self->_update_shock_node($node_url);
    }
    
    # Direct storage node - read metadata from filesystem
    my $uuid = $self->_extract_uuid_from_url($node_url);
    my $metadata = $self->{_filestore}->stat_file($uuid);
    
    if (!$metadata) {
        $self->_error("Storage node not found: $uuid");
    }
    
    return { size => $metadata->{size} };
}

sub _extract_uuid_from_url {
    my ($self, $url) = @_;
    
    # Handle both http://host/node/{uuid} and file:///path/node/{uuid}
    if ($url =~ /node\/([a-f0-9-]{36})(?:\/|$)/i) {
        return $1;
    }
    
    $self->_error("Cannot extract UUID from URL: $url");
}
```

#### Step 2d: Add Direct File Streaming

Update the download streaming code to support direct file access:

```perl
sub _stream_file_content {
    my ($self, $node_url, $offset, $length, $writer) = @_;
    
    if ($node_url =~ /^http/) {
        # Legacy Shock node - use existing HTTP streaming
        return $self->_stream_from_shock($node_url, $offset, $length, $writer);
    }
    
    # Direct storage - stream from filesystem
    my $uuid = $self->_extract_uuid_from_url($node_url);
    my $fh = $self->{_filestore}->open_file($uuid, $offset);
    
    my $bytes_remaining = $length;  # undef means read to end
    my $buffer_size = 65536;
    
    while (1) {
        my $to_read = $buffer_size;
        if (defined $bytes_remaining) {
            $to_read = $bytes_remaining if $bytes_remaining < $to_read;
            last if $to_read <= 0;
        }
        
        my $bytes_read = read($fh, my $buffer, $to_read);
        last if !$bytes_read;
        
        $writer->write($buffer);
        $bytes_remaining -= $bytes_read if defined $bytes_remaining;
    }
    
    close($fh);
}
```

### Phase 3: Update Client Code

The Workspace client library (`WorkspaceClientExt.pm`) handles file uploads and downloads on the client side. It currently uploads files directly to Shock URLs returned by the `create()` API call.

#### Current Upload Flow

1. Client calls `create()` API with `createUploadNodes=1`
2. Server creates Shock node and returns Shock URL in response
3. Client uploads file directly to Shock URL via HTTP PUT
4. Server later retrieves file size from Shock

#### Proposed Upload Flow (Server-Side Upload)

For direct storage, the upload must go through the Workspace server since clients cannot write directly to the server's filesystem:

1. Client calls `create()` API with `createUploadNodes=1`
2. Server creates storage node and returns an upload ticket
3. Client uploads file to Workspace upload endpoint with ticket
4. Server writes file directly to filesystem
5. Server updates object metadata with file size

This requires adding a new upload endpoint to the Workspace service or modifying the existing `create()` method to accept file data directly.

### Phase 4: Update Go Client

The Go-based FUSE client (`go/internal/workspace/shock.go`) reads files with byte-range support for efficient random access. This code needs to be updated to handle direct filesystem access when running on the same host as the storage.

```go
package workspace

import (
    "fmt"
    "io"
    "os"
    "path/filepath"
    "strings"
)

// ReadFile reads file content from either Shock or direct storage.
// For Shock URLs (http://...), it uses HTTP with byte-range headers.
// For direct storage URLs (file://...), it reads directly from the filesystem.
func ReadFile(nodeURL string, offset, length int64) (io.ReadCloser, error) {
    if strings.HasPrefix(nodeURL, "http://") || strings.HasPrefix(nodeURL, "https://") {
        return readFromShock(nodeURL, offset, length)
    }
    
    if strings.HasPrefix(nodeURL, "file://") {
        return readFromFilesystem(nodeURL, offset, length)
    }
    
    return nil, fmt.Errorf("unsupported URL scheme: %s", nodeURL)
}

func readFromFilesystem(nodeURL string, offset, length int64) (io.ReadCloser, error) {
    // Parse file:// URL to extract path
    // URL format: file:///path/to/store/node/{uuid}
    path := strings.TrimPrefix(nodeURL, "file://")
    
    // Extract UUID from path
    uuid := filepath.Base(path)
    baseDir := filepath.Dir(filepath.Dir(path))  // Go up past "node" directory
    
    // Construct full file path using Shock directory structure
    filePath := fmt.Sprintf("%s/%s/%s/%s/%s/%s.data",
        baseDir,
        uuid[0:2],
        uuid[2:4],
        uuid[4:6],
        uuid,
        uuid,
    )
    
    f, err := os.Open(filePath)
    if err != nil {
        return nil, fmt.Errorf("failed to open file %s: %w", filePath, err)
    }
    
    if offset > 0 {
        _, err = f.Seek(offset, io.SeekStart)
        if err != nil {
            f.Close()
            return nil, fmt.Errorf("failed to seek in file %s: %w", filePath, err)
        }
    }
    
    if length > 0 {
        return &limitedReadCloser{
            reader: io.LimitReader(f, length),
            closer: f,
        }, nil
    }
    
    return f, nil
}

type limitedReadCloser struct {
    reader io.Reader
    closer io.Closer
}

func (l *limitedReadCloser) Read(p []byte) (int, error) {
    return l.reader.Read(p)
}

func (l *limitedReadCloser) Close() error {
    return l.closer.Close()
}
```

### Phase 5: Migration Strategy

The migration strategy is straightforward because the Workspace service can directly access Shock's existing data directory. There is no need to copy files or update MongoDB records. However, a transition period is required to support existing clients that communicate directly with the Shock service.

#### Transition Period: Dual-Service Operation

During the transition, both the Shock service and the Workspace service (in direct mode) will operate simultaneously, both accessing the same data directory. This allows:

1. **Existing Shock clients** to continue operating without modification
2. **Workspace service** to read files directly from the filesystem
3. **Gradual client migration** as Shock clients are updated or retired

**Architecture during transition:**

```
Existing Shock Clients → Shock API ─────┐
                                        ├──→ Shared Data Directory
Workspace Service → Direct Filesystem ──┘
```

**Important considerations for dual-service operation:**

1. **Read operations are safe**: Both services can read the same files concurrently without issues.

2. **Write coordination**: If both services might write to the same node (unlikely in practice), file locking may be needed. However, since Shock nodes are typically write-once (uploaded and then only read), this is generally not a concern.

3. **New file creation during transition**: When Workspace creates new files while Shock is still running, we must decide how to handle Shock's MongoDB. There are three options:

   **Option A: Workspace writes to Shock's MongoDB** (Complex)
   
   Workspace would insert documents directly into Shock's `Nodes` collection. This is complex because:
   - Shock stores user UUIDs in ACLs, not usernames
   - The `parseAclRequestTyped()` function in Shock looks up usernames in its `Users` collection to get UUIDs
   - If a user doesn't exist, Shock auto-creates a record with a new UUID
   - Workspace would need to query/insert into Shock's `Users` collection to get the correct UUIDs for ACL entries
   - The Workspace service account (`wsuser`) would also need a valid UUID in Shock's `Users` collection
   
   This requires tight coupling to Shock's internal schema and user management logic.

   **Option B: Ignore Shock MongoDB for new files** (Simple, limitations)
   
   Workspace creates files directly on the filesystem without updating Shock's MongoDB. New files would:
   - Be accessible via Workspace API immediately
   - NOT be accessible via Shock API (Shock wouldn't know they exist)
   
   This is acceptable if direct Shock clients only need to access pre-existing files.

   **Option C: Use Shock API for node creation, write data directly** (Recommended)
   
   During the transition period, Workspace uses a hybrid approach:
   - Call Shock API to create the node and set ACLs (Shock handles user UUID mapping)
   - Write file data directly to the filesystem (bypasses Shock's HTTP upload overhead)
   - Shock's MongoDB is consistent; direct Shock clients can access new files
   
   This gives us the benefit of direct filesystem writes while maintaining full compatibility with Shock clients. The Workspace code already has the Shock API integration; we simply skip the data upload portion.
   
   Implementation:
   ```perl
   sub _create_storage_node_transition {
       my ($self, $user) = @_;
       
       # Use Shock API to create node and set ACLs (maintains Shock MongoDB)
       my $node_id = $self->_create_shock_node();
       
       # Return the ID; file data will be written directly to filesystem
       # using uuid_to_path() instead of uploading via Shock HTTP API
       return $node_id;
   }
   ```
   
   After transition completes and Shock is decommissioned, switch to pure direct storage that skips Shock entirely.

   **Recommendation**: Use Option C during the transition period. It provides full compatibility with minimal code changes and no dependency on Shock's internal user management.

4. **Deletion**: If either service deletes a file, it will be unavailable to both. Coordinate deletion policies during transition.

#### Transition Timeline

| Phase | Duration | Configuration | Notes |
|-------|----------|---------------|-------|
| **Phase 1: Deploy** | Day 1 | Workspace: `use-shock = 0`, Shock: running | Both services active, reading same data |
| **Phase 2: Monitor** | 1-4 weeks | Same | Verify Workspace direct access works correctly |
| **Phase 3: Client migration** | Varies | Same | Update or retire direct Shock clients |
| **Phase 4: Deprecate Shock** | 1 week | Same | Announce Shock deprecation, final client updates |
| **Phase 5: Decommission** | Day N | Workspace: `use-shock = 0`, Shock: stopped | Shock service removed |

The transition period length depends on how many external clients directly access the Shock service and how quickly they can be updated.

#### Identifying Direct Shock Clients

Before decommissioning Shock, identify all clients that access it directly:

1. **Check Shock access logs** for client IP addresses and user agents
2. **Review application configurations** that reference the Shock URL
3. **Search codebases** for Shock API calls outside of Workspace
4. **Notify users** who may have scripts using Shock directly

Common direct Shock clients may include:
- Data upload scripts
- Analysis pipelines that fetch raw data
- Third-party integrations
- Legacy applications

#### Configuration for Transition Period

**Workspace `deploy.cfg`:**
```ini
[Workspace]
# Point to Shock's data directory
file-store-path = /mnt/shock/data

# Disable Shock API calls, use direct filesystem access
use-shock = 0

# Keep shock-url configured for reference/logging (optional)
shock-url = http://shock-server:7078
```

**Shock configuration remains unchanged** during the transition period.

#### Direct Cutover Steps

When ready to begin the transition:

1. **Verify Shock data directory location**: Confirm the path to Shock's `PATH_DATA` directory (e.g., `/mnt/shock/data`).

2. **Verify filesystem permissions**: Ensure the Workspace service user has read access to the Shock data directory. If Shock runs as a different user:
   ```bash
   # Option 1: Add Workspace user to Shock's group
   usermod -a -G shock-group workspace-user
   
   # Option 2: Adjust directory permissions
   chmod -R g+rX /mnt/shock/data
   
   # Option 3: Use ACLs for fine-grained control
   setfacl -R -m u:workspace-user:rX /mnt/shock/data
   ```

3. **Update Workspace configuration**: Set `file-store-path` to point to the Shock data directory.

4. **Deploy updated Workspace code**: Deploy the new version with direct filesystem support.

5. **Restart Workspace service**: The service will now read files directly from the Shock data directory.

6. **Verify operation**: Test file downloads through Workspace to confirm direct access works.

7. **Monitor both services**: Watch logs for errors on either service.

**Shock remains running** and continues serving direct clients during the transition.

#### UUID Extraction from Existing URLs

Existing MongoDB documents contain Shock URLs in the `shocknode` field, such as:
```
http://host/services/shock_api/node/a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

The Workspace service extracts the UUID from these URLs and constructs the filesystem path directly:

```perl
sub _get_file_path_from_shocknode {
    my ($self, $shocknode) = @_;
    
    # Extract UUID from any shocknode URL format
    my ($uuid) = $shocknode =~ /([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/i;
    
    unless ($uuid) {
        $self->_error("Cannot extract UUID from shocknode: $shocknode");
    }
    
    return $self->{_filestore}->data_file_path($uuid);
}
```

This approach works regardless of whether the URL uses `http://`, `https://`, or any host name. The UUID is the only information needed to locate the file on disk.

#### No MongoDB Updates Required

The existing `shocknode` URLs in MongoDB do not need to be updated. The Workspace service simply ignores the URL scheme and host, extracting only the UUID portion. This means:

- No migration script needed to update MongoDB documents
- No risk of data inconsistency during migration
- Easy rollback: just re-enable Shock and set `use-shock = 1`

#### Filesystem Permissions

The Workspace service process must have read access to the Shock data directory. If Shock was running as a different user, you may need to:

1. Change ownership of the data directory to the Workspace service user, or
2. Add the Workspace service user to a group that has read access, or
3. Adjust directory permissions to allow read access

For write operations (new file uploads), the Workspace service user also needs write permission to the data directory.

#### Rollback Plan

If issues are discovered after the cutover:

1. Stop the Workspace service
2. Change configuration back to `use-shock = 1`
3. Restart the Shock service
4. Restart the Workspace service

Since no data was modified or moved, rollback is instantaneous.

#### Optional: URL Cleanup

After the migration is stable and Shock has been decommissioned, you may optionally update the MongoDB documents to use a simpler URL format. This is not required for the system to function, but may improve clarity:

```perl
#!/usr/bin/env perl
# optional-cleanup-shocknode-urls.pl
#
# Converts shocknode URLs from Shock format to a simpler format.
# This is optional and can be run at any time after migration.

use strict;
use warnings;
use MongoDB;

my $client = MongoDB->connect('localhost');
my $db = $client->get_database('Workspace');
my $objects = $db->get_collection('objects');

my $cursor = $objects->find({ shock => 1 });

while (my $obj = $cursor->next) {
    my $shocknode = $obj->{shocknode};
    
    # Extract UUID
    my ($uuid) = $shocknode =~ /([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})/i;
    next unless $uuid;
    
    # Update to simplified format
    $objects->update_one(
        { _id => $obj->{_id} },
        { '$set' => { shocknode => "direct:$uuid" } }
    );
}
```

## ACL Elimination

One significant simplification in this migration is the elimination of Shock's ACL (Access Control List) system. Currently, the Workspace service manages Shock ACLs to control who can access files, but this is redundant with the Workspace's own permission system.

The mapping between Shock ACLs and Workspace permissions is:

| Shock ACL | Workspace Equivalent |
|-----------|---------------------|
| Owner | Workspace object owner (stored in MongoDB) |
| Read ACL | Workspace read permission (`user_permission`, `global_permission`) |
| Write ACL | Workspace write permission |
| Public | Workspace `global_permission = 'r'` |

Since all file access goes through the Workspace API, which enforces its own permissions, the Shock ACLs are never actually checked. With direct filesystem access, we simply skip ACL management entirely. The Workspace service remains the gatekeeper for all file access, and it continues to enforce permissions through its existing mechanisms.

## Benefits of This Change

1. **Eliminate Shock Service Dependency**: Removing Shock means one less service to deploy, configure, monitor, and maintain. This reduces operational complexity and potential points of failure.

2. **Reduce Latency**: Direct filesystem access eliminates the HTTP overhead of communicating with Shock. File reads and writes become simple system calls instead of network requests.

3. **Simplify Deployment**: The Workspace service no longer needs Shock configuration (URL, authentication tokens, etc.). Deployment becomes simpler and less error-prone.

4. **Reduce Failure Modes**: Network issues, Shock service outages, and authentication problems are eliminated as potential causes of file access failures.

5. **Efficient Byte-Range Access**: The FUSE client can perform random access reads with direct `pread()` system calls instead of HTTP byte-range requests, improving performance for applications that read files non-sequentially.

6. **Simplified Debugging**: File access issues can be diagnosed with standard filesystem tools instead of requiring Shock API inspection.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Data loss during migration | Use parallel operation mode; do not delete Shock data until direct storage is verified; verify file sizes match after copy |
| Client compatibility issues | Keep URL format detection logic to support both `http://` and `file://` URLs; test with all client types |
| Filesystem permission errors | Ensure the Workspace service user has read/write access to the storage directory; document required permissions |
| Distributed deployment challenges | If Workspace runs on multiple servers, ensure all servers can access the shared storage (NFS, Lustre, or similar); test concurrent access |
| Storage capacity | Ensure direct storage location has sufficient space; migration temporarily doubles storage requirements |

## Implementation Order

The implementation should proceed in the following order to minimize risk and allow for incremental testing:

1. **Create FileStore.pm module**: Develop and unit test the direct storage module independently.

2. **Add configuration options**: Add the `use-shock` and `file-store-path` settings to the configuration system.

3. **Update WorkspaceImpl.pm**: Implement dual-mode support for node creation, metadata retrieval, and file streaming.

4. **Update download service**: Ensure the WorkspaceDownload PSGI application can stream files from direct storage.

5. **Update WorkspaceClientExt.pm**: Modify client upload logic to work with the new upload mechanism.

6. **Update Go client**: Add direct filesystem support to the FUSE client.

7. **Test in staging environment**: Deploy to staging with `file-store-path` pointed at a copy of Shock data and run comprehensive tests.

8. **Deploy to production**: Update configuration to point at Shock's data directory, set `use-shock = 0`.

9. **Stop Shock service**: Once Workspace is serving files directly, Shock can be stopped.

10. **Monitor and verify**: Confirm all file operations work correctly without Shock.

11. **Decommission Shock**: After a verification period, remove the Shock service entirely.

## Testing Checklist

Before deploying to production, verify the following functionality:

- [ ] Create a new file using direct storage and verify it appears in the correct directory
- [ ] Download a file from direct storage and verify content matches
- [ ] Perform a byte-range read and verify the correct portion is returned
- [ ] Verify that legacy Shock files remain accessible through the old URL
- [ ] Test public file download without authentication
- [ ] Upload and download a large file (>1GB) to verify streaming works correctly
- [ ] Mount a workspace via FUSE and verify file access works
- [ ] Run the migration script on a test dataset and verify all files are copied correctly
- [ ] Test concurrent file access from multiple clients
- [ ] Verify error handling for missing files, permission errors, and disk full conditions

## Estimated Effort

The following estimates assume a developer familiar with the Workspace codebase:

| Task | Estimated Effort |
|------|------------------|
| FileStore.pm module development and testing | 1 day |
| WorkspaceImpl.pm modifications | 2 days |
| Client library updates (Perl) | 1 day |
| Go client updates | 1 day |
| Integration testing and bug fixes | 2 days |
| **Total** | **Approximately 7 days** |

Note that the migration itself requires minimal effort since no data copying is needed. The migration consists of:
- Updating the Workspace configuration file (minutes)
- Stopping the Shock service (minutes)
- Deploying the updated Workspace code (standard deployment)
- Adjusting filesystem permissions if necessary (minutes to hours depending on environment)

This estimate does not include deployment time or any unforeseen issues discovered during testing.
