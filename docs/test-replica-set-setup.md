# Test Replica Set on a Single Machine

Sets up a 3-node replica set on localhost using ports 27117, 27118, 27119.

## Setup

```bash
# Create data directories
mkdir -p /tmp/rs-test/{db0,db1,db2,log}

# Start three mongod instances
mongod --replSet rs-test --port 27117 --dbpath /tmp/rs-test/db0 \
       --logpath /tmp/rs-test/log/db0.log --fork --smallfiles
mongod --replSet rs-test --port 27118 --dbpath /tmp/rs-test/db1 \
       --logpath /tmp/rs-test/log/db1.log --fork --smallfiles
mongod --replSet rs-test --port 27119 --dbpath /tmp/rs-test/db2 \
       --logpath /tmp/rs-test/log/db2.log --fork --smallfiles

# Initialize the replica set
mongo --port 27117 --eval '
rs.initiate({
    _id: "rs-test",
    members: [
        {_id: 0, host: "localhost:27117", priority: 2},
        {_id: 1, host: "localhost:27118", priority: 1},
        {_id: 2, host: "localhost:27119", priority: 1}
    ]
})'

# Wait a few seconds, then verify
mongo --port 27117 --eval 'rs.status().members.forEach(function(m) {
    print(m.name + ": " + m.stateStr)
})'
```

## Enable Authentication

```bash
# Generate a keyfile (shared secret for internal auth)
openssl rand -base64 756 > /tmp/rs-test/keyfile
chmod 400 /tmp/rs-test/keyfile

# First, create an admin user BEFORE enabling auth
mongo --port 27117 --eval '
db.getSiblingDB("admin").createUser({
    user: "admin",
    pwd: "testpassword",
    roles: ["root"]
})
db.getSiblingDB("admin").createUser({
    user: "workspace",
    pwd: "wspassword",
    roles: [{role: "readWrite", db: "WorkspaceTest"}]
})'

# Stop all instances
mongod --dbpath /tmp/rs-test/db0 --shutdown
mongod --dbpath /tmp/rs-test/db1 --shutdown
mongod --dbpath /tmp/rs-test/db2 --shutdown

# Restart with auth enabled
mongod --replSet rs-test --port 27117 --dbpath /tmp/rs-test/db0 \
       --logpath /tmp/rs-test/log/db0.log --fork --smallfiles \
       --keyFile /tmp/rs-test/keyfile
mongod --replSet rs-test --port 27118 --dbpath /tmp/rs-test/db1 \
       --logpath /tmp/rs-test/log/db1.log --fork --smallfiles \
       --keyFile /tmp/rs-test/keyfile
mongod --replSet rs-test --port 27119 --dbpath /tmp/rs-test/db2 \
       --logpath /tmp/rs-test/log/db2.log --fork --smallfiles \
       --keyFile /tmp/rs-test/keyfile

# Verify auth works
mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
      --eval 'rs.status().ok'
```

## Test Failover

```bash
# Connect as admin
mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin

# Force the primary to step down
rs.stepDown()

# Watch election happen (a secondary becomes primary within seconds)
rs.status().members.forEach(function(m) {
    print(m.name + ": " + m.stateStr)
})
```

## Test SCRAM-SHA-1 Authentication

```bash
# Verify auth mechanism
mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
      --eval 'db.getSiblingDB("admin").system.users.find({}, {user:1, mechanisms:1})'

# Should show: "mechanisms": ["SCRAM-SHA-1", "SCRAM-SHA-256"]
```

## Test Workspace Connection

Point a test Workspace instance at the test cluster:

```ini
# test-deploy.cfg
[Workspace]
mongodb-host = mongodb://localhost:27117,localhost:27118,localhost:27119?replicaSet=rs-test
mongodb-database = WorkspaceTest
mongodb-user = workspace
mongodb-pwd = wspassword
```

## Test Driver v2.2.2

```perl
use MongoDB;
my $client = MongoDB->connect(
    "mongodb://localhost:27117,localhost:27118,localhost:27119/?replicaSet=rs-test",
    {
        username => "workspace",
        password => "wspassword",
        auth_mechanism => "SCRAM-SHA-1",
        db_name => "WorkspaceTest",
    }
);
my $db = $client->get_database("WorkspaceTest");
$db->get_collection("test")->insert_one({hello => "world"});
print "Connected and wrote to " . $client->topology_type . "\n";
```

## Cleanup

```bash
mongod --dbpath /tmp/rs-test/db0 --shutdown
mongod --dbpath /tmp/rs-test/db1 --shutdown
mongod --dbpath /tmp/rs-test/db2 --shutdown
rm -rf /tmp/rs-test
```

## Dual-Cluster Migration Test

This simulates the full production migration: p3-rs-1 (3.4) → p3-rs-2 (Percona 5.0).

### Prerequisites

You need both MongoDB 3.4 and Percona 5.0 binaries. Assuming:
- MongoDB 3.4: `/path/to/mongodb-3.4/bin/mongod` (or system default)
- Percona 5.0: `/path/to/percona-5.0/bin/mongod`

Adjust paths below to match your installation.

```bash
MONGO34=/path/to/mongodb-3.4/bin
PERCONA50=/path/to/percona-5.0/bin

# Shared keyfile for both clusters
openssl rand -base64 756 > /tmp/rs-test/keyfile
chmod 400 /tmp/rs-test/keyfile
```

### Start the 3.4 Cluster (simulates p3-rs-1)

```bash
mkdir -p /tmp/rs-test/{old0,old1,old2,old-log}

$MONGO34/mongod --replSet rs-old --port 27117 --dbpath /tmp/rs-test/old0 \
    --logpath /tmp/rs-test/old-log/db0.log --fork --smallfiles

$MONGO34/mongod --replSet rs-old --port 27118 --dbpath /tmp/rs-test/old1 \
    --logpath /tmp/rs-test/old-log/db1.log --fork --smallfiles

$MONGO34/mongod --replSet rs-old --port 27119 --dbpath /tmp/rs-test/old2 \
    --logpath /tmp/rs-test/old-log/db2.log --fork --smallfiles

$MONGO34/bin/mongo --port 27117 --eval '
rs.initiate({
    _id: "rs-old",
    members: [
        {_id: 0, host: "localhost:27117", priority: 2},
        {_id: 1, host: "localhost:27118", priority: 1},
        {_id: 2, host: "localhost:27119", priority: 1}
    ]
})'

# Wait for election, then create users
sleep 5
$MONGO34/bin/mongo --port 27117 --eval '
db.getSiblingDB("admin").createUser({
    user: "admin", pwd: "testpassword", roles: ["root"]
});
db.getSiblingDB("admin").createUser({
    user: "workspace", pwd: "wspassword",
    roles: [{role: "readWrite", db: "WorkspaceBuild"}]
});
db.getSiblingDB("admin").createUser({
    user: "authuser", pwd: "authpassword",
    roles: [{role: "readWrite", db: "p3-user"}]
});'
```

### Populate Test Data on 3.4

```bash
$MONGO34/bin/mongo --port 27117 --eval '
// Simulate workspace objects
var db = db.getSiblingDB("WorkspaceBuild");
var bulk = db.objects.initializeUnorderedBulkOp();
for (var i = 0; i < 10000; i++) {
    bulk.insert({
        workspace_uuid: "TEST-WS-UUID",
        path: "test/path/" + Math.floor(i / 100),
        name: "file-" + i + ".txt",
        uuid: UUID().toString(),
        folder: 0,
        type: "txt",
        size: Math.floor(Math.random() * 100000),
        creation_date: new Date().toISOString(),
        owner: "testuser@bvbrc",
        shock: 0,
        metadata: {}
    });
}
bulk.execute();
print("Inserted " + db.objects.count() + " objects");

// Create indexes matching production
db.objects.createIndex({workspace_uuid: 1, path: 1});
db.objects.createIndex({workspace_uuid: 1, name: 1, creation_date: -1, type: 1});
db.objects.createIndex({uuid: 1});

// Simulate auth data
var auth = db.getSiblingDB("p3-user");
auth.users.insert({username: "testuser@bvbrc", email: "test@example.com", created: new Date()});
print("Auth DB populated");'
```

### Restart 3.4 with Auth (simulates enabling SCRAM-SHA-1)

```bash
# Stop the 3.4 cluster
$MONGO34/mongod --dbpath /tmp/rs-test/old0 --shutdown
$MONGO34/mongod --dbpath /tmp/rs-test/old1 --shutdown
$MONGO34/mongod --dbpath /tmp/rs-test/old2 --shutdown

# Restart with keyfile auth
$MONGO34/mongod --replSet rs-old --port 27117 --dbpath /tmp/rs-test/old0 \
    --logpath /tmp/rs-test/old-log/db0.log --fork --smallfiles \
    --keyFile /tmp/rs-test/keyfile

$MONGO34/mongod --replSet rs-old --port 27118 --dbpath /tmp/rs-test/old1 \
    --logpath /tmp/rs-test/old-log/db1.log --fork --smallfiles \
    --keyFile /tmp/rs-test/keyfile

$MONGO34/mongod --replSet rs-old --port 27119 --dbpath /tmp/rs-test/old2 \
    --logpath /tmp/rs-test/old-log/db2.log --fork --smallfiles \
    --keyFile /tmp/rs-test/keyfile

# Verify auth works
$MONGO34/bin/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'print("Auth OK, RS: " + rs.status().set)'

# Verify SCRAM-SHA-1 credentials
$MONGO34/bin/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'db.getSiblingDB("admin").system.users.find({},{user:1,mechanisms:1}).forEach(printjson)'
```

### Start the Percona 5.0 Cluster (simulates p3-rs-2)

```bash
mkdir -p /tmp/rs-test/{new0,new1,new2,new-log}

$PERCONA50/mongod --replSet rs-new --port 27217 --dbpath /tmp/rs-test/new0 \
    --logpath /tmp/rs-test/new-log/db0.log --fork \
    --keyFile /tmp/rs-test/keyfile

$PERCONA50/mongod --replSet rs-new --port 27218 --dbpath /tmp/rs-test/new1 \
    --logpath /tmp/rs-test/new-log/db1.log --fork \
    --keyFile /tmp/rs-test/keyfile

$PERCONA50/mongod --replSet rs-new --port 27219 --dbpath /tmp/rs-test/new2 \
    --logpath /tmp/rs-test/new-log/db2.log --fork \
    --keyFile /tmp/rs-test/keyfile

$PERCONA50/bin/mongo --port 27217 --eval '
rs.initiate({
    _id: "rs-new",
    members: [
        {_id: 0, host: "localhost:27217", priority: 2},
        {_id: 1, host: "localhost:27218", priority: 1},
        {_id: 2, host: "localhost:27219", priority: 1}
    ]
})'

sleep 5
$PERCONA50/bin/mongo --port 27217 --eval '
db.getSiblingDB("admin").createUser({
    user: "admin", pwd: "testpassword", roles: ["root"]
});
db.getSiblingDB("admin").createUser({
    user: "workspace", pwd: "wspassword",
    roles: [{role: "readWrite", db: "WorkspaceBuild"}]
});
db.getSiblingDB("admin").createUser({
    user: "authuser", pwd: "authpassword",
    roles: [{role: "readWrite", db: "p3-user"}]
});'
```

### Test 1: Migration with mongodump/mongorestore

```bash
# Dump from 3.4 cluster (use the 3.4 mongodump for compatibility)
$MONGO34/bin/mongodump \
    --host "rs-old/localhost:27117,localhost:27118,localhost:27119" \
    -u admin -p testpassword --authenticationDatabase admin \
    --oplog \
    --out /tmp/rs-test/dump \
    --readPreference secondaryPreferred

# Restore to Percona 5.0 cluster
$PERCONA50/bin/mongorestore \
    --host "rs-new/localhost:27217,localhost:27218,localhost:27219" \
    -u admin -p testpassword --authenticationDatabase admin \
    --oplogReplay \
    /tmp/rs-test/dump

# Verify data arrived
$PERCONA50/bin/mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin \
    --eval '
var ws = db.getSiblingDB("WorkspaceBuild");
print("Objects: " + ws.objects.count());
print("Indexes: " + JSON.stringify(ws.objects.getIndexes().map(function(i){return i.name})));
var auth = db.getSiblingDB("p3-user");
print("Auth users: " + auth.users.count());'
```

### Test 2: Driver v0.708 Against Percona 5.0 (should FAIL)

```perl
# This verifies that the old driver cannot connect to 5.0
# Expect: authentication failure
use MongoDB::Connection;
eval {
    my $conn = MongoDB::Connection->new(
        host => "mongodb://localhost:27217,localhost:27218,localhost:27219/?replicaSet=rs-new",
        username => "workspace",
        password => "wspassword",
        db_name => "WorkspaceBuild",
    );
    my $db = $conn->get_database("WorkspaceBuild");
    print "Count: " . $db->get_collection("objects")->count() . "\n";
};
print "Expected failure with v0.708: $@\n" if $@;
```

### Test 3: Driver v2.2.2 Against Percona 5.0 (should PASS)

```perl
use MongoDB;
my $client = MongoDB->connect(
    "mongodb://localhost:27217,localhost:27218,localhost:27219/?replicaSet=rs-new",
    {
        username => "workspace",
        password => "wspassword",
        auth_mechanism => "SCRAM-SHA-1",
        db_name => "WorkspaceBuild",
    }
);
my $db = $client->get_database("WorkspaceBuild");
print "Count: " . $db->get_collection("objects")->count_documents({}) . "\n";
print "Connected OK to Percona 5.0 with v2.2.2 driver\n";
```

### Test 4: Failover with Retry Wrapper

```perl
# Start a write loop, then trigger stepDown in another terminal
use MongoDB;
use Time::HiRes qw(sleep time);

my $client = MongoDB->connect(
    "mongodb://localhost:27217,localhost:27218,localhost:27219/?replicaSet=rs-new",
    {
        username => "workspace",
        password => "wspassword",
        db_name => "WorkspaceBuild",
    }
);
my $coll = $client->get_database("WorkspaceBuild")->get_collection("failover_test");

for my $i (1..100) {
    my $t0 = time();
    eval {
        $coll->insert_one({seq => $i, ts => time()});
    };
    my $elapsed = time() - $t0;
    if ($@) {
        print "WRITE $i FAILED (${elapsed}s): $@";
        sleep(1);  # simulate retry delay
        # Retry
        eval { $coll->insert_one({seq => $i, ts => time(), retry => 1}); };
        if ($@) { print "  RETRY FAILED: $@\n"; }
        else { print "  RETRY OK\n"; }
    } else {
        printf "write %d OK (%.3fs)\n", $i, $elapsed;
    }
    sleep(0.1);
}

# In another terminal, trigger failover:
#   mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin --eval 'rs.stepDown()'
```

### Test 5: Query Planner Comparison

Verify the Percona 5.0 planner handles the `$or` query correctly without hints:

```bash
$PERCONA50/bin/mongo --port 27217 -u workspace -p wspassword \
    --authenticationDatabase WorkspaceBuild --eval '
var db = db.getSiblingDB("WorkspaceBuild");
var explain = db.objects.find({
    "$or": [
        {workspace_uuid: "TEST-WS-UUID", path: "test/path/5"},
        {workspace_uuid: "TEST-WS-UUID", path: /^test\/path\/5\//}
    ]
}).explain("executionStats");
print("Plan: " + explain.queryPlanner.winningPlan.stage);
print("Keys examined: " + explain.executionStats.totalKeysExamined);
print("Docs returned: " + explain.executionStats.nReturned);
print("Time: " + explain.executionStats.executionTimeMillis + "ms");'
```

### Test 6: Incremental Sync (simulates cutover delta)

```bash
# Write some new data to the 3.4 cluster after the initial dump
$MONGO34/bin/mongo --port 27117 -u workspace -p wspassword \
    --authenticationDatabase WorkspaceBuild --eval '
var db = db.getSiblingDB("WorkspaceBuild");
for (var i = 0; i < 100; i++) {
    db.objects.insert({
        workspace_uuid: "TEST-WS-UUID",
        path: "post-dump",
        name: "new-file-" + i,
        uuid: UUID().toString(),
        folder: 0, type: "txt", size: 42,
        creation_date: new Date().toISOString(),
        owner: "testuser@bvbrc", shock: 0, metadata: {}
    });
}'

# Dump just the WorkspaceBuild database again (full, since incremental
# oplog-based delta is complex to set up in test)
$MONGO34/bin/mongodump \
    --host "rs-old/localhost:27117" \
    -u admin -p testpassword --authenticationDatabase admin \
    --db WorkspaceBuild \
    --out /tmp/rs-test/dump-delta

# Restore with --drop to replace (in production you'd use oplog-based sync)
$PERCONA50/bin/mongorestore \
    --host "rs-new/localhost:27217" \
    -u admin -p testpassword --authenticationDatabase admin \
    --drop \
    /tmp/rs-test/dump-delta

# Verify counts match
$MONGO34/bin/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'print("3.4 count: " + db.getSiblingDB("WorkspaceBuild").objects.count())'

$PERCONA50/bin/mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'print("5.0 count: " + db.getSiblingDB("WorkspaceBuild").objects.count())'
```

### Cleanup

```bash
# Stop all instances
$MONGO34/mongod --dbpath /tmp/rs-test/old0 --shutdown
$MONGO34/mongod --dbpath /tmp/rs-test/old1 --shutdown
$MONGO34/mongod --dbpath /tmp/rs-test/old2 --shutdown
$PERCONA50/mongod --dbpath /tmp/rs-test/new0 --shutdown
$PERCONA50/mongod --dbpath /tmp/rs-test/new1 --shutdown
$PERCONA50/mongod --dbpath /tmp/rs-test/new2 --shutdown
rm -rf /tmp/rs-test
```

## Notes

- `--smallfiles` reduces preallocated journal size (good for test, not for production)
- On MongoDB 3.4 use `--smallfiles`; on Percona 5.0 this flag is removed (WiredTiger manages automatically)
- The keyfile enables SCRAM-SHA authentication, which is the same mechanism production will use after the auth migration
- Use 3.4's `mongodump` for dumping from 3.4 and 5.0's `mongorestore` for restoring to 5.0 — this handles any BSON format differences
- The test data is small; production migration of 1.2 TB will take hours but follows the same procedure
