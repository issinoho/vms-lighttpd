# Phase 0: reconnaissance

Status: done 2026-10-07 (x86 and IA64).

Raw output: `docs/env-<node>.txt` (`tools/recon.sh`), `docs/probes-<node>.txt` and
`docs/probes-<node>-R.txt` (`tools/probe.sh`, `PROBE_SETS=R` for the corrected runtime
probes), `docs/php-ia64.txt`. The x86 PHP details below came from a direct check (the x86
recon ran while the PHP logical name was being changed).

## Nodes

| | x86 | IA64 |
|---|---|---|
| OS | OpenVMS E9.2-4 (QEMU VM, 2 CPUs) | V8.4-2L3 (rx2660, 1 CPU) |
| C compiler | VSI C V7.7-003 | VSI C V7.4-001 |
| SSL3 | OpenSSL 3.0.21 (`SSL3$LIBSSL_SHR32` etc.) | OpenSSL 3.0.22 |
| Our quotas | BYTLM 498784, FILLM 1000 | BYTLM 127040, FILLM 150 |
| CHANNELCNT (system) | 32768 | 512 |
| Web servers | VSI Apache 2.4-62 on port 80 (11 processes) | none |
| MariaDB | our `MARIADBD_3306`, port 3306 | none |

## Answers

| # | Question | x86 | IA64 |
|---|---|---|---|
| 1 | PHP | `PHP$ROOT` = `[SYS0.SYSCOMMON.APACHE.PHP.]`: **8.1.23** (Sep 2023) | `PHP$ROOT` = `[SYS0.SYSCOMMON.php.]`: VSI kit **8.0.10** (Dec 2022) |
| 2 | FastCGI php-cgi | `PHP$ROOT:[BIN]PHP_CGI.EXE`, `cgi-fcgi`, has `-b` | `PHP$ROOT:[CSWS]PHP-CGI.EXE`, `cgi-fcgi`; `-b` not yet seen (Phase 3) |
| 3 | mysqli / pdo_mysql | built in (`php -m`) | loadable from `[LIB.EXTENSIONS]` (`-d extension=mysqli`); not in the system php.ini. Explicit `extension=mysqlnd` fails (needs `LIBGD$SHR`), but is not needed |
| 4 | other phpBB needs | gd, mbstring, json, xml, zlib, ctype, openssl built in; opcache as `PHP_OPCACHE.EXE`, not loaded | json, xml, ctype, sqlite3 built in, opcache enabled; **no gd, mbstring, zlib** in `php -m` |
| 5 | `vfork`+`execve`; child stdout to pipe / socketpair / TCP | all work | all work |
| 6 | socket passed to a child (by fd number, or as stdin) | works | works |
| 7 | one spawn+exit | ~60 ms | ~9 ms |
| 8 | Content-Length = bytes read | stream-LF and UDF exact; fixed-512 reads padded (2048 for 2000); stream-CRLF and variable records don't match | same |
| 9 | concurrent connections | 168 before **BYTLM** ran out; `sysconf(_SC_OPEN_MAX)` 1000 (= FILLM) | 44 (BYTLM); open max 150 |
| 9b | `poll()` cost | 0.3 ms over 164 fds | 0.02 ms over 40 fds |
| 10 | writev, half-close, quick re-bind | all work | all work |
| 10b | IPv6 | `bind([::])` fails EINVAL: retry with `_SOCKADDR_LEN` (Phase 1) | same |
| 11 | SSL3 SHR32 from VSI C | TLS 1.3 + ALPN h2 + SNI + resumption + TLS 1.2: all work | same |
| 12 | header/function answers | see below | identical, except no `zlib.h` and no `accept4` link |
| 13 | vms-zlib / vms-pcre2 install trees | none | none |
| 14 | vms-mariadb reachable | yes, port 3306 | (use the x86 server over TCP) |
| 15 | test ports 18080-18099, 19000-19031 | free | free |

## Header and function answers (both nodes, VSI C)

- **Present:** `poll.h`, `sys/poll.h`, `sys/uio.h`, `sys/un.h`, `sys/mman.h`, `sys/resource.h`
  (but **no `getrlimit`/`setrlimit`/`RLIMIT_NOFILE`**), `inttypes.h`, `stdint.h`, `strings.h`,
  `dlfcn.h`, `pwd.h`, `grp.h`, `malloc.h`; `zlib.h` on x86 only.
  `clock_gettime`, `crypt`, `getaddrinfo`, `gmtime_r`, `localtime_r`, `inet_pton`, `inet_aton`,
  `jrand48`, `srandom`, `lstat`, `mkstemp`, `mkostemp`, `mmap`, `pipe`, `poll`, `select`,
  `pread`, `pwrite`, `writev`, `realpath`, `setsid`, `sigaction`, `signal`, `socketpair`,
  `strerror_r`, `strptime`, `strtoll`, `umask`, `getuid`, `getpwnam`.
- **Absent:** `sys/select.h`, `crypt.h`, `getopt.h`, `syslog.h`, `spawn.h`, `stdatomic.h`,
  `pcre2.h` (no install tree yet), every epoll/kqueue/devpoll/port header and function;
  `fork`, `posix_spawn`, `getrlimit`, `setrlimit`, `chroot`, `initgroups`, `setgroups`,
  `fchdir`, `openat`, `fstatat`, `fdatasync`, `timegm`, `pipe2`, `sendfile`, `splice`,
  `copy_file_range`, `preadv`, `pwritev`, `madvise`, `mempcpy`, `explicit_bzero`,
  `getentropy`, `getrandom`, `arc4random_buf`, `getloadavg`, `issetugid`, `malloc_trim`.
- `vfork` is a CRTL macro (`decc$vfork`), so the F_/G_ tests report it missing; `r_spawn`
  shows it works. `decc$set_child_standard_streams` links but has no prototype in the
  headers searched.

## Consequences for the plan

1. **IA64 runs PHP too.** It has a FastCGI php-cgi and loadable mysqli, so it can run
   phpBB against the x86 MariaDB. But its PHP 8.0.10 lacks gd and mbstring, so phpBB
   acceptance stays on x86 and IA64 gets a smaller PHP test.
2. **Server account quotas** are a requirement, not a tuning knob. Each connection needs
   BYTLM; our accounts allow 168 (x86) and 44 (IA64) connections. Phase 5's service account
   needs high BYTLM/FILLM. On IA64, CHANNELCNT 512 caps one process at roughly 250
   connections without a SYSGEN change (the user's call).
3. **Record formats:** serve stream-LF/UDF files straight; for other record formats either
   read them buffered and send them chunked (no Content-Length from `st_size`) or refuse
   them. Decide in Phase 1 (D8 to come). phpBB unpacked by unzip/tar is stream-LF.
4. **Dependencies:** build vms-zlib and vms-pcre2 into this work directory on both nodes
   (PCRE2 is needed for mod_rewrite, which phpBB's routes use).
5. **fastcgi `bin-path` could work** (sockets are inherited), but D4's external pool stays
   the plan: it keeps lighttpd from spawning, and a spawn costs ~60 ms on x86.
6. lighttpd needs patches or config answers for: no `getrlimit` (fd limit from
   `sysconf(_SC_OPEN_MAX)`), no `fork`/`chroot`/`setgroups`/`initgroups`, no `timegm`, no
   `syslog.h`, no `sys/select.h`, `open()` on a directory fails.
