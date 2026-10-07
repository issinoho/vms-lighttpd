# Porting log

One entry per build or run failure: command, error, root cause, fix, patch.
Triage codes: T toolchain/flags, H header, L libc function, N networking,
S process model, D dependency, U upstream bug exposed by a new platform.

| # | Date | Command | Error | Code | Root cause | Fix / patch |
|---|---|---|---|---|---|---|
| 1 | 2026-10-07 | `build.sh x86` | log.c: `ts` incomplete type, `CLOCK_REALTIME` undeclared | H | log.c, ck.c, mod_dirlisting.c define `_XOPEN_SOURCE 700`; the CRTL headers then go strict and hide `struct timespec`/`clock_gettime` (guard: `_XOPEN_SOURCE_EXTENDED \|\| !_ANSI_C_SOURCE`) | first tried `/DEFINE=_XOPEN_SOURCE_EXTENDED` globally: see #2 |
| 2 | 2026-10-07 | `build.sh x86` | 961 × `%CC-E-MISSINGTYPE` `u_short`/`u_char` in `<net/if_arp.h>` (31 files) | H | `<sys/types.h>` declares the BSD types only `#ifndef _POSIX_C_SOURCE`, which the X/Open macros imply | dropped the global define; **0002** stops the three files defining `_XOPEN_SOURCE` on VMS |
| 3 | 2026-10-07 | `build.sh x86` | `%CC-F-NOINCLFILEF` `"ls-hpack/lshpack.h"`, `"../compat/sys/queue.h"` | T | VMS-form `/INCLUDE` directories don't take relative UNIX paths | BUILD.COM uses UNIX-form include dirs (`"./src"`, `"./src/ls-hpack"`), as vms-curl does |
| 4 | 2026-10-07 | `build.sh x86` | `%CC-F-NOINCLFILEF` `"compat/fastcgi.h"` | T | push.sh did not upload `src/compat` | push.sh uploads it |
| 5 | 2026-10-07 | `build.sh x86` | server.c: `last_sighup_info`/`last_sigterm_info` undeclared | U | declared under `HAVE_SIGACTION && SA_SIGINFO`, used under `HAVE_SIGACTION`; VMS has no `SA_SIGINFO` | **0003** |
| 6 | 2026-10-07 | `build.sh x86` | server.c: `%CC-E-BADSTATICCVT` on `static ... sentinel = (connection *)(uintptr_t)&log_con_jqueue` | T | VSI C rejects address-through-integer in a static initializer | **0004** (no `static` on VMS, as upstream does for MSVC) |
| 7 | 2026-10-07 | `build.sh x86` | mod_fastcgi.c: `%CC-W-TOOMANYACTLS` then syntax error | T | VSI C miscounts arguments through the object-like alias `log_error_multiline` → variadic `log_err_multiline` with `BUF_PTR_LEN()` | **0005** calls `log_err_multiline` directly |
| 8 | 2026-10-07 | link x86 | `%ILINK-W-MULDEF` `DECC$GETOPT`, `DECC$GA_OPTARG`, ... | L | no `<getopt.h>`, so server.c built its fallback getopt, which the compiler maps onto the CRTL's names | **0006** uses the CRTL's `getopt()` |
| 9 | 2026-10-07 | link x86 | `%ILINK-W-USEUNDEF` `in6addr_any`, `in6addr_loopback` | L | declared by `<netinet/in6.h>`, defined nowhere on VMS (also the `r_net2` ACCVIO) | overlay `vmsport/vms_in6addr.c` defines them |
| 10 | 2026-10-07 | link x86 | (would not link) `setgroups`, `initgroups` | L | under `HAVE_PWD_H` in server.c | `HAVE_PWD_H` left undefined in config.h: the service account replaces user switching |
| 11 | 2026-10-07 | (review) | `server.max-fds` 0 with no `getrlimit` | L | only `_WIN32` had a default | **0001** uses `sysconf(_SC_OPEN_MAX)` (FILLM) |
