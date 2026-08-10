# Replication & Migration Testing Checklist

Date: 2026-05-29
Reference: [test-replica-set-setup.md](test-replica-set-setup.md)

## Prerequisites

- [ ] MongoDB 3.4 binaries available at: `________________`
- [ ] Percona 5.0 binaries available at: `________________`
- [ ] Perl MongoDB driver v0.708 available (current production)
- [ ] Perl MongoDB driver v2.2.2 installed or available for testing
- [ ] Shock binary available at `/vol/patric3/production/shock/bin/shock-server`
- [ ] Test host identified: `________________`
- [ ] Sufficient disk space for test data directories (~5 GB)

## Phase 1: Single-Cluster Basics

### 1.1 MongoDB 3.4 Replica Set

- [ ] Start 3-node 3.4 replica set (ports 27117-27119)
- [ ] `rs.initiate()` succeeds
- [ ] All three members reach SECONDARY/PRIMARY state
- [ ] Create admin and workspace users
- [ ] Verify: `rs.status()` shows all members healthy

### 1.2 Authentication on 3.4

- [ ] Stop cluster, restart with `--keyFile`
- [ ] Connect with admin credentials succeeds
- [ ] Connect without credentials fails
- [ ] Verify user mechanisms: `db.getSiblingDB("admin").system.users.find({},{user:1,mechanisms:1})`
- [ ] Note mechanism type: ________________ (expect SCRAM-SHA-1 for new users on 3.4)

### 1.3 Failover on 3.4

- [ ] `rs.stepDown()` on primary
- [ ] New primary elected within seconds
- [ ] Writes to new primary succeed
- [ ] Old primary rejoins as secondary

### 1.4 Percona 5.0 Replica Set

- [ ] Start 3-node Percona 5.0 replica set (ports 27217-27219) with `--keyFile`
- [ ] `rs.initiate()` succeeds
- [ ] Create admin and workspace users
- [ ] All members reach SECONDARY/PRIMARY state

### 1.5 Failover on 5.0

- [ ] `rs.stepDown()` on primary
- [ ] New primary elected
- [ ] Writes succeed on new primary
- [ ] Old primary rejoins

## Phase 2: Driver Compatibility

### 2.1 v0.708 Driver Against 3.4

- [ ] Connect with `MongoDB::Connection` succeeds
- [ ] `insert()` succeeds
- [ ] `find()` returns results
- [ ] `update()` succeeds
- [ ] `remove()` succeeds
- [ ] `count()` returns correct number

### 2.2 v0.708 Driver Against Percona 5.0

- [ ] Connect attempt — expected result: **FAIL**
- [ ] Document the error message: `________________`
- [ ] Confirms: driver upgrade is required before migration

### 2.3 v2.2.2 Driver Against 3.4

- [ ] Connect with `MongoDB::MongoClient` succeeds
- [ ] `insert_one()` succeeds
- [ ] `find()` returns results
- [ ] `update_one()` succeeds
- [ ] `delete_one()` succeeds
- [ ] `count_documents()` returns correct number

### 2.4 v2.2.2 Driver Against Percona 5.0

- [ ] Connect succeeds
- [ ] All CRUD operations work
- [ ] Auth mechanism negotiated: ________________ (expect SCRAM-SHA-256 or SCRAM-SHA-1)

### 2.5 v2.2.2 Driver Replica Set Awareness

- [ ] Connect with replica set URI: `mongodb://localhost:27217,localhost:27218,localhost:27219/?replicaSet=rs-new`
- [ ] Writes go to primary
- [ ] `rs.stepDown()` — driver reconnects to new primary automatically
- [ ] Write after failover succeeds without manual intervention
- [ ] Time to recover: ________________ seconds

## Phase 3: Retry Wrapper

### 3.1 Retry on v0.708 (3.4 cluster)

- [ ] Start write loop script
- [ ] Trigger `rs.stepDown()` during writes
- [ ] Retry wrapper catches "not master" error
- [ ] `rs_refresh()` via `$self->{_mongodb}->_client->rs_refresh()` succeeds
- [ ] Writes resume after retry delay
- [ ] No duplicate documents (UUID-based idempotency)
- [ ] Count retries triggered: ________________
- [ ] Max failover gap: ________________ seconds

### 3.2 Retry on v2.2.2 (5.0 cluster)

- [ ] Start write loop script
- [ ] Trigger `rs.stepDown()` during writes
- [ ] Driver handles failover (may not need application retry)
- [ ] Writes resume
- [ ] Time to recover: ________________ seconds

## Phase 4: Data Migration

### 4.1 Populate Test Data on 3.4

- [ ] Insert 10,000 workspace objects
- [ ] Create production-matching indexes (`workspace_uuid_1_path_1`, `uuid_1`, etc.)
- [ ] Insert auth test data in `p3-user` database
- [ ] Record object count: ________________
- [ ] Record index list: ________________

### 4.2 mongodump from 3.4

- [ ] `mongodump --oplog` completes successfully
- [ ] Dump size: ________________
- [ ] Duration: ________________
- [ ] Oplog timestamp recorded: ________________

### 4.3 mongorestore to 5.0

- [ ] `mongorestore --oplogReplay` completes successfully
- [ ] Duration: ________________
- [ ] Object count on 5.0 matches 3.4: ________________
- [ ] Auth data count matches: ________________
- [ ] Indexes rebuilt correctly: ________________
- [ ] Spot-check: query a specific workspace UUID returns correct results

### 4.4 Incremental Sync

- [ ] Insert additional data on 3.4 after initial dump
- [ ] Perform incremental dump
- [ ] Restore incremental to 5.0
- [ ] Final counts match between clusters
- [ ] No duplicate documents

### 4.5 Index Cleanup

- [ ] Drop `name_1` on 5.0 — no query regressions
- [ ] Drop `owner_1_name_1_creation_date_-1` on 5.0 — no query regressions
- [ ] Drop `type_1` on 5.0 — no query regressions
- [ ] Drop `workspace_uuid_1_type_1` on 5.0 — verify `$or` queries still work

## Phase 5: Query Planner Validation

### 5.1 $or Query Without Hint on 5.0

- [ ] Run the `$or` path query with `workspace_uuid` inside each branch
- [ ] `explain()` shows IXSCAN on both branches
- [ ] No hint required
- [ ] `keysExamined` ≈ `nReturned`
- [ ] Execution time: ________________ ms

### 5.2 $or Query With Hint on 5.0

- [ ] Same query with `.hint("workspace_uuid_1_path_1")`
- [ ] Compare execution stats — should be similar to unhinted
- [ ] Conclusion: hints needed on 5.0? ________________

### 5.3 Regex Path Query (old style)

- [ ] `path: /^test\/path(/|$)/` with `workspace_uuid` at top level
- [ ] Does 5.0 planner handle this correctly without hints?
- [ ] Conclusion: ________________

## Phase 6: Shock Integration

### 6.1 Shock Startup

- [ ] Start Shock on port 17078 with `ShockTest` database
- [ ] `curl http://localhost:17078/` returns Shock status
- [ ] Shock log shows successful MongoDB connection

### 6.2 Shock Operations

- [ ] Create node: `curl -X POST http://localhost:17078/node` returns node ID
- [ ] Upload file to node succeeds
- [ ] Download file from node returns correct content
- [ ] File appears on disk at expected path: `data/XX/YY/ZZ/UUID/UUID.data`

### 6.3 Workspace → Shock (use-shock = 1)

- [ ] Configure test Workspace with `shock-url = http://localhost:17078`
- [ ] Create a file through Workspace API
- [ ] File stored in Shock (shocknode URL in MongoDB)
- [ ] Download through Workspace API returns correct content

### 6.4 Workspace Direct Access (use-shock = 0)

- [ ] Switch Workspace to `use-shock = 0`, `file-store-path = /tmp/shock-test/data`
- [ ] **Existing** Shock files still downloadable via Workspace API
- [ ] UUID extracted correctly from shocknode URL
- [ ] File path constructed correctly: `data/XX/YY/ZZ/UUID/UUID.data`
- [ ] Content matches original upload

### 6.5 New Files with Direct Storage

- [ ] Create a new file with `use-shock = 0`
- [ ] File written directly to filesystem (not through Shock API)
- [ ] File downloadable through Workspace API
- [ ] Shock service not contacted

## Phase 7: End-to-End Migration Rehearsal

### 7.1 Simulate Production Cutover

- [ ] Both clusters running (3.4 on 27117-27119, 5.0 on 27217-27219)
- [ ] Workspace running against 3.4 cluster
- [ ] Initial mongodump/mongorestore complete
- [ ] Stop Workspace
- [ ] Final incremental sync
- [ ] Switch Workspace `deploy.cfg` to point at 5.0 cluster
- [ ] Start Workspace with v2.2.2 driver
- [ ] Workspace operations work (ls, create, download)
- [ ] Auth operations work

### 7.2 Rollback Test

- [ ] Stop Workspace
- [ ] Switch `deploy.cfg` back to 3.4 cluster
- [ ] Restart Workspace with v0.708 driver
- [ ] Operations work (data written to 5.0 during test is lost, as expected)
- [ ] Confirm: rollback is clean with no data corruption on 3.4

### 7.3 Timing

- [ ] Total cutover window (stop → sync → config → restart → verify): ________________ minutes
- [ ] Acceptable for production? ________________

## Sign-Off

| Phase | Date Completed | Tester | Notes |
|-------|---------------|--------|-------|
| Phase 1: Single-cluster basics | | | |
| Phase 2: Driver compatibility | | | |
| Phase 3: Retry wrapper | | | |
| Phase 4: Data migration | | | |
| Phase 5: Query planner | | | |
| Phase 6: Shock integration | | | |
| Phase 7: End-to-end rehearsal | | | |
