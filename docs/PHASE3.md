# Phase 3: PHP over FastCGI

Pool: `vmsport/php/php_pool.com` (D4), ini `vmsport/php/php.ini` (PHP_ROOT kits) or
`php-vsi80.ini` (VSI's 8.0 kit). Test harness: `tools/serve.sh <node> phpsetup |
poolstart | poolstop | poolstatus` (test tree `vmsport/tests/p3setup.com`, scripts in
`vmsport/tests/php/`), checks `tools/test_php.sh <node>` (`DB_HOST` = MariaDB address,
`KILL=0` skips the kill test), load `SOAK_PHP=1 tools/soak.sh <node> <min> <workers>`.

| | x86 (PHP 8.1.23) | IA64 (PHP 8.0.29) |
|---|---|---|
| test_php.sh (19 checks) | 19/19 | 19/19 (18 + mysqli to the x86 MariaDB with `DB_HOST`) |
| test_http.sh after Phase 3 | 24/24 | |
| PHP soak, 15 min, 8 workers, `PHP_FCGI_MAX_REQUESTS=500` | 11,112 requests, 10 × 500 at PHP recycles (#22) | |
| PHP soak, 10 min, recycling off (default) | 8,064 requests, all 200; server memory flat (9,792 KB) | |

Checks: cgi-fcgi SAPI and version; mysqli, pdo_mysql, gd, mbstring, json, xml, zlib,
openssl, ctype loaded; opcache on; the pool's php.ini loaded; SCRIPT_NAME, PATH_INFO
(0011), QUERY_STRING/$_GET, REQUEST_METHOD/SERVER_PORT, HTTPS=on over h2; form POST; 3 MB
multipart upload with MD5 and 3 MB raw body (0012); session counter; 1 MB generated
response and 256 KB over h2; mysqli to MariaDB ("1045 Access denied" for a probe user);
requests spread over the 4 processes; one process killed: all requests still 200;
`START` restarts only the missing process.
