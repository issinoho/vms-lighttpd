$! P2SERVER.COM - run the test server in the foreground (submit it as a batch
$! job; stop it with DELETE/ENTRY).  P1: tree top directory.
$! P2: configuration file (default [.T2]LIGHTTPD.CONF)
$ set noon
$! Batch jobs use the traditional parse style, which lowercases -D to -d;
$! DECC$ARGV_PARSE_STYLE (set in the image) only works with EXTENDED.
$ set process/parse_style=extended
$ set default 'p1'
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ lighttpd = "$" + f$search("[.VMS_''arch']LIGHTTPD.EXE")
$ define/process sys$error sys$output
$ show process/quota
$ write sys$output "P2SERVER: starting ", f$time()
$ conf = p2
$ if conf .eqs. "" then conf = "[.T2]LIGHTTPD.CONF"
$ lighttpd "-D" -f 'conf'
$ write sys$output "P2SERVER: exited status ", $status, " at ", f$time()
