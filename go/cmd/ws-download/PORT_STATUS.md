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

> ## RESOLVED 2026-09-25 — root cause found and mitigated in the Perl service
>
> **`AnyEvent::HTTP::$MAX_PER_HOST` defaults to 4** (`HTTP.pm:59`). Requests past
> that are not sent; they queue in `_slot_schedule` until a connection closes.
> Every Shock fetch targets the same hostname, so **the whole service was capped
> at four concurrent Shock downloads**, and on a single-threaded Twiggy process
> everything else queued behind them.
>
> Shipped to production in PRs #101-#103:
>
> | PR | Change |
> |---|---|
> | #101 | `StampedStderr` + the `shock-fetch` timing line — **the instrumentation that found it** |
> | #102 | Raise `MAX_PER_HOST` (the stall fix) |
> | #103 | Cancel the Shock fetch on client disconnect; lower `MAX_PER_HOST` 64 → 16 |
> | #104 | Log the originating client IP (open) |
>
> The user considers the Perl service **mitigated**. The port continues on its
> own merits: the architecture that turns any single blockage into a service-wide
> outage is unchanged, and §1.5 records what the port must not repeat.
>
> §1.1–§1.4 below are kept deliberately — they are a record of four wrong
> hypotheses and how each was killed, which is the most useful part of this
> document for the next person.

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
| Cloudflare | Not in this path at all — `p3.theseed.org` is a direct A record to `140.221.78.42`, `Server: nginx`, no `cf-ray`. (The MAAGE-Web front end *is* behind Cloudflare; the download service is not.) |
| Transfer throughput | ~200 Mbps once past the stall; 8s of dead air first |
| Worker-pool exhaustion | n=1 stalls as long as n=60; no staircase at 25 |
| **Missing Mongo indexes** | `download_key` and `session_token` **are** indexed; the hot query is an IXSCAN at **3ms** |
| **Collection size** | `downloads` has **16** docs, `auth_cookie` **23**. Nothing to scan even unindexed |
| **Replica set health** | All four members `health: 1`, `pingMs: 0`, no unreachable node |
| **Shock backend** | Exonerated by its own log: 368,752 requests, median 0s, p99 1s, and it was serving other clients during the stalls |
| **The network / Shock URL hairpin** | No request was in flight during the gap — the service never sent one |
| Token signer endpoints | ~0.3s, all four reachable |

So the ~9s was spent neither in Mongo query execution nor in any reachable
downstream dependency. Note the probe used (`/download/BOGUS/x`) returns 404
after *only* the indexed `find_one` — it does no Shock or LWP work at all, yet it
stalled. That makes the probe a **victim** of a blocked event loop, not the cause.

**Confirmed from `download.error.log`: the Shock fetches themselves stall for
~10-12s, and because that fetch runs on the shared event loop, every other
request waits behind it.** See §1.2. The hypotheses below were the route there
and are kept because each elimination is load-bearing.

**Two dead hypotheses:**

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

### 1.2 Confirmed cause: Shock fetches stalling on the shared event loop

`download.error.log` settles it. The debug line at `:1942`
(`on_header => sub { print STDERR Dumper(@_) }`) dumps every Shock response's
headers, **including its `date`**, which turns the log into a timeline of when
each upstream fetch actually completed — 2,655 of them for 2026-09-24.

During the exact window where external probes measured total stalls
(20:54-20:55 UTC = 15:54-15:55 CDT):

```
20:54:04  gap=35s
20:54:16  gap=12s
20:54:27  gap=11s   20:54:27  gap=0s   20:54:27  gap=0s
20:54:49  gap=21s   20:54:49  gap=0s   20:54:49  gap=0s
20:54:59  gap= 9s   20:54:59  gap=0s
20:55:10  gap=11s   20:55:10  gap=0s
20:55:22  gap=11s   20:55:23  gap=1s
20:55:34  gap=11s   20:55:35  gap=0s
```

A ~10-12s pause, then a burst of responses landing in the same second, repeating.
That is exactly the shape measured from the client side (~9s dead air, then
everything releases at once) — the same phenomenon seen from inside the process.

Across the whole day, **13% of all inter-response gaps fall in a 9-13s band**,
with a sharp spike at 10/11/12s well above neighbouring values. A clean spike at
a fixed duration is a timeout/retry signature, not a load curve.

**Why one slow fetch stalls everything.** `http_request` to Shock (`:1939`) is
the operation that occupies the loop for the whole duration of a download. While
it hangs, the single Twiggy process serves nothing else — including the
`/download/BOGUS/x` probe, which touches neither Shock nor any slow resource.
That resolves the contradiction that killed the load hypothesis: no traffic
volume is needed, because one hung upstream fetch is sufficient. The 25-worker
RPC service is unaffected for the same reason: there, one hung fetch blocks one
worker out of 25.

This is the `/view` and Shock-backed `/download` path. The `/set-cookie-auth`
signer fetches, suspected earlier, do not appear in the log at all.

**What was tested and does NOT explain it:**

- **Not file size.** Stalled fetches have a *smaller* median payload (0.45 MB)
  than quick ones (0.70 MB), so this is not NFS read latency on large files.
- **Not wall-clock periodicity.** Stall-ending responses are spread evenly across
  all 60 second-of-minute positions — nothing cron-like.
- **Not Shock returning errors.** 2,652 of 2,654 responses are `200 OK`.

**Shock is exonerated, and the delay is inside the download service.** Shock's
own access log for 2026-09-24 (`access.log.114`, 737k lines, paired
`REQ RECEIVED`/`RESPONDED TO`) gives its service time directly:

```
368,752 paired requests
median 0s   p95 0s   p99 1s
>=5s: 466 requests (0.13%)
```

Shock answers essentially everything within the same second.

Tracing a single stall settles it. On the client side, consecutive Shock
responses arrived at 20:54:16 and 20:54:27 UTC — an 11s gap. In Shock's log for
that same node over 15:54:16-15:54:27 CDT:

```
15:54:16  REQ RECEIVED / RESPONDED TO   (several, all same-second)
             <-- 11 seconds with NO request from the download service at all
15:54:27  REQ RECEIVED / RESPONDED TO   (burst, all same-second)
```

**The download service never issued a request during the gap.** Shock did not
take 11s to answer; it was never asked. And Shock was not idle — it logged 11-18
lines/second at 15:54:20 through 15:54:26 serving *other* clients while this
download sat blocked. Request rate was trivial throughout (~1-14/s).

So the missing ~11s is spent inside the Twiggy process, between finishing one
response body and issuing the next fetch. That also rules out the network path
and the `p3.theseed.org` hairpin as the *cause* — no packet was in flight to
blame.

**Where the loop goes.** The relevant code is the Shock streaming callback
(`:1939-1958`). Two things run per chunk on the single loop:

- `on_header => sub { print STDERR Dumper(@_) }` (`:1942`) — a full
  `Data::Dumper` serialization of every response's headers, written to STDERR,
  for **every** fetch. Synchronous blocking writes to a log file on every
  request.
- `on_body` calls `$writer->write($data)` (`:1948`) with **no backpressure and no
  return-value check**. Twiggy buffers whatever it cannot flush to a slow client,
  and the loop keeps pulling from Shock regardless.

The local-file path has the same shape via `AnyEvent::Handle` (`:2003`), likewise
with no backpressure.

That is consistent with the fixed ~10-12s quantum and with stalls arriving in
back-to-back chains: the loop is occupied doing per-chunk work for one transfer
(and blocking on STDERR) and cannot service anything else until that transfer's
current phase completes. It is *not* consistent with a slow upstream, which the
logs now positively exclude.

> Remaining uncertainty: the logs prove where the time is *not* spent (Shock, the
> network) but only localize it to "inside the process". Distinguishing the
> `Dumper`/STDERR cost from writer backpressure from something else needs a
> profile or `strace` of the live process. All three are fixed by the same
> architectural change, so this does not block the port.

**Config note.** Every stored `shocknode` points at `https://p3.theseed.org` even
though Shock runs on the same machine, rather than the `shock-url = 10.1.16.5` in
`deploy.cfg`. `p3.theseed.org` is a direct A record to `140.221.78.42`
(`Server: nginx`, no `cf-ray`) — **not** behind Cloudflare, unlike the MAAGE-Web
front end. The URLs are baked into `objects.shocknode` at creation time
(`:1175`), so a config change affects only new objects. This is a needless TLS +
nginx round trip for a same-host service and worth fixing on its own merits, but
it is **not** the cause of the stall.

### 1.3 Other defects visible in the error log

- **118 × `AnyEvent::Handle uncaught error: Broken pipe`** — clients disconnecting
  mid-download. The `on_error` handler (`:2004`) prints `"Error\n"` and neither
  closes the writer nor drops the handle, so these likely leak.
- **75 × `Child died with status -1`** with `exitcode  0 -1` — archive
  (`p3x-create-archive`) failures. The `exitcode  0` confirms the `child_pid` bug:
  `$self->{child_pid}` is never assigned anywhere, so `:1752` calls
  `waitpid(undef, WNOHANG)`.
- **4 × `Cannot find file details for /public/maage@bvbrc/MAAGE Workshop/...`** —
  the `/public` UI-only prefix reaching the download service as a real path, which
  it then cannot resolve. Documented in MAAGE-Web's CLAUDE.md.

### 1.4 Cheap hedges worth doing regardless

Independent of this port, in rough order of value:

1. **Delete the `Dumper` debug line at `:1942`.** It serializes every Shock
   response's headers to STDERR on every request — synchronous blocking writes on
   the event loop, 2,655 of them on the 24th alone. This is leftover debugging
   with no production value and is a one-line change. Best
   effort-to-plausible-benefit ratio of anything here.
2. Fix the `on_error` handler at `:2004` to close the writer and drop the handle
   (118 broken-pipe events on the 24th, each likely leaking).
3. **Bound the external calls.** `http_request` at `:1939` and the
   `LWP::UserAgent` PUT at `:1823` both have **no timeout**. Not implicated in
   this incident, but unbounded calls on a shared loop are a latent outage.
4. Point `shock-url` at the local address so new objects skip the needless TLS +
   nginx round trip (§1.2). Not the cause; still worth doing.
5. Add the two genuinely missing indexes — `downloads.download_signature` and
   `expiration_time` on both collections. Not implicated (the collections hold 16
   and 23 documents), but free and `downloads` will grow.

**This also constrains the Go port.** A timeout alone is not the fix: with one
event loop, even a bounded 10s hang still blocks everyone for 10s. Per-request
goroutines are what make a slow upstream cost only its own request. Phase 2 must
therefore add `context.Context` to the Shock path — `ShockDownloadToWriter` has
none today, so a client disconnect would not cancel the upstream fetch and the
service would leak exactly the way the Perl one does.

---

### 1.5 What the port must get right (learned the hard way)

Every item here is a defect found in the Perl service during this investigation.
The Go implementation must not reproduce any of them.

**1. No global concurrency cap on the upstream fetch.**
This was the root cause. Go's `http.Transport` defaults `MaxConnsPerHost` to 0
(unlimited), but `MaxIdleConnsPerHost` is **2**, which throttles connection reuse
rather than concurrency — still worth setting explicitly. The port must never
introduce a shared semaphore across requests.

**2. Real backpressure on the body copy.**
Perl's `on_body` calls `$writer->write` and returns 1 regardless of whether the
client can keep up; `Twiggy::Writer::write` is `push_write` into an unbounded
buffer. The service pulls from Shock at ~46 MB/s while a slow client drains at
tens of KB/s. `io.Copy` to an `http.ResponseWriter` blocks the goroutine when the
client is slow, which is correct and free — **do not** buffer the body to make
something else easier.

**3. Cancel the upstream fetch on client disconnect.**
The Perl bug: when the client went away, `push_write` croaked, the exception
escaped `on_body` into `AnyEvent::HTTP`'s read callback, and **EV caught and
ignored it**. `on_body` therefore never returned 0, the fetch was never
cancelled, and the read callback kept firing and throwing for every remaining
byte of a 253 MB body — 100% CPU, flat memory, self-clearing when the body ran
out. In Go this is `context.Context`: `dlservice` must pass `r.Context()` into
the Shock fetch so a disconnect cancels it. `ShockDownloadToWriter` has no ctx
parameter today — **this is a phase-2 blocker, not a nicety.**

**4. Per-request logging with a ttfb/total split.**
Two hypotheses died purely because the Perl logs recorded *that* a response
arrived, not how long it took. Already implemented in `internal/dlservice/accesslog.go`;
keep it. `ttfb` large means a slow dependency; small `ttfb` with large `total`
means a slow client. That single distinction ended the investigation.

**5. Timestamps and client identity in the log.**
The Perl error log had no clock; the stall was only locatable because a stray
debug `Dumper` happened to include an upstream HTTP `date` header. `slog` gives
timestamps by default. Client IP comes from X-Forwarded-For's first hop → X-Real-IP
→ socket peer (`RemoteAddr`), matching `Service.pm:187`; treat it as diagnostic
only, never for authorization.

**6. Distinguish "no record" from "backend down".**
Perl returns 404 for both. Already handled — the Go store returns `ErrNotFound`
separately and a Mongo failure surfaces as 500.

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
