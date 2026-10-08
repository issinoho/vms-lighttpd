#!/usr/bin/env bash
# serve.sh <node> setup|start|stop|log - the Phase 2 test server on <node>.
#
#   setup  push the tree, create [.T2] (vmsport/tests/p2setup.com), upload a
#          self-signed SERVER.PEM and a 100 MB BIG.BIN made on the host
#   start  submit vmsport/tests/p2server.com as a batch job (our quotas; it
#          outlives the ssh session); the entry number goes to cache/
#   stop   DELETE/ENTRY the job
#   log    fetch the job log and lighttpd's error/access logs into out/
# The server listens on 18080 (HTTP) and 18443 (HTTPS) on $BIND (default 0.0.0.0).
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: serve.sh <node> setup|start|stop|log}
op=${2:?usage: serve.sh <node> setup|start|stop|log}
. "$top/upstream.conf"
remote=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _)
read -r _ _ HOST _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
tree="${WORKDIR%]}.$(echo "$remote" | tr a-z A-Z)]"
entry_file=$top/cache/serve-$node.entry
vms() { "$top/tools/vms.sh" "$node" "$@"; }

case $op in
setup)
    "$top/tools/push.sh" "$node" >/dev/null
    vms dcl "set default $tree" "@[.VMSPORT.TESTS]P2SETUP.COM ${BIND:-0.0.0.0}" | grep -E 'P2SETUP' || true
    gen=$top/cache/t2-$node; mkdir -p "$gen"
    [ -f "$gen/server.pem" ] || {
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
            -subj "/CN=lighttpd-vms-test" -keyout "$gen/key.pem" -out "$gen/cert.pem" 2>/dev/null
        cat "$gen/cert.pem" "$gen/key.pem" > "$gen/server.pem"; }
    [ -f "$gen/big.bin" ] || head -c 104857600 /dev/urandom > "$gen/big.bin"
    sha256sum "$gen/big.bin" | awk '{print $1}' > "$gen/big.sha256"
    vms put "$gen/server.pem" -- "$remote/T2"
    vms put "$gen/big.bin" -- "$remote/T2/HTDOCS"
    # again, now that SERVER.PEM exists: adds the HTTPS listener
    vms dcl "set default $tree" "@[.VMSPORT.TESTS]P2SETUP.COM ${BIND:-0.0.0.0}" | grep -E 'P2SETUP|18443' || true
    vms dcl "set default $tree" 'dir/size/full [.T2.HTDOCS]big.bin' | grep -iE 'Record format|Size:' || true
    ;;
start)
    out=$(vms dcl "set default $tree" \
          "if f\$search(\"[.T2.LOGS]*.*\") .nes. \"\" then delete/nolog [.T2.LOGS]*.*;*" \
          "submit/noprint/log_file=$tree"'P2SERVER.LOG'"/name=LTTEST/parameters=(\"$tree\") [.VMSPORT.TESTS]P2SERVER.COM")
    echo "$out"
    entry=$(echo "$out" | grep -oE 'entry [0-9]+' | awk '{print $2}')
    [ -n "$entry" ] || { echo "serve: no entry number" >&2; exit 1; }
    echo "$entry" > "$entry_file"
    echo "serve: job entry $entry; waiting for :18080"
    for _ in $(seq 1 30); do
        curl -s -o /dev/null --max-time 3 "http://$HOST:18080/" && { echo "serve: up"; exit 0; }
        sleep 2
    done
    echo "serve: not answering on :18080 after 60 s" >&2; exit 1
    ;;
stop)
    [ -f "$entry_file" ] || { echo "serve: no entry recorded" >&2; exit 1; }
    vms dcl "delete/entry=$(cat "$entry_file")" || true
    rm -f "$entry_file"
    ;;
log)
    mkdir -p "$top/out"
    vms get "$remote/P2SERVER.LOG" "$top/out/p2server-$node.log" || true
    vms get "$remote/T2/LOGS/error.log" "$top/out/error-$node.log" || true
    vms get "$remote/T2/LOGS/access.log" "$top/out/access-$node.log" || true
    ls -la "$top"/out/*-"$node".log
    ;;
*) echo "usage: serve.sh <node> setup|start|stop|log" >&2; exit 2 ;;
esac
