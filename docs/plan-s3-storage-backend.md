# Plan: S3-Compatible Storage Backend for Workspace Service

Date: 2026-04-10

## Executive Summary

This document outlines a plan to add S3-compatible object storage as a backend option for the Workspace service. The target is a NetApp storage appliance that speaks the S3 protocol. This change will provide cloud-native object storage capabilities while maintaining backward compatibility with existing files stored in Shock or direct filesystem storage.

## Current Architecture

The Workspace service currently supports two storage backends:

1. **Shock API** (being deprecated): Files stored via HTTP API to Shock service
2. **Direct filesystem**: Files stored directly on local/NFS filesystem

Both backends store file references in MongoDB with the `shocknode` field containing either a Shock URL or a filesystem path.

```
Client → Workspace API → Shock API → Filesystem
                      → Direct Filesystem
                      → MongoDB (metadata)
```

### Proposed Architecture

Add S3 as a third storage backend option:

```
Client → Workspace API → S3-Compatible Storage (NetApp)
                      → Direct Filesystem (existing files)
                      → Shock API (legacy, read-only)
                      → MongoDB (metadata)
```

## S3 Storage Design

### Object Key Structure

S3 objects will be organized using a hierarchical key structure similar to the existing filesystem layout. This provides efficient listing and management:

```
{bucket}/
  {prefix}/                    # Optional prefix for multi-tenant or environment separation
    {uuid[0:2]}/
      {uuid[2:4]}/
        {uuid[4:6]}/
          {uuid}               # Object key is the full UUID
```

Example: A file with UUID `a1b2c3d4-e5f6-7890-abcd-ef1234567890` would be stored at:
- Bucket: `workspace-data`
- Key: `a1/b2/c3/a1b2c3d4-e5f6-7890-abcd-ef1234567890`

The hierarchical prefix structure enables efficient `ListObjectsV2` operations when needed for maintenance tasks.

### Alternative: Flat Key Structure

A simpler alternative uses the UUID directly as the key:

```
{bucket}/{uuid}
```

This is simpler but may have performance implications for very large buckets (millions of objects). S3 handles this well internally, but the hierarchical structure provides better organization for debugging and maintenance.

**Recommendation**: Use hierarchical keys for consistency with existing filesystem layout and easier debugging.

### Metadata Storage

The MongoDB `objects` collection will store S3 references in the existing `shocknode` field using a new URL scheme:

```javascript
{
    "shock": 1,                    // Keep as 1 to indicate external storage
    "shocknode": "s3://bucket-name/prefix/a1/b2/c3/a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "size": 12345,
    // ... other workspace object fields
}
```

The `s3://` URL scheme distinguishes S3 storage from Shock URLs (`http://`) and direct filesystem paths (`file://` or bare paths).

## Perl Module: Bio::P3::Workspace::S3Store

Create a new module to encapsulate all S3 operations:

```perl
package Bio::P3::Workspace::S3Store;

use strict;
use warnings;
use Amazon::S3;
use Data::UUID;
use Digest::MD5;
use IO::String;

sub new {
    my ($class, %args) = @_;
    
    my $self = {
        bucket_name    => $args{bucket}       || die "bucket required",
        prefix         => $args{prefix}       || '',
        access_key     => $args{access_key}   || die "access_key required",
        secret_key     => $args{secret_key}   || die "secret_key required",
        endpoint       => $args{endpoint},     # NetApp S3 endpoint URL
        region         => $args{region}       || 'us-east-1',
        use_path_style => $args{use_path_style} // 1,  # Required for most S3-compatible stores
    };
    
    # Initialize S3 client
    my %s3_args = (
        aws_access_key_id     => $self->{access_key},
        aws_secret_access_key => $self->{secret_key},
        retry                 => 1,
        secure                => ($self->{endpoint} =~ /^https/) ? 1 : 0,
    );
    
    if ($self->{endpoint}) {
        # For S3-compatible storage (NetApp, MinIO, etc.)
        $s3_args{host} = $self->{endpoint};
        $s3_args{host} =~ s,^https?://,,;  # Remove scheme if present
    }
    
    $self->{s3} = Amazon::S3->new(\%s3_args);
    $self->{bucket} = $self->{s3}->bucket($self->{bucket_name});
    
    return bless $self, $class;
}

# Convert UUID to S3 object key
sub uuid_to_key {
    my ($self, $uuid) = @_;
    
    my $key = sprintf("%s/%s/%s/%s",
        substr($uuid, 0, 2),
        substr($uuid, 2, 2),
        substr($uuid, 4, 2),
        $uuid
    );
    
    return $self->{prefix} ? "$self->{prefix}/$key" : $key;
}

# Generate a new UUID and return the S3 URL
sub create_node {
    my ($self) = @_;
    
    my $uuid = Data::UUID->new->create_str();
    # Convert to lowercase for consistency
    $uuid = lc($uuid);
    
    return {
        uuid => $uuid,
        url  => sprintf("s3://%s/%s", $self->{bucket_name}, $self->uuid_to_key($uuid)),
    };
}

# Write data to S3, return size and MD5
sub write_file {
    my ($self, $uuid, $data_or_fh) = @_;
    
    my $key = $self->uuid_to_key($uuid);
    my $data;
    my $md5 = Digest::MD5->new;
    
    if (ref($data_or_fh) eq 'GLOB') {
        # Read entire file into memory for S3 upload
        # For very large files, use multipart upload instead
        local $/;
        $data = <$data_or_fh>;
    } elsif (ref($data_or_fh) eq 'SCALAR') {
        $data = $$data_or_fh;
    } else {
        die "write_file requires a filehandle or scalar reference";
    }
    
    $md5->add($data);
    my $size = length($data);
    
    my $result = $self->{bucket}->add_key(
        $key,
        $data,
        {
            content_type => 'application/octet-stream',
        }
    );
    
    unless ($result) {
        die "S3 upload failed: " . $self->{s3}->err . ": " . $self->{s3}->errstr;
    }
    
    return {
        size => $size,
        md5  => $md5->hexdigest,
    };
}

# Write from a local file using streaming (for large files)
sub write_file_from_path {
    my ($self, $uuid, $local_path) = @_;
    
    my $key = $self->uuid_to_key($uuid);
    
    # Use add_key_filename for efficient file upload
    my $result = $self->{bucket}->add_key_filename(
        $key,
        $local_path,
        {
            content_type => 'application/octet-stream',
        }
    );
    
    unless ($result) {
        die "S3 upload failed: " . $self->{s3}->err . ": " . $self->{s3}->errstr;
    }
    
    # Compute MD5 and get size
    my $md5 = Digest::MD5->new;
    open(my $fh, '<', $local_path) or die "Cannot open $local_path: $!";
    binmode($fh);
    $md5->addfile($fh);
    my $size = -s $fh;
    close($fh);
    
    return {
        size => $size,
        md5  => $md5->hexdigest,
    };
}

# Get file content as a string
sub get_file {
    my ($self, $uuid) = @_;
    
    my $key = $self->uuid_to_key($uuid);
    my $value = $self->{bucket}->get_key($key);
    
    unless (defined $value) {
        die "S3 get failed: " . $self->{s3}->err . ": " . $self->{s3}->errstr;
    }
    
    return $value->{value};
}

# Get file content with callback for streaming
sub get_file_streaming {
    my ($self, $uuid, $callback, $offset, $length) = @_;
    
    my $key = $self->uuid_to_key($uuid);
    
    # Build Range header if offset/length specified
    my %headers;
    if (defined $offset || defined $length) {
        my $range_start = $offset // 0;
        my $range_end = defined $length ? ($range_start + $length - 1) : '';
        $headers{Range} = "bytes=$range_start-$range_end";
    }
    
    # Use get_key with callback for streaming
    # Note: Amazon::S3 may not support streaming directly;
    # may need to use LWP::UserAgent directly with signed URLs
    my $value = $self->{bucket}->get_key($key, \%headers);
    
    unless (defined $value) {
        die "S3 get failed: " . $self->{s3}->err . ": " . $self->{s3}->errstr;
    }
    
    $callback->($value->{value});
}

# Generate a presigned URL for direct download
sub presigned_url {
    my ($self, $uuid, $expires_in) = @_;
    
    $expires_in //= 3600;  # Default 1 hour
    my $key = $self->uuid_to_key($uuid);
    
    # Amazon::S3 doesn't have built-in presigned URL support
    # Would need to implement manually or use a different library
    # For NetApp S3, check if presigned URLs are supported
    
    die "presigned_url not yet implemented";
}

# Get object metadata (size, ETag)
sub stat_file {
    my ($self, $uuid) = @_;
    
    my $key = $self->uuid_to_key($uuid);
    my $response = $self->{bucket}->head_key($key);
    
    unless ($response) {
        return undef;  # Object does not exist
    }
    
    return {
        size         => $response->{content_length},
        etag         => $response->{etag},
        last_modified => $response->{last_modified},
    };
}

# Delete an object
sub delete_file {
    my ($self, $uuid) = @_;
    
    my $key = $self->uuid_to_key($uuid);
    my $result = $self->{bucket}->delete_key($key);
    
    unless ($result) {
        die "S3 delete failed: " . $self->{s3}->err . ": " . $self->{s3}->errstr;
    }
    
    return 1;
}

# Check if object exists
sub exists {
    my ($self, $uuid) = @_;
    
    my $stat = $self->stat_file($uuid);
    return defined $stat;
}

1;
```

## Configuration

Add S3 configuration options to `deploy.cfg`:

```ini
[Workspace]

# Storage backend: "s3", "filesystem", or "shock" (deprecated)
# Default: "shock" for backward compatibility
storage-backend = s3

# S3 Configuration (required when storage-backend = s3)
s3-endpoint = https://netapp-s3.example.com
s3-bucket = workspace-data
s3-prefix = prod                    # Optional prefix for environment separation
s3-access-key = AKIAIOSFODNN7EXAMPLE
s3-secret-key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
s3-region = us-east-1               # May be ignored by NetApp
s3-use-path-style = 1               # Required for most S3-compatible stores

# Existing config for backward compatibility
shock-url = http://shock-server:7078
file-store-path = /mnt/workspace/filestore
```

## WorkspaceImpl.pm Modifications

### Add Storage Backend Initialization

```perl
sub _init_storage {
    my ($self) = @_;
    
    my $backend = $self->{_params}->{"storage-backend"} || "shock";
    
    if ($backend eq "s3") {
        require Bio::P3::Workspace::S3Store;
        $self->{_s3store} = Bio::P3::Workspace::S3Store->new(
            endpoint       => $self->{_params}->{"s3-endpoint"},
            bucket         => $self->{_params}->{"s3-bucket"},
            prefix         => $self->{_params}->{"s3-prefix"} || '',
            access_key     => $self->{_params}->{"s3-access-key"},
            secret_key     => $self->{_params}->{"s3-secret-key"},
            region         => $self->{_params}->{"s3-region"} || 'us-east-1',
            use_path_style => $self->{_params}->{"s3-use-path-style"} // 1,
        );
    } elsif ($backend eq "filesystem") {
        require Bio::P3::Workspace::FileStore;
        $self->{_filestore} = Bio::P3::Workspace::FileStore->new(
            base_path => $self->{_params}->{"file-store-path"},
        );
    }
    # Shock is the default - no additional init needed
    
    $self->{_storage_backend} = $backend;
}

sub _storage_backend {
    my ($self) = @_;
    return $self->{_storage_backend} || "shock";
}
```

### Add Unified Storage Node Creation

```perl
sub _create_storage_node {
    my ($self) = @_;
    
    my $backend = $self->_storage_backend();
    
    if ($backend eq "s3") {
        my $node = $self->{_s3store}->create_node();
        return $node->{url};  # Returns s3://bucket/key
    } elsif ($backend eq "filesystem") {
        my $uuid = $self->{_filestore}->create_node();
        return "file://" . $self->_file_store_path() . "/node/$uuid";
    } else {
        # Shock
        return $self->_shockurl() . "/node/" . $self->_create_shock_node();
    }
}
```

### Add Unified Download Streaming

The download code must handle three URL schemes:

```perl
sub _stream_storage_content {
    my ($self, $shocknode, $offset, $length, $writer, $token) = @_;
    
    if ($shocknode =~ /^s3:\/\/([^\/]+)\/(.+)$/) {
        # S3 storage
        my ($bucket, $key) = ($1, $2);
        my $uuid = $self->_extract_uuid_from_s3_key($key);
        
        $self->{_s3store}->get_file_streaming($uuid, sub {
            my ($data) = @_;
            $writer->write($data);
        }, $offset, $length);
        
        $writer->close();
    } elsif ($shocknode =~ /^file:\/\//) {
        # Direct filesystem
        $self->_stream_from_filesystem($shocknode, $offset, $length, $writer);
    } else {
        # Shock URL (http://)
        $self->_stream_from_shock($shocknode, $offset, $length, $writer, $token);
    }
}

sub _extract_uuid_from_s3_key {
    my ($self, $key) = @_;
    
    # Key format: prefix/a1/b2/c3/uuid or a1/b2/c3/uuid
    if ($key =~ /([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i) {
        return lc($1);
    }
    
    die "Cannot extract UUID from S3 key: $key";
}
```

## Client-Side Changes (WorkspaceClientExt.pm)

The client-side upload flow changes significantly with S3:

### Option A: Server-Side Upload (Recommended)

All uploads go through the Workspace server, which writes to S3:

```perl
sub save_file_to_file {
    my ($self, $local_file, $metadata, $path, $type, $overwrite, $use_shock, $token, ...) = @_;
    
    # For S3 backend, always use server-side upload via create() with data
    # The server handles writing to S3
    
    my $file_size = -s $local_file;
    
    if ($file_size > 1000) {
        # Use chunked upload endpoint for large files
        return $self->_upload_large_file($local_file, $path, $type, $metadata, $token);
    } else {
        # Small files: include data in create() call
        my $data = read_file($local_file);
        return $self->create({
            objects => [[$path, $type, $metadata, $data]],
            overwrite => ($overwrite ? 1 : 0),
        })->[0];
    }
}

sub _upload_large_file {
    my ($self, $local_file, $path, $type, $metadata, $token) = @_;
    
    $token = $token->token if ref($token);
    
    # Create the object first to get upload URL
    my $res = $self->create({
        objects => [[$path, $type, $metadata]],
        createUploadNodes => 1,
    })->[0];
    
    my $upload_url = $res->[11];  # shockurl field
    
    # Determine upload method based on URL scheme
    if ($upload_url =~ /^s3:\/\//) {
        # For S3, server provides a presigned upload URL or we use
        # a dedicated upload endpoint
        return $self->_upload_via_workspace_endpoint($local_file, $res, $token);
    } else {
        # Legacy Shock upload
        return $self->_upload_to_shock($local_file, $upload_url, $token);
    }
}
```

### Option B: Presigned URL Upload (If NetApp Supports It)

If the NetApp S3 implementation supports presigned URLs, clients can upload directly:

```perl
sub _upload_via_presigned_url {
    my ($self, $local_file, $presigned_url) = @_;
    
    my $ua = LWP::UserAgent->new();
    $ua->timeout(86400);
    
    my $req = HTTP::Request->new(PUT => $presigned_url);
    $req->content_type('application/octet-stream');
    
    # Stream file content
    open(my $fh, '<', $local_file) or die "Cannot open $local_file: $!";
    binmode($fh);
    $req->content(sub {
        my $buffer;
        my $bytes = read($fh, $buffer, 65536);
        return $bytes ? $buffer : undef;
    });
    
    my $res = $ua->request($req);
    close($fh);
    
    unless ($res->is_success) {
        die "S3 upload failed: " . $res->status_line;
    }
    
    return 1;
}
```

## New Upload Endpoint

Add a dedicated upload endpoint to the Workspace service for large file uploads:

```perl
# In WorkspaceUpload.psgi or similar

# POST /upload/{uuid}
# - Accepts multipart/form-data with file content
# - Writes directly to S3
# - Updates MongoDB with size

sub handle_upload {
    my ($env) = @_;
    
    my $req = Plack::Request->new($env);
    my $uuid = $req->path_info =~ s,^/upload/,,r;
    
    # Validate token and permissions
    my $token = $req->header('Authorization') =~ s/^OAuth //r;
    my $user = validate_token($token);
    
    # Get uploaded file
    my $upload = $req->upload('file');
    my $fh = $upload->fh;
    
    # Write to S3
    my $result = $s3store->write_file($uuid, $fh);
    
    # Update MongoDB
    update_object_size($uuid, $result->{size}, $result->{md5});
    
    return [200, ['Content-Type' => 'application/json'], [
        encode_json({ status => 'ok', size => $result->{size} })
    ]];
}
```

## Go FUSE Client Updates

The Go-based FUSE client needs S3 support for direct file reading:

```go
package workspace

import (
    "context"
    "fmt"
    "io"
    "net/url"
    "strings"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/credentials"
    "github.com/aws/aws-sdk-go-v2/service/s3"
)

type S3Client struct {
    client *s3.Client
    bucket string
}

func NewS3Client(endpoint, accessKey, secretKey, bucket, region string) (*S3Client, error) {
    cfg, err := config.LoadDefaultConfig(context.TODO(),
        config.WithRegion(region),
        config.WithCredentialsProvider(
            credentials.NewStaticCredentialsProvider(accessKey, secretKey, ""),
        ),
    )
    if err != nil {
        return nil, fmt.Errorf("failed to load AWS config: %w", err)
    }

    client := s3.NewFromConfig(cfg, func(o *s3.Options) {
        if endpoint != "" {
            o.BaseEndpoint = aws.String(endpoint)
        }
        o.UsePathStyle = true  // Required for most S3-compatible stores
    })

    return &S3Client{
        client: client,
        bucket: bucket,
    }, nil
}

func (c *S3Client) GetObject(key string, offset, length int64) (io.ReadCloser, error) {
    input := &s3.GetObjectInput{
        Bucket: aws.String(c.bucket),
        Key:    aws.String(key),
    }

    if offset > 0 || length > 0 {
        var rangeHeader string
        if length > 0 {
            rangeHeader = fmt.Sprintf("bytes=%d-%d", offset, offset+length-1)
        } else {
            rangeHeader = fmt.Sprintf("bytes=%d-", offset)
        }
        input.Range = aws.String(rangeHeader)
    }

    result, err := c.client.GetObject(context.TODO(), input)
    if err != nil {
        return nil, fmt.Errorf("S3 GetObject failed: %w", err)
    }

    return result.Body, nil
}

// ReadFile handles both S3 and Shock URLs
func ReadFile(nodeURL string, offset, length int64) (io.ReadCloser, error) {
    u, err := url.Parse(nodeURL)
    if err != nil {
        return nil, err
    }

    switch u.Scheme {
    case "s3":
        // s3://bucket/key
        bucket := u.Host
        key := strings.TrimPrefix(u.Path, "/")
        // Get S3 client from config (implementation depends on how config is managed)
        client := getS3Client(bucket)
        return client.GetObject(key, offset, length)

    case "http", "https":
        // Shock URL
        return readFromShock(nodeURL, offset, length)

    case "file":
        // Direct filesystem
        return readFromFilesystem(nodeURL, offset, length)

    default:
        return nil, fmt.Errorf("unsupported URL scheme: %s", u.Scheme)
    }
}
```

## Migration Strategy

### Phase 1: Deploy S3Store Module

1. Add `Bio::P3::Workspace::S3Store` module
2. Add S3 configuration options
3. Deploy but keep `storage-backend = shock`

### Phase 2: Test S3 Backend

1. Set up test bucket on NetApp
2. Configure test environment with `storage-backend = s3`
3. Verify upload/download/delete operations
4. Performance testing

### Phase 3: Production Cutover

1. Create production bucket
2. Switch `storage-backend = s3`
3. New files go to S3
4. Existing files remain in Shock/filesystem (readable via URL scheme detection)

### Data Migration (Optional)

Existing files can be migrated from Shock/filesystem to S3:

```perl
#!/usr/bin/env perl
# migrate-to-s3.pl

use strict;
use warnings;
use MongoDB;
use Bio::P3::Workspace::S3Store;
use LWP::UserAgent;

my $s3store = Bio::P3::Workspace::S3Store->new(...);
my $mongodb = MongoDB->connect(...);
my $objects = $mongodb->ns('Workspace.objects');

my $cursor = $objects->find({ shock => 1 });

while (my $obj = $cursor->next) {
    my $shocknode = $obj->{shocknode};
    
    # Skip if already S3
    next if $shocknode =~ /^s3:/;
    
    # Download from Shock
    my $uuid = extract_uuid($shocknode);
    my $data = download_from_shock($shocknode);
    
    # Upload to S3
    my $result = $s3store->write_file($uuid, \$data);
    
    # Update MongoDB
    my $new_url = sprintf("s3://%s/%s", $bucket, $s3store->uuid_to_key($uuid));
    $objects->update_one(
        { _id => $obj->{_id} },
        { '$set' => { shocknode => $new_url } }
    );
    
    print "Migrated $uuid\n";
}
```

## NetApp S3 Compatibility Considerations

### Known Differences from AWS S3

NetApp ONTAP S3 is compatible with most S3 operations but may have some differences:

1. **Authentication**: Supports AWS Signature Version 4
2. **Path-style URLs**: Required (virtual-hosted style may not work)
3. **Multipart upload**: Supported but verify part size limits
4. **Presigned URLs**: May have implementation differences
5. **Bucket policies**: May have limited support
6. **Object versioning**: Check if supported/enabled

### Testing Checklist

- [ ] Basic put/get/delete operations
- [ ] Range requests (byte-range reads)
- [ ] Large file uploads (multipart)
- [ ] Concurrent access from multiple clients
- [ ] Error handling (network timeouts, retries)
- [ ] Performance benchmarks vs Shock

## Benefits

1. **Modern protocol**: S3 is industry-standard with excellent tooling
2. **Direct integration**: NetApp appliance provides enterprise storage features
3. **Scalability**: S3 handles large object counts efficiently
4. **Reduced complexity**: Eliminates Shock as a dependency
5. **Ecosystem**: Compatible with many backup, monitoring, and management tools
6. **Performance**: NetApp provides high-performance storage

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| NetApp S3 compatibility issues | Test thoroughly before production deployment |
| Credential management | Use environment variables or secrets management |
| Network latency | NetApp is on local network; benchmark performance |
| Large file handling | Implement multipart upload for files > 100MB |
| Client compatibility | URL scheme detection handles all backends transparently |

## Implementation Order

1. **Create S3Store.pm module** - Develop and test independently
2. **Add configuration options** - Update deploy.cfg parsing
3. **Update WorkspaceImpl.pm** - Add storage backend selection and S3 support
4. **Add upload endpoint** - For large file uploads through server
5. **Update WorkspaceClientExt.pm** - Client-side upload changes
6. **Update Go FUSE client** - S3 support for direct reads
7. **Testing** - Integration and performance testing
8. **Documentation** - Update deployment docs
9. **Deploy to staging** - Test with real data
10. **Production rollout** - Gradual cutover

## Timeline Estimate

| Phase | Duration | Notes |
|-------|----------|-------|
| S3Store module | 2-3 days | Core functionality |
| WorkspaceImpl changes | 2-3 days | Backend integration |
| Upload endpoint | 1-2 days | Server-side upload handling |
| Client updates | 1-2 days | WorkspaceClientExt changes |
| Go client updates | 1-2 days | FUSE filesystem support |
| Testing | 3-5 days | Integration and performance |
| Documentation | 1 day | |
| Staging deployment | 2-3 days | |
| **Total** | **2-3 weeks** | |
