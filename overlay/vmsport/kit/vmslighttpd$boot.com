$! VMSLIGHTTPD$BOOT.COM - batch job, run as the service account by
$! VMSLIGHTTPD$CONTROL START (SUBMIT/USER=<account>): starts the PHP pool and
$! the server as detached processes, then exits.
$!
$! RUN/DETACHED/AUTHORIZE LOGINOUT from a job of the account gives the server
$! the account's own identity, UAF quotas and privileges (TMPMBX,NETMBX);
$! vms-mariadb's DECISIONS D15 compares the alternatives.
$!
$ set noon
$ set process/parse_style=extended
$ say = "write sys$output"
$ @SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ data = vmslighttpd_data
$ logs = data - "]" + ".LOGS]"
$ phpdir = data - "]" + ".PHP]"
$ say "VMSLIGHTTPD$BOOT: ", f$time(), " as ", f$getjpi("", "USERNAME")
$ if f$edit(vmslighttpd_php, "UPCASE") .eqs. "YES" then -
     @VMSLIGHTTPD$ROOT:[COM]PHP_POOL START 'vmslighttpd_php_count' 'vmslighttpd_php_base' -
        'phpdir' 'vmslighttpd_php_root'
$ run/detached/authorize sys$system:loginout.exe -
      /input=VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$SERVER.COM -
      /output='logs'SERVER.LOG /error='logs'SERVER.LOG -
      /process_name=VMSLIGHTTPD
$ say "VMSLIGHTTPD$BOOT: server process ", $status
$ exit 1
