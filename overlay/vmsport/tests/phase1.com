$! PHASE1.COM - Phase 1 exit check: lighttpd -v, -V and -tt on a minimal
$! configuration, using the image from [-.VMS_<arch>].
$! Writes [.T] (docroot, config) under the tree; nothing is started.
$ set noon
$ say = "write sys$output"
$ proc = f$environment("PROCEDURE")
$ here = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'here'
$ set default [-.-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ exe = f$search("[.VMS_''arch']LIGHTTPD.EXE")
$ if exe .eqs. ""
$ then
$   say "PHASE1: no [.VMS_''arch']LIGHTTPD.EXE"
$   exit 44
$ endif
$ lighttpd = "$" + exe
$ define/user sys$error sys$output
$ lighttpd -v
$ say "PHASE1: -v status ", $status
$ define/user sys$error sys$output
$ lighttpd -V
$ say "PHASE1: -V status ", $status
$!
$! Test tree [.T]: htdocs with a stream-LF index.html, and lighttpd.conf.
$ if f$search("T.DIR") .eqs. "" then create/directory [.T]
$ if f$search("[.T]HTDOCS.DIR") .eqs. "" then create/directory [.T.HTDOCS]
$ if f$search("[.T]LOGS.DIR") .eqs. "" then create/directory [.T.LOGS]
$ open/write f [.T]STMLF.FDL
$ write f "RECORD"
$ write f "  FORMAT STREAM_LF"
$ close f
$ open/write f [.T]INDEX.TMP
$ write f "<html><body>lighttpd on OpenVMS</body></html>"
$ close f
$ convert/fdl=[.T]STMLF.FDL [.T]INDEX.TMP [.T.HTDOCS]index.html
$ delete/nolog [.T]INDEX.TMP;*
$!
$! The UNIX form of [.T], e.g. /DISK$USER/USERNAME/VMS_LIGHTTPD/.../T
$ dev = f$parse("[.T]",,,"DEVICE","NO_CONCEAL") - ":"
$! rooted directories come back as [ROOT.][DIR...]: join first, then drop [ ]
$ dir = f$parse("[.T]",,,"DIRECTORY","NO_CONCEAL")
$ i = f$locate(".][", dir)
$ if i .lt. f$length(dir) then dir = f$extract(0, i, dir) + "." + f$extract(i + 3, 999, dir)
$ dir = f$extract(1, f$length(dir) - 2, dir) - "000000."
$ udir = "/" + dev + "/" + dir
$loop:
$ i = f$locate(".", udir)
$ if i .lt. f$length(udir)
$ then
$   udir = f$extract(0, i, udir) + "/" + f$extract(i + 1, 999, udir)
$   goto loop
$ endif
$ say "PHASE1: test tree ", udir
$ open/write f [.T]LIGHTTPD.CONF
$ write f "server.document-root = """, udir, "/htdocs"""
$ write f "server.errorlog      = """, udir, "/logs/error.log"""
$ write f "server.port          = 18080"
$ write f "server.bind          = ""127.0.0.1"""
$ write f "server.modules       = ( ""mod_access"", ""mod_accesslog"", ""mod_staticfile"" )"
$ write f "index-file.names     = ( ""index.html"" )"
$ write f "mimetype.assign      = ( "".html"" => ""text/html"", "".txt"" => ""text/plain"" )"
$ close f
$ convert/fdl=[.T]STMLF.FDL [.T]LIGHTTPD.CONF [.T]LIGHTTPD.CONF
$ purge/nolog [.T]LIGHTTPD.CONF
$ define/user sys$error sys$output
$ lighttpd -tt -f [.T]LIGHTTPD.CONF
$ say "PHASE1: -tt status ", $status
$ say "PHASE1-DONE"
