# Test Workspace Instance on hemlock

Brings up a complete Workspace service against the test MongoDB cluster for testing Workstreams 1 (retry wrapper) and 2 (driver upgrade).

## Prerequisites

- Test MongoDB 3.4 replica set running on hemlock ports 27117-27119 (see [test-replica-set-setup.md](test-replica-set-setup.md))
- dev_container built with `source user-env.sh`

## Directory Setup

```bash
mkdir -p /ws-test/workspace/{db-path,logs}
```

## Configuration

```bash
cat > /ws-test/workspace/deploy.cfg <<'EOF'
[Workspace]
service-port = 17125
service-host = hemlock.cels.anl.gov
service-url = http://hemlock.cels.anl.gov:17125

shock-url = http://hemlock.cels.anl.gov:17078
db-path = /ws-test/workspace/db-path
mongodb-database = WorkspaceBuild
mongodb-host = mongodb://hemlock.cels.anl.gov:27117,hemlock.cels.anl.gov:27118,hemlock.cels.anl.gov:27119?replica_set=rs-test
mongodb-user = workspace
mongodb-pwd = wspassword

wsuser = WSTestUser
wspassword = wstest

types-file = /home/olson/P3/dev-ubuntu/modules/Workspace/typeslist.txt
script-path = /home/olson/P3/dev-ubuntu/bin
log-path = /ws-test/workspace/logs
EOF
```

## Start the Service

```bash
cd /home/olson/P3/dev-ubuntu
source user-env.sh

export KB_DEPLOYMENT_CONFIG=/ws-test/workspace/deploy.cfg
export KB_SERVICE_NAME=Workspace
export KB_INTERACTIVE=1

# Start with starman on the test port
starman --port 17125 --workers 2 \
        --access-log /ws-test/workspace/logs/access.log \
        --error-log /ws-test/workspace/logs/error.log \
        modules/Workspace/lib/Workspace.psgi &

# Verify
curl http://hemlock.cels.anl.gov:17125/ping
```

## Populate Test Data

### Create Test Workspaces and Objects

```bash
export KB_AUTH_TOKEN=<your-token>

# Create a workspace
p3-mkdir /testuser@bvbrc/TestWorkspace

# Create directories
p3-mkdir /testuser@bvbrc/TestWorkspace/dir1
p3-mkdir /testuser@bvbrc/TestWorkspace/dir1/sub1
p3-mkdir /testuser@bvbrc/TestWorkspace/dir1/sub2
p3-mkdir /testuser@bvbrc/TestWorkspace/dir2

# Create files
echo "file content 1" | p3-cp - ws:/testuser@bvbrc/TestWorkspace/dir1/file1.txt
echo "file content 2" | p3-cp - ws:/testuser@bvbrc/TestWorkspace/dir1/sub1/file2.txt
echo "file content 3" | p3-cp - ws:/testuser@bvbrc/TestWorkspace/dir2/file3.txt

# Verify
p3-ls -l /testuser@bvbrc/TestWorkspace
p3-ls -lR /testuser@bvbrc/TestWorkspace
```

Or populate directly via MongoDB for bulk data:

```bash
$MONGO34/mongo --port 27117 -u workspace -p wspassword \
    --authenticationDatabase admin --eval '
var db = db.getSiblingDB("WorkspaceBuild");

// Create a workspace
db.workspaces.insert({
    uuid: UUID().toString().replace(/^"|"$/g, ""),
    name: "TestWorkspace",
    owner: "testuser@bvbrc",
    global_permission: "n",
    user_permission: {},
    metadata: {},
    creation_date: new Date().toISOString()
});

var ws = db.workspaces.findOne({name: "TestWorkspace", owner: "testuser@bvbrc"});
print("Workspace UUID: " + ws.uuid);

// Create bulk objects
var bulk = db.objects.initializeUnorderedBulkOp();
for (var d = 0; d < 10; d++) {
    // Create folder
    bulk.insert({
        workspace_uuid: ws.uuid,
        path: "",
        name: "dir" + d,
        uuid: UUID().toString().replace(/^"|"$/g, ""),
        folder: 1,
        type: "folder",
        size: 0,
        creation_date: new Date().toISOString(),
        owner: "testuser@bvbrc",
        shock: 0,
        metadata: {},
        autometadata: {}
    });
    for (var f = 0; f < 100; f++) {
        bulk.insert({
            workspace_uuid: ws.uuid,
            path: "dir" + d,
            name: "file-" + f + ".txt",
            uuid: UUID().toString().replace(/^"|"$/g, ""),
            folder: 0,
            type: "txt",
            size: Math.floor(Math.random() * 100000),
            creation_date: new Date().toISOString(),
            owner: "testuser@bvbrc",
            shock: 0,
            metadata: {},
            autometadata: {}
        });
    }
}
bulk.execute();
print("Created " + db.objects.count({workspace_uuid: ws.uuid}) + " objects");

// Create production-matching indexes
db.objects.createIndex({workspace_uuid: 1, path: 1});
db.objects.createIndex({path: 1, workspace_uuid: 1});
db.objects.createIndex({workspace_uuid: 1, name: 1, creation_date: -1, type: 1});
db.objects.createIndex({uuid: 1});
'
```

## Workstream 1: Test Retry Wrapper

### Test 1: Verify Normal Operation

```bash
# Run the path query performance test against the test instance
KB_DEPLOYMENT_CONFIG=/ws-test/workspace/deploy.cfg \
    perl modules/Workspace/t/test-path-query-performance.pl \
    --url http://hemlock.cels.anl.gov:17125 \
    --workspace /testuser@bvbrc/TestWorkspace \
    --verbose
```

### Test 2: Failover During Reads

```bash
# Terminal 1: run a continuous read loop
while true; do
    curl -s -X POST http://hemlock.cels.anl.gov:17125 \
        -H "Content-Type: application/json" \
        -d '{"method":"Workspace.ls","params":[{"paths":["/testuser@bvbrc/TestWorkspace"]}],"id":1}' \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print('OK' if 'result' in r else 'ERR: '+str(r.get('error',{}).get('message','')))"
    sleep 0.5
done

# Terminal 2: trigger failover
$MONGO34/mongo --port 27117 -u admin -p testpassword --authenticationDatabase admin \
    --eval 'rs.stepDown()'
```

### Test 3: Failover During Writes (after retry wrapper is implemented)

```bash
# Terminal 1: continuous create loop
for i in $(seq 1 100); do
    curl -s -X POST http://hemlock.cels.anl.gov:17125 \
        -H "Content-Type: application/json" \
        -H "Authorization: OAuth $KB_AUTH_TOKEN" \
        -d "{\"method\":\"Workspace.create\",\"params\":[{\"objects\":[[\"/testuser@bvbrc/TestWorkspace/failover-test-$i\",\"folder\",{},null]]}],\"id\":$i}" \
        | python3 -c "import sys,json; r=json.load(sys.stdin); print('$i OK' if 'result' in r else '$i ERR: '+str(r.get('error',{}).get('message','')))"
    sleep 0.2
done

# Terminal 2: trigger failover mid-loop
sleep 5 && $MONGO34/mongo --port 27117 -u admin -p testpassword \
    --authenticationDatabase admin --eval 'rs.stepDown()'
```

Observe:
- Without retry wrapper: creates fail during election, don't recover
- With retry wrapper: creates pause briefly, then resume

## Workstream 2: Test Driver Upgrade

### Step 1: Verify Current Driver (v0.708)

```bash
# Confirm the test Workspace works with v0.708 against 3.4
KB_DEPLOYMENT_CONFIG=/ws-test/workspace/deploy.cfg \
    perl -e '
use Bio::P3::Workspace::WorkspaceImpl;
my $ws = Bio::P3::Workspace::WorkspaceImpl->new({});
print "Connected with driver: $MongoDB::VERSION\n";
my $result = $ws->ls({paths => ["/testuser@bvbrc/TestWorkspace"]});
my $count = scalar @{$result->{"/testuser@bvbrc/TestWorkspace"} // []};
print "Listed $count objects\n";
'
```

### Step 2: Apply Driver v2.2.2 Code Changes

Modify WorkspaceImpl.pm to use v2.2.2 API (see [mongodb-perl-driver-status.md](mongodb-perl-driver-status.md) for the change list):

```perl
# Key changes:
#   use MongoDB;                          (instead of MongoDB::Connection)
#   MongoDB::MongoClient->new(...)        (instead of MongoDB::Connection->new)
#   ->insert_one($doc)                    (instead of ->insert($doc))
#   ->update_one($query, $update)         (instead of ->update($query, $update))
#   ->delete_one($query)                  (instead of ->remove($query))
#   ->delete_many($query)                 (instead of ->remove($query, {just_one => 0}))
#   ->count_documents($query)             (instead of ->count($query))
```

### Step 3: Verify v2.2.2 Against 3.4

```bash
# Restart Workspace with v2.2.2 driver changes
# Run the same tests as Step 1
# All operations should work identically
```

### Step 4: Verify v2.2.2 Against 5.0 (later, after Workstream 5)

```bash
# Update deploy.cfg to point at the 5.0 cluster (ports 27217-27219)
# Restart Workspace
# Run the same tests
```

## Stop the Test Instance

```bash
# Find and kill the starman process
kill $(pgrep -f 'starman.*17125')

# Or if using the PID file:
# kill $(cat /ws-test/workspace/workspace.pid)
```

## Quick Reference

| Component | Port | URL |
|-----------|------|-----|
| Workspace API | 17125 | http://hemlock.cels.anl.gov:17125 |
| MongoDB node 0 | 27117 | |
| MongoDB node 1 | 27118 | |
| MongoDB node 2 | 27119 | |
| Shock (if needed) | 17078 | http://hemlock.cels.anl.gov:17078 |
