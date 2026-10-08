$! VMS_INSTALLCHECK.COM - install the kit, configure, start, check, stop
$! (batch job, run by tools/installcheck.sh; CHANGES THE SYSTEM)
$! P1: kit directory (where the .PCSI is)    P2: account UIC, e.g. [361,1]
$! P3: data directory                        P4: port (e.g. 981)
$! P5: CLEANUP = remove product, account and data afterwards
$ set noon
$ set process/parse_style=extended
$ set process/privileges=all
$ say = "write sys$output"
$ say "IC: ", f$time(), " on ", f$getsyi("NODENAME"), " ", f$getsyi("ARCH_NAME")
$ say "IC: === PRODUCT INSTALL"
$ product install LIGHTTPD /source='p1' /options=noconfirm /log
$ say "IC: install status ", $status
$ product show product LIGHTTPD
$ say "IC: root ", f$trnlnm("VMSLIGHTTPD$ROOT")
$ install list VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE /full
$ say "IC: === CONFIGURE"
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONFIGURE LIGHTTPD "''p2'" "''p3'" "''p4'" NO YES PHP_ROOT
$ say "IC: configure status ", $status
$ type SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ mcr authorize show LIGHTTPD /brief
$! a PHP page in the document root
$ @SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ htdocs = vmslighttpd_data - "]" + ".HTDOCS]"
$ open/write p 'htdocs'IC.TMP
$ write p "<?php echo 'php ', PHP_VERSION, ' as ', get_current_user(), ' sapi ', php_sapi_name(), PHP_EOL;"
$ close p
$ fdl = vmslighttpd_data - "]" + ".LOGS]STMLF.FDL"
$ convert/fdl='fdl' 'htdocs'IC.TMP 'htdocs'ic.php
$ delete/nolog 'htdocs'IC.TMP;*
$ say "IC: === START"
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL START
$ n = 0
$wait_start:
$ wait 00:00:05
$ n = n + 1
$ ctx = ""
$ x = f$context("PROCESS", ctx, "PRCNAM", "VMSLIGHTTPD", "EQL")
$ pid = f$pid(ctx)
$ if pid .nes. "" then x = f$context("PROCESS", ctx, "CANCEL")
$ if pid .eqs. "" .and. n .lt. 12 then goto wait_start
$ wait 00:00:05
$ say "IC: === STATUS"
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL STATUS
$ say "IC-READY"
$! the host now runs its HTTP checks; it creates IC.GO when done
$ n = 0
$wait_host:
$ if f$search(f$parse(p1,,,"DEVICE") + f$parse(p1,,,"DIRECTORY") + "IC.GO") .nes. "" then goto host_done
$ n = n + 1
$ if n .gt. 120 then goto host_done
$ wait 00:00:05
$ goto wait_host
$host_done:
$ say "IC: === ROTATE"
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL ROTATE
$ logs = vmslighttpd_data - "]" + ".LOGS]"
$ dir 'logs'*.log;*
$ say "IC: === STOP"
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL STOP
$ type/tail=8 'logs'error.log
$ type 'logs'SERVER.LOG
$ if f$edit(p5, "UPCASE") .eqs. "CLEANUP"
$ then
$   say "IC: === CLEANUP"
$   product remove LIGHTTPD /options=noconfirm /log
$   saved = f$environment("DEFAULT")
$   set default sys$system
$   mcr authorize remove LIGHTTPD
$   set default 'saved'
$   delete/nolog SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM;*
$   top = vmslighttpd_data - "]"
$   set security/protection=(o:rwed) 'top'...]*.*;*
$   delete/nolog 'top'...]*.*;*
$   delete/nolog 'top'...]*.*;*
$   delete/nolog 'top'...]*.*;*
$   say "IC: removed product, account LIGHTTPD and ", vmslighttpd_data
$ endif
$ say "IC-DONE"
