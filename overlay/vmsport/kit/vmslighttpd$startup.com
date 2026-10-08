$! VMSLIGHTTPD$STARTUP.COM - lighttpd for OpenVMS at system startup
$!
$! Usage (as SYSTEM):
$!   @SYS$STARTUP:VMSLIGHTTPD$STARTUP            from SYSTARTUP_VMS.COM: define
$!                                               VMSLIGHTTPD$ROOT, install the
$!                                               image, start the server if
$!                                               SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$!                                               says AUTOSTART for this node
$!   @SYS$STARTUP:VMSLIGHTTPD$STARTUP INSTALL    define and install only (PCSI)
$!   @SYS$STARTUP:VMSLIGHTTPD$STARTUP REMOVE     stop, remove the image, deassign
$!
$! LIGHTTPD.EXE is installed /PRIVILEGED=OPER so it can bind ports below 1024;
$! it drops every privilege but TMPMBX,NETMBX once its listeners are bound.
$!
$ set noon
$ say = "write sys$output"
$ op = f$edit(p1, "UPCASE,TRIM")
$ if op .eqs. "REMOVE" then goto remove
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[VMSLIGHTTPD] (as vms-curl's VMSCURL$STARTUP):
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.VMSLIGHTTPD.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "VMSLIGHTTPD.]"
$ if root .eqs. dir + "VMSLIGHTTPD.]"
$ then
$   write sys$error "VMSLIGHTTPD$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = dev + (root - ".000000")
$ define/system/executive_mode/translation_attributes=concealed VMSLIGHTTPD$ROOT 'root'
$ if f$search("VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE") .eqs. ""
$ then
$   say "VMSLIGHTTPD$STARTUP: no VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE (root ", root, ")"
$   exit 44
$ endif
$! the DCL INSTALL verb (through a "$SYS$SYSTEM:INSTALL" symbol the file spec
$! was mis-parsed: %CLI-W-MAXPARM, and the image was not installed)
$ define/user sys$output nla0:
$ define/user sys$error nla0:
$ install list VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE
$ if $status
$ then
$   install replace VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE /open/header_resident/shared/privileged=(oper)
$ else
$   install add VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE /open/header_resident/shared/privileged=(oper)
$ endif
$ install list VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE
$ if .not. $status then write sys$error "VMSLIGHTTPD$STARTUP: LIGHTTPD.EXE is not installed"
$ if op .eqs. "INSTALL" then exit 1
$!
$! boot: start if the site settings ask for it on this node
$ if f$search("SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM") .eqs. "" then exit 1
$ @SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ node = f$edit(f$getsyi("NODENAME"), "UPCASE")
$ if f$edit(vmslighttpd_autostart, "UPCASE") .nes. "YES" then exit 1
$ if vmslighttpd_node .nes. "" .and. f$edit(vmslighttpd_node, "UPCASE") .nes. node then exit 1
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL START
$ exit 1
$!
$remove:
$ if f$trnlnm("VMSLIGHTTPD$ROOT") .nes. ""
$ then
$   if f$search("VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL.COM") .nes. "" then -
       @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL STOP
$   define/user sys$output nla0:
$   define/user sys$error nla0:
$   install remove VMSLIGHTTPD$ROOT:[BIN]LIGHTTPD.EXE
$   deassign/system/executive_mode VMSLIGHTTPD$ROOT
$ endif
$ exit 1
