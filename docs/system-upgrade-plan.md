# BV-BRC Workspace System Upgrade Plan

Date: 2026-05-28

## Overview

This document is the master plan for the Workspace service infrastructure upgrade. It coordinates multiple interdependent workstreams across the Workspace service, its storage backends, database layer, authentication system, and the operational constraints of the BV-BRC data center environment.

The overarching goals are:

1. **Reliability** — eliminate single points of failure and handle failover gracefully
2. **Maintainability** — retire EOL components (Perl MongoDB driver, Shock, MongoDB 3.4)
3. **Performance** — resolve index/cache pressure on the metadata database
4. **Modernization** — position for OAuth2, Go port, and S3 storage

## Operational Environment

### Data Center Topology

| Facility | Role | Characteristics |
|----------|------|-----------------|
| **B386** | Primary services | Stable power, houses primary databases (MongoDB replica set primary) and web endpoints |
| **B240** | Compute + storage | Power subject to outages for cluster maintenance; contains NetApp NFS filers and compute nodes backing the site |

The MongoDB replica set (`p3-rs-1`) spans both facilities with the primary (`bio-gp`) in B386. Secondaries are distributed across both. NFS storage used by some services lives on NetApp filers in B240, creating a dependency on B240 power for workloads that touch NFS-backed data.

### Maintenance Windows

- **Monthly**: System patch and reboot. Hosts are divided into three tiers; one tier is updated per month.
- **Quarterly**: The tier containing master machines is patched, requiring a full shutdown of the Workspace service and all user compute. This is a ~3-month cycle.
- The quarterly master-tier window is the natural time for deploying major database or service upgrades that require downtime.

### Implications for Upgrade Sequencing

- Database migrations (MongoDB version upgrade, auth schema changes) should target the quarterly master-tier window.
- The retry wrapper and driver upgrade can be deployed during any monthly window since they don't require database downtime.
- B240 power outages mean any component with an NFS dependency on B240 filers will have unplanned downtime — the Workspace service itself (in B386) should remain available if it doesn't depend on B240 NFS.
- Replica set failover during tier maintenance is a real scenario. The retry wrapper directly addresses this.

---

## Workstream 1: MongoDB Retry Wrapper

**Status**: Plan complete, implementation not started
**Risk**: Low
**Effort**: ~3 days
**Reference**: [retry-wrapper-implementation-plan.md](retry-wrapper-implementation-plan.md)

### What

Add application-level retry logic for MongoDB write operations in WorkspaceImpl.pm. When a write fails with a retryable error (e.g., "not master" during failover), the wrapper sleeps with exponential backoff (1s → 2s → 4s) and retries up to 3 times.

### Why

During replica set failover — caused by monthly/quarterly maintenance or unplanned B240 power events — write operations fail immediately with "not master and slaveOK=false". The current code does not retry, so user requests fail even though a new primary is elected within seconds.

### Key Findings (verified 2026-05-28)

- The v0.708 `MongoDB::Connection` is a thin wrapper around `MongoDB::MongoClient`, which has full replica set support including `rs_refresh()`.
- Production uses a 3-node replica set URI, so the driver can discover the new primary.
- `auto_reconnect => 1` is already enabled.
- The `rs_refresh()` method is accessible via `$self->{_mongodb}->_client->rs_refresh()`.
- All Workspace write operations use UUIDs, making retries idempotent. Duplicate key errors on retry are treated as success.

### Dependencies

- None. Works with the current v0.708 driver and MongoDB 3.4.

### Deployment

- Can be deployed in any monthly maintenance window.
- No database changes required.
- Rollback: set `MONGO_RETRY_COUNT => 0` or revert the code.

---

## Workstream 2: Perl MongoDB Driver Upgrade (v0.708 → v2.2.2)

**Status**: Plan complete, prerequisite (auth migration) identified
**Risk**: Medium
**Effort**: ~5 days
**Reference**: [mongodb-perl-driver-status.md](mongodb-perl-driver-status.md)

### What

Upgrade from the v0.708 Perl MongoDB driver to v2.2.2 (the final release). This requires changing ~15 method calls (`insert` → `insert_one`, `update` → `update_one`, `remove` → `delete_one`/`delete_many`, `count` → `count_documents`).

### Is This Necessary?

**If the retry wrapper works solidly with master failover, the driver upgrade becomes less urgent but remains important for two reasons:**

1. **MongoDB server upgrade prerequisite**: The v0.708 driver uses MONGODB-CR authentication and OP_QUERY wire protocol, both of which are removed in MongoDB 5.0+. You cannot upgrade the MongoDB server past 3.4 without upgrading the driver first.

2. **Better failover behavior**: The v2.2.2 driver has more robust replica set handling, automatic primary rediscovery, and built-in connection pooling. Combined with the retry wrapper, this provides defense in depth. The retry wrapper catches what the driver misses; the better driver reduces how often the wrapper needs to fire.

**If the MongoDB server will stay on 3.4 indefinitely**, and the retry wrapper handles failover adequately, the driver upgrade can be deferred. But given that MongoDB 3.4 is EOL (no security patches since January 2020), staying on 3.4 is not a sustainable position.

**Recommendation**: Implement the retry wrapper first (Workstream 1). If failover is solid, schedule the driver upgrade alongside the MongoDB server upgrade (Workstream 5) — do both in the same quarterly window.

### Prerequisites

- **Auth credential migration**: The `authSchemaVersion` is already 5 (SCRAM-SHA-1), but user records still have MONGODB-CR credentials only. Run `db.adminCommand({authSchemaUpgrade: 1})` on the primary to convert. This is safe to do now — the v0.708 driver continues to work after conversion.
- Verify conversion with: `db.getSiblingDB("admin").system.users.find({}, {user: 1, mechanisms: 1, db: 1})` — each user should show `"mechanisms": ["SCRAM-SHA-1"]`.

### Deployment

- Target the quarterly master-tier window, paired with MongoDB server upgrade.
- Auth credential migration can be done earlier (any window) as a preparatory step.

---

## Workstream 3: Remove Shock Storage Layer

**Status**: Plan complete, implementation not started
**Risk**: Low-Medium
**Effort**: ~7 days
**Reference**: [plan-remove-shock-layer.md](plan-remove-shock-layer.md)

### What

Replace the Shock API integration with direct filesystem access. The Workspace service currently routes file I/O through Shock's HTTP API. Since Shock stores files in a deterministic directory structure based on UUID, the Workspace service can read/write directly to the same filesystem, eliminating the HTTP hop.

### Why

- Shock is a single point of failure for all file operations.
- HTTP overhead adds latency to every file read/write.
- Shock has its own MongoDB database and user management that must be maintained in parallel.
- Shock has no active upstream development.

### Key Design Decisions

- **No data migration needed**: The Workspace service reads existing Shock files by extracting the UUID from the stored `shocknode` URL and constructing the filesystem path directly.
- **Dual-mode operation**: A `use-shock` config toggle supports gradual transition. During transition, Option C (use Shock API for node creation, write data directly) maintains compatibility with any direct Shock clients.
- **ACL elimination**: Shock's ACL system is redundant with Workspace permissions and can be dropped entirely.

### Intersection with Go Port

The Shock removal is the recommended **first phase** of the Go port (Workstream 4). Rationale:

- It's the simplest backend change — replacing HTTP calls with filesystem calls.
- It can be done entirely in the existing Perl codebase, validated, and deployed.
- Once Shock is removed, the Go port only needs to implement direct filesystem and S3 backends, not the Shock API client.
- The FileStore.pm module's design (UUID-to-path mapping, read/write/stat/delete) translates directly to Go.

### Dependencies

- None for the Perl implementation. Can proceed independently.
- The S3 storage backend ([plan-s3-storage-backend.md](plan-s3-storage-backend.md)) is a follow-on that adds NetApp S3 as an alternative to direct filesystem. It depends on Shock removal being complete or the storage backend abstraction being in place.

### Deployment

- Can be deployed in any monthly window.
- Rollback: change `use-shock = 1` in config and restart. No data is modified.

---

## Workstream 4: Workspace Go Port

**Status**: Plan complete, early stage
**Risk**: High (largest effort)
**Effort**: Weeks to months
**Reference**: [plan-workspace-go-port.md](plan-workspace-go-port.md)

### What

Rewrite the Workspace service in Go, using the existing BV-BRC-Go-SDK as a foundation. The Go service would be a drop-in replacement speaking the same JSON-RPC protocol, using the same MongoDB schema, and reading the same file storage.

### Why

- Eliminates dependency on EOL Perl MongoDB driver entirely.
- Go has an actively maintained MongoDB driver with full replica set support, retryable writes, and connection pooling.
- Better concurrency model for handling many simultaneous file transfers.
- The Go SDK already has auth, JSON-RPC, and partial Workspace client implementations.

### Sequencing

The Go port is the long-term play. The recommended order is:

1. **Remove Shock** (Workstream 3) — simplifies the Go port by eliminating one backend.
2. **Implement retry wrapper** (Workstream 1) — immediate reliability improvement.
3. **Upgrade MongoDB server** (Workstream 5) — the Go MongoDB driver works best with modern MongoDB.
4. **Port to Go** — build against the post-Shock, post-upgrade infrastructure.
5. **Add S3 backend** — implement in Go rather than Perl, since the Go service will be the long-term home.

### Deployment

- Run the Go service in parallel with the Perl service during validation.
- Traffic can be shifted via load balancer or DNS.
- The JSON-RPC API contract is the compatibility boundary — both implementations serve the same API.

---

## Workstream 5: MongoDB Server Upgrade

**Status**: Planning
**Risk**: Medium-High
**Effort**: ~1-2 weeks including testing
**Target**: MongoDB 5.0+ (Percona Server for MongoDB)

### What

Upgrade the MongoDB server from 3.4.24 to Percona Server for MongoDB 5.0+ (or later). A Percona 5.0.17-14 cluster already exists as an alternate cluster.

### Why

- MongoDB 3.4 has been EOL since January 2020 — no security patches.
- The query planner in 3.4 has known issues (we've hit plan cache problems directly — it cached a plan using `workspace_uuid_1_type_1` for an `$or` query that should have used `workspace_uuid_1_path_1`).
- Server-side retryable writes (available in 3.6+) complement the application-level retry wrapper.
- WiredTiger improvements in newer versions provide better cache efficiency.

### Current Database Profile (verified 2026-05-28)

| Metric | Value |
|--------|-------|
| Data size | 1,168 GB |
| Total index size | 69 GB |
| WiredTiger cache configured | 46.5 GB |
| WiredTiger cache used | 37.2 GB |
| Cache hit rate | ~95.7% |
| Pages evicted by app threads | 0 (background eviction keeping up) |
| Server RAM | ~94 GB |

**Index pressure**: 69 GB of indexes vs 46.5 GB cache means indexes are continuously evicted and re-read from disk. Four unused or nearly-unused indexes total ~19.3 GB:

| Index | Size | Ops (9 days) | Status |
|-------|------|-------------|--------|
| `name_1` | 4.3 GB | 0 | Drop candidate |
| `owner_1_name_1_creation_date_-1` | 11.4 GB | 0 | Drop candidate |
| `type_1` | 1.8 GB | 0 | Drop candidate |
| `workspace_uuid_1_type_1` | 1.8 GB | 35K | Drop candidate (causes bad query plans, covered by 4-field index) |

Dropping these four recovers 19.3 GB, bringing indexes from 69 GB to ~50 GB — at the cache limit. Adding RAM (96 GB → 128-160 GB) would definitively solve the cache pressure.

### Prerequisites

- Perl driver upgrade to v2.2.2 (Workstream 2) — v0.708 cannot authenticate with MongoDB 5.0.
- Auth credential migration to SCRAM-SHA-1 (part of Workstream 2 prerequisites).

### Deployment

- Target the quarterly master-tier window.
- Procedure: upgrade secondaries first, step down primary, upgrade former primary, verify.
- The existing Percona 5.0 alternate cluster can serve as a validation target.

### MongoDB Alternatives: Should We Leave MongoDB?

With hundreds of millions of objects in the store, the question of whether MongoDB remains the right choice deserves examination.

#### Staying with MongoDB

**Pros:**
- Known entity — the schema, indexes, and query patterns are well understood.
- The Go MongoDB driver is actively maintained and full-featured.
- MongoDB handles the Workspace's document-oriented data model naturally (nested metadata, flexible schema).
- Sharding is available if a single replica set becomes insufficient.
- Percona provides enterprise MongoDB with hot backups, audit logging, and encryption at rest.

**Cons:**
- WiredTiger cache pressure at scale requires significant RAM.
- The query planner has surprising behaviors (plan cache, `$or` handling) that require workarounds.
- License changes (SSPL) may create compliance concerns depending on institutional policy.

#### PostgreSQL

**Pros:**
- Mature, stable, open source (true OSS license).
- JSONB columns handle the flexible metadata use case.
- Superior query planner — no plan cache surprises.
- Excellent indexing (GIN indexes on JSONB, partial indexes, expression indexes).
- Strong ecosystem: pgBackRest, Patroni for HA, pg_stat_statements for observability.
- `ltree` extension provides efficient hierarchical path queries (directly applicable to workspace paths).

**Cons:**
- Schema migration effort — the current document-oriented model would need to be mapped to relational tables or heavy JSONB usage.
- Path-based recursive queries need careful design (though `ltree` handles this well).
- Different operational knowledge required.
- Vacuum maintenance becomes important at hundreds of millions of rows.

#### CockroachDB / TiDB (Distributed SQL)

**Pros:**
- Horizontally scalable SQL with automatic sharding.
- Strong consistency, automatic failover.
- SQL compatibility means standard tooling and driver support.

**Cons:**
- Operational complexity for self-hosted deployments.
- Performance characteristics differ from single-node databases — latency can be higher for single-key lookups.
- Smaller ecosystem and fewer battle-tested years at extreme scale.
- Overkill unless the data volume or write throughput exceeds a single machine's capacity.

#### Recommendation

**Stay with MongoDB (Percona) for now.** The reasons:

1. The Workspace schema is a natural fit for document storage.
2. A server upgrade (3.4 → 5.0+) resolves the immediate issues (EOL, plan cache, retryable writes).
3. The Go port will use the actively maintained Go MongoDB driver.
4. The data volume (1.2 TB, hundreds of millions of objects) is well within MongoDB's capacity on a single replica set with adequate RAM.
5. Switching databases would be a multi-month effort that competes with higher-priority work (Go port, Shock removal, OAuth2).

**Revisit if**: write throughput saturates a single primary, the SSPL license becomes a compliance issue, or the Go port provides a natural inflection point for schema redesign.

---

## Workstream 6: OAuth2 / OIDC Migration

**Status**: Plan complete (external)
**Risk**: High (touches every service)
**Reference**: https://github.com/olsonanl/bvbrc_website/blob/alpha/PLAN-oauth2-migration.md

### What

Migrate from the custom RSA-SHA1 pipe-delimited token system to standard OAuth2/OIDC. A new `p3_oidc` service (based on `node-oidc-provider`) issues JWT tokens. This enables third-party login (Google, ORCID, GitHub), browser-based CLI auth via Device Authorization Grant, and proper token rotation.

### Intersection with Workspace

- **Token validation**: The Workspace service validates auth tokens on every request. During the dual-token transition period, it must accept both legacy tokens (`|`-delimited) and JWTs (two `.` separators). The `sub` claim in JWTs is set to `username@realm`, matching the existing identity format — no downstream changes to workspace paths or permissions.
- **Service-to-service auth**: The Workspace service's internal communication with other services (app_service, etc.) will migrate from service tokens to OAuth2 Client Credentials grant.
- **Job token handling**: The current system stores long-lived tokens with submitted jobs. The OAuth2 plan replaces this with one-time job startup tickets exchanged for time-scoped JWTs, which is more secure but requires changes to how the app_service passes credentials to compute jobs.

### Sequencing

OAuth2 migration is largely independent of the Workspace infrastructure upgrades but should be coordinated:

- The retry wrapper, Shock removal, and driver upgrade do not affect auth.
- The Go port should plan for JWT validation from the start (the Go SDK's `auth/token.go` will need to handle both token formats during transition).
- OAuth2 Phase 5 (service-to-service migration) affects how the Workspace service authenticates to other services, but this is a configuration change, not an architectural one.

### Deployment

- Six phases, deployed incrementally.
- Phase 2 (dual-token validation) is the critical gate — once p3_api accepts both formats, the rest can proceed gradually.
- Legacy token deprecation (Phase 6) is 6+ months after Phase 3.

---

## Recommended Sequencing

The workstreams have dependencies and shared deployment windows. Here is the recommended order:

```
Immediate (any monthly window)
├── 1. Retry wrapper implementation
├── 5. Drop unused MongoDB indexes (19.3 GB recovery)
├── 5. Auth credential migration (SCRAM-SHA-1 conversion)
└── 9. SSD Phase 2 easy (hot-add to Solr hosts with empty slots)

Next quarterly master-tier window
├── 3. Shock removal (deploy with use-shock toggle)
├── 6. OAuth2 Phase 1-2 (p3_oidc deploy, dual-token validation)
└── 9. SSD Phase 1 + Phase 2 special (DB server swaps, larch/hemlock/arborvitae)

Following quarterly window
├── 2. Driver upgrade v0.708 → v2.2.2
├── 5. MongoDB server upgrade 3.4 → 5.0+ (Percona)
└── 6. OAuth2 Phase 3-4 (website + CLI OIDC login)

After MongoDB server upgrade
├── 8. Schema redesign: backfill ancestors array (dual-field mode)
├── 8. Schema redesign: cut over reads to ancestors
└── 8. Schema redesign: drop path field and old indexes

Ongoing (months)
├── 4. Go port development (build against ancestors schema)
├── S3 storage backend (in Go)
└── 6. OAuth2 Phase 5-6 (service-to-service, legacy deprecation)
```

### Critical Path

The critical path for the database modernization is:

```
Auth credential migration → Driver upgrade → MongoDB server upgrade → Schema redesign
```

Each step is a prerequisite for the next. The auth migration is safe to do immediately. The driver upgrade and server upgrade should be done together in the same quarterly window. The schema redesign depends on MongoDB 4.2+ for the aggregation pipeline `$set` used in move operations — without it, moves fall back to a slower query-and-update approach.

### Parallel Work

These can proceed in parallel without blocking each other:

- Retry wrapper (independent of everything)
- Shock removal (independent of database changes)
- OAuth2 Phases 1-2 (independent of Workspace internals)
- Go port development (can start anytime, runs alongside Perl service)
- Index cleanup (immediate, independent)
- SSD hot-adds to Solr hosts (independent of software changes)
- Schema redesign development/testing (can be coded and tested before MongoDB upgrade, deployed after)

---

## Risk Summary

| Workstream | Risk | Impact of Failure | Rollback |
|------------|------|-------------------|----------|
| Retry wrapper | Low | Worst case: retries don't help, no change from current behavior | Set retry count to 0 |
| Driver upgrade | Medium | Auth failure, API incompatibility | Revert to v0.708 (keep both installed) |
| Shock removal | Low | File access failure | Set `use-shock = 1` in config |
| Go port | High | Service outage | Route traffic back to Perl service |
| MongoDB upgrade | Medium-High | Data access failure | Revert replica set members (requires planning) |
| OAuth2 | High | Auth outage affecting all services | Dual-token period provides fallback |
| Schema redesign | Medium | Query failures, incorrect results | Dual-field period — fall back to `path` queries |
| SSD upgrades | Low-Medium | Drive failure during swap, RAID rebuild | Keep displaced drives; restore from backup |

---

## Workstream 8: MongoDB Schema Redesign (Ancestors Array)

**Status**: Design complete
**Risk**: Medium (schema migration on hundreds of millions of documents)
**Effort**: ~2 weeks development + migration
**Reference**: [schema-redesign-ancestors-array.md](schema-redesign-ancestors-array.md)

### Problem

The current schema stores hierarchical position as a `path` string (e.g., `"experiments/2024/genome-analysis"`). This causes three operational problems we've hit directly:

1. **Recursive listing requires regex** — `path: /^experiments\/2024/` forces index scans or depends on fragile `hint()` directives. We spent significant effort fixing MongoDB 3.4 query planner bugs where it selected wrong indexes for `$or` queries on path, and even the fixed version requires `workspace_uuid` inside each `$or` branch plus explicit hints.

2. **Renames are O(n)** — renaming a folder updates the `path` string of every descendant. A folder with 100,000 objects underneath requires 100,000 individual document updates.

3. **Deletes walk the tree** — `_delete_object` queries children level by level, deleting one at a time.

### Solution: Ancestors Array Pattern

Replace the `path` string with:
- `ancestors: [UUID_A, UUID_B, UUID_C]` — array of ancestor folder UUIDs, root to parent
- `parent_uuid: UUID_C` — direct parent (last element of ancestors)
- `depth: 3` — length of ancestors array

```javascript
// Current
{ workspace_uuid: "WS", path: "exp/2024/analysis", name: "results.json" }

// Proposed
{ workspace_uuid: "WS", parent_uuid: "ANALYSIS-UUID",
  ancestors: ["EXP-UUID", "2024-UUID", "ANALYSIS-UUID"],
  depth: 3, name: "results.json" }
```

### Impact on Each Operation

| Operation | Current | Proposed | Improvement |
|-----------|---------|----------|-------------|
| Recursive ls | Regex + hint + `$or` workaround | `{ancestors: UUID}` equality match | Eliminates regex, `$or`, hints entirely |
| Non-recursive ls | `{path: "exact"}` | `{parent_uuid: UUID}` | Equivalent |
| Rename (same location) | O(n) descendant updates | O(1) — update folder `name` only | Descendants reference by UUID, not path string |
| Move (different parent) | O(n) query + re-insert each | Single `updateMany` array splice | Still O(n) but one atomic operation |
| Recursive delete | Walk tree level by level | Single `deleteMany` | One query |
| Disk usage (du) | Regex aggregate + hint | `{ancestors: UUID}` aggregate | Clean, no hint needed |
| Path display | Free (stored in `path`) | O(depth) UUID→name lookup | 3-5 docs, cacheable |

### Index Changes

| Remove | Size | Reason |
|--------|------|--------|
| `workspace_uuid_1_path_1` | 2.5 GB | Replaced by ancestors |
| `path_1_workspace_uuid_1` | 4.0 GB | Replaced by ancestors |

| Add | Est. Size | Purpose |
|-----|-----------|---------|
| `{workspace_uuid: 1, ancestors: 1}` | ~7-10 GB | Multikey index for recursive queries |
| `{workspace_uuid: 1, parent_uuid: 1}` | ~2 GB | Non-recursive listing |

The multikey index is 3-4x the current path index size (one entry per array element at avg depth 3-4). This is offset by dropping the 19 GB of unused indexes identified in Workstream 5.

### Migration Strategy

Four-phase dual-field transition — both `path` and `ancestors` maintained simultaneously:

1. **Add fields**: Backfill `parent_uuid`, `ancestors`, `depth` for all existing objects. Source: parse the existing `path` string, look up each component's folder UUID.
2. **Dual-write**: New objects written with both `path` and `ancestors`. Reads use `ancestors` for recursive, `path` as fallback.
3. **Cut over**: All reads use `ancestors`/`parent_uuid`. `path` no longer queried.
4. **Remove**: Drop `path` field and old path indexes.

The backfill processes workspace-by-workspace and can run online. Background index build for the new multikey index.

### Sequencing with Other Workstreams

The schema redesign intersects with:

- **Go port (Workstream 4)**: The Go service can be built against the new schema from the start. If timed together, the schema migration validates during the Go port validation period — the Perl service reads `path`, the Go service reads `ancestors`, both work during dual-field mode.

- **MongoDB server upgrade (Workstream 5)**: The aggregation pipeline `$set` used for move operations (array splice) works on MongoDB 4.2+. If the schema migration happens before the server upgrade, moves must use the slower query-and-update approach. **Recommendation**: do the server upgrade first, then the schema migration.

- **Query performance fixes (current)**: The `$or` restructuring and hint work we've done is a stopgap. The ancestors array eliminates the need for `$or`, regex, and hints entirely — it's the definitive fix.

### Risks

| Risk | Mitigation |
|------|------------|
| Missing folder documents | Some path components may lack MongoDB documents. Backfill script creates them. |
| Multikey index build time | Background build on hundreds of millions of docs. May take hours. |
| Backfill duration | Process workspace-by-workspace. Can pause/resume. |
| Rollback | Keep `path` field until fully validated. Revert reads to path-based queries instantly. |

---

## Workstream 9: SSD Storage Upgrades

**Status**: Inventory complete, allocation planned
**Risk**: Low for Phase 2 (additive); Medium for Phase 1 and special-handling hosts (disk swaps)
**Effort**: ~1-2 days physical installation per phase

### Inventory

| Drive | Quantity |
|-------|----------|
| 3.84 TB SSD | 12 |
| 7.68 TB SSD | 20 |

### Infrastructure Survey Findings (2026-05-28)

A full hardware survey of 45 hosts was conducted using `survey-host.sh` with storcli/MegaCli RAID controller interrogation. The survey identified physical drive types behind RAID controllers (not just `lsblk` ROTA flags, which report the virtual disk type), enclosure slot counts, and empty bays.

Key findings:

- **Most Solr hosts already have SSDs** behind MegaRAID controllers (Micron 5300 1.7TB, Intel 960GB). The `lsblk` ROTA flag was misleading — it reported the RAID virtual disk, not the underlying physical media.
- Solr hosts with 24-slot enclosures have 8-18 empty slots available for adding drives without swapping.
- **Three hosts are all-HDD with no empty slots**: hemlock (12 HDD, enc 0 full), larch (12 HDD, enc 0 full), pecan (8 HDD, enc 32 full).
- Several MongoDB hosts (gum, spruce, maple) have HDD but no RAID controller data (likely direct-attached or different controller type).
- bio-gp (MongoDB primary, 94 GB RAM) is already all-SSD but needs a RAM upgrade.
- pecan (MongoDB secondary) is deprioritized — all HDD, 8 slots full.
- Enclosure 252 on many hosts is an SGPIO virtual enclosure (drive LED controller), not a real drive bay — filtered from slot counts.

### Actual Drive Types (from RAID physical drive data)

| Host | DC | Role | RAID SSDs | RAID HDDs | Real Empty Slots |
|------|-----|------|-----------|-----------|------------------|
| arborvitae | B386 | Solr | 24 | 0 | 0 (enc 0 full) |
| balsam | B386 | Solr | 16 | 0 | 8 (enc 0) |
| bio-gp1 | B240 | Solr | 14 | 0 | 10 (enc 0) |
| bio-gp2 | B240 | Solr | 14 | 0 | 10 (enc 0) |
| bio-gp3 | B240 | Solr | 14 | 0 | 10 (enc 0) |
| butternut | B386 | Solr | 8 | 0 | 16 (enc 0) |
| cottonwood | B240 | Solr | 4 | 2 | 18 (enc 0) |
| hemlock | B240 | Solr+compute | 0 | 12 | 0 (enc 0 full) |
| larch | B386 | MongoDB+Solr | 0 | 12 | 0 (enc 0 full) |
| magnolia | B240 | Solr | 4 | 2 | 18 (enc 0) |
| walnut | B240 | Solr+web | 2 | 0 | 6 (enc 32) |

### Phase 1: Database Servers (10x 3.84TB)

All replacements — swap out existing small HDDs.

| Host | Role | Drives | Notes |
|------|------|--------|-------|
| gum | MongoDB | 2x 3.84TB | Replace 2x 932G HDD. Keep 2x 1.8T HDD for non-DB data |
| spruce | MongoDB | 2x 3.84TB | Replace 2x 932G HDD. Existing 2x 1.8T SSD stay for mongodb-v5 |
| maple | MongoDB, web | 2x 3.84TB | Replace 2x 3.7T HDD |
| aspen | MySQL | 2x 3.84TB | Replace 2x 932G HDD. Existing 2x SSD stay |
| chestnut | MongoDB, Solr | 2x 3.84TB | Replace 2x 932G HDD. 8x SSD already installed |

### Phase 2: Solr Servers (2x 3.84TB + 18x 7.68TB)

Most Solr hosts already have SSD pools. The new drives **add capacity** to existing SSD arrays via empty slots. Each host gets 2x 7.68TB (15.4 TB additional) for balanced capacity growth, except magnolia and walnut which get 1x 3.84TB each.

| Host | DC | Existing SSDs | Empty Slots | Drives | + TB | Notes |
|------|-----|---------------|-------------|--------|------|-------|
| arborvitae | B386 | 24 | 0 | 2x 7.68TB | 15.4 | Enc 0 full — see special handling below |
| balsam | B386 | 16 | 8 | 2x 7.68TB | 15.4 | Add to enc 0 |
| bio-gp1 | B240 | 14 | 10 | 2x 7.68TB | 15.4 | Add to enc 0 |
| bio-gp2 | B240 | 14 | 10 | 2x 7.68TB | 15.4 | Add to enc 0 |
| bio-gp3 | B240 | 14 | 10 | 2x 7.68TB | 15.4 | Add to enc 0 |
| butternut | B386 | 8 | 16 | 2x 7.68TB | 15.4 | Add to enc 0 |
| cottonwood | B240 | 4 | 18 | 2x 7.68TB | 15.4 | Add to enc 0 |
| hemlock | B240 | 0 | 0 | 2x 7.68TB | 15.4 | All HDD — see special handling below |
| larch | B386 | 0 | 0 | 2x 7.68TB | 15.4 | All HDD, also MongoDB — see special handling |
| magnolia | B240 | 4 | 18 | 1x 3.84TB | 3.8 | Add to enc 0 |
| walnut | B240 | 2 | 6 | 1x 3.84TB | 3.8 | Add to enc 32 |

### Hosts Requiring Special Handling

**arborvitae** (B386, Solr): Enc 0 is full at 24/24 (all SSD — 2x Intel 960GB + 22x Micron 1.7TB). No real empty slots. Options:
- Remove 2x older 960GB Intel SSDs from enc 0, replace with 2x 7.68TB (net gain: ~14 TB).
- The displaced 960GB drives can be reused in hosts with empty slots.

**hemlock** (B240, Solr+compute): Enc 0 full with 12x 3TB Seagate HDD. No empty slots in the physical enclosure. Options:
- Swap 2 HDDs out of enc 0, replace with 2x 7.68TB SSDs. Requires RAID rebuild.
- Displaced HDDs can go to compute hosts with empty slots.

**larch** (B386, MongoDB+Solr): Same situation as hemlock — enc 0 full with 12x 3TB Seagate HDD. Highest priority for SSD given MongoDB role (500G LV) alongside Solr (10.2TB LV). Same swap approach as hemlock.

### Allocation Summary

| Pool | Available | Allocated | Remaining |
|------|-----------|-----------|-----------|
| 3.84 TB | 12 | 12 | 0 |
| 7.68 TB | 20 | 18 | 2 (spares) |
| **Total new capacity** | | | **184.3 TB** |

### Displaced HDD Reuse

HDDs removed in Phases 1 and 2 (Phase 1: 10 small HDDs from DB servers; Phase 2: 2 HDDs each from hemlock, larch, and 2 SSDs from arborvitae) can be installed in hosts with empty slots:

| Host | Role | Empty Slots | Enclosure |
|------|------|-------------|-----------|
| ash | slurm_compute | 8 | enc 252 |
| cedar | slurm_compute | 8 | enc 252 |
| cherry | slurm_compute | 3 | enc 32 |
| fir | slurm_compute | 11 | enc 0 (3), enc 252 (8) |
| lemon | slurm_compute | 18 | enc 251 |
| pear | slurm_compute | 3 | enc 32 |
| willow | other | 18 | enc 0 |

### Deployment

- **Phase 1** (DB servers): Can be done during any monthly maintenance window, one host at a time. Each swap is: power down, replace drives, rebuild RAID VD, restore from backup or let RAID rebuild.
- **Phase 2 easy** (balsam, bio-gp1/2/3, butternut, cottonwood, magnolia, walnut): Drives hot-add to empty slots on MegaRAID controllers. A new VD must be created or the existing VD expanded to use the new drives. Possible without downtime on most controllers.
- **Phase 2 special** (arborvitae, hemlock, larch): Requires drive swaps and RAID rebuild. Schedule during quarterly master-tier window for larch (MongoDB). Hemlock and arborvitae can be done in any monthly window with Solr service coordination.

---

## Open Questions

1. **RAM upgrade for bio-gp**: Can the primary MongoDB host be upgraded from 96 GB to 128-160 GB? This would resolve index cache pressure independent of other changes.

2. **Index cleanup authorization**: Can we drop the four identified unused indexes (`name_1`, `owner_1_name_1_creation_date_-1`, `type_1`, `workspace_uuid_1_type_1`)? This is zero-risk for the three with 0 ops but requires confirming `workspace_uuid_1_type_1` (35K ops) has no critical callers.

3. **Percona 5.0 cluster readiness**: The alternate Percona 5.0.17-14 cluster exists. Is it sized and configured for production workload? Can it serve as the upgrade target, or does the existing 3.4 cluster need an in-place upgrade?

4. **B240 NFS dependency**: Which Workspace operations depend on B240 NFS filers? Can the Workspace service remain available during B240 power outages if it's deployed in B386?

5. **Go port timeline**: Is there a target date or event driving the Go port, or is it opportunistic?

6. **S3 backend priority**: The NetApp S3 backend plan exists but its priority relative to the Go port is unclear. Should S3 support be implemented in Perl (faster, throwaway) or wait for the Go port (cleaner, one implementation)?

7. **Schema redesign: implement in Perl or Go?** The ancestors array can be implemented in the current Perl service first (validates the schema before the Go port) or only in the Go service (less throwaway code, but delays the benefits). If the Go port is 6+ months out, implementing in Perl first gives immediate query performance improvements.

8. **Schema redesign: missing folder documents**: The backfill script needs a folder document for every path component. Are there known cases where folder objects are missing from the database? (e.g., objects created by direct MongoDB inserts or migration scripts that skipped folder creation.) A pre-migration audit query can identify these.

9. **Schema redesign: multikey index size vs cache budget**: The `{workspace_uuid, ancestors}` multikey index is estimated at 7-10 GB (3-4x the current 2.5 GB path index). After dropping unused indexes (19 GB freed) and with potential RAM upgrade for bio-gp, is this within budget?
