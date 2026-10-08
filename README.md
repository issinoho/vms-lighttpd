# vms-lighttpd

A port of [lighttpd](https://www.lighttpd.net/) 1.4 to OpenVMS (x86-64 and IA64),
built natively with VSI C against VSI's SSL3 (OpenSSL 3.0). It is meant as a light, modern
alternative to VSI's Apache for HTTPS and PHP sites. The acceptance test is phpBB 3.3.x on
VSI PHP over FastCGI.

**Status:** all five phases done on x86-64 and IA64: lighttpd 1.4.85 serves static files,
HTTPS (TLS 1.3/1.2, HTTP/2) and PHP over FastCGI; phpBB 3.3.19 runs on it with PHP 8.1 and
vms-mariadb; PCSI kits (product LIGHTTPD V1.4-85E1) install a service that runs under its
own account and drops privileges after binding.  See docs/PHASE0-5.md.

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
