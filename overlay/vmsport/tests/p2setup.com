$! P2SETUP.COM - Phase 2 test tree and configuration.
$! Run from the tree's top directory.  Creates [.T2]:
$!   [.T2.HTDOCS]  index.html (stream-LF), plain.txt (stream-LF),
$!                 var.txt (variable records, as DCL CREATE makes),
$!                 [.SUB] with two files (directory listing)
$!   [.T2.LOGS]
$!   LIGHTTPD.CONF HTTP on :18080, HTTPS on :18443 if [.T2]SERVER.PEM exists
$! P1: bind address for the listeners (default 0.0.0.0)
$! Large test files and SERVER.PEM are uploaded into [.T2] by the host.
$ set noon
$! extended parse style keeps the case of the test file names (a.txt, not A.TXT)
$ set process/parse_style=extended
$ say = "write sys$output"
$ bind = p1
$ if bind .eqs. "" then bind = "0.0.0.0"
$ if f$search("T2.DIR") .eqs. "" then create/directory [.T2]
$ if f$search("[.T2]HTDOCS.DIR") .eqs. "" then create/directory [.T2.HTDOCS]
$ if f$search("[.T2.HTDOCS]SUB.DIR") .eqs. "" then create/directory [.T2.HTDOCS.SUB]
$ if f$search("[.T2]LOGS.DIR") .eqs. "" then create/directory [.T2.LOGS]
$ if f$search("[.T2]TMP.DIR") .eqs. "" then create/directory [.T2.TMP]
$ open/write f [.T2]STMLF.FDL
$ write f "RECORD"
$ write f "  FORMAT STREAM_LF"
$ close f
$!
$ call stmlf [.T2.HTDOCS]index.html "<html><body>lighttpd on OpenVMS</body></html>"
$ call stmlf [.T2.HTDOCS]plain.txt "plain stream-LF text"
$ call stmlf [.T2.HTDOCS.SUB]a.txt "file a"
$ call stmlf [.T2.HTDOCS.SUB]b.txt "file b"
$! var.txt: 3 records of 10 bytes; served correctly it is 33 bytes ("0123456789\n" x 3)
$ if f$search("[.T2.HTDOCS]var.txt") .nes. "" then delete/nolog [.T2.HTDOCS]var.txt;*
$ open/write f [.T2.HTDOCS]var.txt
$ write f "0123456789"
$ write f "0123456789"
$ write f "0123456789"
$ close f
$!
$! UNIX form of [.T2]
$ dev = f$parse("[.T2]",,,"DEVICE","NO_CONCEAL") - ":"
$! rooted directories come back as [ROOT.][DIR...]: join first, then drop [ ]
$ dir = f$parse("[.T2]",,,"DIRECTORY","NO_CONCEAL")
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
$!
$ if f$search("[.T2]LIGHTTPD.CONF") .nes. "" then delete/nolog [.T2]LIGHTTPD.CONF;*
$ open/write f [.T2]LIGHTTPD.TMP
$ write f "server.document-root = """, udir, "/htdocs"""
$ write f "server.errorlog      = """, udir, "/logs/error.log"""
$ write f "accesslog.filename   = """, udir, "/logs/access.log"""
$ write f "server.upload-dirs   = ( """, udir, "/tmp"" )"
$ write f "server.port          = 18080"
$ write f "server.bind          = """, bind, """"
$ write f "server.modules       = ( ""mod_access"", ""mod_accesslog"", ""mod_dirlisting"", ""mod_staticfile"", ""mod_openssl"" )"
$ write f "index-file.names     = ( ""index.html"" )"
$ write f "dir-listing.activate = ""enable"""
$ write f "mimetype.assign      = ( "".html"" => ""text/html"", "".txt"" => ""text/plain"", "".bin"" => ""application/octet-stream"" )"
$ if f$search("[.T2]SERVER.PEM") .nes. ""
$ then
$   write f "$SERVER[""socket""] == """, bind, ":18443"" {"
$   write f "  ssl.engine  = ""enable"""
$   write f "  ssl.pemfile = """, udir, "/server.pem"""
$   write f "}"
$!  :18444 also accepts TLS 1.2 (lighttpd's default minimum is TLS 1.3)
$   write f "$SERVER[""socket""] == """, bind, ":18444"" {"
$   write f "  ssl.engine  = ""enable"""
$   write f "  ssl.pemfile = """, udir, "/server.pem"""
$   write f "  ssl.openssl.ssl-conf-cmd = ( ""MinProtocol"" => ""TLSv1.2"" )"
$   write f "}"
$ endif
$ close f
$ convert/fdl=[.T2]STMLF.FDL [.T2]LIGHTTPD.TMP [.T2]LIGHTTPD.CONF
$ delete/nolog [.T2]LIGHTTPD.TMP;*
$ say "P2SETUP: tree ", udir
$ type [.T2]LIGHTTPD.CONF
$ say "P2SETUP-DONE"
$ exit 1
$!
$stmlf: subroutine
$ if f$search(p1) .nes. "" then delete/nolog 'p1';*
$ open/write t P2SETUP.TMP
$ write t p2
$ close t
$ convert/fdl=[.T2]STMLF.FDL P2SETUP.TMP 'p1'
$ delete/nolog P2SETUP.TMP;*
$ exit 1
$ endsubroutine
