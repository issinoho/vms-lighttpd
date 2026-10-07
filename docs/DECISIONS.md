# Decisions

Each entry: the decision, its status, the alternatives considered and the evidence.

## D0. Repository method: release tarball + patches + overlay (as the sibling ports)

**Status:** approved by the user (2026-10-07).

Same layout and tooling as vms-curl / vms-mariadb: `upstream.conf` pins lighttpd's signed
release tarball, `patches/` changes upstream files, `overlay/` adds ours, `tools/vms.sh` runs
everything on the nodes. A fork of lighttpd1.4 on GitHub was not chosen: rebasing a short
patch series on each release is simpler and keeps the VMS delta visible.

## D1. Which server: lighttpd 1.4.x

**Status:** approved by the user (2026-10-07).

Requirements: HTTPS with VSI SSL3 (OpenSSL 3.0); PHP from VSI's PHP kit (8.1) good enough
for phpBB 3.3.x; light, stable, fast; x86-64 required, IA64 a bonus.

Platform facts (vms-mariadb's x86 probes, `docs/probes-x86-cc.txt` there): no `fork`, no
`posix_spawn`, no epoll; `poll`, `socketpair`, `writev`, `mmap`, non-blocking `accept`,
IPv6 work. Process creation is slow on VMS, so PHP must not start a process per request.

| Candidate | For | Against |
|---|---|---|
| **lighttpd 1.4.85** | One process with an event loop; `poll` backend. Since 1.4.70 a native Windows build puts process creation behind `fdevent_createprocess()` and builds without fork (`fdevent_fork_execve` has a no-fork `#else`). Modules can be linked statically (`LIGHTTPD_STATIC`). Pure C, ~110 kLOC, few dependencies (OpenSSL, PCRE2, zlib: all available). FastCGI to external `host:port` backends. Built-in HTTP/2. | Uses some C11 (`static_assert` with a fallback in `ck.h`, one `_Alignas`); configure is CMake/meson/autotools, none usable on VMS (D3). |
| nginx | Best known, fastest on Unix. | Its production model needs `fork` (master and workers), shared memory across processes (`MAP_ANON|MAP_SHARED` zones) and Unix signals for control. Single-process mode (`master_process off`) is for development only. Its Windows port is Win32 API code and can't be reused. Its shell `configure` would have to be cross-run. Much bigger port, and the multi-worker speed would not carry over. |
| Apache httpd 2.4 (current) | Familiar to CSWS users; mod_php exists. | Needs APR, which has no maintained VMS port (VSI keeps its own); heavy; it's what we are replacing. |
| CivetWeb (VSI ships 1.17) | Already on the node. | PHP only as plain CGI, one process per request: slow on VMS. No FastCGI. |
| H2O, Caddy, OpenLiteSpeed | Modern. | libuv/epoll/kqueue, Go, or C++ with Linux-specific I/O: far from VMS. |
| WASD (native VMS) | Mature, runs on x86, persistent PHP. | Not a port of a mainstream server; it is our **performance baseline**, not the target. |

## D2. Compiler: VSI C, not clang

**Status:** proposed (2026-10-07); confirm with the Phase 0 probes and the first compile.

lighttpd is pure C. VSI C (V7.7 on x86, ILP32 by default) shares an ABI with VSI SSL3's
`*_SHR32` images, the vms-zlib and vms-pcre2 install trees and every other VSI C sibling,
exactly as vms-curl links them. clang on x86 is LP64 (vms-mariadb D4), which would need
SSL3's 64-bit images and a `long` audit (vms-mariadb D9) and clang builds of zlib/PCRE2.
VSI C is also the same compiler family on IA64, so IA64 comes almost for free.

lighttpd's CMake/meson set C11, but its use of C11 is light: `static_assert` already
falls back to a runtime assert in `ck.h`, `_Alignas` appears once, `__builtin_expect` and
`__has_builtin` have fallbacks in `first.h`. Expect a small patch or two.

Fallback: clang on x86 only, with SSL3's 64-bit images.

## D3. Configuration: a hand-maintained config_vms.h, no configure run

**Status:** proposed (2026-10-07).

lighttpd's configuration is about 60 header/function checks (`probes/headers.list`,
`probes/functions.list`), and most answers are fixed for VMS. A hand-written
`overlay/vmsport/config_vms.h`, with every `HAVE_*` traced to a probe result, is simpler than
replaying CMake checks (vms-mariadb D1/D8) or running autoconf under GNV (vms-grep, 50-70
min). The build is `vmsport/BUILD.COM` + `DESCRIP.MMS` (MMS ships with VMS).

## D4. PHP: a persistent FastCGI pool of php-cgi processes

**Status:** proposed (2026-10-07); depends on Phase 0 finding a FastCGI-capable php-cgi in
VSI's PHP kit.

N detached `php-cgi -b 127.0.0.1:<port>` processes (`PHP_FCGI_CHILDREN=0`, which needs no
`fork`), started and restarted by a DCL procedure; lighttpd's `fastcgi.server` lists all
N as hosts and balances over them. No process starts per request. lighttpd does not spawn
backends itself (`bin-path`): that needs passing a listening socket to a child, which
`probes/r_spawn.c` tests.

Rejected: plain CGI (a process per request); embedding libphp in lighttpd (no upstream SAPI
for it; VSI's MOD_PHP.EXE is tied to Apache's module ABI).

## D5. phpBB's database: our vms-mariadb server

**Status:** approved by the user (2026-10-07).

Tests our ports together. Needs PHP's `mysqli` extension on the node running PHP. VSI's PHP
8.0 kit listed `MYSQLI.EXE`/`MYSQLND.EXE`/`PDO_MYSQL.EXE` as **IA64 only**; Phase 0 checks the
installed x86 kit. If x86 has none, the alternatives are PHP on IA64 using the x86 server
over TCP, or SQLite3/PostgreSQL (VSI LIBPQ is installed on x86) for the test only.
