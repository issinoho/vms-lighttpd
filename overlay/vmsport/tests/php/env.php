<?php
header('Content-Type: application/json');
$k = ['REQUEST_METHOD', 'SCRIPT_NAME', 'SCRIPT_FILENAME', 'PATH_INFO', 'QUERY_STRING',
      'REQUEST_URI', 'DOCUMENT_ROOT', 'SERVER_PORT', 'HTTPS', 'REMOTE_ADDR', 'HTTP_HOST',
      'SERVER_SOFTWARE', 'GATEWAY_INTERFACE'];
$o = [];
foreach ($k as $x) $o[$x] = $_SERVER[$x] ?? null;
$o['get'] = $_GET;
echo json_encode($o), "\n";
