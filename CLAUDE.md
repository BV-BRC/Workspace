# CLAUDE.md

Guidance for Claude Code working in the BV-BRC Workspace repository.

## What this is

The Workspace service: a JSON-RPC API over MongoDB plus Shock object storage,
with a separate download service for serving file bytes to browsers.

## Services and how they run

`service/start_service.tt` starts **three** servers, and their concurrency models
differ in ways that matter:

| Service | PSGI | Port | Server | Concurrency |
|---|---|---|---|---|
| Workspace (RPC) | `Workspace.psgi` | 7125 | starman | **25 worker processes** |
| WorkspaceDownload | `WorkspaceDownload.psgi` | 7129 | **Twiggy** | **1 process, 1 event loop** |
| WorkspaceCompletion | `WorkspaceCompletion.psgi` | 7140 | Monoceros | |

**`kb_starman_workers=25` in the Makefile applies only to starman.** The download
service gets no `--workers` and is single-threaded. Anything that blocks its event
loop blocks *every* download — this is the single most important fact about this
codebase's runtime behavior.

All three sit behind nginx. `p3.theseed.org` is a direct A record
(`140.221.78.42`, `Server: nginx`) and is **not** behind Cloudflare, unlike the
MAAGE-Web front end.

## The download service (`WorkspaceImpl.pm:1460-2040`)

Four routes, mounted by `WorkspaceDownload.psgi`: `/download`, `/view`,
`/set-cookie-auth`, and `/` (a legacy fallback identical to `/download`).
`/archive/{sig}` is reachable via both `/download/archive/...` and `/archive/...`.

Things that will surprise you:

- **`$MAX_PER_HOST` must stay set.** `AnyEvent::HTTP` defaults it to 4 and
  *queues* everything beyond that per hostname. Since all Shock fetches share one
  hostname, the default caps the whole service at four concurrent downloads. This
  caused a multi-hour production stall (see below). It is now set explicitly in
  `WorkspaceDownload.psgi` — **do not remove it**, and think before raising it
  (it also bounds memory, see next point).
- **There is no backpressure on the body copy.** `on_body` calls
  `$writer->write` and returns 1 regardless of whether the client can keep up,
  and `Twiggy::Writer::write` is `push_write` into an unbounded buffer. The
  service pulls from Shock at ~46 MB/s while a slow client may drain at tens of
  KB/s, so each in-flight transfer can buffer most of its response in memory.
  `MAX_PER_HOST` is therefore also the memory bound: ~253 MB per slot worst case.
- **`/view` returns 503**, not 401/403, for every session failure.
- **Expiry is not checked on `/download` or `/archive`** — only the 120s sweep
  removes expired records, so a key stays usable in the gap.
- **Four distinct 404 bodies** exist: `Invalid path\n`, `Not found\n`,
  `Not a file\n`, and URLMap's unreachable one. Preserve them if touching this.
- `db-path` gains a `/P3WSDB/` suffix in the constructor (`:2182`).
- Download keys and session cookies are **bearer secrets**. Never log them.

## Logging

`Bio::P3::Workspace::StampedStderr` ties STDERR so `warn`, `die`, `Dumper` and
every `print STDERR` get `[timestamp pid]`. Installed in all three `.psgi` files.
Add new services to it.

Per-transfer lines, one per fetch, in `download.error.log`:

```
shock-fetch client=140.221.78.40 status=200 ttfb=0.164 total=30.191 bytes=253425891 url=...
file-fetch  client=140.221.78.40 total=2.114 bytes=88210 path=...
```

**`ttfb` vs `total` is the diagnostic.** A large `ttfb` means a slow dependency;
a small `ttfb` with a large `total` means a slow client. Two investigations went
down blind alleys for want of that split — keep it.

Note the **main RPC service does not use StampedStderr for RPC errors**. It routes
them through `ServiceStderrWrapper` (`Service.pm:314`, `:562`) to a per-request
log file with its own ISO-8601 stamp. Only `warn` from inside handlers reaches
real STDERR.

Client IP comes from `_client_address`: X-Forwarded-For first hop → X-Real-IP →
socket peer, mirroring `Service.pm:187`. **Diagnostic only** — the header is
client-supplied and nginx appends rather than replaces, so it is spoofable.

> **Known limitation as of 2026-09-25: the forwarding headers do not currently
> carry the real client address.** A tshark capture on the RPC service showed
>
> ```
> X-Real-IP: 140.221.78.20
> X-Forwarded-For: 140.221.78.20, 140.221.78.20
> ```
>
> — an internal ANL host (no PTR; `.40` is `plum.mcs.anl.gov`, `.42` is
> `p3.theseed.org`), not the originating client. The duplicated value is the
> signature of `proxy_add_x_forwarded_for` running at two hops where the *first*
> one already could not see the true peer, or of an inner proxy overwriting
> `X-Real-IP $remote_addr` instead of passing `$http_x_real_ip` through.
>
> This is an **nginx configuration issue, not a code issue** — the Perl side
> extracts the first hop correctly, there is simply nothing useful in it. The
> nginx config is not in this repo. To confirm the plumbing works, send
> `curl -H 'X-Forwarded-For: 1.2.3.4'` from outside: if the log shows `1.2.3.4`
> the extraction is fine and only the front end needs fixing; if it still shows
> the internal address, something downstream is overwriting the header.

## The 2026-09-24 download stall (resolved)

The service was blocked ~91-93% of wall-clock time in ~9s blocks. Root cause was
`$MAX_PER_HOST = 4`. Fixed in PRs #101-#103.

Worth reading if you are debugging something similar, because **four plausible
hypotheses were wrong** before the right one: missing Mongo indexes, replica-set
health, slow-client backpressure, and upstream Shock latency. Each was killed by
data, not argument:

- Shock's own access log (paired `REQ RECEIVED`/`RESPONDED TO`) gave median 0s,
  p99 1s over 368,752 requests — and showed the service *never sent* a request
  during the gaps.
- Ganglia showed the host idle (~7% CPU, 0.19% wio) — blocked, not busy, and not
  I/O bound, which also cleared NFS.
- Collection counts of 16 and 23 documents killed the index theory outright.
- A purpose-built load tool (`go/cmd/slowclient`) failed to reproduce at 2, 20,
  and 200 slow clients.

The lesson: **instrument first.** The `ttfb`/`total` line found the answer on its
first real use, after days of inference from logs that recorded the wrong thing.

## Go components (`go/`)

- `cmd/p3-mount-ws` — FUSE driver. Needs CGO and platform FUSE headers.
- `cmd/ws-download` — in-progress Go port of the download service. See
  `go/cmd/ws-download/PORT_STATUS.md`, whose §1.5 lists the six defects the port
  must not reproduce.
- `cmd/slowclient` — load tool for reproducing download stalls against a live
  service. Read its header for safety notes before pointing it at production.

Build the Go server components with `make server` / `make test-server`; both set
`CGO_ENABLED=0` so they stay independent of the FUSE toolchain. Plain `make test`
runs `./...` and needs FUSE headers.

## Local development caveat

`WorkspaceImpl.pm` cannot be compiled on a machine without the deployment runtime
— it fails at line 18 on a missing `RPC::Any`, and Plack/Twiggy/MongoDB are
usually absent too. `perl -c` on individual new modules still works. Verify
`.psgi` changes on a host with the runtime before deploying.
