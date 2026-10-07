# vms-lighttpd

A port of [lighttpd](https://www.lighttpd.net/) 1.4 to OpenVMS (x86-64 and IA64),
built natively with VSI C against VSI's SSL3 (OpenSSL 3.0). It is meant as a light, modern
alternative to VSI's Apache for HTTPS and PHP sites. The acceptance test is phpBB 3.3.x on
VSI PHP over FastCGI.

**Status:** Phase 1 done: `LIGHTTPD.EXE` builds and links on x86-64 and IA64 and checks a
configuration (`-tt`). Serving (Phase 2) is next.

This repository stores only the VMS delta over the signed upstream release, the same way as
its siblings ([vms-curl](https://github.com/issinoho/vms-curl),
[vms-mariadb](https://github.com/issinoho/vms-mariadb), ...):

- `upstream.conf`: the pinned release, its SHA-256 and signing key (`keys/`)
- `patches/`: changes to upstream files, applied in `patches/series` order
- `overlay/`: files we add (VMS build procedures, config header, DCL wrappers)
- `tools/`: host-side scripts that prepare the tree and drive the VMS nodes over SSH
- `probes/`: small C programs that pin down platform behaviour
- `docs/`: decisions, porting log, Phase 0 results

See `LIGHTTPD_OPENVMS_PLAN.md` for the plan and `docs/DECISIONS.md` for why lighttpd.
