$! VMSLIGHTTPD$SERVER.COM - the lighttpd server process (detached, started by
$! VMSLIGHTTPD$BOOT).  Runs lighttpd in the foreground until it exits.
$!
$ set noon
$! EXTENDED: otherwise the C RTL lowercases "-D" (DECC$ARGV_PARSE_STYLE, which
$! LIGHTTPD.EXE sets itself, only takes effect with it)
$ set process/parse_style=extended
$ @SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ lighttpd = "$VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE"
$ write sys$output "VMSLIGHTTPD$SERVER: start ", f$time(), " as ", f$getjpi("", "USERNAME")
$! -f in UNIX form: lighttpd resolves relative includes against its directory
$ lighttpd "-D" "-f" "''vmslighttpd_conf'"
$ write sys$output "VMSLIGHTTPD$SERVER: exit ", $status, " ", f$time()
$ exit 1
