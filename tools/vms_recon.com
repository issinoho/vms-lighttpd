$! VMS_RECON.COM - Phase 0 reconnaissance for the lighttpd port (read-only).
$! Run through tools/recon.sh; the output becomes docs/env-<node>.txt.
$ set noon
$ say = "write sys$output"
$ sect: subroutine
$   say ""
$   say "=== ''p1'"
$ endsubroutine
$ call sect "system"
$ say "version   ", f$getsyi("version")
$ say "arch      ", f$getsyi("arch_name")
$ say "hw_name   ", f$getsyi("hw_name")
$ say "node      <redacted>"
$ say "cpus      ", f$getsyi("activecpu_cnt")
$ say "memsize   ", f$getsyi("memsize"), " pages of ", f$getsyi("page_size"), " bytes"
$ say "pgflquota ", f$getjpi("", "pgflquota"), "  wsextent ", f$getjpi("", "wsextent")
$ say "bytlm     ", f$getjpi("", "bytlm"), "  fillm ", f$getjpi("", "fillm"), -
      "  prclm ", f$getjpi("", "prclm"), "  tqlm ", f$getjpi("", "tqlm"), -
      "  biolm ", f$getjpi("", "biolm"), "  diolm ", f$getjpi("", "diolm")
$ say "maxprocesscnt ", f$getsyi("maxprocesscnt"), "  channelcnt ", f$getsyi("channelcnt")
$ say "workdir disk ", f$getdvi("sys$disk", "acpptype"), "  ods ", f$getdvi("sys$disk", "odstructure")
$ say "free blocks ", f$getdvi("sys$disk", "freeblocks"), " of ", f$getdvi("sys$disk", "maxblock")
$ call sect "products (web, php, ssl, compilers)"
$ product show product *php*,*ssl*,*apache*,*csws*,*civetweb*,*wasd*,*tcpip*,*c,*cxx,*mms,*gnv,*perl*
$ call sect "cc/version"
$ cc/version
$ call sect "TCP/IP"
$ tcpip show version
$ say "IPv6: ", f$trnlnm("tcpip$ipv6_enabled")
$ tcpip show services
$ call sect "listeners on 80/443/8080/8443 and our test range 18080-18099, 19000-19031"
$ pipe tcpip netstat -an | search sys$pipe ".80 ",".443 ",".8080 ",".8443 ",".180",".190" /match=or
$ call sect "web servers already running"
$ show system/process=*APACHE*
$ show system/process=*HTTP*
$ show system/process=*WASD*
$ show system/process=*CIVET*
$ call sect "PHP kit"
$ show logical php$*
$ dir/size/date/nohead/notrail php$root:[bin]
$ dir/nohead/notrail php$root:[000000]
$ dir/nohead/notrail php$root:[extensions], php$root:[lib...]*.exe
$ dir/nohead/notrail php$root:[etc]
$ php = "$php$root:[bin]php.exe"
$ say "--- php -v"
$ php -v
$ say "--- php -m"
$ php -m
$ say "--- php --ini"
$ php --ini
$ say "--- php -i (selected)"
$ pipe php -i | search sys$pipe "Server API","extension_dir","Loaded Configuration","opcache.enable","mysqli","pdo_mysql","sqlite","session.save_path","upload_tmp_dir","sys_temp_dir" /match=or
$ say "--- php-cgi candidates"
$ dir/size/date/nohead/notrail php$root:[000000...]*cgi*.exe, php$root:[000000...]*fpm*.exe
$ dir/nohead/notrail php$root:[csws]
$ call sect "SSL3 kit"
$ show logical ssl3$*
$ dir/nohead/notrail sys$share:ssl3$*.exe
$ define/user sys$error nla0:
$ openssl3 = "$ssl3$exe:openssl.exe"
$ openssl3 version -a
$ call sect "zlib / pcre2 install trees in the work directory"
$ dir/nohead/notrail [...]*ZLIB*INSTALL*.DIR, [...]*PCRE2*INSTALL*.DIR
$ call sect "MariaDB (our vms-mariadb server, port 3307)"
$ show system/process=*MARIA*
$ pipe tcpip netstat -an | search sys$pipe ".3307 "
$ call sect "decc$ logicals"
$ show logical decc$*
$ call sect "batch queues"
$ show queue/batch/all
$ say "RECON-DONE"
