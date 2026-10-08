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
set -uo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: soak.sh <node> [minutes] [workers]}
minutes=${2:-60}
workers=${3:-8}
read -r _ _ HOST _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
entry=$(cat "$top/cache/serve-$node.entry" 2>/dev/null) || { echo "soak: server not started (tools/serve.sh)" >&2; exit 1; }
out=$top/out/soak-$node.log
res=$top/cache/soak-$node.results
mkdir -p "$top/out"; : > "$res"
end=$(( $(date +%s) + minutes * 60 ))

worker() {
    local urls=("http://$HOST:18080/" "http://$HOST:18080/plain.txt" "http://$HOST:18080/var.txt"
                "http://$HOST:18080/sub/" "http://$HOST:18080/nope.html" "https://$HOST:18443/index.html"
                "range" "https://$HOST:18443/plain.txt")
    while [ "$(date +%s)" -lt "$end" ]; do
        u=${urls[$((RANDOM % ${#urls[@]}))]}
        if [ "$u" = range ]; then
            r=$(curl -s -o /dev/null --max-time 30 -r 0-65535 -w '%{http_code} %{time_total}' "http://$HOST:18080/big.bin")
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
