$! PHP_POOL.COM - a pool of persistent PHP FastCGI processes for lighttpd.
$!
$! Usage:  @PHP_POOL START|STOP|STATUS [count] [base-port] [pool-dir] [php-root] [max-req]
$!   count      number of processes (default 4)
$!   base-port  first TCP port; process n listens on 127.0.0.1:base-port+n
$!              (default 19000)
$!   pool-dir   directory holding the pool's PHP.INI (default: this
$!              procedure's directory); [.LOGS], [.SESSIONS] and [.TMP] are
$!              created under it
$!   php-root   rooted logical name of the PHP install (default PHP_ROOT:
$!              the PHP 8.1 kit with mysqli built in; docs/DECISIONS.md D4)
$!   max-req    PHP_FCGI_MAX_REQUESTS (default 0 = no limit).  PHP exits after
$!              that many requests and the loop restarts it, but requests
$!              already queued on its socket are lost (lighttpd answers 500:
$!              "response not received, but request sent"), so recycling is
$!              off unless asked for.
$!
$! Each process is detached, named LTPHP_<port>, and runs
$!   <php-root>:[BIN]PHP_CGI.EXE -c <pool-dir>PHP.INI -b 127.0.0.1:<port>
$! ([CSWS]PHP-CGI.EXE for VSI's PHP 8.0 kit)
$! in a DCL loop that starts PHP again if it exits.  PHP_FCGI_CHILDREN is 0,
$! so PHP never forks.  lighttpd's fastcgi.server lists the same host:port pairs.
$! STOP writes [.LOGS]POOL.STOP so the loops end, then stops the processes.
$!
$ set noon
$ say = "write sys$output"
$ op = f$edit(p1, "UPCASE,TRIM")
$ count = 4
$ if p2 .nes. "" then count = f$integer(p2)
$ base = 19000
$ if p3 .nes. "" then base = f$integer(p3)
$ pool = p4
$ if pool .eqs. "" then pool = f$parse(f$environment("PROCEDURE"),,,"DEVICE") + -
                                f$parse(f$environment("PROCEDURE"),,,"DIRECTORY")
$ pool = f$parse(pool,,,"DEVICE","NO_CONCEAL") + f$parse(pool,,,"DIRECTORY","NO_CONCEAL")
$ i = f$locate("][", pool)
$ if i .lt. f$length(pool) then pool = f$extract(0, i - 1, pool) + "." + f$extract(i + 2, 999, pool)
$ root = f$edit(p5, "UPCASE,TRIM")
$ if root .eqs. "" then root = "PHP_ROOT"
$ maxreq = 0
$ if p6 .nes. "" then maxreq = f$integer(p6)
$ pooldir = pool - "]"
$ logs = pooldir + ".LOGS]"
$ stopfile = logs + "POOL.STOP"
$ if op .eqs. "START" then goto start
$ if op .eqs. "STOP" then goto stop
$ if op .eqs. "STATUS" then goto status
$ say "usage: @PHP_POOL START|STOP|STATUS [count] [base-port] [pool-dir] [php-root] [max-req]"
$ exit 44
$!
$start:
$ if f$trnlnm(root) .eqs. ""
$ then
$   say "PHP_POOL: ", root, " is not defined"
$   exit 44
$ endif
$! the CGI/FastCGI image: [BIN]PHP_CGI.EXE (PHP 8.1 kit), or
$! [CSWS]PHP-CGI.EXE (VSI's PHP 8.0 kit)
$ cgiexe = root + ":[BIN]PHP_CGI.EXE"
$ if f$search(cgiexe) .eqs. "" then cgiexe = root + ":[CSWS]PHP-CGI.EXE"
$ if f$search(cgiexe) .eqs. ""
$ then
$   say "PHP_POOL: no ", root, ":[BIN]PHP_CGI.EXE or ", root, ":[CSWS]PHP-CGI.EXE"
$   exit 44
$ endif
$ if f$search(pool + "PHP.INI") .eqs. ""
$ then
$   say "PHP_POOL: no ", pool, "PHP.INI"
$   exit 44
$ endif
$ if f$search(pooldir + "]LOGS.DIR") .eqs. "" then create/directory 'logs'
$ if f$search(pooldir + "]SESSIONS.DIR") .eqs. "" then create/directory 'pooldir'.SESSIONS]
$ if f$search(pooldir + "]TMP.DIR") .eqs. "" then create/directory 'pooldir'.TMP]
$ if f$search(stopfile) .nes. "" then delete/nolog 'stopfile';*
$ gosub unixpath
$ n = 0
$start_loop:
$ if n .ge. count then goto start_done
$ port = base + n
$ n = n + 1
$ name = "LTPHP_" + f$string(port)
$ gosub find_pid
$ if pid .nes. ""
$ then
$   say "PHP_POOL: ", name, " already running"
$   goto start_loop
$ endif
$ com = logs + name + ".COM"
$ open/write w 'com'
$ write w "$ set noon"
$ write w "$ set process/parse_style=extended"
$ write w "$ define/process PHP_FCGI_CHILDREN ""0"""
$ write w "$ define/process PHP_FCGI_MAX_REQUESTS """, maxreq, """"
$ write w "$ define/process TMPDIR """, upool, "/tmp"""
$ write w "$ cgi = ""$", cgiexe, """"
$ write w "$loop:"
$ write w "$ if f$search(""", stopfile, """) .nes. """" then exit"
$ write w "$ write sys$output """, name, " start "", f$time()"
$ write w "$ cgi ""-c"" """, upool, "/php.ini"" ""-b"" ""127.0.0.1:", port, """"
$ write w "$ write sys$output """, name, " exit "", $status, "" "", f$time()"
$ write w "$ if f$search(""", stopfile, """) .nes. """" then exit"
$ write w "$ wait 00:00:01"
$ write w "$ goto loop"
$ close w
$ run/detached sys$system:loginout.exe /input='com' -
      /output='logs''name'.LOG /error='logs''name'.LOG -
      /process_name='name' -
      /buffer_limit=200000 /file_limit=200 /io_buffered=200 /io_direct=200 -
      /queue_limit=64 /enqueue_limit=4000 /ast_limit=300 /subprocess_limit=4 -
      /page_file=2000000 /working_set=8192 /maximum_working_set=32768 /extent=131072
$ say "PHP_POOL: started ", name, " on 127.0.0.1:", port
$ goto start_loop
$start_done:
$ exit 1
$!
$stop:
$ if f$search(pooldir + "]LOGS.DIR") .eqs. "" then create/directory 'logs'
$ open/write s 'stopfile'
$ close s
$ n = 0
$stop_loop:
$ if n .ge. count then goto stop_done
$ port = base + n
$ n = n + 1
$ name = "LTPHP_" + f$string(port)
$ gosub find_pid
$ if pid .eqs. ""
$ then
$   say "PHP_POOL: ", name, " not running"
$ else
$   stop/id='pid'
$   say "PHP_POOL: stopped ", name, " (", pid, ")"
$ endif
$ goto stop_loop
$stop_done:
$ delete/nolog 'stopfile';*
$ exit 1
$!
$status:
$ n = 0
$status_loop:
$ if n .ge. count then exit 1
$ port = base + n
$ n = n + 1
$ name = "LTPHP_" + f$string(port)
$ gosub find_pid
$ if pid .eqs. ""
$ then
$   say "PHP_POOL: ", name, " not running"
$ else
$   say "PHP_POOL: ", name, " pid ", pid, " cpu ", f$getjpi(pid, "CPUTIM"), -
        " pagefile ", f$getjpi(pid, "PAGFILCNT"), " state ", f$getjpi(pid, "STATE")
$ endif
$ goto status_loop
$!
$! pid: the PID of the process called <name> (ours), or ""
$find_pid:
$ ctx = ""
$ x = f$context("PROCESS", ctx, "PRCNAM", name, "EQL")
$ pid = f$pid(ctx)
$ if pid .nes. "" then x = f$context("PROCESS", ctx, "CANCEL")
$ return
$!
$! upool: the pool directory in UNIX form (for PHP's -c and TMPDIR)
$unixpath:
$ udev = f$parse(pool,,,"DEVICE","NO_CONCEAL") - ":"
$ udir = f$parse(pool,,,"DIRECTORY","NO_CONCEAL")
$ i = f$locate("][", udir)
$ if i .lt. f$length(udir) then udir = f$extract(0, i - 1, udir) + "." + f$extract(i + 2, 999, udir)
$ udir = f$extract(1, f$length(udir) - 2, udir) - "000000."
$ upool = "/" + udev + "/" + udir
$up_loop:
$ i = f$locate(".", upool)
$ if i .lt. f$length(upool)
$ then
$   upool = f$extract(0, i, upool) + "/" + f$extract(i + 1, 999, upool)
$   goto up_loop
$ endif
$ return
