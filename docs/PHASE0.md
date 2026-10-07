# Phase 0: reconnaissance

Status: not run yet (needs `tools/nodes.conf` and the SSH key).

Raw output: `docs/env-<node>.txt` (`tools/recon.sh`), `docs/probes-<node>.txt`
(`tools/probe.sh`). This file summarises them.

## Questions to answer

| # | Question | x86 | IA64 |
|---|---|---|---|
| 1 | PHP kit version; `php -m` | | |
| 2 | php-cgi (FastCGI, `-b`) present? | | |
| 3 | mysqli / mysqlnd / pdo_mysql present? (phpBB, D5) | | |
| 4 | opcache, mbstring, xml, gd, zlib, json, sqlite3 | | |
| 5 | `vfork`+`execv` works; child stdout to pipe / socketpair / TCP (`r_spawn`) | | |
| 6 | socket inherited by a child (fastcgi `bin-path`) (`r_spawn`) | | |
| 7 | cost of one spawn (ms) (`r_spawn`) | | |
| 8 | `st_size` = bytes read for stream-LF / var / fix files (`r_files`) | | |
| 9 | max concurrent connections; `poll()` cost per call (`r_net2`) | | |
| 10 | `writev`, half-close, IPv6 dual stack, quick re-bind (`r_net2`) | | |
| 11 | SSL3 SHR32 from VSI C: TLS 1.3 + ALPN h2 + resumption (`s_ssl3_tls`) | | |
| 12 | header/function answers for config_vms.h (H_/F_/G_ sets) | | |
| 13 | vms-zlib / vms-pcre2 install trees in the work directory | | |
| 14 | vms-mariadb server reachable (port 3307) | | |
| 15 | ports free for tests (18080-18099, 19000-19031); other web servers running | | |
