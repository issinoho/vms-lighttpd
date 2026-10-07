#!/usr/bin/env bash
# build.sh <node> [ALL|CLEAN|LINK] [KEEP_GOING] - push the prepared tree and run
# [.VMSPORT]BUILD.COM on <node>.  The log is printed and saved to out/build-<node>.log.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: build.sh <node> [ALL|CLEAN|LINK] [KEEP_GOING]}
target=${2:-ALL}
keep=${3:-}
. "$top/upstream.conf"
remote=$(echo "$UPSTREAM_NAME-$UPSTREAM_VERSION" | tr . _ | tr a-z A-Z)
read -r _ _ _ _ _ WORKDIR _ < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")

"$top/tools/push.sh" "$node"
mkdir -p "$top/out"
job=$top/cache/build-$node.com
# rooted() defines a concealed rooted logical for <workdir>.<tree>.INSTALL_<arch>]
cat > "$job" <<DCL
\$ set noon
\$ set process/parse_style=extended
\$ zarch = f\$edit(f\$getsyi("ARCH_NAME"), "UPCASE")
\$ zdir = "${WORKDIR%]}.$ZLIB_TREE.INSTALL_" + zarch + "]"
\$ zdev = f\$parse(zdir,,,"DEVICE","NO_CONCEAL")
\$ zroot = f\$parse(zdir,,,"DIRECTORY","NO_CONCEAL") - "][" - "]" + ".]"
\$ define/process/translation_attributes=concealed ZLIB\$ROOT 'zdev''zroot'
\$ zdir = "${WORKDIR%]}.$PCRE2_TREE.INSTALL_" + zarch + "]"
\$ zdev = f\$parse(zdir,,,"DEVICE","NO_CONCEAL")
\$ zroot = f\$parse(zdir,,,"DIRECTORY","NO_CONCEAL") - "][" - "]" + ".]"
\$ define/process/translation_attributes=concealed PCRE2\$ROOT 'zdev''zroot'
\$ purge/nolog ${WORKDIR%]}.$remote...]*.*
\$ @${WORKDIR%]}.$remote.VMSPORT]BUILD.COM $target $keep
DCL
VMS_TIMEOUT=${VMS_BUILD_TIMEOUT:-5400} "$top/tools/vms.sh" "$node" run "$job" | tee "$top/out/build-$node.log"
grep -q 'BUILD: done' "$top/out/build-$node.log"
if grep -aE '%LINK-[WEF]-|%ILINK-[WEF]-|%DCL-[WEF]-|%CC-[EF]-|BUILD: [0-9]+ compile failure' "$top/out/build-$node.log" >&2; then
    echo "build: errors or undefined symbols in out/build-$node.log" >&2
    exit 1
fi
