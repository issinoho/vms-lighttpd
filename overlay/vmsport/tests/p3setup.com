$! P3SETUP.COM - Phase 3 test tree: the Phase 2 tree plus PHP over FastCGI.
$! Run from the tree's top directory, after the host has uploaded the PHP
$! test scripts into [.T2.HTDOCS] (stream-LF).
$!   [.T3POOL]PHP.INI   from [.VMSPORT.PHP]PHP.INI with @POOL@ filled in
$!   [.T2]LIGHTTPD.CONF Phase 2 config + mod_fastcgi, 4 backends on P3..P3+3
$! P1: bind address (default 0.0.0.0)
$! P2: PHP root logical name (default PHP_ROOT); its kit decides the template:
$!     [BIN]PHP_CGI.EXE (PHP 8.1 kit) -> PHP.INI, else PHP-VSI80.INI
$! P3: the pool's first port (default 19100; tools/serve.sh POOL_BASE)
$ set noon
$ set process/parse_style=extended
$ say = "write sys$output"
$ base = 19100
$ if p3 .nes. "" then base = f$integer(p3)
$ @[.VMSPORT.TESTS]P2SETUP.COM 'p1'
$ if f$search("T3POOL.DIR") .eqs. "" then create/directory [.T3POOL]
$!
$! UNIX form of [.T3POOL] (rooted directories: [ROOT.][DIR] -> ROOT.DIR)
$ dev = f$parse("[.T3POOL]",,,"DEVICE","NO_CONCEAL") - ":"
$ dir = f$parse("[.T3POOL]",,,"DIRECTORY","NO_CONCEAL")
$ i = f$locate(".][", dir)
$ if i .lt. f$length(dir) then dir = f$extract(0, i, dir) + "." + f$extract(i + 3, 999, dir)
$ dir = f$extract(1, f$length(dir) - 2, dir) - "000000."
$ upool = "/" + dev + "/" + dir
$loop:
$ i = f$locate(".", upool)
$ if i .lt. f$length(upool)
$ then
$   upool = f$extract(0, i, upool) + "/" + f$extract(i + 1, 999, upool)
$   goto loop
$ endif
$!
$! PHP.INI: copy the template, replacing @POOL@
$ if f$search("[.T3POOL]PHP.INI") .nes. "" then delete/nolog [.T3POOL]PHP.INI;*
$ root = p2
$ if root .eqs. "" then root = "PHP_ROOT"
$ template = "[.VMSPORT.PHP]PHP.INI"
$ if f$search(root + ":[BIN]PHP_CGI.EXE") .eqs. "" then template = "[.VMSPORT.PHP]PHP-VSI80.INI"
$ say "P3SETUP: ", root, " -> ", template
$ open/read  in  'template'
$ open/write out [.T3POOL]PHP.TMP
$ini_loop:
$ read/end=ini_done in line
$ i = f$locate("@POOL@", line)
$ if i .lt. f$length(line) then line = f$extract(0, i, line) + upool + f$extract(i + 6, 9999, line)
$ write out line
$ goto ini_loop
$ini_done:
$ close in
$ close out
$ convert/fdl=[.T2]STMLF.FDL [.T3POOL]PHP.TMP [.T3POOL]PHP.INI
$ delete/nolog [.T3POOL]PHP.TMP;*
$!
$! lighttpd: add mod_fastcgi and the four backends
$ open/append f [.T2]LIGHTTPD.CONF
$ write f "server.modules += ( ""mod_fastcgi"" )"
$ write f "index-file.names += ( ""index.php"" )"
$! never serve PHP source if no backend takes a .php request
$ write f "static-file.exclude-extensions = ( "".php"" )"
$ write f "fastcgi.server = ( "".php"" => ("
$ n = 0
$fcgi_loop:
$ sep = ","
$ if n .eq. 3 then sep = ""
$ write f "    ( ""host"" => ""127.0.0.1"", ""port"" => ", base + n, ", ""check-local"" => ""enable"" )", sep
$ n = n + 1
$ if n .lt. 4 then goto fcgi_loop
$ write f "  ) )"
$! reverse proxy: X-Forwarded-For/-Proto from any client (test only; a real
$! configuration trusts the proxy's address alone)
$ write f "server.modules += ( ""mod_extforward"" )"
$ write f "extforward.forwarder = ( ""all"" => ""trust"" )"
$ write f "extforward.headers = ( ""X-Forwarded-For"" )"
$ close f
$ say "P3SETUP: pool ", upool
$ type [.T2]LIGHTTPD.CONF
$ say "P3SETUP-DONE"
$ exit 1
