#!/usr/bin/env bash
# test_php.sh <node> - Phase 3 checks: PHP over FastCGI through the test server
# (tools/serve.sh <node> phpsetup, poolstart, start).  One PASS/FAIL per check;
# exit status 1 if any failed.  KILL=0 skips the backend-kill check.
set -uo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: test_php.sh <node>}
read -r _ _ HOST _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
H=http://$HOST:18080 S=https://$HOST:18443
tmp=$(mktemp -d)
pass=0 fail=0
check() {
    if [ "$2" = 0 ]; then pass=$((pass+1)); printf 'PASS %-46s %s\n' "$1" "${3:-}"
    else fail=$((fail+1)); printf 'FAIL %-46s %s\n' "$1" "${3:-}"; fi
}
j() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

# --- PHP itself -------------------------------------------------------------
info=$(curl -s --max-time 30 "$H/info.php")
[ "$(echo "$info" | j "d['sapi']")" = cgi-fcgi ]; check "PHP over FastCGI (cgi-fcgi SAPI)" $? "$(echo "$info" | j "d['version']")"
m=$(echo "$info" | j "','.join(k for k,v in d['ext'].items() if not v)")
[ -z "$m" ]; check "phpBB extensions loaded" $? "${m:+missing: $m}"
[ "$(echo "$info" | j "d['opcache']")" = True ]; check "opcache enabled" $?
echo "$info" | j "d['ini']" | grep -q 'php.ini$'; check "pool php.ini loaded" $?

# --- FastCGI environment ------------------------------------------------------
e=$(curl -s --max-time 30 "$H/env.php/extra/path?a=1&b=two")
[ "$(echo "$e" | j "d['SCRIPT_NAME']")" = /env.php ]; check "SCRIPT_NAME" $? "$(echo "$e" | j "d['SCRIPT_NAME']")"
[ "$(echo "$e" | j "d['PATH_INFO']")" = /extra/path ]; check "PATH_INFO" $? "$(echo "$e" | j "d['PATH_INFO']")"
[ "$(echo "$e" | j "d['QUERY_STRING']")" = 'a=1&b=two' ] && [ "$(echo "$e" | j "d['get']['b']")" = two ]
check "QUERY_STRING and \$_GET" $?
[ "$(echo "$e" | j "d['REQUEST_METHOD']")" = GET ] && [ "$(echo "$e" | j "d['SERVER_PORT']")" = 18080 ]
check "REQUEST_METHOD, SERVER_PORT" $?
e=$(curl -sk --http2 --max-time 30 "$S/env.php")
[ "$(echo "$e" | j "d['HTTPS']")" = on ]; check "HTTPS=on over TLS (h2)" $?

# --- request bodies -----------------------------------------------------------
p=$(curl -s --max-time 30 -d a=1 -d b=hello "$H/post.php")
[ "$(echo "$p" | j "d['post']['b']")" = hello ]; check "form POST" $?
head -c 3145728 /dev/urandom > "$tmp/up.bin"
want=$(md5sum < "$tmp/up.bin" | cut -d' ' -f1)
p=$(curl -s --max-time 300 -F "f=@$tmp/up.bin" -F x=y "$H/post.php")
[ "$(echo "$p" | j "d['files']['f']['md5']")" = "$want" ] && [ "$(echo "$p" | j "d['files']['f']['size']")" = 3145728 ]
check "3 MB multipart upload, MD5 matches" $? "$(echo "$p" | j "d['files']['f']['size']") bytes"
p=$(curl -s --max-time 120 -H 'Content-Type: application/octet-stream' --data-binary "@$tmp/up.bin" "$H/post.php")
[ "$(echo "$p" | j "d['rawlen']")" = 3145728 ]; check "3 MB raw request body" $?

# --- sessions -----------------------------------------------------------------
c=$tmp/cookies
r=$(for i in 1 2 3; do curl -s -b "$c" -c "$c" --max-time 30 "$H/session.php"; done | tr '\n' ' ')
[ "$r" = "1 2 3 " ]; check "session counter 1 2 3" $? "$r"

# --- response bodies ----------------------------------------------------------
curl -s --max-time 120 -o "$tmp/big" "$H/big.php?n=1048576"
python3 -c "import sys; b=open(sys.argv[1],'rb').read(); sys.exit(0 if b==(b'0123456789abcdef'*65536) else 1)" "$tmp/big"
check "1 MB generated response" $? "$(stat -c %s "$tmp/big") bytes"
curl -sk --http2 --max-time 120 -o "$tmp/big2" "$S/big.php?n=262144"
[ "$(stat -c %s "$tmp/big2")" = 262144 ]; check "256 KB generated response over h2" $?

# --- database -----------------------------------------------------------------
# DB_HOST: where the vms-mariadb server is (default: this node)
d=$(curl -s --max-time 30 "$H/db.php?host=${DB_HOST:-127.0.0.1}")
echo "$d" | grep -q '^1045 '; check "mysqli reaches MariaDB (1045 expected)" $? "$d"

# --- the pool -----------------------------------------------------------------
pids=$(seq 1 16 | xargs -P 8 -I{} curl -s --max-time 60 "$H/pid.php?sleep=500" | sort -u)
n=$(echo "$pids" | grep -c .)
[ "$n" -ge 3 ]; check "requests spread over the pool" $? "$n distinct PHP processes"
if [ "${KILL:-1}" = 1 ]; then
    victim=$("$top/tools/serve.sh" "$node" poolstatus | awk '/LTPHP_19001 pid/{print $4}')
    "$top/tools/vms.sh" "$node" dcl "stop/id=$victim" >/dev/null 2>&1
    codes=$(seq 1 12 | xargs -P 4 -I{} curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 "$H/pid.php?sleep=200" | sort | uniq -c | tr -s ' ' | tr '\n' ' ')
    echo "$codes" | grep -qv ' 200' ; bad=$?
    [ "$(echo "$codes" | grep -o ' 200' | wc -l)" = 1 ] && ! echo "$codes" | grep -qE ' (5[0-9][0-9]|000)'
    check "one backend killed: all requests still 200" $? "codes: $codes (killed $victim)"
    "$top/tools/serve.sh" "$node" poolstart | grep -q 'started LTPHP_19001'
    check "poolstart restarts only the missing backend" $?
fi

rm -rf "$tmp"
echo "SUMMARY: $pass passed, $fail failed"
[ "$fail" = 0 ]
