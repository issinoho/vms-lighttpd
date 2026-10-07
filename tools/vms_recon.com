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
$ say "--- where is PHP? (startup procedures, PHP.EXE images on the system disk)"
$ dir/nohead/notrail sys$startup:*php*.com
$ dir/nohead/notrail/date sys$sysdevice:[000000...]php*.exe
$ show logical php$*
$ show logical php_*
$ proot = "php$root"
$ if f$trnlnm("php$root") .eqs. "" .and. f$trnlnm("php_root") .nes. "" then proot = "php_root"
$ say "--- using ", proot
$ dir/size/date/nohead/notrail 'proot':[bin]
$ dir/nohead/notrail 'proot':[000000]
$ dir/nohead/notrail 'proot':[extensions], 'proot':[lib...]*.exe
$ dir/nohead/notrail 'proot':[etc]
$ php = "$''proot':[bin]php.exe"
$ say "--- php -v"
$ php -v
$ say "--- php -m"
$ php -m
$ say "--- php --ini"
$ php --ini
$ say "--- php -i (selected)"
$ pipe php -i | search sys$pipe "Server API","extension_dir","Loaded Configuration","opcache.enable","MysqlI Support","PDO drivers","sqlite","session.save_path","upload_tmp_dir","sys_temp_dir" /match=or
$ say "--- php_cgi (FastCGI server mode is -b)"
$ cgi = "$''proot':[bin]php_cgi.exe"
$ define/user sys$error sys$output
$ cgi -v
$ pipe cgi -h | search sys$pipe "-b "
$ say "--- php-cgi candidates"
$ dir/size/date/nohead/notrail 'proot':[000000...]*cgi*.exe, 'proot':[000000...]*fpm*.exe
$ dir/nohead/notrail 'proot':[csws]
$ call sect "SSL3 kit"
$ show logical ssl3$*
$ dir/nohead/notrail sys$share:ssl3$*.exe
$ define/user sys$error nla0:
$ openssl3 = "$ssl3$exe:openssl.exe"
$ openssl3 version -a
$ call sect "zlib / pcre2 install trees in this and the sibling work directories"
$ dir/nohead/notrail [-...]*ZLIB*INSTALL*.DIR, [-...]*PCRE2*INSTALL*.DIR
$ call sect "MariaDB (our vms-mariadb server)"
$ show system/process=*MARIA*
$ pipe tcpip netstat -an | search sys$pipe ".3306 ",".3307 " /match=or
$ call sect "decc$ logicals"
$ show logical decc$*
$ call sect "batch queues"
$ show queue/batch/all
$ say "RECON-DONE"
