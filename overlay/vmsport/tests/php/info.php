<?php
// SAPI, version and the extensions phpBB needs
$ext = ['mysqli', 'pdo_mysql', 'gd', 'mbstring', 'json', 'xml', 'zlib', 'openssl', 'ctype'];
$have = [];
foreach ($ext as $e) $have[$e] = extension_loaded($e);
$oc = function_exists('opcache_get_status') ? opcache_get_status(false) : false;
header('Content-Type: application/json');
echo json_encode(['version' => PHP_VERSION, 'sapi' => php_sapi_name(), 'ext' => $have,
                  'opcache' => $oc ? (bool)$oc['opcache_enabled'] : false,
                  'ini' => php_ini_loaded_file()]), "\n";
