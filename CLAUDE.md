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
socket peer, mirroring `Service.pm:187`. **Treat as diagnostic, not
authorization** — the value is only as trustworthy as the proxy that set it, and
the code cannot tell a proxy-set header from a client-supplied one.

> **Fixed 2026-09-25 in the nginx config.** The `/services/WorkspaceDownload/`
> location now sets the forwarding header, and the real client address is
> logging correctly:
>
> ```nginx
> location /services/WorkspaceDownload/ {
>     proxy_set_header X-Forwarded-For $remote_addr;
>     proxy_pass http://spruce.cels.anl.gov:7129/;
> }
> ```
>
> Note this uses `$remote_addr` rather than `$proxy_add_x_forwarded_for`. That
> is deliberate here and arguably safer: `$proxy_add_x_forwarded_for` *appends*
> to any client-supplied `X-Forwarded-For`, so a client can inject a bogus first
> hop, and `_client_address` takes the first hop. With `$remote_addr` the header
> is overwritten with the address nginx actually observed, which cannot be
> spoofed. The trade-off is that a genuine upstream proxy's chain is discarded —
> fine for this deployment.
>
> **Two ways to get an internal address in the log, both expected:**
>
> 1. **The request bypassed nginx.** The service also listens directly on
>    `http://spruce.cels.anl.gov:7129/`, which carries no forwarding headers at
>    all, so `_client_address` falls through to the socket peer. Confirmed by
>    tshark. Test through the public `https://p3.theseed.org/...` URL to
>    exercise the proxy path.
> 2. A `location` block without the `proxy_set_header` line. Each one needs it
>    individually — an RPC-service capture showed
>    `X-Forwarded-For: 140.221.78.20, 140.221.78.20`, an internal host
>    duplicated rather than an originating client, which is what a differently
>    configured location produces.

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
