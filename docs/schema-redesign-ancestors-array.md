# Workspace MongoDB Schema Redesign: Ancestors Array Pattern

Date: 2026-05-28

## Problem Statement

The current Workspace object schema stores hierarchical position using a single `path` string field:

```javascript
{
    workspace_uuid: "942D0C20-...",
    path: "experiments/2024/genome-analysis",
    name: "results.json",
    folder: 0,
    type: "json",
    uuid: "...",
    // ...
}
```

This creates three problems:

1. **Recursive listing requires regex** — finding all descendants of a path requires `path: /^experiments\/2024/`, which either causes full index scans or depends on fragile hint() directives. We've hit MongoDB 3.4 query planner bugs where it selects the wrong index for `$or` queries, and even the fix requires careful query structuring.

2. **Renames are O(n)** — renaming a folder requires updating the `path` field of every descendant. Renaming `/experiments` to `/archived` in a workspace with 100,000 objects under that path means 100,000 individual document updates, each modifying a string.

3. **Deletes are recursive** — `_delete_object` walks the tree level by level, querying and deleting children one at a time.

## Proposed Schema: Ancestors Array

Replace the string `path` with an `ancestors` array containing the UUIDs of all ancestor folders, ordered from root to immediate parent. Add a `parent_uuid` field for the direct parent.

### Current Schema

```javascript
{
    workspace_uuid: "WS-UUID",
    path: "experiments/2024/genome-analysis",
    name: "results.json",
    uuid: "OBJ-UUID",
    folder: 0,
    // ...
}
```

### Proposed Schema

```javascript
{
    workspace_uuid: "WS-UUID",
    name: "results.json",
    uuid: "OBJ-UUID",
    parent_uuid: "GENOME-ANALYSIS-UUID",   // direct parent folder UUID
    ancestors: [                            // root-to-parent order
        "EXPERIMENTS-UUID",
        "2024-UUID",
        "GENOME-ANALYSIS-UUID"
    ],
    depth: 3,                              // len(ancestors), for efficient depth queries
    folder: 0,
    // ...
}

// The folder "genome-analysis" itself:
{
    workspace_uuid: "WS-UUID",
    name: "genome-analysis",
    uuid: "GENOME-ANALYSIS-UUID",
    parent_uuid: "2024-UUID",
    ancestors: ["EXPERIMENTS-UUID", "2024-UUID"],
    depth: 2,
    folder: 1,
}

// A top-level object (no parent folder):
{
    workspace_uuid: "WS-UUID",
    name: "README.md",
    uuid: "README-UUID",
    parent_uuid: null,                     // directly in workspace root
    ancestors: [],
    depth: 0,
    folder: 0,
}
```

## How Each Operation Improves

### Recursive Listing (ls --recursive)

**Current**: regex on path string, requires hint, subject to query planner bugs.
```javascript
// Old: regex scan
db.objects.find({
    workspace_uuid: "WS-UUID",
    path: /^experiments\/2024/
})
```

**Proposed**: exact match on ancestor UUID in array.
```javascript
// New: ancestors array contains target UUID
db.objects.find({
    workspace_uuid: "WS-UUID",
    ancestors: "GENOME-ANALYSIS-UUID"
})
```

MongoDB's multikey index on `ancestors` handles this as a simple equality match — no regex, no `$or`, no query planner ambiguity. A compound index `{ workspace_uuid: 1, ancestors: 1 }` covers this perfectly.

To list all objects recursively under a folder, you need only the folder's UUID, which you already have from looking it up. One query returns all descendants at any depth.

### Non-Recursive Listing (ls)

**Current**: exact match on path string.
```javascript
db.objects.find({
    workspace_uuid: "WS-UUID",
    path: "experiments/2024"
})
```

**Proposed**: exact match on parent_uuid.
```javascript
db.objects.find({
    workspace_uuid: "WS-UUID",
    parent_uuid: "2024-UUID"
})
```

Same performance, cleaner semantics. Index: `{ workspace_uuid: 1, parent_uuid: 1 }`.

### Rename / Move

**Current**: O(n) — update every descendant's `path` string.
```javascript
// Must update ALL descendants when renaming "experiments" to "archived"
db.objects.updateMany(
    { workspace_uuid: "WS-UUID", path: /^experiments/ },
    // Can't even do a simple $set — need to compute new path per document
)
// In practice, the code queries all descendants, then re-creates each one
```

**Proposed**: O(1) for leaf rename, O(n) for move but with cheap array operation.

**Renaming a folder** (same location, new name): Only update the folder's own `name` field. Zero descendant updates — descendants reference the folder by UUID, which doesn't change.
```javascript
// Rename genome-analysis → genome-analysis-v2
db.objects.updateOne(
    { uuid: "GENOME-ANALYSIS-UUID" },
    { $set: { name: "genome-analysis-v2" } }
)
// Done. All descendants still reference GENOME-ANALYSIS-UUID in their ancestors.
```

**Moving a folder** (different parent): Update the moved folder's `parent_uuid` and `ancestors`, then update descendants' `ancestors` arrays. The descendant update is a simple array splice — replace the prefix — which MongoDB can do atomically:
```javascript
// Move "genome-analysis" from under "2024" to under "archived"
// 1. Update the folder itself
db.objects.updateOne(
    { uuid: "GENOME-ANALYSIS-UUID" },
    { $set: {
        parent_uuid: "ARCHIVED-UUID",
        ancestors: ["ARCHIVED-UUID"]
    }}
)

// 2. Update all descendants: replace old ancestor prefix with new one
// Old ancestors for a descendant: [EXPERIMENTS-UUID, 2024-UUID, GENOME-ANALYSIS-UUID]
// New ancestors:                   [ARCHIVED-UUID, GENOME-ANALYSIS-UUID]
// This requires a bulk update, but it's a simple array replacement, not string surgery
db.objects.updateMany(
    { workspace_uuid: "WS-UUID", ancestors: "GENOME-ANALYSIS-UUID" },
    [{ $set: {
        ancestors: {
            $concatArrays: [
                ["ARCHIVED-UUID"],           // new prefix
                { $slice: [                  // keep from moved folder onward
                    "$ancestors",
                    { $indexOfArray: ["$ancestors", "GENOME-ANALYSIS-UUID"] },
                    { $size: "$ancestors" }
                ]}
            ]
        }
    }}]
)
```

This is still O(n) in the number of descendants, but it's a single `updateMany` instead of querying every descendant and re-inserting them. The aggregation pipeline `$set` computes the new array server-side.

### Delete

**Current**: recursive walk, one level at a time, individual removes.

**Proposed**: single query deletes all descendants.
```javascript
// Delete a folder and everything under it
db.objects.deleteMany({
    workspace_uuid: "WS-UUID",
    ancestors: "GENOME-ANALYSIS-UUID"
})
// Then delete the folder itself
db.objects.deleteOne({ uuid: "GENOME-ANALYSIS-UUID" })
```

### Disk Usage (du)

**Current**: aggregate with regex path match and hint.

**Proposed**: aggregate with ancestors array match.
```javascript
db.objects.aggregate([
    { $match: {
        workspace_uuid: "WS-UUID",
        ancestors: "TARGET-UUID",
        folder: 0
    }},
    { $group: {
        _id: null,
        total_size: { $sum: "$size" },
        file_count: { $sum: 1 }
    }}
])
```

### Path Reconstruction

To display full paths (e.g., for `ls` output), the service needs to map ancestor UUIDs back to names. This requires a lookup:

```javascript
// Given ancestors: ["UUID-A", "UUID-B", "UUID-C"]
db.objects.find(
    { uuid: { $in: ["UUID-A", "UUID-B", "UUID-C"] } },
    { uuid: 1, name: 1 }
)
```

This is an O(depth) lookup with an index on `uuid`. Workspace paths are typically 3-5 levels deep, so this is 1 query returning 3-5 documents. The results can be cached aggressively since folder UUIDs and names rarely change.

The current code already maintains a `_wscache` — extending it to cache `uuid → name` for folders is straightforward.

## Indexes

### Remove

| Index | Reason |
|-------|--------|
| `workspace_uuid_1_path_1` | Replaced by ancestors-based queries |
| `path_1_workspace_uuid_1` | Same |

### Add

| Index | Purpose |
|-------|---------|
| `{ workspace_uuid: 1, ancestors: 1 }` | Recursive listing, du, delete (multikey) |
| `{ workspace_uuid: 1, parent_uuid: 1 }` | Non-recursive listing |
| `{ uuid: 1 }` | Already exists — path reconstruction lookups |

### Keep

| Index | Purpose |
|-------|---------|
| `{ uuid: 1 }` | Single-object lookups |
| `{ workspace_uuid: 1, name: 1, ... }` | Name-based queries |

### Multikey Index Size

MongoDB creates one index entry per array element for multikey indexes. With an average depth of 3-4, the `{ workspace_uuid: 1, ancestors: 1 }` index will be 3-4x the size of the current `{ workspace_uuid: 1, path: 1 }` index. For the current 2.5 GB path index, expect ~7-10 GB. This is within cache budget, especially after dropping unused indexes.

## Migration Strategy

### Dual-Mode Transition

Maintain both `path` and `ancestors` fields during migration:

1. **Phase 1: Add fields** — Backfill `parent_uuid`, `ancestors`, and `depth` for all existing objects. The `path` field provides the source data:
   - Parse `path` into components
   - Look up each component's UUID (folder objects already exist in the database)
   - Populate `ancestors` array and `parent_uuid`

2. **Phase 2: Dual-write** — New objects are written with both `path` and `ancestors`. Read operations use `ancestors` for recursive queries, `path` as fallback.

3. **Phase 3: Cut over** — All reads use `ancestors`/`parent_uuid`. `path` is no longer queried.

4. **Phase 4: Remove** — Drop `path` field and old indexes.

### Backfill Script

```python
# Conceptual backfill — process workspace by workspace
for ws in db.workspaces.find():
    # Build path→uuid mapping for all folders in this workspace
    folder_map = {}  # path_string → uuid
    for folder in db.objects.find({workspace_uuid: ws.uuid, folder: 1}):
        full_path = f"{folder.path}/{folder.name}" if folder.path else folder.name
        folder_map[full_path] = folder.uuid

    # Update each object
    for obj in db.objects.find({workspace_uuid: ws.uuid}):
        if not obj.path:
            # Top-level object
            ancestors = []
            parent = None
        else:
            # Split path into components, look up each UUID
            parts = obj.path.split("/")
            ancestors = []
            for i in range(len(parts)):
                component_path = "/".join(parts[:i+1])
                ancestors.append(folder_map[component_path])
            parent = ancestors[-1]

        db.objects.update_one(
            {"_id": obj._id},
            {"$set": {
                "ancestors": ancestors,
                "parent_uuid": parent,
                "depth": len(ancestors)
            }}
        )
```

### Migration Risks

| Risk | Mitigation |
|------|------------|
| Missing folder objects | Some paths may reference folders that don't have a MongoDB document. The backfill script should create these. |
| Multikey index build time | Building the `ancestors` index on hundreds of millions of documents takes time. Use background index build. |
| Increased index size | ~3-4x path index size. Offset by dropping unused indexes (19 GB freed). |
| Rollback | Keep `path` field until fully validated. Can revert reads to path-based queries. |

## Interaction with Go Port

This schema change is best implemented as part of the Go port (Workstream 4):

- The Go service can be built against the new schema from the start.
- The Perl service continues using `path` during the transition.
- Once the Go service is validated, the Perl service is retired and `path` can be dropped.

Alternatively, the Perl service can be updated to use `ancestors` first (Workstream 2-3 timeframe), which de-risks the Go port by validating the schema independently.

## Summary

| Operation | Current | Proposed |
|-----------|---------|----------|
| Recursive listing | Regex on path + hint + $or workaround | `ancestors: UUID` equality match |
| Non-recursive listing | `path: "exact"` | `parent_uuid: UUID` |
| Rename (same location) | O(n) descendant updates | O(1) — update folder name only |
| Move (different parent) | O(n) query + re-insert | O(1) folder + O(n) single updateMany |
| Delete recursive | Recursive walk + individual removes | Single deleteMany |
| Disk usage | Regex aggregate + hint | ancestors aggregate |
| Path display | Free (stored in path) | O(depth) UUID→name lookup (cacheable) |
| Index pressure | 2 path indexes ~5 GB | 1 multikey ~7-10 GB + 1 parent ~2 GB |
