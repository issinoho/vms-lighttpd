$! MAKE_KIT.COM - build the PCSI kit for this node's architecture
$!
$! Usage:  @[.VMSPORT.KIT]MAKE_KIT
$! Needs a built tree (@[.VMSPORT]BUILD): [.VMS_<arch>]LIGHTTPD.EXE and
$! LIGHTTPD_SIGNAL.EXE.  Writes the kit to [.KIT_<arch>].  The product
$! description, text module, configuration templates and documentation were
$! put in [.VMSPORT.KIT] by tools/prepare.sh.
$!
$ set noon
$ set process/parse_style=extended
$ status = 44
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ kitdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'kitdir'
$ set default [--]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$!
$! KIT_PRODUCER, KIT_PRODUCT, PCSI_VERSION, KIT_VERSION from kit.env
$ open/read env [.VMSPORT.KIT]KIT.ENV
$env_loop:
$ read/end=env_done env line
$ name = f$element(0, "=", line)
$ 'name' = f$element(1, "=", line)
$ goto env_loop
$env_done:
$ close env
$!
$ bin = "[.VMS_''arch']"
$ if f$search(bin + "LIGHTTPD.EXE") .eqs. "" .or. f$search(bin + "LIGHTTPD_SIGNAL.EXE") .eqs. ""
$ then
$   write sys$error "MAKE_KIT: no ''bin'LIGHTTPD.EXE or LIGHTTPD_SIGNAL.EXE; build first"
$   goto done
$ endif
$!
$! Gather the files flat in [.KIT_<arch>.MAT]: PRODUCT PACKAGE looks each one
$! up by name in the material directory (destinations are in the PDF).
$ mat = "[.KIT_''arch'.MAT]"
$ out = "[.KIT_''arch']"
$ if f$search("KIT_''arch'.DIR") .eqs. "" then create/directory 'out'
$ if f$search("[.KIT_''arch']MAT.DIR") .eqs. "" then create/directory 'mat'
$ if f$search("''out'*.PCSI;*") .nes. "" then delete/nolog 'out'*.PCSI;*
$ if f$search("''mat'*.*;*") .nes. "" then delete/nolog 'mat'*.*;*
$ copy/nolog 'bin'LIGHTTPD.EXE,LIGHTTPD_SIGNAL.EXE 'mat'
$ copy/nolog [.VMSPORT.KIT]VMSLIGHTTPD$*.COM,PHP_POOL.COM 'mat'
$ copy/nolog [.VMSPORT.KIT]LIGHTTPD.CONF,MIME.CONF,PHPBB.CONF,PHP.INI,PHP-VSI80.INI 'mat'
$ copy/nolog [.VMSPORT.KIT]README.VMS,COPYING.,NEWS. 'mat'
$ matspec = f$parse(mat,,,"DEVICE","NO_CONCEAL") + f$parse(mat,,,"DIRECTORY","NO_CONCEAL")
$!
$ write sys$output "MAKE_KIT: ''KIT_PRODUCER' ''base' ''KIT_PRODUCT' ''PCSI_VERSION' (lighttpd ''KIT_VERSION')"
$ product package 'KIT_PRODUCT' -
    /producer='KIT_PRODUCER' /base_system='base' /version='PCSI_VERSION' -
    /source=[.VMSPORT.KIT]PRODUCT-'base'.PCSI$DESC -
    /material='matspec' -
    /destination='out' -
    /format=sequential -
    /options=noconfirm /log
$ status = $status
$ kit = f$search("''out'*.PCSI")
$ if kit .nes. "" then write sys$output "MAKE_KIT: kit ", kit
$ if kit .eqs. "" then status = 44
$done:
$ set default 'saved_default'
$ exit status
