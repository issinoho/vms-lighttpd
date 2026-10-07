$! VMS_PROBE.COM - compile, link and run the Phase 0 probes in this directory
$! with VSI C (both architectures).
$! P1: sets to run, any of H F G R S (default all).
$! H_*.C  header compiles?         F_*.C  CMake-style link test (no header)
$! G_*.C  declared by a header and links?
$! R_*.C  runtime probes, run twice: CRTL defaults, then with the feature
$!        logicals lighttpd would set (process table only).
$! S_*.C  runtime probes linked with VSI SSL3's 32-bit-pointer images.
$ set noon
$ set process/parse_style=extended
$ say = "write sys$output"
$ proc = f$environment("PROCEDURE")
$ set default 'f$parse(proc,,,"DEVICE")''f$parse(proc,,,"DIRECTORY")'
$ ccmd = "cc/names=(as_is,shortened)/float=ieee/define=(_LARGEFILE,_USE_STD_STAT,_POSIX_EXIT)/nolist/object=probe_tmp.obj"
$ say "PROBE compiler: ", ccmd
$ cc/version
$ sets = f$edit(p1, "UPCASE")
$ if sets .eqs. "" then sets = "HFGRS"
$ if f$locate("H", sets) .lt. f$length(sets) then gosub compile_set_h
$ if f$locate("F", sets) .lt. f$length(sets) then gosub compile_set_f
$ if f$locate("G", sets) .lt. f$length(sets) then gosub compile_set_g
$ if f$locate("R", sets) .lt. f$length(sets) then gosub runtime
$ if f$locate("S", sets) .lt. f$length(sets) then gosub ssl
$ if f$search("probe_tmp.*") .nes. "" then delete/nolog probe_tmp.*;*
$ say "PROBE-DONE"
$ exit
$!
$compile_set_h:
$ pat = "H_*.C"
$ goto compile_set
$compile_set_f:
$ pat = "F_*.C"
$ goto compile_set
$compile_set_g:
$ pat = "G_*.C"
$compile_set:
$ f = f$search(pat, 1)
$ if f .eqs. "" then return
$ n = f$edit(f$parse(f,,,"NAME"), "LOWERCASE")
$ if f$search("probe_tmp.obj") .nes. "" then delete/nolog probe_tmp.obj;*
$ define/user sys$output probe_cc.lis
$ define/user sys$error probe_cc.lis
$ 'ccmd' 'n'.c
$ csev = $severity
$ lsev = "-"
$ if csev .ne. 2 .and. csev .ne. 4 .and. f$extract(0,2,n) .nes. "h_"
$ then
$   define/user sys$output probe_ln.lis
$   define/user sys$error probe_ln.lis
$   link/exe=probe_tmp.exe probe_tmp.obj
$   lsev = $severity
$ endif
$ msg = ""
$ open/read/error=nomsg in probe_cc.lis
$msgloop:
$ read/end=msgend in line
$ if f$extract(0,1,line) .nes. "%" .or. f$length(msg) .ge. 200 then goto msgloop
$ msg = msg + " " + f$element(0,",",line)
$ goto msgloop
$msgend:
$ close in
$nomsg:
$ say "RESULT ", n, " cc=", csev, " link=", lsev, msg
$ if f$search("probe_cc.lis") .nes. "" then delete/nolog probe_cc.lis;*
$ if f$search("probe_ln.lis") .nes. "" then delete/nolog probe_ln.lis;*
$ goto compile_set
$!
$runtime:
$ f = f$search("R_*.C", 2)
$ if f .eqs. "" then return
$ n = f$edit(f$parse(f,,,"NAME"), "LOWERCASE")
$ if f$search("probe_tmp.obj") .nes. "" then delete/nolog probe_tmp.obj;*
$ if f$search("''n'.exe") .nes. "" then delete/nolog 'n'.exe;*
$ define/user sys$error sys$output
$ 'ccmd' 'n'.c
$ if f$search("probe_tmp.obj") .eqs. ""
$ then
$   say "--- ", n, " did not compile"
$   goto runtime
$ endif
$ link/exe='n'.exe probe_tmp.obj
$ say "--- ", n, " (CRTL defaults)"
$ define/user sys$error sys$output
$ mcr sys$disk:[]'n'.exe
$ say "--- ", n, " (feature logicals)"
$ gosub features_on
$ define/user sys$error sys$output
$ mcr sys$disk:[]'n'.exe
$ gosub features_off
$ goto runtime
$!
$ssl:
$ if f$trnlnm("SSL3$INCLUDE") .eqs. ""
$ then
$   say "--- SSL3 kit not installed (no SSL3$INCLUDE)"
$   return
$ endif
$ define/process OPENSSL SSL3$INCLUDE:
$ open/write opt ssl3_probe.opt
$ write opt "sys$share:ssl3$libssl_shr32/share"
$ write opt "sys$share:ssl3$libcrypto_shr32/share"
$ close opt
$ssl_loop:
$ f = f$search("S_*.C", 3)
$ if f .eqs. ""
$ then
$   deassign/process OPENSSL
$   delete/nolog ssl3_probe.opt;*
$   return
$ endif
$ n = f$edit(f$parse(f,,,"NAME"), "LOWERCASE")
$ if f$search("probe_tmp.obj") .nes. "" then delete/nolog probe_tmp.obj;*
$ define/user sys$error sys$output
$ 'ccmd' 'n'.c
$ if f$search("probe_tmp.obj") .eqs. ""
$ then
$   say "--- ", n, " did not compile"
$   goto ssl_loop
$ endif
$ define/user sys$error sys$output
$ link/exe='n'.exe probe_tmp.obj, ssl3_probe.opt/options
$ say "--- ", n
$ define/user sys$error sys$output
$ mcr sys$disk:[]'n'.exe
$ goto ssl_loop
$!
$features_on:
$ define/process decc$efs_charset enable
$ define/process decc$efs_case_preserve enable
$ define/process decc$filename_unix_report enable
$ define/process decc$filename_unix_no_version enable
$ define/process decc$readdir_dropdotnotype enable
$ define/process decc$file_sharing enable
$ define/process decc$posix_seek_stream_file enable
$ define/process decc$argv_parse_style enable
$ return
$features_off:
$ deassign/process decc$efs_charset
$ deassign/process decc$efs_case_preserve
$ deassign/process decc$filename_unix_report
$ deassign/process decc$filename_unix_no_version
$ deassign/process decc$readdir_dropdotnotype
$ deassign/process decc$file_sharing
$ deassign/process decc$posix_seek_stream_file
$ deassign/process decc$argv_parse_style
$ return
