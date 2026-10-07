# CLAUDE.md

lighttpd for OpenVMS (x86-64 first, IA64 second), built natively with VSI C and wrapped by
the same tooling as `~/projects/vms-curl`, `vms-zlib`, `vms-pcre2` and the other sibling
ports. Read vms-grep's `CLAUDE.md` for the ground rules and the VMS/ssh pitfalls; they all
apply. Read `LIGHTTPD_OPENVMS_PLAN.md` (the plan) and `docs/DECISIONS.md` (where we departed
from it, and why) before starting work. Work phase by phase; stop and ask at each phase exit.

Goal: a modern, light HTTP/S server to replace VSI's Apache (CSWS). Acceptance test: TLS
plus phpBB 3.3.x on VSI PHP 8.1 (FastCGI) with our vms-mariadb server as the database.

## Ground rules (from the sibling ports)

- **Never edit `staging/`, `cache/` or `out/`.** Every build starts from the signed release
  tarball pinned in `upstream.conf` (key in `keys/`). Upstream files change only through
  `patches/` (listed in `patches/series`); our own files live in `overlay/`, which may only
  add files.
- **Keep VMS changes minimal and upstreamable:** guard with `#ifdef __VMS`, one fix per patch,
  each with a `Subject:` line and the VMS reason.
- **Use `tools/vms.sh`** for remote work; never raw `ssh host cmd`, never `WAIT` over ssh.
  Run long jobs (probes, builds, soak tests) with `run_in_background`.
- **Committed files must not contain real node details** (they live in the git-ignored
  `tools/nodes.conf`), nor credentials. Use `<ia64-host>`, `<x86-host>`.
- **Nothing destructive or system-wide on the nodes** without asking: no DELETE/PURGE outside
  our work directories, no installs, no system logical names, no privileged ports, no
  stopping other web servers. CRTL feature logicals are set per process (`DEFINE/PROCESS`)
  or in the image via `LIB$INITIALIZE`. Test servers listen on high ports (18080-18099,
  FastCGI 19000-19031) and are stopped when a test ends.
- Every build failure gets one entry in `docs/PORTING_LOG.md` (command, error, root cause,
  fix, patch). Every decision goes in `docs/DECISIONS.md` with the alternatives considered.
- Prefer a 20-line probe in `probes/` over speculation. Do not claim something works until a
  test on the node shows it.

## Platform facts that shape the port (details in docs/DECISIONS.md)

- No `fork()` and no `posix_spawn()` in the CRTL; `vfork()` + `exec*()` only. lighttpd runs
  as one process in the foreground; DCL makes it a detached process.
- No epoll/kqueue: lighttpd's `poll()` backend.
- VSI C, ILP32 by default: the same ABI as SSL3's `*_SHR32` images and the vms-zlib /
  vms-pcre2 trees. Don't mix in clang objects.
- `time_t` is 32-bit.
- C diagnostics go to SYS$ERROR: `define sys$error sys$output` in procedures run by vms.sh.

## Commands

```sh
tools/prepare.sh                     # fetch+verify, extract, patches, overlay -> staging/
tools/recon.sh <node>                # Phase 0 environment -> docs/env-<node>.txt (read-only)
tools/probe.sh <node>                # Phase 0 probes (VSI C) -> docs/probes-<node>.txt
tools/vms.sh <node> dcl '<cmd>' ...  # run DCL; also run/batch/put/get
```

## Commits

Commit in logical steps with messages that explain the VMS reason for each change. Don't push
without the user asking; the remote will be `origin` (github.com/issinoho/vms-lighttpd).
