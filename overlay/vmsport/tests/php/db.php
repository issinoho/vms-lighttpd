<?php
// mysqli to the vms-mariadb server with a user that does not exist:
// "Access denied" proves the driver, TCP and the MariaDB handshake work.
header('Content-Type: text/plain');
mysqli_report(MYSQLI_REPORT_OFF);
// ?host=a.b.c.d to reach a MariaDB on another node (IPv4 literal only)
$host = (isset($_GET['host']) && filter_var($_GET['host'], FILTER_VALIDATE_IP, FILTER_FLAG_IPV4))
        ? $_GET['host'] : '127.0.0.1';
$m = @mysqli_connect($host, 'lighttpd_probe_nouser', 'x', '', 3306);
echo $m ? "connected\n" : mysqli_connect_errno() . " " . mysqli_connect_error() . "\n";
