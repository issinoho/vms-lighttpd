#!/usr/bin/env bash
# installcheck.sh <node> <uic> <data-dir> [port] [CLEANUP]
# Install the PCSI kit from out/kits/ on <node>, run VMSLIGHTTPD$CONFIGURE
# (creates the service account and data directory), start the service, check
# it over HTTP from here (static page, PHP, process identity and privileges),
# rotate the logs, stop it; with CLEANUP, remove the product, account and data.
#
# CHANGES THE SYSTEM: ask the user first.  Runs as a batch job on the node.
set -uo pipefail   # not -e: the checks below decide
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: installcheck.sh <node> <uic> <data-dir> [port] [CLEANUP]}
uic=${2:?uic, e.g. [361,1]}
data=${3:?data directory, e.g. SYS\$SYSDEVICE:[VMSLIGHTTPD_DATA]}
port=${4:-981}
cleanup=${5:-}
read -r _ ARCH HOST _ _ WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
base=I64VMS; [ "$ARCH" = X86_64 ] && base=X86VMS
kit=$(ls -t "$top"/out/kits/*-"$base"-LIGHTTPD-*.PCSI | head -1)
echo "installcheck: $node kit $(basename "$kit"), port $port ${cleanup:+(cleanup)}"
"$top/tools/vms.sh" "$node" dcl 'if f$search("ic_kit.dir") .eqs. "" then create/directory [.ic_kit]' \
    'if f$search("[.ic_kit]*.*") .nes. "" then delete/nolog [.ic_kit]*.*;*' >/dev/null
"$top/tools/vms.sh" "$node" put "$kit" -- ic_kit
kitdir="${WORKDIR%]}.IC_KIT]"
log=$top/out/installcheck-$node.log
( VMS_BATCH_POLLS=200 VMS_BATCH_POLL_SECS=15 "$top/tools/vms.sh" "$node" batch "$top/tools/vms_installcheck.com" \
    "$kitdir" "$uic" "$data" "$port" "$cleanup" > "$log" 2>&1 ) &
bpid=$!
# wait for the service to answer, then check it
for _ in $(seq 1 60); do curl -s -o /dev/null --max-time 3 "http://$HOST:$port/" && break; sleep 5; done
pass=0 fail=0
chk() { if [ "$2" = 0 ]; then pass=$((pass+1)); echo "PASS $1 ${3:-}"; else fail=$((fail+1)); echo "FAIL $1 ${3:-}"; fi; }
b=$(curl -s --max-time 30 "http://$HOST:$port/"); echo "$b" | grep -q 'VMSLIGHTTPD is running'; chk "default page on :$port" $?
b=$(curl -s --max-time 60 "http://$HOST:$port/ic.php"); echo "$b" | grep -q 'sapi cgi-fcgi'; chk "PHP through the pool" $? "$b"
c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "http://$HOST:$port/ic.php.txt"); chk "404 for a missing file" $([ "$c" = 404 ]; echo $?) "$c"
# let the batch job go on: ROTATE, STOP (and CLEANUP)
"$top/tools/vms.sh" "$node" dcl "create ${kitdir}IC.GO" >/dev/null 2>&1 || true
wait $bpid || true
grep -E '^IC|SUBMIT|VMSLIGHTTPD:|privileges|%PCSI|%' "$log" | grep -v '^\s*$' | head -60
grep -q 'privileges TMPMBX,NETMBX' "$log"; chk "server privileges TMPMBX,NETMBX only" $?
grep -q 'user LIGHTTPD' "$log"; chk "server runs as LIGHTTPD" $?
grep -q 'VMS: listeners bound' "$log"; chk "privilege drop logged" $?
grep -q 'server stopped' "$log"; chk "graceful stop (SIGTERM)" $?
echo "SUMMARY: $pass passed, $fail failed (log: out/installcheck-$node.log)"
[ "$fail" = 0 ]
