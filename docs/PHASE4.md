# Phase 4: phpBB acceptance test

phpBB 3.3.19 (pinned in `upstream.conf`, SHA-256 checked) unpacked on the host and uploaded
with sftp (`put -r`, 3,893 files, all Stream_LF) to `<workdir>.PHPBB]`; installed with
phpBB's CLI installer (`install/phpbbcli.php install`) with PHP_ROOT's PHP 8.1.23 CLI
(needs `COLUMNS`/`LINES`, PORTING_LOG #24) into database `phpbb` (utf8mb4) on the x86
vms-mariadb server, user `phpbb`@`localhost`/`127.0.0.1`.  Secrets (MariaDB root, phpBB DB
and admin passwords) live only in the git-ignored `cache/db.secrets`.

Server: `tools/serve.sh x86 phpbbsetup` (renames `install/` to `install_done/`, writes
`[.T4]LIGHTTPD.CONF` from `vmsport/tests/p4setup.com`, which includes
`vmsport/conf/phpbb.conf`), the Phase 3 PHP pool, `CONF='[.T4]LIGHTTPD.CONF'
tools/serve.sh x86 start`.  Checklist: `tools/test_phpbb.py x86`.

| Check | x86 (2026-10-08) |
|---|---|
| board index, denied paths (config.php, cache, store, files, includes, vendor) | pass |
| admin login, new topic, reply with a 40 KB attachment, download (MD5), search, logout | pass |
| `test_phpbb.py` total | 14/14 |
| ACP | pass (by the user in a browser, 2026-10-08; the script's re-authentication is accepted but it doesn't reach /adm/) |
| registration | manual (CAPTCHA) |

First request per PHP process takes 10-18 s (opcache compiling phpBB); after that pages
take 0.7-4 s over this network.

The installer enabled the bundled `phpbb/viglink` extension despite `extensions: []`; the user
disabled it in the ACP (2026-10-08).
