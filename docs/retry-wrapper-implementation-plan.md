# Retry Wrapper Implementation Plan for MongoDB Write Operations

Date: 2026-04-10

## Overview

This document describes the plan to add application-level retry logic for MongoDB write operations in the Workspace service. This addresses the "not master and slaveOK=false" error that occurs during replica set failover.

## Problem Statement

When the MongoDB primary goes down in a replica set:

1. Read operations can fail over to secondaries (with `read_preference => PRIMARY_PREFERRED`)
2. Write operations fail because they must go to the primary
3. The error "not master and slaveOK=false" is returned
4. A new primary is elected within seconds, but the current code doesn't retry

## Solution: Application-Level Retry Wrapper

Since MongoDB 3.4 doesn't support server-side retryable writes, and the v0.708 Perl driver doesn't have built-in retry, we implement retry logic at the application level.

## Implementation Design

### New Helper Methods

Add these methods to `WorkspaceImpl.pm`:

```perl
#
# Retry configuration for MongoDB operations during failover
#
use constant {
    MONGO_RETRY_COUNT => 3,           # Number of retry attempts
    MONGO_RETRY_DELAY_MS => 1000,     # Initial delay between retries (1 second)
    MONGO_RETRY_BACKOFF => 2,         # Exponential backoff multiplier
};

#
# Determine if an error is retryable (connection/failover related)
#
sub _is_retryable_error {
    my ($self, $error) = @_;
    return 0 unless defined $error;
    
    my $err_str = "$error";  # Stringify the error
    
    # Retryable error patterns during failover
    my @retryable_patterns = (
        qr/not master/i,
        qr/slaveOK=false/i,
        qr/connection refused/i,
        qr/couldn't connect/i,
        qr/connection reset/i,
        qr/socket error/i,
        qr/network error/i,
        qr/topology was destroyed/i,
        qr/no primary/i,
        qr/node is recovering/i,
        qr/not master or secondary/i,
    );
    
    for my $pattern (@retryable_patterns) {
        return 1 if $err_str =~ $pattern;
    }
    
    return 0;
}

#
# Execute a MongoDB write operation with retry logic
# Usage: $self->_retry_write(sub { $collection->insert($doc) });
#
sub _retry_write {
    my ($self, $operation, $description) = @_;
    $description //= "MongoDB write operation";
    
    my $max_retries = MONGO_RETRY_COUNT;
    my $delay_ms = MONGO_RETRY_DELAY_MS;
    my $last_error;
    
    for my $attempt (1 .. $max_retries + 1) {
        eval {
            $operation->();
        };
        
        if ($@) {
            $last_error = $@;
            
            if ($self->_is_retryable_error($last_error) && $attempt <= $max_retries) {
                my $delay_sec = $delay_ms / 1000;
                warn "[$description] Attempt $attempt failed with retryable error: $last_error\n";
                warn "[$description] Retrying in ${delay_sec}s...\n";
                
                # Sleep before retry
                select(undef, undef, undef, $delay_sec);
                
                # Exponential backoff
                $delay_ms *= MONGO_RETRY_BACKOFF;
                
                # Trigger reconnection
                eval { $self->{_mongoclient}->rs_refresh(); };
                
                next;
            }
            
            # Non-retryable error or max retries exceeded
            die $last_error;
        }
        
        # Success
        if ($attempt > 1) {
            warn "[$description] Succeeded on attempt $attempt\n";
        }
        return 1;
    }
    
    # Should not reach here, but just in case
    die $last_error;
}

#
# Wrapper for insert operations with retry
#
sub _insert_with_retry {
    my ($self, $collection_name, $doc) = @_;
    return $self->_retry_write(
        sub { $self->_mongodb()->get_collection($collection_name)->insert($doc) },
        "insert into $collection_name"
    );
}

#
# Wrapper for update operations with retry
#
sub _update_with_retry {
    my ($self, $collection_name, $query, $update) = @_;
    return $self->_retry_write(
        sub { $self->_mongodb()->get_collection($collection_name)->update($query, $update) },
        "update $collection_name"
    );
}

#
# Wrapper for remove operations with retry
#
sub _remove_with_retry {
    my ($self, $collection_name, $query) = @_;
    return $self->_retry_write(
        sub { $self->_mongodb()->get_collection($collection_name)->remove($query) },
        "remove from $collection_name"
    );
}
```

### Changes to Existing Code

#### 1. Update `_updateDB` method (line ~217)

```perl
# Current:
sub _updateDB {
    my ($self,$name,$query,$update) = @_;
    $self->_mongodb()->get_collection($name)->update($query,$update);
    return 1;
}

# New:
sub _updateDB {
    my ($self,$name,$query,$update) = @_;
    return $self->_update_with_retry($name, $query, $update);
}
```

#### 2. Workspace creation (line ~1077)

```perl
# Current:
$self->_mongodb()->get_collection('workspaces')->insert({...});

# New:
$self->_insert_with_retry('workspaces', {...});
```

#### 3. Object creation (line ~1182)

```perl
# Current:
$self->_mongodb()->get_collection('objects')->insert($object);

# New:
$self->_insert_with_retry('objects', $object);
```

#### 4. Workspace deletion (lines ~953-954)

```perl
# Current:
$self->_mongodb()->get_collection('workspaces')->remove({uuid => $wsobj->{uuid}});
$self->_mongodb()->get_collection('objects')->remove({workspace_uuid => $wsobj->{uuid}});

# New:
$self->_remove_with_retry('workspaces', {uuid => $wsobj->{uuid}});
$self->_remove_with_retry('objects', {workspace_uuid => $wsobj->{uuid}});
```

#### 5. Object deletion (lines ~982, 991)

```perl
# Current:
$self->_mongodb()->get_collection('objects')->remove({...});

# New:
$self->_remove_with_retry('objects', {...});
```

#### 6. Duplicate object cleanup (line ~662)

```perl
# Current:
$self->_mongodb()->get_collection('objects')->remove({...});

# New:
$self->_remove_with_retry('objects', {...});
```

#### 7. Download/session inserts (lines ~1525, 3167, 3411)

```perl
# Current:
$coll->insert($doc);

# New:
$self->_retry_write(sub { $coll->insert($doc) }, "insert download record");
```

#### 8. Download cleanup (line ~1461)

```perl
# Current:
$coll->remove({expiration_time => {'$lt', $now}});

# New:
$self->_retry_write(sub { $coll->remove({expiration_time => {'$lt', $now}}) }, "cleanup expired downloads");
```

## Retry Behavior

| Parameter | Value | Description |
|-----------|-------|-------------|
| Max Retries | 3 | Number of retry attempts after initial failure |
| Initial Delay | 1 second | Time to wait before first retry |
| Backoff Multiplier | 2x | Each retry waits twice as long |
| Max Total Wait | ~7 seconds | 1s + 2s + 4s = 7s total delay |

### Retry Timeline Example

```
Attempt 1: Execute immediately → Fails with "not master"
Wait 1 second
Attempt 2: Retry → Fails (election in progress)
Wait 2 seconds
Attempt 3: Retry → Fails (election still in progress)
Wait 4 seconds
Attempt 4: Retry → Success (new primary elected)
```

MongoDB replica set elections typically complete in 10-12 seconds, but often a new primary is available within 2-5 seconds. The retry timing is designed to cover most failover scenarios.

## Idempotency Considerations

**Important**: Retrying write operations is only safe if the operations are idempotent or can handle duplicates.

| Operation | Idempotent? | Notes |
|-----------|-------------|-------|
| Insert with UUID | Yes | Duplicate insert will fail with duplicate key error |
| Update by UUID | Yes | Same update applied twice has same result |
| Remove by UUID | Yes | Removing already-removed document is no-op |
| Insert without unique key | **No** | Could create duplicates - needs special handling |

The Workspace service uses UUIDs for all documents, so retries are generally safe:
- Workspace documents have `uuid` field
- Object documents have `uuid` field
- If a write succeeds but the response is lost during failover, the retry will either:
  - Succeed (if the original write was lost)
  - Fail with duplicate key error (if the original write succeeded)

The retry wrapper should catch duplicate key errors and treat them as success:

```perl
sub _is_duplicate_key_error {
    my ($self, $error) = @_;
    return 0 unless defined $error;
    my $err_str = "$error";
    return $err_str =~ /duplicate key error/i || $err_str =~ /E11000/;
}

# In _retry_write, after catching an error:
if ($self->_is_duplicate_key_error($@)) {
    # Treat as success - the write already happened
    warn "[$description] Write already applied (duplicate key), treating as success\n";
    return 1;
}
```

## Testing Plan

### Unit Tests

1. Test `_is_retryable_error()` with various error strings
2. Test `_retry_write()` with mock operations that fail then succeed
3. Test retry timing and backoff

### Integration Tests

1. Test with single MongoDB instance (no retry needed)
2. Test with replica set, operations during normal state
3. Test with replica set, simulate primary stepdown:
   ```javascript
   // In mongo shell on primary:
   rs.stepDown()
   ```
4. Verify write operations complete successfully after failover

### Failover Test Script

```bash
#!/bin/bash
# Test failover behavior

# 1. Start a write-heavy workload
for i in {1..100}; do
    p3-mkdir /user@patricbrc.org/home/test-$i &
done

# 2. While writes are running, trigger failover
mongo --host primary:27017 --eval "rs.stepDown()"

# 3. Check that all directories were created
for i in {1..100}; do
    p3-ls /user@patricbrc.org/home/test-$i || echo "FAILED: test-$i"
done
```

## Rollback Plan

If issues arise with the retry wrapper:

1. The changes are isolated to the helper methods
2. Revert by changing calls back to direct `->insert()`, `->update()`, `->remove()`
3. Or set `MONGO_RETRY_COUNT => 0` to disable retries

## Files to Modify

| File | Changes |
|------|---------|
| `lib/Bio/P3/Workspace/WorkspaceImpl.pm` | Add retry helpers, update write calls |
| `t/client-tests/retry-tests.t` | New test file for retry logic |

## Implementation Steps

1. [ ] Add retry configuration constants
2. [ ] Add `_is_retryable_error()` method
3. [ ] Add `_retry_write()` method
4. [ ] Add `_insert_with_retry()` wrapper
5. [ ] Add `_update_with_retry()` wrapper
6. [ ] Add `_remove_with_retry()` wrapper
7. [ ] Update `_updateDB()` to use retry wrapper
8. [ ] Update workspace insert to use retry wrapper
9. [ ] Update object insert to use retry wrapper
10. [ ] Update all remove calls to use retry wrapper
11. [ ] Update download/session inserts to use retry wrapper
12. [ ] Add duplicate key error handling
13. [ ] Write tests
14. [ ] Test with replica set failover
15. [ ] Deploy to staging
16. [ ] Monitor for issues
17. [ ] Deploy to production

## Monitoring

After deployment, monitor for:

1. Retry warning messages in logs
2. Frequency of retries (indicates failover events)
3. Failed operations after max retries (indicates prolonged outages)
4. Operation latency increases during failover

Log messages to grep for:
```
"retryable error"
"Retrying in"
"Succeeded on attempt"
```
