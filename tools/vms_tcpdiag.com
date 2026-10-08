$! VMS_TCPDIAG.COM - read-only TCP/IP diagnosis (docs/DECISIONS.md D10).
$! Settings, interfaces, NIC state and TCP statistics; changes nothing.
$ set noon
$ say = "write sys$output"
$ sect: subroutine
$   say ""
$   say "=== ''p1'"
$ endsubroutine
$ call sect "system"
$ say f$getsyi("arch_name"), " ", f$getsyi("version"), " cpus ", f$getsyi("activecpu_cnt")
$ tcpip show version
$ call sect "inet subsystem (sysconfig -q inet)"
$ tcpip sysconfig -q inet
$ call sect "socket subsystem (sysconfig -q socket)"
$ tcpip sysconfig -q socket
$ call sect "interfaces"
$ tcpip show interface/full
$ call sect "LAN devices"
$ show device/full ew
$ show device/full ei
$ show device/full we
$ call sect "LANCP device characteristics and counters"
$ define/user sys$error sys$output
$ mcr lancp show device/characteristics
$ define/user sys$error sys$output
$ mcr lancp show device/counters
$ call sect "TCP statistics (netstat -s -p tcp)"
$ tcpip netstat -s -p tcp
$ call sect "IP statistics (netstat -s -p ip)"
$ tcpip netstat -s -p ip
$ call sect "route table"
$ tcpip show route
$ say "TCPDIAG-DONE"
