#!/usr/bin/env bash
# probe.sh <node> - Phase 0 platform probes, compiled with VSI C.
#
# Generates one tiny C file per header in probes/headers.list (H_), and two per
# function in probes/functions.list: CMake's CHECK_FUNCTION_EXISTS form with no
# header (F_) and a declared-by-a-header form (G_).  Uploads them with the
# hand-written probes (r_*.c runtime, s_*.c linked with SSL3) to
# [.LIGHTTPD_PROBE] and runs tools/vms_probe.com there.
# Output: docs/probes-<node>.txt (raw) - summarised in docs/PHASE0.md.
# PROBE_SETS (default HFGRS) limits the run; a partial run writes
# docs/probes-<node>-<sets>.txt.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: probe.sh <node>}
sets=${PROBE_SETS:-HFGRS}
gen=$top/cache/probe-src-$node
rm -rf "$gen"; mkdir -p "$gen"

lists() { grep -v '^#' "$top/probes/$1" | grep .; }

# Headers that are on every VMS node; G_ files include these.  (VSI C has no
# __has_include, so this is a fixed list.)
base_headers="stdio.h stdlib.h string.h strings.h unistd.h fcntl.h time.h signal.h
netdb.h errno.h sys/time.h sys/types.h sys/stat.h sys/socket.h sys/uio.h
sys/resource.h sys/mman.h sys/wait.h netinet/in.h netinet/tcp.h arpa/inet.h
dirent.h pwd.h grp.h locale.h stdarg.h poll.h sys/ioctl.h sys/file.h"

while read -r h; do
    n=h_$(echo "$h" | tr '/.' '__')
    printf '#include <%s>\nint main(void) { return 0; }\n' "$h" > "$gen/$n.c"
done < <(lists headers.list)

for h in $base_headers; do printf '#include <%s>\n' "$h"; done > "$gen/probe_hdrs.h"

while read -r f; do
    printf 'char %s(void);\nint main(void) { return %s(); }\n' "$f" "$f" > "$gen/f_$f.c"
    printf '#include "probe_hdrs.h"\nint main(void) { void *p = (void *) &%s; return p == 0; }\n' "$f" > "$gen/g_$f.c"
done < <(lists functions.list)

cp "$top"/probes/*.c "$top/tools/vms_probe.com" "$gen/"
nfiles=$(ls "$gen" | wc -l)
echo "probe: uploading $nfiles files to $node"
"$top/tools/vms.sh" "$node" dcl 'if f$search("lighttpd_probe.dir") .eqs. "" then create/directory [.lighttpd_probe]' >/dev/null
( cd "$gen" && "$top/tools/vms.sh" "$node" put * -- lighttpd_probe )

read -r _ _ HOST _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
job=$top/cache/probe-$node.com
printf '$ set noon\n$ @%s.LIGHTTPD_PROBE]VMS_PROBE.COM %s\n' "${WORKDIR%]}" "$sets" > "$job"
out=$top/docs/probes-$node$([ "$sets" = HFGRS ] || echo "-$sets").txt
VMS_TIMEOUT=${VMS_TIMEOUT:-5400} "$top/tools/vms.sh" "$node" run "$job" |
    sed -e "s/$HOST/<$node-host>/g" > "$out"
grep -q PROBE-DONE "$out" || { echo "probe: incomplete output in $out" >&2; exit 1; }
echo "probe: $out"
