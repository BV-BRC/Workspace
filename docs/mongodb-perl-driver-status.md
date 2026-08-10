# MongoDB Perl Driver Status and Compatibility Analysis

Date: 2026-04-10

## Driver Status

**The MongoDB Perl driver is officially End of Life (EOL)** as of August 13, 2020.

| Detail | Status |
|--------|--------|
| Final Version | v2.2.2 (August 2020) |
| Maintenance | None - EOL |
| MongoDB Support | No longer officially supported |
| License | Apache 2.0 (can be forked) |

Source: https://metacpan.org/pod/MongoDB

The maintainers noted: "As of August 13, 2020, the MongoDB Perl driver and related libraries have reached end of life and are no longer supported by MongoDB. Members of the community wishing to continue development are welcome to fork the code under the terms of the Apache 2 license and release it under a new namespace."

## Current Environment

| Component | Version | Notes |
|-----------|---------|-------|
| Workspace MongoDB | 3.4.24 | EOL since January 2020 |
| Alternate Cluster | Percona Server for MongoDB 5.0.17-14 | Actively maintained |
| Current Perl Driver | v0.708.3.0 | Very old, limited replica set support |
| Latest Perl Driver | v2.2.2 | EOL but more modern |

## Driver Version Comparison

### v0.708.3.0 (Currently Installed)

- Uses deprecated `MongoDB::Connection` class
- Uses older wire protocol (OP_QUERY)
- Authentication: MONGODB-CR (legacy)
- Limited replica set failover support
- No read preference support in constructor
- No retryable writes

### v2.2.2 (Final Release)

- Uses `MongoDB::MongoClient` class
- Uses modern wire protocol (OP_MSG)
- Authentication: SCRAM-SHA-1/256
- Better replica set support with automatic failover
- Built-in read preference support
- Supports retryable writes (requires MongoDB 3.6+)

### API Changes: v0.708 → v2.2.2

| v0.708 | v2.2.2 | Notes |
|--------|--------|-------|
| `->insert($doc)` | `->insert_one($doc)` | Single document |
| `->insert(\@docs)` | `->insert_many(\@docs)` | Multiple documents |
| `->update($query, $update)` | `->update_one($query, $update)` | Single document |
| `->update($query, $update, {multiple => 1})` | `->update_many($query, $update)` | Multiple documents |
| `->remove($query)` | `->delete_one($query)` | Single document |
| `->remove($query, {just_one => 0})` | `->delete_many($query)` | Multiple documents |
| `->count($query)` | `->count_documents($query)` | Count matching docs |
| `->find($query)` | `->find($query)` | Compatible |
| `->find_one($query)` | `->find_one($query)` | Compatible |

## MongoDB Server Compatibility

### Authentication Protocol Evolution

| MongoDB Server | Auth Mechanism | v0.708 | v2.2.2 |
|----------------|----------------|--------|--------|
| MongoDB 2.x-3.x | MONGODB-CR | ✓ | ✓ |
| MongoDB 3.0+ | SCRAM-SHA-1 | ⚠️ Limited | ✓ |
| MongoDB 4.0+ | SCRAM-SHA-256 (default) | ✗ | ✓ |
| MongoDB 5.0+ | SCRAM-SHA-256 only | ✗ | ✓ (untested) |

### Wire Protocol Evolution

| MongoDB Server | Wire Protocol | v0.708 | v2.2.2 |
|----------------|---------------|--------|--------|
| MongoDB 3.x | OP_QUERY | ✓ | ✓ |
| MongoDB 4.x | OP_MSG preferred | ⚠️ | ✓ |
| MongoDB 5.0-5.1 | OP_MSG, OP_QUERY deprecated | ⚠️ | ✓ |
| MongoDB 6.0+ | OP_MSG only (OP_QUERY removed) | ✗ | ✓ (untested) |

### Retryable Writes Support

| MongoDB Server | Server-side Retryable Writes |
|----------------|-----------------------------|
| MongoDB 3.4 | ✗ Not supported |
| MongoDB 3.6+ | ✓ Supported (replica sets) |
| MongoDB 4.2+ | ✓ Supported (sharded clusters too) |

## Compatibility Assessment

### v0.708 + MongoDB 3.4.24 (Current Production)

**Status: Working but limited**

- Authentication works (MONGODB-CR supported)
- Basic operations work
- Replica set failover: Limited (reason for "not master and slaveOK=false" errors)
- Retryable writes: Not available (neither driver nor server supports it)

### v0.708 + MongoDB 5.0 (Percona)

**Status: High risk - likely will NOT work**

- Authentication: MONGODB-CR not supported in 5.0
- Wire protocol: OP_QUERY deprecated, may fail
- Not recommended

### v2.2.2 + MongoDB 3.4.24

**Status: Should work**

- Authentication: SCRAM-SHA-1 supported in both
- Wire protocol: Compatible
- Retryable writes: Not available (server doesn't support it)

**Auth migration status (verified 2026-05-28):**
- `authSchemaVersion` is already 5 (SCRAM-SHA-1 schema)
- However, existing user records were never converted — they lack `mechanisms` field and still have MONGODB-CR credentials only
- Before switching to v2.2.2 driver, run `db.adminCommand({authSchemaUpgrade: 1})` on the primary to convert user credentials to SCRAM-SHA-1
- After conversion, verify with: `db.getSiblingDB("admin").system.users.find({}, {user: 1, mechanisms: 1, db: 1})` — each user should show `"mechanisms": ["SCRAM-SHA-1"]`
- The current v0.708 driver will continue to work after the auth upgrade (3.4 accepts both mechanisms)

### v2.2.2 + MongoDB 5.0 (Percona)

**Status: Probably works but untested**

- Authentication: SCRAM-SHA-256 supported in both
- Wire protocol: OP_MSG supported in both
- Retryable writes: Available
- Risk: No official testing since driver EOL'd before MongoDB 5.0 release
- This combination has no official support from either MongoDB or Percona

## Recommendations

### Short-term (Immediate fix for failover)

1. Add application-level retry wrapper to v0.708 code:
   - Fixes "not master and slaveOK=false" errors during failover
   - Minimal code changes
   - No authentication risk
   - Works with current MongoDB 3.4

2. Upgrade user credentials to SCRAM-SHA-1 (prerequisite for driver upgrade):
   - Run `db.adminCommand({authSchemaUpgrade: 1})` on primary
   - Safe to do now — v0.708 driver continues to work after this
   - Must be done before upgrading to v2.2.2 driver

### Medium-term Options

#### Option A: Upgrade to v2.2.2 + Migrate to Percona 5.0

**Pros:**
- Server-side retryable writes
- Better replica set handling
- More modern MongoDB features
- Active server maintenance (Percona)

**Cons:**
- Code changes required (~15 method calls)
- Untested driver/server combination
- Driver still EOL - no fixes for any issues
- Migration effort and testing required

#### Option B: Keep v0.708 + Retry Wrapper + Stay on MongoDB 3.4

**Pros:**
- Known working combination
- Minimal changes
- Lower immediate risk

**Cons:**
- MongoDB 3.4 is EOL (security vulnerabilities)
- No server-side retryable writes
- Deferred technical debt

### Long-term Consideration

Given the EOL status of the Perl driver, consider:

1. **Microservice wrapper**: Create a thin service in Python/Go/Node.js that handles MongoDB access, called by the Perl code via HTTP/REST. All these languages have actively maintained MongoDB drivers.

2. **Gradual migration**: As parts of the Workspace service are updated, migrate them away from direct Perl MongoDB access.

3. **Community fork**: Monitor for community forks of the Perl driver that may provide ongoing maintenance.

## Code Changes Required for v2.2.2 Upgrade

If upgrading to v2.2.2, the following changes would be needed in WorkspaceImpl.pm:

```perl
# Change import
use MongoDB;  # Already done

# Connection (already updated for MongoClient)
my $client = MongoDB::MongoClient->new(%$client_options);

# Insert operations - change from:
$collection->insert($doc);
# To:
$collection->insert_one($doc);

# Update operations - change from:
$collection->update($query, $update);
# To:
$collection->update_one($query, $update);

# Remove operations - change from:
$collection->remove($query);
# To:
$collection->delete_one($query);   # For single document
$collection->delete_many($query);  # For multiple documents

# Count operations - change from:
$collection->count($query);
# To:
$collection->count_documents($query);
```

## Files Affected

In WorkspaceImpl.pm, the following methods/lines use write operations:

- Line 217: `_updateDB()` - uses `->update()`
- Line 662: duplicate object removal - uses `->remove()`
- Lines 953-954: workspace deletion - uses `->remove()`
- Lines 982, 991: object deletion - uses `->remove()`
- Line 1077: workspace creation - uses `->insert()`
- Line 1182: object creation - uses `->insert()`
- Line 1461: download cleanup - uses `->remove()`
- Line 1525: session insert - uses `->insert()`
- Lines 3167, 3411: download doc insert - uses `->insert()`
- Line 642: count query - uses `->count()`
