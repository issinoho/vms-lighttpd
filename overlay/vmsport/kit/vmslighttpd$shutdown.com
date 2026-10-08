$! VMSLIGHTTPD$SHUTDOWN.COM - stop lighttpd and its PHP pool cleanly at system
$! shutdown.  Add to SYS$MANAGER:SYSHUTDWN.COM:
$!     $ @SYS$STARTUP:VMSLIGHTTPD$SHUTDOWN.COM
$ set noon
$ if f$trnlnm("VMSLIGHTTPD$ROOT") .eqs. "" then exit 1
$ if f$search("SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM") .eqs. "" then exit 1
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL STOP
$ exit 1
