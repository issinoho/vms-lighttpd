$! P4SETUP.COM - Phase 4 configuration: lighttpd serving phpBB from the work
$! directory's [.PHPBB], PHP from the Phase 3 pool ([.T3POOL], 19000-19003).
$! Run from the tree's top directory; writes [.T4]LIGHTTPD.CONF and copies
$! [.VMSPORT.CONF]PHPBB.CONF beside it.  HTTP :18080, HTTPS :18443 with the
$! Phase 2 certificate ([.T2]SERVER.PEM).
$! P1: bind address (default 0.0.0.0)
$ set noon
$ set process/parse_style=extended
$ say = "write sys$output"
$ bind = p1
$ if bind .eqs. "" then bind = "0.0.0.0"
$ if f$search("T4.DIR") .eqs. "" then create/directory [.T4]
$ if f$search("[.T4]LOGS.DIR") .eqs. "" then create/directory [.T4.LOGS]
$ if f$search("[.T4]TMP.DIR") .eqs. "" then create/directory [.T4.TMP]
$ if f$search("[-]PHPBB.DIR") .eqs. ""
$ then
$   say "P4SETUP: no [-.PHPBB]"
$   exit 44
$ endif
$! UNIX forms of [.T4], [.T2] and [-.PHPBB]
$ call unix "[.T4]"
$ ut4 = upath
$ call unix "[.T2]"
$ ut2 = upath
$ call unix "[-.PHPBB]"
$ uphpbb = upath
$ copy [.VMSPORT.CONF]PHPBB.CONF [.T4]PHPBB.CONF
$ purge/nolog [.T4]PHPBB.CONF
$ if f$search("[.T4]LIGHTTPD.CONF") .nes. "" then delete/nolog [.T4]LIGHTTPD.CONF;*
$ open/write f [.T4]LIGHTTPD.TMP
$ write f "server.modules = ( ""mod_access"", ""mod_rewrite"", ""mod_accesslog"", ""mod_fastcgi"", ""mod_openssl"" )"
$ write f "server.document-root = """, uphpbb, """"
$ write f "server.errorlog      = """, ut4, "/logs/error.log"""
$ write f "accesslog.filename   = """, ut4, "/logs/access.log"""
$ write f "server.upload-dirs   = ( """, ut4, "/tmp"" )"
$ write f "server.port          = 18080"
$ write f "server.bind          = """, bind, """"
$ write f "mimetype.assign      = ( "".html"" => ""text/html"", "".css"" => ""text/css"", "".js"" => ""text/javascript"","
$ write f "  "".png"" => ""image/png"", "".gif"" => ""image/gif"", "".jpg"" => ""image/jpeg"", "".svg"" => ""image/svg+xml"","
$ write f "  "".ico"" => ""image/x-icon"", "".woff"" => ""font/woff"", "".woff2"" => ""font/woff2"", "".txt"" => ""text/plain"" )"
$ write f "fastcgi.server = ( "".php"" => ("
$ n = 0
$fcgi_loop:
$ sep = ","
$ if n .eq. 3 then sep = ""
$ write f "    ( ""host"" => ""127.0.0.1"", ""port"" => ", 19000 + n, ", ""check-local"" => ""enable"", ""broken-scriptfilename"" => ""enable"" )", sep
$ n = n + 1
$ if n .lt. 4 then goto fcgi_loop
$ write f "  ) )"
$! absolute: lighttpd takes include paths relative to the -f file's directory,
$! which it cannot work out from a VMS file spec such as [.T4]LIGHTTPD.CONF
$! the including config sets these; phpbb.conf relies on it (a key may be
$! assigned only once per scope)
$ write f "index-file.names = ( ""index.php"", ""index.html"" )"
$ write f "static-file.exclude-extensions = ( "".php"", "".inc"" )"
$ write f "include """, ut4, "/phpbb.conf"""
$ write f "$SERVER[""socket""] == """, bind, ":18443"" {"
$ write f "  ssl.engine  = ""enable"""
$ write f "  ssl.pemfile = """, ut2, "/server.pem"""
$ write f "}"
$ close f
$ convert/fdl=[.T2]STMLF.FDL [.T4]LIGHTTPD.TMP [.T4]LIGHTTPD.CONF
$ delete/nolog [.T4]LIGHTTPD.TMP;*
$ say "P4SETUP: phpBB at ", uphpbb
$ say "P4SETUP-DONE"
$ exit 1
$!
$! upath = UNIX form of directory P1 (rooted [ROOT.][DIR] handled)
$unix: subroutine
$ dev = f$parse(p1,,,"DEVICE","NO_CONCEAL") - ":"
$ dir = f$parse(p1,,,"DIRECTORY","NO_CONCEAL")
$ i = f$locate(".][", dir)
$ if i .lt. f$length(dir) then dir = f$extract(0, i, dir) + "." + f$extract(i + 3, 999, dir)
$ dir = f$extract(1, f$length(dir) - 2, dir) - "000000."
$ u = "/" + dev + "/" + dir
$uloop:
$ i = f$locate(".", u)
$ if i .lt. f$length(u)
$ then
$   u = f$extract(0, i, u) + "/" + f$extract(i + 1, 999, u)
$   goto uloop
$ endif
$ upath == u
$ exit 1
$ endsubroutine
