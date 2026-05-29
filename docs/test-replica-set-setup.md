# Test Replica Set Setup on hemlock

Host: hemlock.cels.anl.gov
MongoDB 3.4 binaries: `/ws-test/mongo-3.4/mongodb-linux-x86_64-3.4.24/bin`
Data directories: `/ws-test/mongo-3.4/data`
Ports: 27117, 27118, 27119 (3.4 cluster), 27217, 27218, 27219 (Percona 5.0 cluster)

## Environment

```bash
export MONGO34=/ws-test/mongo-3.4/mongodb-linux-x86_64-3.4.24/bin
export TESTHOST=hemlock.cels.anl.gov
export DATADIR=/ws-test/mongo-3.4/data
```

## Single 3.4 Replica Set

### Setup

```bash
mkdir -p $DATADIR/{db0,db1,db2,log}

# Generate keyfile for auth (shared by all nodes and both clusters)
openssl rand -base64 756 > $DATADIR/keyfile
chmod 400 $DATADIR/keyfile

# Start three instances WITHOUT auth first (need to create users)
$MONGO34/mongod --replSet rs-test --port 27117 --dbpath $DATADIR/db0 \
       --logpath $DATADIR/log/db0.log --fork --smallfiles --bind_ip 0.0.0.0

$MONGO34/mongod --replSet rs-test --port 27118 --dbpath $DATADIR/db1 \
       --logpath $DATADIR/log/db1.log --fork --smallfiles --bind_ip 0.0.0.0

$MONGO34/mongod --replSet rs-test --port 27119 --dbpath $DATADIR/db2 \
       --logpath $DATADIR/log/db2.log --fork --smallfiles --bind_ip 0.0.0.0

# Initialize replica set using the real hostname (not localhost)
$MONGO34/mongo --port 27117 --eval '
rs.initiate({
    _id: "rs-test",
    members: [
        {_id: 0, host: "hemlock.cels.anl.gov:27117", priority: 2},
        {_id: 1, host: "hemlock.cels.anl.gov:27118", priority: 1},
        {_id: 2, host: "hemlock.cels.anl.gov:27119", priority: 1}
    ]
})'

# Wait for election, then verify
sleep 5
$MONGO34/mongo --port 27117 --eval 'rs.status().members.forEach(function(m) {
    print(m.name + ": " + m.stateStr)
})'
```

### Create Users

```bash
$MONGO34/mongo --port 27117 --eval '
db.getSiblingDB("admin").createUser({
    user: "admin",
    pwd: "testpassword",
    roles: ["root"]
});
db.getSiblingDB("admin").createUser({
    user: "workspace",
    pwd: "wspassword",
    roles: [{role: "readWrite", db: "WorkspaceBuild"}]
});
db.getSiblingDB("admin").createUser({
    user: "authuser",
    pwd: "authpassword",
    roles: [{role: "readWrite", db: "p3-user"}]
});'
```

### Enable Authentication

```bash
# Stop all instances
$MONGO34/mongod --dbpath $DATADIR/db0 --shutdown
$MONGO34/mongod --dbpath $DATADIR/db1 --shutdown
$MONGO34/mongod --dbpath $DATADIR/db2 --shutdown

# Restart with keyfile auth
$MONGO34/mongod --replSet rs-test --port 27117 --dbpath $DATADIR/db0 \
       --logpath $DATADIR/log/db0.log --fork --smallfiles --bind_ip 0.0.0.0 \
       --keyFile $DATADIR/keyfile

$MONGO34/mongod --replSet rs-test --port 27118 --dbpath $DATADIR/db1 \
       --logpath $DATADIR/log/db1.log --fork --smallfiles --bind_ip 0.0.0.0 \
       --keyFile $DATADIR/keyfile

$MONGO34/mongod --replSet rs-test --port 27119 --dbpath $DATADIR/db2 \
       --logpath $DATADIR/log/db2.log --fork --smallfiles --bind_ip 0.0.0.0 \
       --keyFile $DATADIR/keyfile

# Verify auth works
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
      --eval 'rs.status().ok'
```

### Test Failover

```bash
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin

# In the shell:
rs.stepDown()

rs.status().members.forEach(function(m) {
    print(m.name + ": " + m.stateStr)
})
```

### Test SCRAM-SHA-1 Authentication

```bash
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
      --eval 'db.getSiblingDB("admin").system.users.find({}, {user:1, mechanisms:1}).forEach(printjson)'
```

### Test Workspace Connection

```ini
# test-deploy.cfg
[Workspace]
mongodb-host = mongodb://hemlock.cels.anl.gov:27117,hemlock.cels.anl.gov:27118,hemlock.cels.anl.gov:27119?replicaSet=rs-test
mongodb-database = WorkspaceTest
mongodb-user = workspace
mongodb-pwd = wspassword
```

### Test Driver v2.2.2

```perl
use MongoDB;
my $client = MongoDB->connect(
    "mongodb://hemlock.cels.anl.gov:27117,hemlock.cels.anl.gov:27118,hemlock.cels.anl.gov:27119/?replicaSet=rs-test",
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

### Cleanup (single cluster only)

```bash
$MONGO34/mongod --dbpath $DATADIR/db0 --shutdown
$MONGO34/mongod --dbpath $DATADIR/db1 --shutdown
$MONGO34/mongod --dbpath $DATADIR/db2 --shutdown
rm -rf $DATADIR/{db0,db1,db2,log}
```

---

## Dual-Cluster Migration Test

Simulates the full production migration: p3-rs-1 (3.4) → p3-rs-2 (Percona 5.0).

### Prerequisites

Percona 5.0 binaries must be installed. Set the path:

```bash
export PERCONA50=/path/to/percona-5.0/bin
```

### Start the 3.4 Cluster (simulates p3-rs-1)

```bash
mkdir -p $DATADIR/{old0,old1,old2,old-log}

$MONGO34/mongod --replSet rs-old --port 27117 --dbpath $DATADIR/old0 \
    --logpath $DATADIR/old-log/db0.log --fork --smallfiles --bind_ip 0.0.0.0

$MONGO34/mongod --replSet rs-old --port 27118 --dbpath $DATADIR/old1 \
    --logpath $DATADIR/old-log/db1.log --fork --smallfiles --bind_ip 0.0.0.0

$MONGO34/mongod --replSet rs-old --port 27119 --dbpath $DATADIR/old2 \
    --logpath $DATADIR/old-log/db2.log --fork --smallfiles --bind_ip 0.0.0.0

$MONGO34/mongo --port 27117 --eval '
rs.initiate({
    _id: "rs-old",
    members: [
        {_id: 0, host: "hemlock.cels.anl.gov:27117", priority: 2},
        {_id: 1, host: "hemlock.cels.anl.gov:27118", priority: 1},
        {_id: 2, host: "hemlock.cels.anl.gov:27119", priority: 1}
    ]
})'

sleep 5
$MONGO34/mongo --port 27117 --eval '
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

# Stop and restart with auth
$MONGO34/mongod --dbpath $DATADIR/old0 --shutdown
$MONGO34/mongod --dbpath $DATADIR/old1 --shutdown
$MONGO34/mongod --dbpath $DATADIR/old2 --shutdown

$MONGO34/mongod --replSet rs-old --port 27117 --dbpath $DATADIR/old0 \
    --logpath $DATADIR/old-log/db0.log --fork --smallfiles --bind_ip 0.0.0.0 \
    --keyFile $DATADIR/keyfile

$MONGO34/mongod --replSet rs-old --port 27118 --dbpath $DATADIR/old1 \
    --logpath $DATADIR/old-log/db1.log --fork --smallfiles --bind_ip 0.0.0.0 \
    --keyFile $DATADIR/keyfile

$MONGO34/mongod --replSet rs-old --port 27119 --dbpath $DATADIR/old2 \
    --logpath $DATADIR/old-log/db2.log --fork --smallfiles --bind_ip 0.0.0.0 \
    --keyFile $DATADIR/keyfile
```

### Populate Test Data on 3.4

```bash
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin --eval '
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

db.objects.createIndex({workspace_uuid: 1, path: 1});
db.objects.createIndex({workspace_uuid: 1, name: 1, creation_date: -1, type: 1});
db.objects.createIndex({uuid: 1});

var auth = db.getSiblingDB("p3-user");
auth.users.insert({username: "testuser@bvbrc", email: "test@example.com", created: new Date()});
print("Auth DB populated");'
```

### Start the Percona 5.0 Cluster (simulates p3-rs-2)

```bash
mkdir -p $DATADIR/{new0,new1,new2,new-log}

$PERCONA50/mongod --replSet rs-new --port 27217 --dbpath $DATADIR/new0 \
    --logpath $DATADIR/new-log/db0.log --fork --bind_ip 0.0.0.0 \
    --keyFile $DATADIR/keyfile

$PERCONA50/mongod --replSet rs-new --port 27218 --dbpath $DATADIR/new1 \
    --logpath $DATADIR/new-log/db1.log --fork --bind_ip 0.0.0.0 \
    --keyFile $DATADIR/keyfile

$PERCONA50/mongod --replSet rs-new --port 27219 --dbpath $DATADIR/new2 \
    --logpath $DATADIR/new-log/db2.log --fork --bind_ip 0.0.0.0 \
    --keyFile $DATADIR/keyfile

$PERCONA50/mongo --port 27217 --eval '
rs.initiate({
    _id: "rs-new",
    members: [
        {_id: 0, host: "hemlock.cels.anl.gov:27217", priority: 2},
        {_id: 1, host: "hemlock.cels.anl.gov:27218", priority: 1},
        {_id: 2, host: "hemlock.cels.anl.gov:27219", priority: 1}
    ]
})'

sleep 5
$PERCONA50/mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin --eval '
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

Note: Percona 5.0 with `--keyFile` requires auth from the start. The `rs.initiate()` works without auth on the localhost exception, but user creation needs to happen through that exception before any remote connections. If the above fails, start without `--keyFile`, create users, then restart with it.

### Test 1: Migration with mongodump/mongorestore

```bash
mkdir -p $DATADIR/dump

# Dump from 3.4 (use 3.4's mongodump)
$MONGO34/mongodump \
    --host "rs-old/hemlock.cels.anl.gov:27117,hemlock.cels.anl.gov:27118,hemlock.cels.anl.gov:27119" \
    -u admin -p testpassword --authenticationDatabase admin \
    --oplog \
    --out $DATADIR/dump \
    --readPreference secondaryPreferred

# Restore to 5.0 (use 5.0's mongorestore)
$PERCONA50/mongorestore \
    --host "rs-new/hemlock.cels.anl.gov:27217,hemlock.cels.anl.gov:27218,hemlock.cels.anl.gov:27219" \
    -u admin -p testpassword --authenticationDatabase admin \
    --oplogReplay \
    $DATADIR/dump

# Verify
$PERCONA50/mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin --eval '
var ws = db.getSiblingDB("WorkspaceBuild");
print("Objects: " + ws.objects.count());
print("Indexes: " + JSON.stringify(ws.objects.getIndexes().map(function(i){return i.name})));
var auth = db.getSiblingDB("p3-user");
print("Auth users: " + auth.users.count());'
```

### Test 2: Driver v0.708 Against Percona 5.0 (should FAIL)

```perl
use MongoDB::Connection;
eval {
    my $conn = MongoDB::Connection->new(
        host => "mongodb://hemlock.cels.anl.gov:27217,hemlock.cels.anl.gov:27218,hemlock.cels.anl.gov:27219/?replicaSet=rs-new",
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
    "mongodb://hemlock.cels.anl.gov:27217,hemlock.cels.anl.gov:27218,hemlock.cels.anl.gov:27219/?replicaSet=rs-new",
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
    "mongodb://hemlock.cels.anl.gov:27217,hemlock.cels.anl.gov:27218,hemlock.cels.anl.gov:27219/?replicaSet=rs-new",
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
        sleep(1);
        eval { $coll->insert_one({seq => $i, ts => time(), retry => 1}); };
        if ($@) { print "  RETRY FAILED: $@\n"; }
        else { print "  RETRY OK\n"; }
    } else {
        printf "write %d OK (%.3fs)\n", $i, $elapsed;
    }
    sleep(0.1);
}

# In another terminal, trigger failover:
#   $PERCONA50/mongo --port 27217 -u admin -p testpassword \
#       --authenticationDatabase admin --eval 'rs.stepDown()'
```

### Test 5: Query Planner Comparison

Verify Percona 5.0 handles the `$or` query correctly without hints:

```bash
$PERCONA50/mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin --eval '
var db = db.getSiblingDB("WorkspaceBuild");
var explain = db.objects.find({
    "$or": [
        {workspace_uuid: "TEST-WS-UUID", path: "test/path/5"},
        {workspace_uuid: "TEST-WS-UUID", path: /^test\/path\/5\//}
    ]
}).explain("executionStats");
printjson({
    plan: explain.queryPlanner.winningPlan.stage,
    keysExamined: explain.executionStats.totalKeysExamined,
    docsReturned: explain.executionStats.nReturned,
    timeMs: explain.executionStats.executionTimeMillis
});'
```

### Test 6: Incremental Sync (simulates cutover delta)

```bash
# Write new data to 3.4 after the initial dump
$MONGO34/mongo --port 27117 -u workspace -p wspassword \
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

# Full re-dump of WorkspaceBuild
$MONGO34/mongodump \
    --host "rs-old/hemlock.cels.anl.gov:27117" \
    -u admin -p testpassword --authenticationDatabase admin \
    --db WorkspaceBuild \
    --out $DATADIR/dump-delta

# Restore with --drop
$PERCONA50/mongorestore \
    --host "rs-new/hemlock.cels.anl.gov:27217" \
    -u admin -p testpassword --authenticationDatabase admin \
    --drop \
    $DATADIR/dump-delta

# Verify counts match
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'print("3.4 count: " + db.getSiblingDB("WorkspaceBuild").objects.count())'

$PERCONA50/mongo --port 27217 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'print("5.0 count: " + db.getSiblingDB("WorkspaceBuild").objects.count())'
```

### Cleanup (dual cluster)

```bash
$MONGO34/mongod --dbpath $DATADIR/old0 --shutdown
$MONGO34/mongod --dbpath $DATADIR/old1 --shutdown
$MONGO34/mongod --dbpath $DATADIR/old2 --shutdown
$PERCONA50/mongod --dbpath $DATADIR/new0 --shutdown
$PERCONA50/mongod --dbpath $DATADIR/new1 --shutdown
$PERCONA50/mongod --dbpath $DATADIR/new2 --shutdown
rm -rf $DATADIR/{old0,old1,old2,old-log,new0,new1,new2,new-log,dump,dump-delta}
```

---

## Test Shock Service

Sets up a local Shock instance using the production binary, pointed at a test database on one of the test MongoDB instances. No replication needed.

### Setup

```bash
mkdir -p /ws-test/shock-test/{data,logs,site}

cat > /ws-test/shock-test/shock.cfg <<'EOF'
[Address]
api-ip=0.0.0.0
api-port=17078

[Admin]
email=test@test.com
users=olson

[Anonymous]
read=true
write=false
create-user=false

[Auth]
globus_token_url=https://p3.theseed.org/goauth/token?grant_type=client_credentials
globus_profile_url=https://p3.theseed.org/users

[External]
api-url=

[Log]
perf_log=false

[Mongodb]
hosts=hemlock.cels.anl.gov:27117
database=ShockTest
user=
password=
attribute_indexes=

[Mongodb-Node-Indices]
id=unique:true

[Paths]
site=/ws-test/shock-test/site
data=/ws-test/shock-test/data
logs=/ws-test/shock-test/logs
local_paths=
pidfile=/ws-test/shock-test/shock.pid

[Runtime]
GOMAXPROCS=
EOF
```

If the test MongoDB has auth enabled, create a Shock user first:

```bash
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin --eval '
db.getSiblingDB("ShockTest").createUser({
    user: "shock", pwd: "shocktest",
    roles: [{role: "readWrite", db: "ShockTest"}]
})'
```

Then set `user=shock` and `password=shocktest` in the `[Mongodb]` section of `shock.cfg`.

### Start Shock

```bash
/vol/patric3/production/shock/bin/shock-server \
    -conf /ws-test/shock-test/shock.cfg &

# Or daemonize:
daemonize -e /ws-test/shock-test/logs/shock.stderr \
          -o /ws-test/shock-test/logs/shock.stdout \
          -p /ws-test/shock-test/shock.pid \
          /vol/patric3/production/shock/bin/shock-server \
          -conf /ws-test/shock-test/shock.cfg

# Verify
curl http://hemlock.cels.anl.gov:17078/
```

### Test Shock Operations

```bash
# Create a node
curl -X POST http://hemlock.cels.anl.gov:17078/node

# Upload a file
echo "test content" > /ws-test/shock-test/testfile.txt
curl -X POST -F "upload=@/ws-test/shock-test/testfile.txt" http://hemlock.cels.anl.gov:17078/node

# List nodes
curl http://hemlock.cels.anl.gov:17078/node?limit=10

# Download (replace NODE_ID with actual ID from create response)
curl http://hemlock.cels.anl.gov:17078/node/NODE_ID?download
```

### Test Workspace with Shock

```ini
# test-deploy.cfg
[Workspace]
mongodb-host = hemlock.cels.anl.gov:27117
mongodb-database = WorkspaceTest
mongodb-user = workspace
mongodb-pwd = wspassword
shock-url = http://hemlock.cels.anl.gov:17078
```

### Test Shock Removal (Workstream 3)

```bash
# 1. Upload a file through Workspace with use-shock = 1
# 2. Note the shocknode URL in MongoDB
# 3. Switch to use-shock = 0, set file-store-path = /ws-test/shock-test/data
# 4. Download the same file through Workspace
# 5. Verify content matches

# Check data directory structure:
find /ws-test/shock-test/data -name '*.data' | head -5
# Should show: data/XX/YY/ZZ/UUID/UUID.data
```

### Cleanup

```bash
kill $(cat /ws-test/shock-test/shock.pid 2>/dev/null) 2>/dev/null

$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'db.getSiblingDB("ShockTest").dropDatabase()'

rm -rf /ws-test/shock-test
```

---

## Notes

- `--smallfiles` reduces preallocated journal size (3.4 only; Percona 5.0 manages automatically)
- `--bind_ip 0.0.0.0` allows connections from other hosts if needed for testing
- All replica set members use `hemlock.cels.anl.gov` as hostname (not localhost) so connection strings work from remote hosts
- Use 3.4's `mongodump` for dumping from 3.4 and 5.0's `mongorestore` for restoring to 5.0
- The keyfile in `$DATADIR/keyfile` is shared between both clusters for simplicity
- Shock uses port 17078 to avoid clashing with any production instance on 7078
- Shock points at the 3.4 cluster (port 27117) since that simulates the production setup
