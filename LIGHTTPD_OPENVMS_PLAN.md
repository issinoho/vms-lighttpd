# lighttpd → OpenVMS port: working plan (approved 2026-10-07)

## Context

VSI's Apache (CSWS 2.4-62) lags upstream and has a poor record for stability and performance.
We want a modern, light, fast HTTP/S server for OpenVMS x86-64 (IA64 is a bonus). The
acceptance test is **TLS plus a working phpBB 3.3.x** on VSI PHP 8.1.x and VSI SSL3
(OpenSSL 3.0.x). The port joins the `issinoho/vms-*` family and uses the same method:
signed upstream tarball + `patches/` + `overlay/`, `tools/vms.sh`, PCSI kit.

**Decision (approved): lighttpd 1.4.x.** Why it fits:
- It runs as one process with an event loop and a `poll` backend. Our probes show the x86
  CRTL has `poll`, `socketpair`, `writev`, `mmap` and non-blocking `accept`. It has no `fork`,
  no `posix_spawn` and no epoll.
- Since 1.4.70, lighttpd's native Windows build routes process creation through
  `fdevent_createprocess()`. That gives a VMS implementation one clean place to go.
- It can link its modules in statically (`LIGHTTPD_STATIC`, `plugin-static.h`), so we don't
  need `dlopen`.
- It is pure C. Built with **VSI C** (ILP32), it shares an ABI with SSL3's `*_SHR32` images,
  vms-zlib and vms-pcre2, exactly as vms-curl does. That avoids the clang LP64 mismatch from
  vms-mariadb (D4) and gives IA64 almost for free.
- PHP runs as a persistent **FastCGI pool**: detached `php-cgi -b 127.0.0.1:<port>`
  processes that lighttpd load-balances. No process is created per request, which matters
  because process creation on VMS is slow.

We rejected nginx: it needs `fork` for master and workers, shared memory across processes
and Unix signals, and its Win32 port can't be reused. CivetWeb (VSI ships 1.17) runs PHP
only as plain CGI. **WASD** is the native-VMS performance baseline.

**phpBB database: our vms-mariadb server** (x86), reached over TCP.

## Workspace and conventions

- Repo: `~/projects/vms-lighttpd` in this machine's **Ubuntu WSL**. Remote:
  `github.com/issinoho/vms-lighttpd`; don't create it or push without being asked.
- Copy the tooling from **vms-curl**, the closest sibling (C, VSI C, SSL3, both
  architectures, PCSI): `tools/{vms.sh,fetch.sh,prepare.sh,push.sh,build.sh,test.sh,kit.sh,installcheck.sh}`,
  `tools/nodes.conf.example`, `.gitignore`, and the `CLAUDE.md` ground rules. Clone vms-curl,
  vms-zlib, vms-pcre2 and vms-mariadb into `~/projects` for reference.
- The user supplies `tools/nodes.conf`, which is git-ignored. Committed files use `<x86-host>` and `<ia64-host>`.
- Docs: `docs/DECISIONS.md` (D0 records this choice), `docs/PORTING_LOG.md`, `docs/PHASE0.md`.
- Naming: product **VMSLIGHTTPD**, `VMSLIGHTTPD$ROOT`, `VMSLIGHTTPD$STARTUP.COM`, version
  `V1.4-84E1` style (three-part version + `VMS_PATCH_LEVEL`).

```
vms-lighttpd/
  CLAUDE.md  README.md  upstream.conf  keys/lighttpd-signing-key.asc
  patches/series  patches/NNNN-*.patch
  overlay/vmsport/  build.com  descrip.mms  config_vms.h  plugin-static.h
                    vms_crtl_init.c  vms_process.c   # fdevent_createprocess for __VMS
                    php_pool.com  lighttpd$server.com  conf/lighttpd.conf  conf/phpbb.conf
                    kit/...  tests/...
  probes/  tools/  docs/
```

`upstream.conf` pins the latest 1.4.x release tarball (`.tar.xz`), its SHA-256 and the
signing key. It also sets `ZLIB_TREE`, `PCRE2_TREE`, `SSL_KIT=SSL3`, and later `PHPBB_VERSION` with its SHA-256.

## Phase 0: Reconnaissance (stop and report at the end)

On both nodes, using `tools/vms.sh`, and record results in `docs/PHASE0.md`:
1. **PHP kit:** check the version, `php -m`, `PHP$ROOT:[BIN]` contents, and whether
   `php-cgi`/`PHP_CGI.EXE` exists with FastCGI (`-b`). Look for **mysqli/mysqlnd** (needed
   for phpBB), opcache, mbstring, json, xml, gd and zlib. If x86 has no mysqli, stop and
   decide: phpBB on IA64 PHP talking to x86 MariaDB, or SQLite3/PostgreSQL for the test.
2. **Probes** (`probes/*.c`, built with VSI C):
   - `vfork`+`execve` of an image, and whether a socket fd is inherited by the child.
   - `poll` with many fds; the per-process FILLM/CHANNELCNT limit.
   - `stat().st_size` versus bytes from `read()` and `mmap` on stream-LF, fixed-512 and
     variable-record files. Content-Length depends on this.
   - `writev` on sockets; `SO_REUSEADDR` and an IPv6 dual-stack listener.
   - SSL3 `*_SHR32` TLS handshake from VSI C (`SSL_CTX_new`, ALPN, session tickets).
   - Calls returning `long`, as in vms-mariadb D9.
3. Confirm vms-zlib and vms-pcre2 install trees exist on both nodes, or build them there.
4. Confirm the vms-mariadb server can be reached on x86 (port 3307).

**Exit:** PHASE0.md complete, the PHP/DB route decided, and probe results recorded in DECISIONS.md.

## Phase 1: Build lighttpd (x86 first, then IA64)

- **Configuration:** write a hand-maintained `overlay/vmsport/config_vms.h` with the
  `HAVE_*` set from the probes. lighttpd's config is small. Don't run autotools, CMake or
  meson on VMS. `build.com` + `descrip.mms` compile with VSI C, using `/STANDARD=C99`,
  `/NAMES=(AS_IS,SHORTENED)` to match the sibling libraries, and `LIGHTTPD_STATIC`.
- **Static module set:** `mod_openssl`, `mod_fastcgi` (+ `gw_backend`), `mod_rewrite`,
  `mod_redirect`, `mod_access`, `mod_accesslog`, `mod_alias`, `mod_setenv`, `mod_expire`,
  `mod_deflate`, `mod_indexfile`, `mod_dirlisting`, `mod_staticfile`.
- **Expected patches**, one per fix, `#ifdef __VMS`, each with a `Subject:` line:
  - `fork()` in `server.c`: daemonize, `server.max-worker`, graceful restart. Run in the
    foreground and let DCL make the process detached.
  - A `fdevent_createprocess` / `fdevent_fork_execve` path using `vfork`+`execve`, needed
    only for mod_cgi and piped logs, which are optional. If probes show sockets don't
    inherit, document that `fastcgi.server` `bin-path` is unsupported.
  - Header gaps (`sys/select.h`, `sys/uio.h`, `crypt.h`), `getrlimit`/`setrlimit`, and
    `chroot`/`setuid` (no-ops or errors on VMS).
  - **Static files:** serve record-format files correctly, so Content-Length is right.
    Either detect non-stream files and fall back to buffered `read()` without `mmap`, or
    reject them with a logged error. Choose from the probe results.
  - Entropy/RNG through OpenSSL `RAND_bytes`; there is no `/dev/urandom`.
- `vms_crtl_init.c` sets CRTL features in the image through `LIB$INITIALIZE`, as vms-mariadb
  does: `DECC$EFS_CHARSET`, `EFS_CASE_PRESERVE`, `FILENAME_UNIX_REPORT`, `ARGV_PARSE_STYLE`,
  `POSIX_COMPLIANT_PATHNAMES` if needed.

**Exit:** `lighttpd -v`, `-V` and `-tt` (config test) run on x86, then on IA64.

## Phase 2: Static HTTP, then HTTPS

1. Serve a docroot over HTTP on a high port. Test from WSL with curl: GET/HEAD, Range,
   If-Modified-Since, keep-alive, 404/403, a large (100 MB) file, directory index.
2. Turn on `mod_openssl` with the SSL3 images: a self-signed certificate, then a proper
   chain. Test TLS 1.2 and 1.3, ALPN, HTTP/2 (lighttpd 1.4.x has h2 built in), and session
   resumption. Scan with `testssl.sh` from WSL.
3. **Soak:** `h2load`/`wrk` from WSL for 1 h at moderate concurrency; no leaks (watch
   `SHOW PROCESS/QUOTA` and page file use) and no stuck connections.

## Phase 3: PHP over FastCGI

- `overlay/vmsport/php_pool.com` starts N detached `php-cgi -b 127.0.0.1:90NN` processes
  (`PHP_FCGI_CHILDREN=0`, `PHP_FCGI_MAX_REQUESTS` for recycling), with their own
  `PHP.INI` and opcache on. It also stops and restarts them.
- `fastcgi.server` lists the N hosts so lighttpd balances across them.
- Tests: `phpinfo()`, POST and uploads (`upload_tmp_dir`), cookies and sessions, large
  responses, and what happens when one backend is killed.

## Phase 4: phpBB acceptance test

- Fetch phpBB 3.3.x (latest; pin the version and SHA-256), unpack it as **stream-LF** on an
  ODS-5 disk, and set writable `cache/`, `store/`, `files/`, `images/avatars/upload/`.
- Write `conf/phpbb.conf` with phpBB's lighttpd rules: deny `config.php`, `cache`,
  `store`, `files` and `includes`, and the `app.php` rewrite.
- Run the web installer against the vms-mariadb server, then a functional checklist:
  register, log in, post, reply, attach a file, search, ACP pages, the email queue (the
  cron task), purging the cache.
- **Benchmark** phpBB index and topic pages with the same `wrk` script against WASD and
  VSI Apache with MOD_PHP on the same node. Record the numbers in the README.

## Phase 5: Service and kit

- `lighttpd$server.com`: run as a detached process under a dedicated account (follow
  vms-mariadb's `docs/PLAN_SERVICE.md` pattern), with startup and shutdown procedures. Log
  rotation by reopening the log on a signal or by file versions.
- PCSI kit `VMSLIGHTTPD`: the image, sample configs, `php_pool.com`, the phpBB snippet and
  `readme.vms`. Run `tools/installcheck.sh` only after asking, because it changes the system.

## Verification

At each phase, from WSL against `<x86-host>` (then `<ia64-host>`):
- `tools/build.sh x86 CLEAN` then `ALL` must finish with no undefined symbols. Also
  `tools/test.sh x86`, a smoke test that starts the server, runs curl checks for HTTP,
  HTTPS and PHP, then stops it and checks the exit severity.
- TLS: a `testssl.sh` report with no high or critical findings.
- PHP/phpBB: the Phase 4 checklist script plus manual browser checks; the error log stays
  clean.
- Stability: 1 h soak + kill-a-backend + restart cycles; process quotas stay flat.
- A failure counts as fixed only when the test passes again on the node.
