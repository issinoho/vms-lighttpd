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

**Status:** proposed (2026-10-07). Phase 0 (x86, 2026-10-07): `PHP$ROOT` (system logical; briefly `PHP_ROOT` on 2026-10-07,
`[SYS0.SYSCOMMON.APACHE.PHP.]`) is PHP 8.1.23 built 13-Sep-2023; `PHP$ROOT:[BIN]PHP_CGI.EXE`
is the `cgi-fcgi` SAPI and has `-b <address:port>` (FastCGI server mode). opcache is
`PHP$ROOT:[EXTENSIONS]PHP_OPCACHE.EXE`, not loaded by the system `PHP.INI`; the pool will use
its own ini. An older VSI 8.0 kit also sits in `SYS$COMMON:[PHP]` (unused). IA64 (PHP
installed there on 2026-10-07): VSI's 8.0.10 kit, `PHP$ROOT:[CSWS]PHP-CGI.EXE` (`cgi-fcgi`),
opcache built in. See docs/PHASE0.md.

N detached `php-cgi -b 127.0.0.1:<port>` processes (`PHP_FCGI_CHILDREN=0`, which needs no
`fork`), started and restarted by a DCL procedure; lighttpd's `fastcgi.server` lists all
N as hosts and balances over them. No process starts per request. lighttpd does not spawn
backends itself (`bin-path`). `probes/r_spawn.c` shows it could: a listening socket
reaches a `vfork`+`execve` child, as an inherited fd or as stdin. We still use the external
pool, because each spawn costs ~60 ms on the x86 VM and the pool keeps process control
in DCL.

Rejected: plain CGI (a process per request); embedding libphp in lighttpd (no upstream SAPI
for it; VSI's MOD_PHP.EXE is tied to Apache's module ABI).

## D5. phpBB's database: our vms-mariadb server

**Status:** approved by the user (2026-10-07).

Tests our ports together. Needs PHP's `mysqli`. Phase 0 (x86): PHP 8.1.23 has `mysqli`,
`mysqlnd` and `pdo_mysql` built in (`php -m`), and the vms-mariadb server (`MARIADBD_3306`)
listens on port 3306. So phpBB runs on x86 against it, over TCP to 127.0.0.1:3306.
Fallbacks if needed: `PHP_SQLITE3.EXE` / `PHP_PDO_PGSQL.EXE` are in `PHP$ROOT:[EXTENSIONS]`.
IA64's PHP 8.0.10 loads `mysqli`/`pdo_mysql` from `PHP$ROOT:[LIB.EXTENSIONS]` when its ini
names them, so it could use the x86 server over TCP. But it has no gd or mbstring, so the
full phpBB test runs on x86.

## D6. Dependencies: build vms-zlib and vms-pcre2 into this work directory

**Status:** proposed (2026-10-07).

Neither node has a vms-zlib or vms-pcre2 install tree in this work directory or a sibling
one. PCRE2 is needed for lighttpd's regex conditionals and mod_rewrite, which phpBB uses;
zlib for mod_deflate. Build both with their own repos' tooling into
`<workdir>.ZLIB-1_3_2.INSTALL_<arch>]` and `<workdir>.PCRE2-10_49.INSTALL_<arch>]` on each
node. x86 also has a `zlib.h` in the default include path, origin unknown; we don't use it, so
the zlib version stays pinned.

## D7. Connection capacity comes from process quotas

**Status:** finding (2026-10-07); acting on it is Phase 5.

`r_net2`: every socket uses BYTLM. Our accounts reach 168 (x86, BYTLM 498784) and 44 (IA64,
BYTLM 127040) concurrent connections; FILLM (1000 / 150) is the fd limit
(`sysconf(_SC_OPEN_MAX)`), and the CRTL has no `getrlimit`. The server's account needs high
BYTLM and FILLM. IA64's system CHANNELCNT is 512, which caps one process at about 250
connections unless SYSGEN is changed. lighttpd's `server.max-connections` must be set below
the quota-derived limit; the startup procedure computes it.

## D8. Files that are not stream-LF: buffered read, chunked, with a warning

**Status:** approved by the user (2026-10-07); to implement in Phase 2 with the static-file
tests.

`r_files`: only stream-LF and UDF files have `st_size` equal to the bytes `read()` returns.
For fixed, variable and stream-CRLF files lighttpd must not take Content-Length from
`st_size` or `mmap()` the file: read them through the CRTL (which converts records),
send the response chunked, and log a warning naming the file once. Rejected: refusing them
(500): friendlier to serve, and the warning tells the admin to `CONVERT` the file.

## D9. Phase 1 build notes

**Status:** record (2026-10-08).

- Compile flags: `/NAMES=(AS_IS,SHORTENED)/FLOAT=IEEE`, `_LARGEFILE`, `_USE_STD_STAT`,
  `_POSIX_EXIT`, `_SOCKADDR_LEN`; no `_XOPEN_SOURCE*` (PORTING_LOG #1-2).
- Include directories in UNIX form so relative includes resolve (PORTING_LOG #3).
- The process-creation path (`fdevent_fork_execve` via `vfork`+`execve`) is **not** written
  yet: nothing built needs it (no mod_cgi, PHP is an external FastCGI pool, D4). Without
  `HAVE_FORK` it returns -1, so `bin-path` and piped logs fail cleanly.
- Not yet looked at: `server.upload-dirs` defaults to `/var/tmp` (absent on VMS);
  `__FILE__` in log lines is a full VMS file spec; `-V` loses its feature list when run
  with `/OUTPUT=` (write() then printf()).

D8 as built (2026-10-08, patch 0008): non-Stream_LF/UDF files up to 32 MB are read through
the CRTL and sent from memory **with their exact Content-Length** (Range/ETag still work),
rather than chunked; larger ones are refused with 500 and a log entry. One warning per file.

## D10. TCP throughput (first measured ~50-130 KB/s; see "D10 revisited": mostly the client)

**Status:** finding (2026-10-08), reported to the user; outside the port.

Phase 2 downloads crawled. Measured with `probes/r_blast.c` (sends 10 MB from memory, blocking
or poll()-driven, optional SO_SNDBUF): x86 → WSL 55-86 KB/s, IA64 → WSL 70-80 KB/s, x86 →
Windows directly 71 KB/s, x86 loopback (VMSCURL client) 90 KB/s, OpenSSH sftp download from
x86 46 KB/s; a 256 KB or 1 MB SO_SNDBUF changes nothing. lighttpd matches these (2 MB in
16-50 s). Files read at ~35 MB/s and `poll()`/`TCP_NODELAY` behave (`r_pollout`,
`r_nodelay`, `r_fileread`), so the limit is the TCP/IP stack configuration on these systems
(`sysconfig -q inet`: tcp_sendspace/recvspace 61440, delayed ACK on, tcp_cwnd_segments 2,
mssdflt 536, SACK/timestamps off) or the hosts' network setup; tuning it is a system change
for the user. Consequences: tests move 2 MB, not 100 MB; Phase 4 benchmarks must compare
servers on the same node and network, and will be dominated by this limit for large pages.

D4 as built (2026-10-08): `vmsport/php/php_pool.com START|STOP|STATUS [count] [base-port]
[pool-dir] [php-root] [max-req]` starts detached `LTPHP_<port>` processes running
`PHP_CGI.EXE -c <pool>PHP.INI -b 127.0.0.1:<port>` in a DCL restart loop, with explicit
quotas; `vmsport/php/php.ini` is the pool's ini (opcache needs `opcache.lockfile_path`
on VMS; no `/tmp`). PHP's own recycling (`PHP_FCGI_MAX_REQUESTS`) is off by default: it
drops requests queued on the exiting process (PORTING_LOG #22). A killed PHP process costs
no requests: lighttpd marks the backend down and uses the others; `START` again restarts
only the missing ones.

## D11. Which PHP on each node

**Status:** approved by the user (2026-10-08) for x86; IA64 follows the same default.

Both nodes now have two logical names. x86: `PHP_ROOT` = `[SYS0.SYSCOMMON.APACHE.PHP.]`,
PHP **8.1.23** (mysqli, gd, mbstring built in); `PHP$ROOT` = VSI's PHP 8.0.10 kit (no
mysqli on x86). The user chose `PHP_ROOT` for the pool, overriding the earlier
"`PHP$ROOT` first" rule (which still applies to the recon script). IA64 (reinstalled during
Phase 3): `PHP_ROOT` = `DKA800:[PHP.]`, PHP **8.0.29**, same layout and built-ins as the
x86 8.1 kit; `PHP$ROOT` points to a directory that no longer exists. `php_pool.com`
defaults to `PHP_ROOT`; `php-vsi80.ini` covers VSI's 8.0 kit layout if wanted.

D10 revisited (2026-10-08, user-approved runtime experiments, `tools/tcptune.sh`, all
settings restored afterwards): one at a time, `tcpnodelack=1`, `tcp_cwnd_segments=10`,
256 KB send/recv space, SACK + timestamps, and all together, measured with `r_blast`
(KB/s, 20 s):

| | x86 loopback | x86 LAN | IA64 loopback | IA64 LAN |
|---|---|---|---|---|
| baseline | 97 | – | 457 | 1,111 |
| tcpnodelack=1 | – | – | 458 | 663 |
| cwnd 10 | 98 | 1,393 | 453 | 761 |
| 256 KB space | 100 | – | – | 725 |
| SACK + ts | 99 | 1,117 | 458 | 621 |
| all | 98 | – | 457 | – |

(– = no reading.) No setting helps; the defaults stay. The LAN figures are 10-20x the
Phase 2 ones because the WSL/Windows client was short of memory then (Claude Code had to
stop a job for low memory; after the user freed memory the same probe moved 0.6-1.4 MB/s).
So D10's ~50-130 KB/s was mostly the client, not VMS. x86 loopback stays ~98 KB/s whatever
the TCP settings (IA64: ~457 KB/s): a property of the x86 VM or of VMSCURL writing to NLA0:
there, not TCP tuning; it does not affect serving remote clients. `tools/vms_tcpdiag.com`
is the read-only diagnosis (settings, NICs, `netstat -s`).
