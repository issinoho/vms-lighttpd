#!/usr/bin/env bash
# tcptune.sh <node> - measure TCP throughput on <node> under runtime TCP/IP
# settings (TCPIP SYSCONFIG -r inet ...), one change at a time, then combined.
#
# CHANGES THE NODE'S TCP/IP SETTINGS while it runs (approved by the user,
# 2026-10-08); every changed attribute is restored to the value recorded at
# the start, also on error or Ctrl-C.  Runtime changes do not survive a reboot.
#
# Each measurement runs probes/r_blast.c (10 MB from memory, blocking writes)
# on the node, compiled in [.LIGHTTPD_PROBE] by an earlier probe run, and reads
# it for 20 s: once over loopback with VMSCURL on the node, once over the LAN
# with curl here.  Output: out/tcptune-<node>.txt
set -uo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: tcptune.sh <node>}
read -r _ _ HOST _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
vms() { VMS_TIMEOUT=${VMS_TIMEOUT:-300} "$top/tools/vms.sh" "$node" "$@"; }
out=$top/out/tcptune-$node.txt
attrs="tcpnodelack tcp_cwnd_segments tcp_sendspace tcp_recvspace tcp_sack_default tcp_tsopt_default"

# --- record the current values ------------------------------------------------
declare -A orig
q=$(vms dcl "tcpip sysconfig -q inet $attrs" 2>&1)
for a in $attrs; do
    orig[$a]=$(echo "$q" | awk -v a="$a" '$1==a {print $3}')
    [ -n "${orig[$a]}" ] || { echo "tcptune: could not read $a" >&2; exit 1; }
done
restore() {
    local args=""
    for a in $attrs; do args+=" $a=${orig[$a]}"; done
    echo "restoring:$args" | tee -a "$out"
    vms dcl "tcpip sysconfig -r inet$args" "tcpip sysconfig -q inet $attrs" 2>&1 | grep -E '=' | tr '\n' ' ' | tee -a "$out"; echo | tee -a "$out"
}
trap restore EXIT
trap 'exit 130' INT TERM

setv() { vms dcl "tcpip sysconfig -r inet $*" >/dev/null 2>&1; }
blast() {  # start r_blast for one connection on the node (background ssh session)
    ( vms dcl 'set default [.lighttpd_probe]' 'bl = "$" + f$search("r_blast.exe")' "bl 18090 block" >/dev/null 2>&1 ) &
    sleep 10
}
measure() {
    local label=$1 lb lan
    blast
    lb=$(vms dcl 'set process/parse_style=extended' 'curl :== $vmscurl$root:[bin]curl.exe' \
          'curl -s -o NLA0: --max-time 20 -w "%{size_download} %{time_total}" http://127.0.0.1:18090/' 2>&1 |
         grep -E '^[0-9]+ [0-9.]+$' | awk '{printf "%.0f", $1/$2/1024}')
    wait
    blast
    # refused connections are retried (the probe may still be starting); they
    # do not use up its single accept()
    lan=$(curl -s -o /dev/null --retry 10 --retry-delay 2 --retry-connrefused --max-time 20             -w '%{size_download} %{time_total}' "http://$HOST:18090/" |
          awk '{printf "%.0f", $1/$2/1024}')
    wait
    printf '%-40s loopback %8s KB/s   LAN %8s KB/s\n' "$label" "${lb:-?}" "${lan:-?}" | tee -a "$out"
}

echo "tcptune $node $(date -u +%FT%TZ); original:$(for a in $attrs; do printf ' %s=%s' $a "${orig[$a]}"; done)" | tee "$out"
measure "baseline"
setv tcpnodelack=1;                                   measure "tcpnodelack=1 (no delayed ACK)"; restore >/dev/null
setv tcp_cwnd_segments=10;                            measure "tcp_cwnd_segments=10";          restore >/dev/null
setv tcp_sendspace=262144 tcp_recvspace=262144;       measure "send/recvspace 256 KB";         restore >/dev/null
setv tcp_sack_default=1 tcp_tsopt_default=1;          measure "SACK + timestamps";             restore >/dev/null
setv tcpnodelack=1 tcp_cwnd_segments=10 tcp_sendspace=262144 tcp_recvspace=262144 tcp_sack_default=1 tcp_tsopt_default=1
measure "all of the above"
