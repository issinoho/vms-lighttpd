$! VMSLIGHTTPD$CONFIGURE.COM - set up the lighttpd service (run once, as SYSTEM)
$!
$! Usage:  @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONFIGURE [account] [uic] [data-dir]
$!                                                     [port] [autostart] [php] [php-root]
$!   account    service account (default LIGHTTPD)
$!   uic        its UIC, e.g. [361,1]; needed only if the account is new
$!   data-dir   data directory: CONF, LOGS, HTDOCS, PHP, TMP (default
$!              SYS$SYSDEVICE:[VMSLIGHTTPD_DATA])
$!   port       HTTP port (default 80)
$!   autostart  YES: VMSLIGHTTPD$STARTUP starts the server at boot (default NO)
$!   php        YES: run the PHP FastCGI pool (default YES if php-root is defined)
$!   php-root   rooted logical of the PHP install (default PHP_ROOT)
$! Missing values are asked for when run interactively.
$!
$! What it does (docs/DECISIONS.md D12):
$!  - the account: batch access only, privileges TMPMBX,NETMBX, quotas for a
$!    network server (FILLM below SYSGEN CHANNELCNT; BYTLM ~3.5 KB per socket).
$!    An existing account keeps its password and UIC; its quotas are updated.
$!  - the data directory tree, owned by the account
$!  - CONF: LIGHTTPD.CONF, MIME.CONF, PHPBB.CONF (existing files are kept)
$!  - PHP:  PHP.INI for the pool (kept if present)
$!  - SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM, the site settings (rewritten)
$!
$ set noon
$ set process/parse_style=extended
$ say = "write sys$output"
$ interactive = f$mode() .eqs. "INTERACTIVE"
$ if f$trnlnm("VMSLIGHTTPD$ROOT") .eqs. ""
$ then
$   say "VMSLIGHTTPD$CONFIGURE: VMSLIGHTTPD$ROOT is not defined (@SYS$STARTUP:VMSLIGHTTPD$STARTUP)"
$   exit 44
$ endif
$ if .not. f$privilege("SYSPRV,CMKRNL")
$ then
$   say "VMSLIGHTTPD$CONFIGURE: needs SYSPRV and CMKRNL (run it as SYSTEM)"
$   exit 36
$ endif
$!
$ call ask account "Service account" "LIGHTTPD" 'p1'
$ call ask datadir "Data directory" "SYS$SYSDEVICE:[VMSLIGHTTPD_DATA]" 'p3'
$ call ask port "HTTP port" "80" 'p4'
$ call ask autostart "Start at boot (YES/NO)" "NO" 'p5'
$ call ask phproot "PHP install (rooted logical)" "PHP_ROOT" 'p7'
$ phpdefault = "NO"
$ if f$trnlnm(phproot) .nes. "" then phpdefault = "YES"
$ call ask php "Run the PHP FastCGI pool (YES/NO)" 'phpdefault' 'p6'
$ account = f$edit(account, "UPCASE")
$ autostart = f$edit(autostart, "UPCASE")
$ php = f$edit(php, "UPCASE")
$!
$! --- the account ------------------------------------------------------------
$ channelcnt = f$getsyi("CHANNELCNT")
$ fillm = channelcnt - 64
$ if fillm .gt. 2000 then fillm = 2000
$ bytlm = fillm * 3500
$ quotas = "/FILLM=''fillm'/BYTLM=''bytlm'/BIOLM=1000/DIOLM=1000/ASTLM=2000/TQELM=200" + -
           "/ENQLM=4000/PRCLM=16/JTQUOTA=4096/PGFLQUOTA=2000000" + -
           "/WSDEFAULT=4096/WSQUOTA=16384/WSEXTENT=65536"
$ access = "/NOINTERACTIVE/NONETWORK/NOLOCAL/NODIALUP/NOREMOTE/BATCH"
$ privs = "/PRIVILEGES=(TMPMBX,NETMBX)/DEFPRIVILEGES=(TMPMBX,NETMBX)"
$ datadev = f$parse(datadir,,,"DEVICE")
$ datadirpart = f$parse(datadir,,,"DIRECTORY")
$ saved = f$environment("DEFAULT")
$ set default SYS$SYSTEM
$ if f$identifier(account, "NAME_TO_NUMBER") .eq. 0
$ then
$   call ask uic "UIC for the new account, e.g. [361,1]" "" 'p2'
$   if uic .eqs. ""
$   then
$     say "VMSLIGHTTPD$CONFIGURE: a UIC is needed for a new account"
$     set default 'saved'
$     exit 44
$   endif
$   password = f$extract(0, 24, f$unique())
$   define/user sys$output nla0:
$   mcr authorize add 'account' /uic='uic' /password='password' /flags=(nodisuser) -
        /device='datadev' /directory='datadirpart' /pwdlifetime=none -
        'access' 'privs' 'quotas' /owner="lighttpd service"
$   if f$identifier(account, "NAME_TO_NUMBER") .eq. 0
$   then
$     say "VMSLIGHTTPD$CONFIGURE: AUTHORIZE ADD ", account, " failed"
$     set default 'saved'
$     exit 44
$   endif
$   say "VMSLIGHTTPD$CONFIGURE: added account ", account, " ", uic
$ else
$   define/user sys$output nla0:
$   mcr authorize modify 'account' 'access' 'privs' 'quotas'
$   say "VMSLIGHTTPD$CONFIGURE: account ", account, " exists; access, privileges and quotas updated"
$ endif
$ set default 'saved'
$ uicnum = f$identifier(account, "NAME_TO_NUMBER")
$ uicstr = f$fao("[!OW,!OW]", uicnum / 65536, uicnum - (uicnum / 65536) * 65536)
$!
$! --- the data tree ------------------------------------------------------------
$ base = f$parse(datadir,,,"DEVICE") + f$parse(datadir,,,"DIRECTORY")
$ top = base - "]"
$ prot = "(S:RWE,O:RWE,G,W)"
$ i = 0
$dir_loop:
$ sub = f$element(i, ",", ",CONF,LOGS,HTDOCS,TMP,PHP,PHP.LOGS,PHP.SESSIONS,PHP.TMP")
$ if sub .eqs. "," then goto dir_done
$ i = i + 1
$ d = top + "]"
$ if sub .nes. "" then d = top + "." + sub + "]"
$ if f$parse(d) .eqs. "" then create/directory/owner='uicstr'/protection='prot' 'd'
$ set directory/owner='uicstr' 'd'
$ goto dir_loop
$dir_done:
$ conf = top + ".CONF]"
$ logsd = top + ".LOGS]"
$ phpd = top + ".PHP]"
$ htdocs = top + ".HTDOCS]"
$!
$! UNIX form of the data directory (rooted [ROOT.][DIR] joined)
$ udev = f$parse(base,,,"DEVICE","NO_CONCEAL") - ":"
$ udir = f$parse(base,,,"DIRECTORY","NO_CONCEAL")
$ j = f$locate(".][", udir)
$ if j .lt. f$length(udir) then udir = f$extract(0, j, udir) + "." + f$extract(j + 3, 999, udir)
$ udir = f$extract(1, f$length(udir) - 2, udir) - "000000."
$ udata = "/" + udev + "/" + udir
$up_loop:
$ j = f$locate(".", udata)
$ if j .lt. f$length(udata)
$ then
$   udata = f$extract(0, j, udata) + "/" + f$extract(j + 1, 999, udata)
$   goto up_loop
$ endif
$!
$! Stream_LF FDL for the files written here and for log rotation
$ open/write fdl 'logsd'STMLF.FDL
$ write fdl "RECORD"
$ write fdl "  FORMAT STREAM_LF"
$ close fdl
$!
$! --- configuration files ----------------------------------------------------
$ count = 4
$ phpbase = 19000
$ if f$search(conf + "LIGHTTPD.CONF") .eqs. ""
$ then
$   call template VMSLIGHTTPD$ROOT:[CONF]LIGHTTPD.CONF 'conf'LIGHTTPD.CONF
$   say "VMSLIGHTTPD$CONFIGURE: wrote ", conf, "LIGHTTPD.CONF"
$ else
$   say "VMSLIGHTTPD$CONFIGURE: kept ", conf, "LIGHTTPD.CONF"
$ endif
$ if f$search(conf + "MIME.CONF") .eqs. "" then convert/fdl='logsd'STMLF.FDL VMSLIGHTTPD$ROOT:[CONF]MIME.CONF 'conf'MIME.CONF
$ if f$search(conf + "PHPBB.CONF") .eqs. "" then convert/fdl='logsd'STMLF.FDL VMSLIGHTTPD$ROOT:[CONF]PHPBB.CONF 'conf'PHPBB.CONF
$ if php .eqs. "YES" .and. f$search(phpd + "PHP.INI") .eqs. ""
$ then
$   ini = "VMSLIGHTTPD$ROOT:[CONF]PHP.INI"
$   if f$search(phproot + ":[BIN]PHP_CGI.EXE") .eqs. "" then ini = "VMSLIGHTTPD$ROOT:[CONF]PHP-VSI80.INI"
$   call template 'ini' 'phpd'PHP.INI
$   say "VMSLIGHTTPD$CONFIGURE: wrote ", phpd, "PHP.INI from ", ini
$ endif
$ if f$search(htdocs + "*.*") .eqs. ""
$ then
$   open/write h 'htdocs'INDEX.TMP
$   write h "<!DOCTYPE html><html><head><title>lighttpd on OpenVMS</title></head>"
$   write h "<body><h1>lighttpd on OpenVMS</h1><p>VMSLIGHTTPD is running. Put your site in ", htdocs, ".</p></body></html>"
$   close h
$   convert/fdl='logsd'STMLF.FDL 'htdocs'INDEX.TMP 'htdocs'index.html
$   delete/nolog 'htdocs'INDEX.TMP;*
$ endif
$ set file/owner='uicstr' 'top'...]*.*;*
$!
$! --- site settings ----------------------------------------------------------
$ node = f$edit(f$getsyi("NODENAME"), "UPCASE")
$ open/write s SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ write s "$! VMSLIGHTTPD$CONFIG.COM - lighttpd site settings, written by VMSLIGHTTPD$CONFIGURE"
$ write s "$! ", f$time(), "; edit to change, then VMSLIGHTTPD$CONTROL RESTART"
$ write s "$ vmslighttpd_account   == """, account, """"
$ write s "$ vmslighttpd_data      == """, base, """"
$ write s "$ vmslighttpd_conf      == """, udata, "/conf/lighttpd.conf"""
$ write s "$ vmslighttpd_autostart == """, autostart, """"
$ write s "$ vmslighttpd_node      == """, node, """   ! start only on this cluster member"
$ write s "$ vmslighttpd_keep_logs == ""7"""
$ write s "$ vmslighttpd_php       == """, php, """"
$ write s "$ vmslighttpd_php_count == """, count, """"
$ write s "$ vmslighttpd_php_base  == """, phpbase, """"
$ write s "$ vmslighttpd_php_root  == """, phproot, """"
$ close s
$ set security/protection=(S:RWED,O:RWED,G:RE,W:RE) SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ say "VMSLIGHTTPD$CONFIGURE: wrote SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM"
$ say ""
$ say "    Start:      @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL START"
$ say "    At boot:    add @SYS$STARTUP:VMSLIGHTTPD$STARTUP to SYS$MANAGER:SYSTARTUP_VMS.COM"
$ say "    At shutdown: add @SYS$STARTUP:VMSLIGHTTPD$SHUTDOWN to SYS$MANAGER:SYSHUTDWN.COM"
$ say "    HTTPS:      put a PEM (certificate, chain, key) in ", conf, "SERVER.PEM, readable"
$ say "                by ", account, " only, and uncomment the $SERVER block in LIGHTTPD.CONF"
$ exit 1
$!
$! ask <symbol> <prompt> <default> [<value given>]
$ask: subroutine
$ v = p4
$ if v .eqs. "" .and. interactive
$ then
$   read/prompt="''p2' [''p3']: " sys$command v
$ endif
$ if v .eqs. "" then v = p3
$ 'p1' == v
$ exit 1
$ endsubroutine
$!
$! template <in> <out>: copy, replacing @DATA@, @PORT@, @POOL@, and a line
$! @FASTCGI@ with the fastcgi.server block for the pool; Stream_LF result
$template: subroutine
$ tmpf = f$parse(p2,,,"DEVICE") + f$parse(p2,,,"DIRECTORY") + "TEMPLATE.TMP"
$ open/read  tin  'p1'
$ open/write tout 'tmpf'
$t_loop:
$ read/end=t_done tin line
$ if f$edit(line, "TRIM") .eqs. "@FASTCGI@"
$ then
$   if php .nes. "YES"
$   then
$     write tout "# (PHP pool not configured: VMSLIGHTTPD$CONFIGURE php=NO)"
$     goto t_loop
$   endif
$   write tout "fastcgi.server = ( "".php"" => ("
$   n = 0
$t_fcgi:
$   sep = ","
$   if n .eq. count - 1 then sep = ""
$   write tout "    ( ""host"" => ""127.0.0.1"", ""port"" => ", phpbase + n, ", ""check-local"" => ""enable"", ""broken-scriptfilename"" => ""enable"" )", sep
$   n = n + 1
$   if n .lt. count then goto t_fcgi
$   write tout "  ) )"
$   goto t_loop
$ endif
$t_sub:
$ k = f$locate("@DATA@", line)
$ if k .lt. f$length(line)
$ then
$   line = f$extract(0, k, line) + udata + f$extract(k + 6, 9999, line)
$   goto t_sub
$ endif
$ k = f$locate("@POOL@", line)
$ if k .lt. f$length(line)
$ then
$   line = f$extract(0, k, line) + udata + "/php" + f$extract(k + 6, 9999, line)
$   goto t_sub
$ endif
$ k = f$locate("@PORT@", line)
$ if k .lt. f$length(line) then line = f$extract(0, k, line) + port + f$extract(k + 6, 9999, line)
$ write tout line
$ goto t_loop
$t_done:
$ close tin
$ close tout
$ convert/fdl='logsd'STMLF.FDL 'tmpf' 'p2'
$ delete/nolog 'tmpf';*
$ exit 1
$ endsubroutine
