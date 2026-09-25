# Port the Workspace download service to Go

> **This is the original design plan, kept as written before implementation
> began.** For what is actually built, what is verified, and what is left, see
> [`PORT_STATUS.md`](PORT_STATUS.md) — that file is the one to keep current.
>
> Where the two disagree, `PORT_STATUS.md` wins: implementation turned up
> details this plan got wrong (notably that a multi-range header does not match
> the Perl regex at all, rather than taking the last pair).
>
> ### Superseded: the Context section below
>
> This plan attributes the stall to "synchronous blocking I/O on a single event
> loop." That is true of the architecture but was **not** the trigger. The actual
> cause, found 2026-09-25, is `AnyEvent::HTTP::$MAX_PER_HOST = 4` capping the
> whole service at four concurrent Shock downloads — see `PORT_STATUS.md` §1.
> It has been mitigated in the Perl service (PRs #101-#103).
>
> The port is still worth doing, for the reason the plan gives: a single-threaded
> loop turns any one blockage into a service-wide outage, and the investigation
> found several such blockages. But the **urgency argument in this plan is spent**
> — this is now planned work, not incident response. `PORT_STATUS.md` §1.5 lists
> the six specific defects the port must not reproduce.

## Context

`/services/WorkspaceDownload` is stalled **~91-93% of wall-clock time**, in ~9s blocks
separated by ~1s clear windows. Measured from two networks (onsite and external);
transfer throughput when not stalled is ~200 Mbps, so the network is fine.

Root cause, established from measurement plus the code:

- `service/start_service.tt` runs the main Workspace API under **starman with 25 worker
  processes**, but runs the download service under **`plackup -s Twiggy` with no
  `--workers`**. Twiggy is single-process, single-threaded AnyEvent. The
  `kb_starman_workers=25` in the Makefile never reaches it.
- The handlers do **synchronous blocking I/O on that single event loop**: MongoDB
  `find_one` (`WorkspaceImpl.pm:1628`, `:1836`), the `_wscache`/`_get_db_object` lookups
  (`:1790-1793`), and a synchronous `LWP::UserAgent->put` to Shock (`:1823`).
  `WorkspaceImpl.pm:1462` already says *"we cannot allow the download request to block"*
  and `:1485` says *"This should be an async mongo lookup. Later."*

Evidence it is one serialization point, not worker exhaustion: **n=1 concurrent request
stalls as long as n=60**; 60 concurrent requests all release within a **70 ms** window;
no staircase at the 25 boundary; `Workspace` RPC and static routes on the same host stay
at **0%** stalled during download stalls.

Perl has no path forward here — the official Mongo driver is sync-only and retired, the
code uses the pre-1.0 `MongoDB::Connection` API removed in 2015, and the async drivers
are abandoned. In Go, goroutines make these blocking calls harmless.

**Outcome:** a Go binary serving the same four routes, byte-compatible, deployed
side-by-side and cut over by an nginx upstream switch.

> Being checked separately: whether `downloads.download_key` and
> `auth_cookie.session_token` are indexed (no `ensure_index`/`create_index` exists
> anywhere in the Perl repo). If they are missing, that likely explains the ~9s
> query time and a `createIndex` may relieve it today. **It does not change this
> plan** — the single-threaded blocking architecture is a defect regardless, and
> the Go service creates these indexes at startup.

## Scope decisions (already made)

1. **Archive/zip rewritten in Go** with `archive/zip` — not shelling out to `p3x-create-archive`.
2. **Config from the existing `deploy.cfg` INI** (`[Workspace]` section) — one source of truth with Perl.
3. **Differential test harness** diffing status/headers/body-sha256 between Go and Perl.

## Route contract to reproduce

Source: `lib/WorkspaceDownload.psgi` + `WorkspaceImpl.pm:1460-2040`. Bug-compatible by
default; deliberate deviations are flagged in "Decisions to confirm".

| Route | Auth | Success | Errors |
|---|---|---|---|
| `POST /set-cookie-auth` | `Authorization` header, validated | 200, body `Cookie set\n`, sets `bvbrc_ws_view_session` | 401 `Authentication required`; 403 `Authentication failed` |
| `GET /download/{key}/{name}` | `download_key` in URL | 200/206 stream, `Content-Disposition: attachment; filename="<name>"`, `application/octet-stream` | 404 `Invalid path\n` |
| `GET /view/{ws_path}` | cookie `bvbrc_ws_view_session` | 200/206 stream, `Content-Disposition: inline`, mime-sniffed | **503** `Invalid session\n`; 404 `Invalid path\n` |
| `GET /archive/{sig}` | `download_signature` in URL | 200 zip stream, `attachment; filename="<archive_name>"` | 404 `Invalid path\n`; 404 `Not found\n` |

All error bodies are `Content-Type: text/plain` and include the trailing newline.
`/` is a fallback mount whose handler (`_download_request_orig` :1592) is byte-identical
to `_download_request` :1566.

**Path parsing:** `^/archive/([a-z0-9]{40})$`, else `^/([^/]+)/([^/]+)$` → `(dlid, name)`.

**Mime (view only)** — `WorkspaceImpl.pm:54-64`: `MIME::Types`, plus `.fa/.fasta/.fna/.faa`
→ `text/plain`, plus overrides `pdb|sdf|gb|sh` → `text/plain`, fallback `text/plain`.

**Range** — `/bytes=(\d+)-(\d*)\s*$/`; open-ended or past EOF clamps to `size-1`;
206 with `Content-Range: bytes B-E/SIZE` and `Content-Length: len`. Shock fetches
`<node>?download&seek=B&length=LEN`; local files `seek()` then stream.

**CORS** — verified live against the running service; must be reproduced or
`viewer/File.js`'s credentialed `set-cookie-auth` fetch breaks:
`Access-Control-Allow-Origin` **reflects** the request Origin,
`Access-Control-Allow-Credentials: true`, `Vary: Origin`.

`/view` takes the **raw `path_info`** as the workspace path (`:1618`) and resolves it live
via `_lookup_ws_file_details` (`:1778`) — permission is re-checked per request against the
session's stored `auth_token`, unlike `/download`, which trusts the pre-minted key.

**Mongo documents** (read-only here; written by `get_download_url` :3060-3175 and
`get_archive_url` :3380-3415):
- `downloads`: `workspace_path`, `file_path` | `shock_node`, `user_token`, `download_key`,
  `expiration_time`, `name`, `size`; archives add `download_signature`, `archive_name`,
  `objects`, `archive_type`, `user`, `total_size`, `file_count`.
- `auth_cookie`: `session_token`, `auth_token`, `expiration_time`.
- Local file path = `<db-path>/P3WSDB/<owner>/<ws name>/<path>/<name>` (`:1814`, `:3107`).
  **The constructor appends `/P3WSDB/` to the configured `db-path`** (`:2182`) and then
  collapses `//` and strips the trailing `/` (`:2216-2217`). Verified. An object at the
  workspace root has an empty `path`, producing a doubled slash mid-path — harmless for
  `open()`, but `filepath.Join` will normalize it, so don't string-compare against Perl logs.

### Corrections from the full behavioral spec

Details that differ from a naive port and are observable:

- **Header-name casing is inconsistent and deliberate.** `/view` inline uses `Content-Type`;
  `/download` attachment uses **`Content-type`** (lowercase t, `:1871`), as does the archive
  route (`:1702`). Observable over HTTP/1.1. Go's `http.Header.Set` canonicalizes — use
  direct map assignment to reproduce, or accept the deviation knowingly.
- **CORS emits `Access-Control-Expose-Headers` with an empty value** on every response,
  and appends `Vary: Origin` even when no `Origin` was sent. Preflight is answered by the
  middleware without calling the app, and does **not** emit `Access-Control-Max-Age`.
- **Legacy URL forms are live and must be served**: `/download/{key}/{name}`,
  `/{key}/{name}` (the `/` mount), `/download/archive/{sig}`, and `/archive/{sig}`.
  `get_archive_url` mints the `/archive/{sig}` form, so it is not merely legacy.
- **Four distinct 404 bodies**: `Invalid path\n`, `Not found\n` (archive with empty/non-array
  `objects`), `Not a file\n` (local path is a directory), and URLMap's unreachable `Not Found`.
- **Archive regex is `[a-z0-9]{40}`, not hex** — accepts g-z. Match it.
- **`{name}` in the download URL is parsed and then never used**; the served filename always
  comes from the Mongo record's `name`.
- **`/set-cookie-auth` accepts any HTTP method** and its 401/403 responses carry **no
  `Content-Type`**. The 403 returns a bare string body rather than an arrayref — malformed
  PSGI, so confirm the real wire behavior against the live service before matching it.
- **`/set-cookie-auth` constructs `P3TokenValidator->new` per request**, so the 86400s pubkey
  cache never hits — every call does a live HTTP GET to the signer. The Go port should cache
  process-wide (a latency improvement, not a behavior change).
- **Range**: suffix ranges (`bytes=-500`) are unsupported and fall through to a 200. A
  multi-range header matches only the **last** pair. There is no `416` anywhere, and an
  out-of-range start yields a **negative `Content-Length`** — do not reproduce that; return
  416 and flag it as a deliberate fix.
- **`Accept-Ranges` is never sent**; no ETag/Last-Modified/conditional requests exist.
- **Shock errors are silently swallowed** — the completion callback is `sub {}`, so a 404 or
  connection failure from Shock still yields a 200 with an empty/partial body. The Go port
  should fail properly before headers are written; flag as a deliberate fix.
- **MIME**: the `.fa/.fasta/.fna/.faa` registration at `:56` is **buggy** (extensions were
  given with leading dots, which `MIME::Types` never matches), so FASTA resolves via the
  `// "text/plain"` fallback anyway. Net behavior is `text/plain`; just hardcode the fallback.
  The override lookup is **case-sensitive** while `mimeTypeOf` lowercases, so `X.PDB` misses
  the override and returns `application/vnd.palm`. Go's `mime.TypeByExtension` differs from
  Perl's table (and adds `; charset=utf-8`) — vendor the extension map from the deployed
  `MIME/types.db` rather than using Go's.

## Design

New binary `cmd/ws-download`, new packages under `internal/`. Must **not** import
`internal/fuse` (cgo/FUSE headers) — build with `CGO_ENABLED=0` and its own make target.

```
go/cmd/ws-download/main.go        flags, config load, wiring, graceful shutdown
go/internal/dlservice/            handlers, routing, mime, range, CORS
go/internal/dlstore/              mongo: docs, queries, index creation, expiry sweep
go/internal/p3auth/               inbound token validation (signature + expiry)
go/internal/wsconfig/             deploy.cfg [Workspace] INI parser
go/internal/dlarchive/            streaming zip
```

**Reuse as-is:** `internal/workspace.ObjectMeta` + its array `UnmarshalJSON`
(`types.go:24,:80` — fiddly tuple decoding, already correct); `workspace.Client` and its
RPC plumbing; `ShockReadBytes` (`shock.go:16` — builds exactly the right
`?download&seek=&length=` form, accepts 200 and 206); `auth.Token.Authorization()` for
**outbound** auth only.

**Must extend or write fresh** (gaps found in the existing Go module — it is 100%
client-side, has no HTTP server, no tests, no `go.sum`, no mongo dep):

- `context.Context` is absent from every Shock/RPC call, so a client disconnect will not
  cancel the upstream fetch — a real goroutine/socket leak under load. Add ctx-aware variants.
- `ShockDownloadToWriter` (`shock.go:70`) accepts **only 200**, so it rejects the 206 a
  ranged fetch returns. Needs a range-aware sibling.
- Shock errors are untyped `fmt.Errorf` strings — cannot map upstream status to response
  codes without string matching. Add a typed error carrying the status.
- `Ls` (`client.go:120`) exposes no `Recursive`/`ExcludeDirectories`, both of which the
  archive walk needs.
- `auth.parseToken` does **no** signature or expiry checking and is unexported. It must
  never authenticate an inbound request.
- Default `http.Transport` caps `MaxIdleConnsPerHost` at 2 — tune for a server.
- There is **no `go.sum` and no `vendor/`** (only `pflag` and `cgofuse` are required today).
  Adding the Mongo driver generates a large first `go.sum` — expect that diff and commit it.

`/view` needs the Workspace permission check that `_lookup_ws_file_details` performs. The
Go `workspace.Client` bakes one token per client, so per-request clients (or a
token-per-call refactor) are required — a shared singleton would leak one user's
credentials into another's request.

### Token validation (`internal/p3auth`)

Port `P3TokenValidator::validate` exactly
(`/Users/olson/P3/dev-slurm/modules/p3_auth/lib/P3TokenValidator.pm:26`):
take everything before `|sig=` as signed data; parse `|`-separated `k=v`; reject if
`time >= expiry`; reject unless `SigningSubject` is in the trusted list
(`P3AuthConstants.pm`: `rast.nmpdr.org/goauth/keys`, `user.alpha.patricbrc.org/public_key`,
`nexus.api.globusonline.org/goauth/keys`, `user.patricbrc.org/public_key`); fetch the
signer URL (JSON `{valid, pubkey}`), and RSA-verify the hex-decoded `sig` over the signed
data using **SHA-1** (`crypto/rsa.VerifyPKCS1v15` + `crypto.SHA1`). Cache pubkeys 86400s.

SHA-1 is required for compatibility — it is what the signers emit. Note it in the code,
do not silently "upgrade" it.

### Mongo (`internal/dlstore`)

`go.mongodb.org/mongo-driver/mongo`, one shared `*mongo.Client` (pooled, goroutine-safe).
Typed structs with bson tags for the two collections. At startup, create indexes on
`downloads.download_key`, `downloads.download_signature`, `auth_cookie.session_token`, and
`expiration_time` on both (idempotent; safe if they already exist). Replace the 120s
AnyEvent timer (`:1472`) with a `time.Ticker` goroutine doing the same two
`DeleteMany({expiration_time: {$lt: now}})`.

### Streaming

One helper for both backends: resolve size → parse Range → write 200 or 206 + headers →
stream with `io.Copy` under the request context. Local files: `os.Open`, reject
directories (404 `Not a file\n`, matching `:1972`), `Seek` for ranges. Shock: ranged
`ShockReadBytes`-style URL, streamed not buffered.

`ShockDownload` (`shock.go:43`) buffers whole files in memory — **must not** be used here.

### Archive (`internal/dlarchive`)

Reimplement `p3x-create-archive.pl`: `Get(metadata_only)` + recursive
`Ls(excludeDirectories)` to expand folders; apply max-size filter; compute the prefix
(`dirname` for a single path, else longest common prefix) and strip it from member names;
stream `archive/zip` straight to the `ResponseWriter`. Default name
`ws-archive-2006-01-02-15-04.zip` (UTC).

Mid-stream failure after headers are sent cannot become a 404 — log it and abort the
response so the client sees a truncated transfer, which is what Twiggy effectively does today.

### Security fixes (not ports)

- **SSRF allowlist** on `shock_node` before fetching — it comes from Mongo and is currently
  fetched verbatim.
- Treat `download_key` / `session_token` as bearer secrets: never log them.
- Real inbound token verification, per above.

## Decisions to confirm during implementation

Defaulting to bug-compatible; each is a one-line change if you want it fixed:

1. **`/download` never checks `expiration_time`** (`:1836` queries `download_key` only).
   Expiry is enforced *only* by the 120s sweep, so a key stays live in the gap. Recommend
   adding the check.
2. **`/view` returns 503** for a missing/invalid/expired session (`:1623`, `:1632`, `:1638`)
   where 401/403 is correct. 503 makes clients retry.
3. `$range_len` is computed unconditionally at `:1896`, so with no Range header it is
   arithmetic on `undef`. Harmless in Perl; Go must guard it rather than mirror it.
4. **Out-of-range start emits a negative `Content-Length`** (no 416 exists anywhere).
   Recommend returning 416 instead — this is a bug, not a contract.
5. **Shock failures are swallowed into a 200 with a truncated body** (`sub {}` completion
   callback, `:1976`). Recommend failing before headers are written.
6. **`/archive` does not check `expiration_time` either** — same 120s grace as `/download`.
7. Object names are interpolated into `Content-Disposition` **unescaped**, so a name
   containing `"` or CRLF injects headers. Recommend escaping regardless of compatibility.

## Verification

**Differential harness** (`go/cmd/ws-download-difftest` or a script), run against the Go
service and the Perl service with identical inputs, diffing status code, headers, and
body sha256:

- download keys minted for real via the `Workspace.get_download_url` RPC
- valid / expired / bogus `download_key`
- missing / valid / expired session cookie on `/view`
- Range: none, `bytes=0-0`, bounded, open-ended `bytes=N-`, past EOF
- shock-backed vs local-file objects; folder vs file; a name needing URL escaping
- archive with 1 path and with N paths (prefix computation differs)
- CORS preflight with an `Origin` header

**Load check** — rerun the measurement that found the bug: back-to-back probes for ~90s
computing percent of wall-clock stalled (must be ~0%, vs 91-93% today), plus the
n=1/25/60 concurrency sweep (durations must stay flat and low, with no lockstep release).

**Cutover** — run on a spare port against production Mongo, diff, then switch the nginx
upstream for `/services/WorkspaceDownload`. Rollback is switching it back; the Perl
service stays installed and untouched. Note nginx config is **not** in this repo, so that
change is external.

## Phasing

1. `wsconfig` + `dlstore` + **index creation**, and a `/download` route for local files only.
   Verifiable immediately: fastest win, exercises the whole stack.
2. Shock-backed files with ctx-aware ranged streaming (extend `shock.go`).
3. `p3auth` + `/set-cookie-auth` + `/view` + mime table.
4. Differential harness; run everything above against Perl.
5. `/archive` in Go.
6. Expiry sweep, graceful shutdown, structured logging (`log/slog`), SSRF allowlist.
7. Deploy side-by-side, diff on real traffic, cut over.

Steps 1-4 already replace the majority of real traffic (`viewer/File.js` and the
workspace DWNLD button), so the stall is fixed before the archive work starts.
