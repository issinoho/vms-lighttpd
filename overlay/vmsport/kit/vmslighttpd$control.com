$! VMSLIGHTTPD$CONTROL.COM - start, stop and look after the lighttpd service
$!
$! Usage (privileged: SYSPRV, WORLD, CMKRNL to submit as the service account):
$!   @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL START     submit VMSLIGHTTPD$BOOT
$!                                                       as the service account
$!   @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL STOP      graceful stop (SIGTERM,
$!                                                       then STOP/ID after 30 s),
$!                                                       then the PHP pool
$!   @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL RESTART
$!   @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL STATUS
$!   @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL ROTATE    new log file versions,
$!                                                       SIGHUP (lighttpd reopens
$!                                                       its logs), PURGE/KEEP
$!
$! Site settings: SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM (VMSLIGHTTPD$CONFIGURE).
$! The server process is named VMSLIGHTTPD; the PHP pool's LTPHP_<port>.
$!
$ set noon
$ say = "write sys$output"
$ op = f$edit(p1, "UPCASE,TRIM")
$ if f$search("SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM") .eqs. ""
$ then
$   say "VMSLIGHTTPD: no SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM; run VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONFIGURE first"
$   exit 44
$ endif
$ @SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ data = vmslighttpd_data
$ logs = data - "]" + ".LOGS]"
$ phpdir = data - "]" + ".PHP]"
$ signal = "$VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD_SIGNAL.EXE"
$ if op .eqs. "START" then goto start
$ if op .eqs. "STOP" then goto stop
$ if op .eqs. "RESTART" then goto restart
$ if op .eqs. "STATUS" then goto status
$ if op .eqs. "ROTATE" then goto rotate
$ say "usage: @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL START|STOP|RESTART|STATUS|ROTATE"
$ exit 44
$!
$start:
$ gosub find_server
$ if pid .nes. ""
$ then
$   say "VMSLIGHTTPD: already running (pid ", pid, ")"
$   exit 1
$ endif
$ submit/user='vmslighttpd_account'/noprint/name=VMSLIGHTTPD_BOOT -
      /log_file='logs'BOOT.LOG VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$BOOT.COM
$ if .not. $status then exit $status
$ say "VMSLIGHTTPD: start submitted as ", vmslighttpd_account, " (log ", logs, "BOOT.LOG)"
$ exit 1
$!
$restart:
$ gosub do_stop
$ goto start
$!
$stop:
$ gosub do_stop
$ exit 1
$!
$do_stop:
$ gosub find_server
$ if pid .eqs. ""
$ then
$   say "VMSLIGHTTPD: server not running"
$ else
$   define/user sys$error sys$output
$   signal 'pid' "TERM"
$   n = 0
$stop_wait:
$   gosub find_server
$   if pid .eqs. "" then goto stop_done
$   n = n + 1
$   if n .gt. 30
$   then
$     say "VMSLIGHTTPD: no exit after 30 s; STOP/ID ", pid
$     stop/id='pid'
$     goto stop_done
$   endif
$   wait 00:00:01
$   goto stop_wait
$stop_done:
$   say "VMSLIGHTTPD: server stopped"
$ endif
$ if f$edit(vmslighttpd_php, "UPCASE") .eqs. "YES" then -
     @VMSLIGHTTPD$ROOT:[COM]PHP_POOL STOP 'vmslighttpd_php_count' 'vmslighttpd_php_base' -
        'phpdir' 'vmslighttpd_php_root'
$ return
$!
$status:
$ gosub find_server
$ if pid .eqs. ""
$ then
$   say "VMSLIGHTTPD: server not running"
$ else
$   say "VMSLIGHTTPD: server pid ", pid, " user ", f$getjpi(pid, "USERNAME"), -
        " cpu ", f$getjpi(pid, "CPUTIM"), " privileges ", f$getjpi(pid, "CURPRIV")
$ endif
$ if f$edit(vmslighttpd_php, "UPCASE") .eqs. "YES" then -
     @VMSLIGHTTPD$ROOT:[COM]PHP_POOL STATUS 'vmslighttpd_php_count' 'vmslighttpd_php_base' -
        'phpdir' 'vmslighttpd_php_root'
$ tail_file = logs + "error.log"
$ gosub tail
$! not running: why it stopped or failed to start (configuration errors come
$! before lighttpd opens its error log, so they are only in SERVER.LOG)
$ if pid .eqs. ""
$ then
$   tail_file = logs + "SERVER.LOG"
$   gosub tail
$ endif
$ exit 1
$!
$rotate:
$ gosub find_server
$ if pid .eqs. ""
$ then
$   say "VMSLIGHTTPD: server not running"
$   exit 1
$ endif
$! a new, empty version of each log, owned by the service account; on SIGHUP
$! lighttpd reopens its logs by name and so writes to the new versions
$ uic = f$identifier(vmslighttpd_account, "NAME_TO_NUMBER")
$ uicstr = f$fao("[!OW,!OW]", uic / 65536, uic - (uic / 65536) * 65536)
$ i = 0
$rot_loop:
$ f = f$element(i, ",", "error.log,access.log")
$ if f .eqs. "," then goto rot_signal
$ i = i + 1
$ if f$search(logs + f) .eqs. "" then goto rot_loop
$ create/fdl='logs'STMLF.FDL 'logs''f'
$ set file/owner='uicstr' 'logs''f';0
$ goto rot_loop
$rot_signal:
$ define/user sys$error sys$output
$ signal 'pid' "HUP"
$ keep = 7
$ if f$type(vmslighttpd_keep_logs) .nes. "" then keep = f$integer(vmslighttpd_keep_logs)
$ purge/nolog/keep='keep' 'logs'error.log,access.log
$ say "VMSLIGHTTPD: logs rotated (keeping ", keep, " versions)"
$ exit 1
$!
$! the last 5 lines of tail_file: read here, as TYPE/TAIL does not support
$! Stream_LF files (%TYPE-W-OPENIN, RMS-F-ORG); long lines are cut, as DCL
$! cannot write a string over 255 characters (%DCL-W-TKNOVF); SERVER.LOG stops
$! before LOGINOUT's "job terminated" and accounting lines
$tail:
$ if f$search(tail_file) .eqs. "" then return
$ say "--- last lines of ", tail_file
$ open/read/share=write tfile 'tail_file'
$ n = 0
$tail_read:
$ read/end=tail_show tfile line
$ if f$locate("job terminated at", line) .lt. f$length(line) then goto tail_show
$ if f$length(line) .gt. 250 then line = f$extract(0, 247, line) + "..."
$ tail_'f$string(n - (n / 5) * 5)' = line
$ n = n + 1
$ goto tail_read
$tail_show:
$ close tfile
$ k = n - 5
$ if k .lt. 0 then k = 0
$tail_loop:
$ if k .ge. n then return
$ say tail_'f$string(k - (k / 5) * 5)'
$ k = k + 1
$ goto tail_loop
$!
$! pid of the process named VMSLIGHTTPD (any user), or ""
$find_server:
$ ctx = ""
$ x = f$context("PROCESS", ctx, "PRCNAM", "VMSLIGHTTPD", "EQL")
$ pid = f$pid(ctx)
$ if pid .nes. "" then x = f$context("PROCESS", ctx, "CANCEL")
$ return
