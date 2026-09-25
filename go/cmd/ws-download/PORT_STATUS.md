# ws-download: port status

Port of the Perl `WorkspaceDownload` service (`lib/WorkspaceDownload.psgi` +
`lib/Bio/P3/Workspace/WorkspaceImpl.pm:1460-2040`) to Go.

- **Branch:** `feature/go-download-service`
- **Phase 1 commit:** `9c84eab`
- **Status:** phase 1 of 7 complete. `/download` serves local files end to end;
  `/view`, `/archive`, `/set-cookie-auth` and Shock-backed files return 501 with
  their routing, session handling and error paths already in place and tested.
- **Last updated:** 2026-09-25

---

## 1. Why this exists

> **UPDATE 2026-09-25: the stall has cleared.** Re-measuring production the day
> after the original readings gives **1% of wall-clock stalled** (one 1.12s stall
> in 723 back-to-back probes over 90s), and the concurrency sweep at n=1/5/10/25/
> 26/40/60 is flat at **0.10-0.22s** where it was 7-10s in lockstep. The service
> is currently healthy.
>
> Everything below describes the incident as measured on 2026-09-24. The
> architectural defect it exposed is unchanged and still latent, but this is now
> fragility work rather than a live outage. See §1.1 for what was ruled out and
> what the likely trigger was.

On 2026-09-24, `/services/WorkspaceDownload` was stalled **~91-93% of wall-clock
time**, in ~9s blocks separated by ~1s clear windows. Measured from two separate
networks (onsite and external, ~24ms RTT); throughput when *not* stalled was
~200 Mbps, so the network was not the problem.

### Root cause

`service/start_service.tt` runs the main Workspace API under **starman with 25
worker processes**, but runs the download service under **`plackup -s Twiggy`
with no `--workers`** — a single-process, single-threaded AnyEvent loop. The
`kb_starman_workers=25` in the Makefile never reaches it.

The handlers then do **synchronous blocking I/O on that one loop**:

| Site | Blocking call |
|---|---|
| `WorkspaceImpl.pm:1628`, `:1836` | Mongo `find_one` |
| `:1790-1793` | `_wscache` / `_check_ws_permissions` / `_get_db_object` |
| `:1823` | `LWP::UserAgent->put` to Shock (no timeout) |
| `:1487` | the 120s cleanup sweep |

The code already knows: `:1462` says *"we cannot allow the download request to
block"*, and `:1485` says *"This should be an async mongo lookup. Later."*

### Evidence it is one serialization point, not worker exhaustion

- **n=1 stalls as long as n=60** (8.3s vs 5.9s) — a saturated pool cannot make a
  single idle request wait 10s.
- **60 concurrent requests all released within a 70ms spread** — lockstep, not a
  queue draining 25 at a time.
- **No jump at the 25 boundary**: n=1/5/10/25/26/40/60 all ~7-10s median.
- During an 8s download stall, the `Workspace` RPC and static `/` on the *same
  host* answered in **40ms** (0% stalled over 45s of parallel probing).

Adding instances would not have helped.

### Why Go

Perl has no path forward: the official Mongo driver is sync-only and retired,
this code uses the pre-1.0 `MongoDB::Connection` API removed in 2015, and every
async Perl Mongo driver is abandoned. Goroutines make the blocking calls cost
only their own request.

### 1.1 What was ruled out

Every hypothesis raised during the investigation was tested and eliminated:

| Hypothesis | Verdict |
|---|---|
| Local network / venue | Reproduced identically from two networks |
| Cloudflare | Direct-to-origin `p3.theseed.org` stalls the same way |
| Transfer throughput | ~200 Mbps once past the stall; 8s of dead air first |
| Worker-pool exhaustion | n=1 stalls as long as n=60; no staircase at 25 |
| **Missing Mongo indexes** | `download_key` and `session_token` **are** indexed; the hot query is an IXSCAN at **3ms** |
| **Collection size** | `downloads` has **16** docs, `auth_cookie` **23**. Nothing to scan even unindexed |
| **Replica set health** | All four members `health: 1`, `pingMs: 0`, no unreachable node |
| Shock backend | ~100ms |
| Token signer endpoints | ~0.3s, all four reachable |

So the ~9s was spent neither in Mongo query execution nor in any reachable
downstream dependency. Note the probe used (`/download/BOGUS/x`) returns 404
after *only* the indexed `find_one` — it does no Shock or LWP work at all, yet it
stalled. That makes the probe a **victim** of a blocked event loop, not the cause.

**No confirmed trigger yet.** Two hypotheses were raised and both are now dead:

*Wedged process, cleared by a restart* — ruled out. The `start_server` supervisor
has been up since Aug 13. (Caveat: that PID is the supervisor, not the Twiggy
worker, and `start_server` supports graceful worker restarts, so checking the
child's start time would make this airtight.)

*Load-induced saturation* — **ruled out by the access logs.** During five
consecutive ~10s stalls at 15:54:39-15:55:35, real user traffic on the download
service was **four requests**:

```
15:54:59  POST /set-cookie-auth
15:54:59  GET /view/.../sankey.html
15:55:22  POST /set-cookie-auth
15:55:23  GET /view/.../sankey.html
```

Two page loads. Peak real traffic for the whole day was 424 req/hour (~0.12/s),
nowhere near enough to saturate a loop even with a serialized 100ms call. A
genuine 62-request burst did occur at 15:38-15:39, but no probes were running
then, so there is no stall data for the one moment load was actually high.

> Note on log hygiene: 1,530 of the 4,630 lines in `dl.access` are the
> investigation's own probes. The `curl/8.7.1` and `Python-urllib/3.14` user
> agents are both mine, including a run of `core_SNPs.tsv` 206s that initially
> looked like user traffic. Filter both out before drawing conclusions.

**What still fits.** The two busiest real routes are exactly the two that make
blocking external calls on the shared loop:

| Route | Day total | Blocking call |
|---|---|---|
| `POST /set-cookie-auth` | 1,319 | `P3TokenValidator->new` **per request**, so the 86400s pubkey cache never hits — a live HTTPS GET to the signer every time |
| `GET /view` | 1,035 | synchronous, **unbounded** `LWP` PUT to Shock (`:1823`) |
| `GET /download` | 652 | local: `AnyEvent::Handle` over a regular file, no backpressure (`:2003`) |
| `GET /archive` | 86 | |

A handful of those calls going slow — not a flood of them — is enough to hold the
loop for seconds. That matches the observed shape (9s blocks, ~1s gaps,
independent of concurrency) better than volume does.

**Next diagnostic:** `download.error.log` for 2026-09-24 15:30-16:30. Several of
these paths `warn` on failure, and the Shock response headers are `Dumper`ed on
every request (`:1942`), so a hanging Shock PUT or signer fetch should be visible
there.

### 1.2 Cheap hedges worth doing regardless

Independent of this port:

- Add the two genuinely missing indexes — `downloads.download_signature` and
  `expiration_time` on both collections. Free, correct, and `downloads` will grow.
- **Put a timeout on the `LWP::UserAgent` call at `:1823`** — it is currently
  unbounded, and is the best candidate for a wedge that stalls the whole loop.

---

## 2. What is built

```
go/cmd/ws-download/main.go          175   binary: flags, config, wiring, graceful shutdown
go/internal/wsconfig/               180   deploy.cfg [Workspace] INI parser
go/internal/dlstore/                265   mongo: docs, queries, index creation, expiry sweep
go/internal/dlservice/service.go    363   routing, handlers, streaming
go/internal/dlservice/cors.go        78   Plack::Middleware::CrossOrigin equivalent
go/internal/dlservice/httprange.go   74   Perl-compatible Range parsing
go/internal/dlservice/mime.go       115   MIME table + overrides
                                   ~950   non-test lines
                                   ~800   test lines
```

### Build and test

```bash
cd go
make server        # CGO_ENABLED=0 -> bin/ws-download
make test-server   # tests only the four new packages
```

Both are `CGO_ENABLED=0` and deliberately scoped, so they stay independent of the
FUSE/cgo toolchain `cmd/p3-mount-ws` needs. Plain `make test` (`./...`) still
pulls in `internal/fuse` and needs macFUSE headers.

Deployment builds: `make server-linux-amd64`, `make server-linux-arm64` — no
cross-toolchain required.

### Running

```bash
ws-download --config /kb/deployment/deployment.cfg --listen :7129
```

| Flag | Default | Effect |
|---|---|---|
| `--config` / `-c` | `$KB_DEPLOYMENT_CONFIG` | deployment INI to read |
| `--section` | `$KB_SERVICE_NAME`, else `Workspace` | INI section |
| `--listen` / `-l` | `:7129` | bind address |
| `--log-level` | `info` | debug/info/warn/error |
| `--skip-index-creation` | off | don't create Mongo indexes at startup |
| `--enforce-download-expiry` | off | reject expired keys now, vs the 120s sweep |
| `--strict-range-errors` | off | 416 instead of Perl's negative Content-Length |

---

## 3. Route status

| Route | Status | Notes |
|---|---|---|
| `GET /download/{key}/{name}` | **done** (local files) | Shock backend → 501 |
| `GET /{key}/{name}` | **done** | legacy form, `/` mount |
| `GET /view/{ws_path}` | session handling done | resolution → 501 |
| `GET /archive/{sig}` | lookup + both 404s done | zip streaming → 501 |
| `GET /download/archive/{sig}` | same | routes to the archive handler |
| `POST /set-cookie-auth` | 401 path done | token validation → 501 |
| CORS (all routes) | **done** | verified against the live service |

---

## 4. Compatibility decisions

Everything below was verified against the Perl source or the live service, not
assumed.

### Reproduced deliberately

- **`db-path` gains a `/P3WSDB/` suffix** (`:2182`) before slash normalization, so
  `/mnt/workspace` → `/mnt/workspace/P3WSDB`.
- **Four distinct 404 bodies**: `Invalid path\n`, `Not found\n` (archive with no
  objects), `Not a file\n` (path is a directory), plus URLMap's unreachable one.
- **CORS echoes the Origin literally** — credentials are enabled, so a `*` would
  make `viewer/File.js`'s credentialed `set-cookie-auth` fetch illegal and break
  the viewer. `Access-Control-Expose-Headers` is emitted **empty**, `Vary: Origin`
  is added even with no Origin, and there is **no `Max-Age`**.
- **All four URL forms stay live**, including the legacy `/{key}/{name}`.
- **Archive regex is `[a-z0-9]{40}`, not hex** — accepts g-z.
- **`{name}` in a download URL is ignored**; the served filename always comes from
  the Mongo record.
- **A multi-range header does not match the Perl regex at all** and is served as a
  200. I initially wrote a test asserting it took the *last* pair; running the
  regex directly disproved that. Same for suffix ranges (`bytes=-500`).
- **The MIME override table is case-sensitive while the fallback lowercases**, so
  `X.PDB` misses the override and returns `application/vnd.palm`.
- **`/view` returns 503** (not 401/403) for every session failure.
- **`/set-cookie-auth` accepts any HTTP method** and sends no `Content-Type` on
  its 401.
- **The FASTA MIME registration in Perl is broken** (extensions registered with
  leading dots, which `MIME::Types` never matches), so `.fa/.fasta/.fna/.faa`
  resolve via the `text/plain` fallback anyway. Net behavior matches.
- Go's `mime.TypeByExtension` is **not** used: its table differs and it appends
  `; charset=utf-8`, which Perl never does. The extension map is vendored instead.

### Deliberate deviations

| Deviation | Why |
|---|---|
| Mongo failure → **500**, not 404 | Perl cannot tell "no record" from "DB down". An outage should not look like a missing file. |
| `--strict-range-errors` → **416** | Perl emits a 206 with a **negative `Content-Length`** for a start past EOF. That is a bug, not a contract. |
| `--enforce-download-expiry` | `/download` and `/archive` never check `expiration_time`; only the 120s sweep does, so a key stays live in the gap. |
| Filenames **quoted** in `Content-Disposition` | Perl interpolates raw, so an object name with `"` or CRLF injects headers. |
| **Indexes created at startup** | The Perl repo creates none in code. Two of the four exist in production (added out of band); `download_signature` and `expiration_time` do not. Idempotent, so safe on every boot. |
| Mongo timeout **10s**, not 120s | `:2189` uses 120s; a slow query there blocks every download for two minutes. |
| Header casing normalized | Perl mixes `Content-Type` (inline) and `Content-type` (attachment). Go canonicalizes; observable on HTTP/1.1 only, and no client cares. |

---

## 5. Verification

`make test-server` → **78 assertions pass** across the three tested packages.

### The regression test for the actual bug

`TestConcurrentRequestsDoNotSerialize` — 40 concurrent downloads against a store
with a 300ms injected delay:

```
40 concurrent requests: total=322ms  slowest=321ms  (store delay 300ms)
```

Serialized, that would be 12s. This is the property Twiggy cannot provide.
`TestClientDisconnectIsPropagated` confirms a disconnecting client no longer
leaves a handler blocked.

### Live wire check

`TestLiveWithCurl` drives the real server over a real socket with `curl` and
checks actual bytes: full download headers, body, `bytes=2-4` →
`206` + `Content-Range: bytes 2-4/10` + `Content-Length: 3` + body `234`, both
404 shapes, CORS preflight, and the legacy URL form.

### Coverage by area

- **Config** — real `deploy.cfg` and `test.cfg` parsed correctly, `/P3WSDB`
  suffix, `null` → unset, falsy-0 lifetime, `MongoURI` credential rules.
- **Store** — all three real Perl document shapes decode; expiry boundary is
  strict `<`, matching `:1635`.
- **Range** — 13 cases including the suffix/multi-range fallbacks and the
  out-of-range split between bug-compatible and strict modes.
- **Routes** — happy path, 7 distinct 404 shapes, store-error-is-500, both expiry
  modes, URL-name-ignored, all URL forms, session states, archive bodies.
- **CORS** — no-Origin, simple, preflight, non-preflight OPTIONS, nested paths.
- **MIME** — overrides, the case asymmetry, FASTA, no charset parameter.

### Not yet verified

- **No live Mongo was available** on this machine (no local instance, no Docker
  daemon). `Open`, `EnsureIndexes` and `Sweep` have **never run against a real
  server**. This is the first thing to exercise.
- No differential run against the live Perl service yet (phase 4).

---

## 6. Remaining phases

| # | Work | State |
|---|---|---|
| 1 | `wsconfig` + `dlstore` + index creation + `/download` local files | **done** (`9c84eab`) |
| 2 | Shock-backed files: ctx-aware ranged streaming | next |
| 3 | `p3auth` token validation + `/set-cookie-auth` + `/view` | |
| 4 | Differential harness vs. the Perl service | |
| 5 | `/archive` streaming zip in Go | |
| 6 | SSRF allowlist on shock URLs, log polish | |
| 7 | Deploy side-by-side, diff on real traffic, nginx cutover | |

Phases 1-4 already cover the majority of real traffic (`viewer/File.js` and the
workspace DWNLD button), so the stall is fixed before the archive work starts.

### Phase 2-3 notes (gaps found in the existing Go module)

The module is 100% client-side today — no HTTP server, no tests, and it had no
`go.sum` before this work. Specifically:

- **No `context.Context` anywhere** in `shock.go`/`client.go`, so a client
  disconnect will not cancel the upstream fetch — a real goroutine/socket leak.
- **`ShockDownloadToWriter` (`shock.go:70`) accepts only 200**, so it rejects the
  206 a ranged fetch returns. Needs a range-aware sibling.
- **`ShockDownload` (`shock.go:43`) buffers whole files in memory** — must not be
  used here.
- Shock errors are untyped `fmt.Errorf` strings; mapping upstream status to a
  response code needs a typed error.
- **`Ls` exposes no `Recursive`/`ExcludeDirectories`**, both of which the archive
  walk needs.
- **`auth.parseToken` does no signature or expiry checking** and is unexported. It
  must never authenticate an inbound request; phase 3 needs a real validator.
- Default `http.Transport` caps `MaxIdleConnsPerHost` at 2 — tune for a server.
- `workspace.Client` bakes one token per client, so `/view` needs a per-request
  client; a shared singleton would leak one user's credentials into another's
  request.

### Token validation algorithm for phase 3

Port `P3TokenValidator::validate`
(`/Users/olson/P3/dev-slurm/modules/p3_auth/lib/P3TokenValidator.pm:26`): take
everything before `|sig=` as signed data; parse `|`-separated `k=v`; reject if
`time >= expiry`; reject unless `SigningSubject` is in the trusted list; fetch the
signer URL (JSON `{valid, pubkey}`); RSA-verify the hex-decoded `sig` over the
signed data using **SHA-1** (`rsa.VerifyPKCS1v15` + `crypto.SHA1`); cache pubkeys
86400s. SHA-1 is required for compatibility — note it, do not "upgrade" it.

Trusted signers (`P3AuthConstants.pm`):
`https://rast.nmpdr.org/goauth/keys`, `https://user.alpha.patricbrc.org/public_key`,
`https://nexus.api.globusonline.org/goauth/keys`, `https://user.patricbrc.org/public_key`.

---

## 7. Cutover

Run on a spare port against production Mongo, diff against the Perl service, then
switch the nginx upstream for `/services/WorkspaceDownload`. Rollback is switching
it back — the Perl service stays installed and untouched.

**nginx config is not in this repo**, so that change is external.

### Acceptance measurement

Rerun the probes that found the bug:

1. Back-to-back requests for ~90s, computing percent of wall-clock stalled.
   Must be **~0%**, against 91-93% today.
2. Concurrency sweep at n=1/25/60. Durations must stay flat and low, with **no
   lockstep release**.
