$! BUILD.COM - build lighttpd for OpenVMS with VSI C
$!
$! Usage:  @[.VMSPORT]BUILD [ALL|CLEAN|LINK] [KEEP_GOING]
$!
$! Prerequisites (tools/build.sh defines the logical names):
$!   ZLIB$ROOT   rooted logical for a github.com/issinoho/vms-zlib install tree
$!   PCRE2$ROOT  rooted logical for a github.com/issinoho/vms-pcre2 install tree
$!   VSI's SSL3 kit (SSL3$INCLUDE, SYS$SHARE:SSL3$LIBSSL_SHR32, SSL3$LIBCRYPTO_SHR32)
$!
$! There is no configure step: [.SRC]CONFIG.H is kept by hand (docs/DECISIONS.md D3)
$! and the modules in [.SRC]PLUGIN-STATIC.H are linked in (LIGHTTPD_STATIC).
$! A source is compiled when its object is missing or older than the source;
$! headers and qualifiers are not tracked, so use CLEAN after changing either.
$! Output: [.VMS_<arch>]LIGHTTPD.EXE
$!
$ status = 44
$ set noon
$ on control_y then goto done
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ set default 'f$parse(proc,,,"DEVICE")''f$parse(proc,,,"DIRECTORY")'
$ set default [-]
$ top = f$environment("DEFAULT")
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ target = f$edit(p1, "UPCASE")
$ if target .eqs. "" then target = "ALL"
$ keep_going = f$edit(p2, "UPCASE") .eqs. "KEEP_GOING"
$ objdir = "[.VMS_''arch']"
$ write sys$output "BUILD: ''target' for ''arch' in ''top'"
$ if target .eqs. "CLEAN"
$ then
$   if f$search("''objdir'*.*") .nes. "" then delete/nolog 'objdir'*.*;*
$   write sys$output "BUILD: done"
$   status = 1
$   goto done
$ endif
$ if f$trnlnm("SSL3$INCLUDE") .eqs. ""
$ then
$   write sys$error "BUILD: VSI's SSL3 kit (SSL3$INCLUDE) is not installed"
$   goto done
$ endif
$ if f$trnlnm("ZLIB$ROOT") .eqs. "" .or. f$trnlnm("PCRE2$ROOT") .eqs. ""
$ then
$   write sys$error "BUILD: define ZLIB$ROOT and PCRE2$ROOT for the vms-zlib/vms-pcre2 install trees"
$   goto done
$ endif
$ if f$search("VMS_''arch'.DIR") .eqs. "" then create/directory 'objdir'
$ define/process OPENSSL SSL3$INCLUDE:
$ define/process sys$error sys$output
$!
$! _LARGEFILE: 64-bit off_t.  _USE_STD_STAT: POSIX st_ino/st_dev.
$! _POSIX_EXIT: exit() codes are POSIX ones.  _SOCKADDR_LEN: 4.4BSD
$! sockaddr layout, as SSL3 is built (and needed for sockaddr_in6).
$! Include directories in UNIX form, so that "ls-hpack/lshpack.h" and
$! "../compat/sys/queue.h" resolve against them (as in vms-curl).
$ cflags = "/NAMES=(AS_IS,SHORTENED)/FLOAT=IEEE/NOLIST/DEBUG=TRACEBACK" + -
    "/DEFINE=(HAVE_CONFIG_H,LIGHTTPD_STATIC,_LARGEFILE,_USE_STD_STAT,_POSIX_EXIT,_SOCKADDR_LEN)" + -
    "/INCLUDE_DIRECTORY=(""./src"",""./src/ls-hpack"",""./vmsport"",ZLIB$ROOT:[INCLUDE],PCRE2$ROOT:[INCLUDE])"
$!
$! Sources: COMMON_SRC + SERVER_SRC from src/CMakeLists.txt, the parser lemon
$! made (tools/prepare.sh), the modules in plugin-static.h, and ours.
$ common = "base64,buffer,burl,log,http_header,http_kv,http_status,keyvalue,chunk," + -
    "http_chunk,fdevent,fdevent_fdnode,gw_backend,stat_cache,http_etag,array," + -
    "algo_md5,algo_sha1,algo_splaytree,configfile-glue,http-header-glue,http_cgi," + -
    "http_date,plugin,reqpool,request,sock_addr,rand,fdlog_maint,fdlog,sys-setjmp,ck"
$ server = "server,response,connections,h1,sock_addr_cache,fdevent_impl,http_range," + -
    "network,network_write,data_config,configfile,configparser"
$ modules = "mod_rewrite,mod_redirect,mod_access,mod_alias,mod_indexfile,mod_staticfile," + -
    "mod_setenv,mod_expire,mod_simple_vhost,mod_evhost,mod_fastcgi,mod_scgi," + -
    "mod_accesslog,mod_deflate,mod_dirlisting,mod_extforward,mod_proxy,mod_status," + -
    "h2,ls-hpack/lshpack,algo_xxhash,mod_openssl"
$ sources = common + "," + server + "," + modules
$ errors == 0
$ if target .eqs. "LINK" then goto link
$!
$ i = 0
$compile_loop:
$ f = f$element(i, ",", sources)
$ if f .eqs. "," then goto compile_ours
$ i = i + 1
$ dir = "[.SRC]"
$ name = f
$ if f$locate("/", f) .lt. f$length(f)
$ then
$   dir = "[.SRC." + f$element(0, "/", f) + "]"
$   name = f$element(1, "/", f)
$ endif
$ call compile 'dir''name'.C 'objdir''name'.OBJ
$ goto compile_loop
$compile_ours:
$ call compile [.VMSPORT]VMS_CRTL_INIT.C 'objdir'VMS_CRTL_INIT.OBJ
$ call compile [.VMSPORT]VMS_IN6ADDR.C 'objdir'VMS_IN6ADDR.OBJ
$ if errors .gt. 0
$ then
$   write sys$error "BUILD: ''errors' compile failure(s)"
$   if .not. keep_going then goto done
$ endif
$!
$link:
$ opt = objdir + "LIGHTTPD.OPT"
$ open/write o 'opt'
$ i = 0
$opt_loop:
$ f = f$element(i, ",", sources)
$ if f .eqs. "," then goto opt_end
$ i = i + 1
$ if f$locate("/", f) .lt. f$length(f) then f = f$element(1, "/", f)
$ write o objdir, f, ".OBJ"
$ goto opt_loop
$opt_end:
$ write o objdir, "VMS_CRTL_INIT.OBJ"
$ write o objdir, "VMS_IN6ADDR.OBJ"
$ write o "ZLIB$ROOT:[LIB]LIBZ.OLB/LIBRARY"
$ write o "PCRE2$ROOT:[LIB]PCRE2-8.OLB/LIBRARY"
$ write o "SYS$SHARE:SSL3$LIBSSL_SHR32/SHAREABLE"
$ write o "SYS$SHARE:SSL3$LIBCRYPTO_SHR32/SHAREABLE"
$ close o
$ write sys$output "BUILD: link ''objdir'LIGHTTPD.EXE"
$ link/executable='objdir'LIGHTTPD.EXE/map='objdir'LIGHTTPD.MAP/full 'opt'/options
$ if .not. $status then goto done
$ status = 1
$ write sys$output "BUILD: done"
$done:
$ if f$trnlnm("OPENSSL", "LNM$PROCESS") .nes. "" then deassign/process OPENSSL
$ if f$trnlnm("SYS$ERROR", "LNM$PROCESS") .nes. "" then deassign/process sys$error
$ set default 'saved_default'
$ exit status
$!
$compile: subroutine
$ src = p1
$ obj = p2
$ if f$search(obj) .nes. ""
$ then
$   if f$cvtime(f$file_attributes(src, "RDT"), "COMPARISON") .les. -
       f$cvtime(f$file_attributes(obj, "CDT"), "COMPARISON") then exit 1
$ endif
$ write sys$output "BUILD: cc ", src
$ cc'cflags'/object='obj' 'src'
$ if .not. $status
$ then
$   errors == errors + 1
$   if f$search(obj) .nes. "" then delete/nolog 'obj';*
$ endif
$ exit 1
$ endsubroutine
