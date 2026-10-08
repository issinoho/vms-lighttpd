# Phase 5: service and PCSI kits

Kits (`tools/kit.sh <node>` -> `out/kits/`): `ISSINOHO-X86VMS-LIGHTTPD-V0104-85E1-1.PCSI`,
`ISSINOHO-I64VMS-LIGHTTPD-V0104-85E1-1.PCSI` (product LIGHTTPD, D12).  Install check
(`tools/installcheck.sh <node> <uic> <data-dir> [port] [CLEANUP]`, approved by the user;
it installs the kit, runs VMSLIGHTTPD$CONFIGURE, starts the service, checks it over HTTP,
rotates logs and stops it):

| Check | x86 (2026-10-08) | IA64 (2026-10-08) |
|---|---|---|
| default page on port 981 (< 1024: needs the installed image's OPER) | pass | pass |
| PHP through the pool, as LIGHTTPD | pass (8.1.23) | pass (8.0.29) |
| 404 | pass | pass |
| server process user LIGHTTPD | pass | pass |
| server privileges TMPMBX,NETMBX only (CURPRIV, and logged mask 0x108000) | pass | pass |
| ROTATE: new log versions, SIGHUP | pass | pass |
| graceful stop (SIGTERM) | pass | pass |
| total | 7/7 | 7/7 |

Left installed on both nodes (user's choice): product LIGHTTPD, account LIGHTTPD [361,1]
(batch only, TMPMBX,NETMBX; FILLM 2000 on x86, 448 on IA64 where CHANNELCNT is 512), data
directory SYS$SYSDEVICE:[VMSLIGHTTPD_DATA], SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM with port 981
and AUTOSTART NO; the service is stopped.  To go live on port 80: edit server.port in
[VMSLIGHTTPD_DATA.CONF]LIGHTTPD.CONF (on x86 once Apache has released port 80), add
VMSLIGHTTPD$STARTUP/SHUTDOWN to SYSTARTUP_VMS/SYSHUTDWN, set vmslighttpd_autostart "YES".

Found on the way (PORTING_LOG #28-32): PCSI's 39-character kit name limit; INSTALL through a
foreign-command symbol; INSTALL refuses /TRACEBACK images as privileged (link /NOTRACEBACK);
privileges from an installed image live in the *current* mask, so the first privilege drop
left OPER enabled until both masks were changed and the result checked (patch 0014 now stops
the server if anything beyond TMPMBX,NETMBX remains); PHP moved out of APACHE$ROOT by the
user, its images given W:RE (with approval) so the service account can run them.
