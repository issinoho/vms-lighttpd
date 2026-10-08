#!/usr/bin/env bash
# test_http.sh <node> - Phase 2 checks against the test server (tools/serve.sh).
# Prints one PASS/FAIL line per check and a summary; exit status 1 if any failed.
set -uo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: test_http.sh <node>}
read -r _ _ HOST _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
H=http://$HOST:18080 S=https://$HOST:18443
gen=$top/cache/t2-$node
tmp=$(mktemp -d)
pass=0 fail=0
check() {  # check <name> <condition-result 0/1> [detail]
    if [ "$2" = 0 ]; then pass=$((pass+1)); printf 'PASS %-44s %s\n' "$1" "${3:-}"
    else fail=$((fail+1)); printf 'FAIL %-44s %s\n' "$1" "${3:-}"; fi
}
hdr() { curl -s -D - -o /dev/null --max-time 20 "$@" | tr -d '\r'; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$@"; }

# --- HTTP ---------------------------------------------------------------
body=$(curl -s --max-time 10 "$H/")
[ "$body" = "<html><body>lighttpd on OpenVMS</body></html>" ]; check "GET / (index.html)" $? "$(echo "$body" | head -c 60)"
h=$(hdr "$H/plain.txt"); cl=$(echo "$h" | awk -F': ' 'tolower($1)=="content-length"{print $2}')
[ "$cl" = 21 ]; check "stream-LF Content-Length = 21" $? "got $cl"
echo "$h" | grep -qi '^content-type: text/plain'; check "Content-Type text/plain" $?
want=$(printf '0123456789
0123456789
0123456789
' | sha256sum | cut -d' ' -f1)
got=$(curl -s --max-time 10 "$H/var.txt" | sha256sum | cut -d' ' -f1)
[ "$got" = "$want" ]
check "variable-record file served as 33 bytes" $? "$(curl -s -o /dev/null -w 'size=%{size_download}' "$H/var.txt") hdr-len=$(hdr "$H/var.txt" | awk -F': ' 'tolower($1)=="content-length"{print $2}')"
[ "$(code "$H/nope.html")" = 404 ]; check "404 for a missing file" $?
c=$(code --path-as-is "$H/../../../etc/passwd"); [ "$c" = 400 ] || [ "$c" = 404 ] || [ "$c" = 403 ]; check "path traversal refused" $? "code $c"
l=$(curl -s --max-time 10 "$H/sub/"); echo "$l" | grep -qi 'href="a.txt"' && echo "$l" | grep -qi 'href="b.txt"'; check "directory listing /sub/" $?
lm=$(hdr "$H/plain.txt" | awk -F': ' 'tolower($1)=="last-modified"{print $2}')
[ "$(code -H "If-Modified-Since: $lm" "$H/plain.txt")" = 304 ]; check "If-Modified-Since -> 304" $? "$lm"
et=$(hdr "$H/plain.txt" | awk -F': ' 'tolower($1)=="etag"{print $2}')
[ -n "$et" ] && [ "$(code -H "If-None-Match: $et" "$H/plain.txt")" = 304 ]; check "If-None-Match -> 304" $? "$et"
r=$(curl -s --max-time 10 -r 0-99 -w '%{http_code}' -o "$tmp/r1" "$H/big.bin")
[ "$r" = 206 ] && [ "$(stat -c %s "$tmp/r1")" = 100 ] && cmp -s "$tmp/r1" <(head -c 100 "$gen/big.bin")
check "Range 0-99 -> 206, 100 bytes, right data" $? "code $r"
r=$(curl -s --max-time 10 -r 104857500- -w '%{http_code}' -o "$tmp/r2" "$H/big.bin")
[ "$r" = 206 ] && cmp -s "$tmp/r2" <(tail -c 100 "$gen/big.bin"); check "Range last 100 bytes" $? "code $r"
r=$(curl -s --max-time 10 -r 50000000-50000099 -o "$tmp/r3" -w '%{http_code}' "$H/big.bin")
[ "$r" = 206 ] && cmp -s "$tmp/r3" <(tail -c +50000001 "$gen/big.bin" | head -c 100); check "Range in the middle" $? "code $r"
# The nodes' TCP/IP gives ~50-100 KB/s for any sender (docs/PHASE2.md), so the
# default checks move 2 MB; BIG=1 also fetches all 100 MB.
t=$(curl -s --max-time 120 -r 0-2097151 -o "$tmp/r4" -w '%{time_total} %{speed_download}' "$H/big.bin")
cmp -s "$tmp/r4" <(head -c 2097152 "$gen/big.bin"); check "2 MB over HTTP, data matches" $? "$(echo "$t" | awk '{printf "%.1f s, %.1f KB/s", $1, $2/1024}')"
if [ "${BIG:-0}" = 1 ]; then
  t=$(curl -s --max-time 3600 -o "$tmp/big" -w '%{time_total} %{speed_download}' "$H/big.bin")
  [ "$(sha256sum < "$tmp/big" | cut -d' ' -f1)" = "$(cat "$gen/big.sha256")" ]
  check "100 MB download, SHA-256 matches" $? "$(echo "$t" | awk '{printf "%.1f s, %.1f KB/s", $1, $2/1024}')"
fi
n=$(curl -s -v --max-time 10 "$H/plain.txt" "$H/index.html" 2>&1 | grep -c 'Re-using existing connection\|Reusing existing')
[ "$n" -ge 1 ]; check "keep-alive: second request reuses connection" $?
[ "$(code -X POST --data x "$H/plain.txt")" != 000 ]; check "POST to a static file answered" $? "code $(code -X POST --data x "$H/plain.txt")"

# --- HTTPS --------------------------------------------------------------
o=$(curl -sk -o /dev/null -w '%{http_code} %{ssl_verify_result} %{http_version}' --max-time 10 "$S/")
[ "${o%% *}" = 200 ]; check "HTTPS GET /" $? "$o"
v=$(echo | openssl s_client -connect "$HOST:18443" -tls1_3 2>/dev/null | grep -E '^ *Protocol|Cipher is' | head -2 | tr -s ' ' | tr '\n' ' ')
echo "$v" | grep -q 'TLSv1.3'; check "TLS 1.3" $? "$v"
v=$(echo | openssl s_client -connect "$HOST:18443" -tls1_2 2>/dev/null | grep -E 'Cipher is' | head -1 | tr -s ' ')
echo "$v" | grep -q 'Cipher is (NONE)'; check "TLS 1.2 refused on :18443 (default min 1.3)" $? "$v"
v=$(echo | openssl s_client -connect "$HOST:18444" -tls1_2 2>/dev/null | grep -E '^ *Protocol|Cipher is' | head -2 | tr -s ' ' | tr '
' ' ')
echo "$v" | grep -q 'TLSv1.2' && ! echo "$v" | grep -q 'Cipher is (NONE)'; check "TLS 1.2 on :18444 (MinProtocol TLSv1.2)" $? "$v"
echo | openssl s_client -connect "$HOST:18443" -tls1_1 >/dev/null 2>&1; [ $? != 0 ]; check "TLS 1.1 refused" $?
v=$(curl -sk --http2 -o /dev/null -w '%{http_version}' --max-time 10 "$S/index.html"); [ "$v" = 2 ]; check "HTTP/2 over TLS (ALPN h2)" $? "http_version $v"
t=$(curl -sk --http2 --max-time 120 -r 0-2097151 -o "$tmp/r5" -w '%{time_total} %{speed_download}' "$S/big.bin")
cmp -s "$tmp/r5" <(head -c 2097152 "$gen/big.bin"); check "2 MB over HTTPS h2, data matches" $? "$(echo "$t" | awk '{printf "%.1f s, %.1f KB/s", $1, $2/1024}')"
# TLS 1.3 tickets arrive after the handshake: keep the first connection open a moment
(sleep 2; echo) | openssl s_client -connect "$HOST:18443" -tls1_3 -sess_out "$tmp/s13" >/dev/null 2>&1
r=$( (sleep 1; echo) | openssl s_client -connect "$HOST:18443" -tls1_3 -sess_in "$tmp/s13" 2>/dev/null | grep -E '^(New|Reused)')
echo "$r" | grep -q '^Reused'; check "TLS 1.3 session resumption (ticket)" $? "$r"
r=$(echo | openssl s_client -connect "$HOST:18444" -reconnect -tls1_2 2>/dev/null | grep -c '^Reused')
[ "$r" -ge 1 ]; check "TLS 1.2 session resumption" $? "$r of 5 reconnects reused"

rm -rf "$tmp"
echo "SUMMARY: $pass passed, $fail failed"
[ "$fail" = 0 ]
