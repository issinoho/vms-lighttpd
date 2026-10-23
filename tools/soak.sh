#!/usr/bin/env bash
# soak.sh <node> [minutes] [workers] - load the Phase 2 test server for a while.
#
# <workers> curl loops (default 8) for <minutes> (default 60), each request
# picked from a mix of small static files, a 64 KB range, a 404, a directory
# listing and HTTPS/HTTP2.  Every 5 minutes the server's batch process is
# sampled (CPU, page faults, pages, I/O) so leaks show up as a trend.
# Results: out/soak-<node>.log (samples) and a summary of status codes.
# The nodes' TCP/IP gives ~100 KB/s per connection (docs/DECISIONS.md D10),
# so the mix is small requests.
# Another server (e.g. vms-php's SQLite board): SOAK_PORT (default 18080),
# SOAK_TLS_PORT (default 18443; empty: no HTTPS requests in the phpBB mix) and
# SOAK_ENTRY (the server's batch entry file, default cache/serve-<node>.entry).
set -uo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: soak.sh <node> [minutes] [workers]}
minutes=${2:-60}
workers=${3:-8}
read -r _ _ HOST _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
port=${SOAK_PORT:-18080}
tlsport=${SOAK_TLS_PORT-18443}
entry=$(cat "${SOAK_ENTRY:-$top/cache/serve-$node.entry}" 2>/dev/null) || { echo "soak: server not started (tools/serve.sh)" >&2; exit 1; }
out=$top/out/soak-$node.log
res=$top/cache/soak-$node.results
mkdir -p "$top/out"; : > "$res"
end=$(( $(date +%s) + minutes * 60 ))

worker() {
    local urls=("http://$HOST:$port/" "http://$HOST:$port/plain.txt" "http://$HOST:$port/var.txt"
                "http://$HOST:$port/sub/" "http://$HOST:$port/nope.html" "https://$HOST:$tlsport/index.html"
                "range" "https://$HOST:$tlsport/plain.txt")
    # SOAK_PHP=1: Phase 3 mix, mostly PHP through the FastCGI pool
    [ "${SOAK_PHP:-0}" = 1 ] && urls=("http://$HOST:$port/info.php" "http://$HOST:$port/env.php/a/b?x=1"
                "http://$HOST:$port/pid.php" "http://$HOST:$port/session.php" "post"
                "https://$HOST:$tlsport/info.php" "http://$HOST:$port/big.php?n=32768" "http://$HOST:$port/plain.txt")
    # SOAK_PHPBB=1: Phase 4 server (CONF=[.T4]LIGHTTPD.CONF), guest pages of the
    # test board: index, forum, topic, search, login form, FAQ, member list
    [ "${SOAK_PHPBB:-0}" = 1 ] && urls=("http://$HOST:$port/" "http://$HOST:$port/viewforum.php?f=2"
                "http://$HOST:$port/viewtopic.php?t=1" "http://$HOST:$port/search.php?keywords=welcome"
                "http://$HOST:$port/ucp.php?mode=login" "http://$HOST:$port/app.php/help/faq"
                "http://$HOST:$port/memberlist.php" "https://$HOST:$tlsport/viewtopic.php?t=1")
    [ "${SOAK_PHPBB:-0}" = 1 ] && [ -z "$tlsport" ] && unset 'urls[7]'
    while [ "$(date +%s)" -lt "$end" ]; do
        u=${urls[$((RANDOM % ${#urls[@]}))]}
        if [ "$u" = post ]; then
            r=$(curl -s -o /dev/null --max-time 30 -d a=1 -d b=2 -w '%{http_code} %{time_total}' "http://$HOST:$port/post.php")
        elif [ "$u" = range ]; then
            r=$(curl -s -o /dev/null --max-time 30 -r 0-65535 -w '%{http_code} %{time_total}' "http://$HOST:$port/big.bin")
        else
            r=$(curl -sk --http2 -o /dev/null --max-time 30 -w '%{http_code} %{time_total}' "$u")
        fi
        echo "$r" >> "$res"
    done
}
sample() {
    "$top/tools/vms.sh" "$node" dcl 'show system/batch/full' 2>/dev/null |
        grep -A1 "BATCH_$entry\|^.\{9\}BATCH_" | head -2 | tr -s ' ' | tr '\n' ' '
}

echo "soak: $node, $workers workers, $minutes min, server job $entry" | tee "$out"
echo "$(date +%T) start  $(sample)" | tee -a "$out"
for _ in $(seq 1 "$workers"); do worker & done
while [ "$(date +%s)" -lt "$end" ]; do
    sleep 300
    echo "$(date +%T) $(wc -l < "$res") req  $(sample)" | tee -a "$out"
done
wait
echo "$(date +%T) end    $(sample)" | tee -a "$out"
echo "--- status codes" | tee -a "$out"
awk '{print $1}' "$res" | sort | uniq -c | tee -a "$out"
awk '{s+=$2; n++; if ($2>m) m=$2} END {printf "requests %d, mean %.3f s, max %.3f s\n", n, s/n, m}' "$res" | tee -a "$out"
