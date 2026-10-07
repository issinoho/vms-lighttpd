#!/usr/bin/env bash
# push.sh <node> - upload the prepared tree (staging/) to <node>'s work directory.
#
# Uploads what the VMS build needs (src with ls-hpack, vmsport) into
# <workdir>/<name>-<version with dots as underscores>, e.g. [.LIGHTTPD-1_4_85].
# Only files whose content changed since the last push to that node are sent,
# so BUILD.COM sees new dates only on what really changed.  Set PUSH_ALL=1
# to send everything.  Re-pushing makes new file versions; build.sh purges.
set -euo pipefail
export LC_ALL=C   # sort and comm must agree on collation

top=$(cd "$(dirname "$0")/.." && pwd)
node=${1:?usage: push.sh <node>}
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
stage=$top/staging/$name
remote=$(echo "$name" | tr . _)
[ -f "$stage/vmsport/build.com" ] || { echo "push: run tools/prepare.sh first" >&2; exit 1; }

pack=$top/cache/push-$name-$node
rm -rf "$pack"; mkdir -p "$pack/$remote"
mkdir -p "$pack/$remote/src"
(cd "$stage/src" && find . -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' \) -print0 |
    xargs -0 cp -t "$pack/$remote/src/")
cp -a "$stage/src/ls-hpack" "$stage/src/compat" "$pack/$remote/src/"
cp -a "$stage/vmsport" "$pack/$remote/"
# Host leftovers and files VMS never builds.
find "$pack/$remote" \( -name '*.o' -o -name 'lemon.c' -o -name 'lempar.c' \) -delete

echo "push: -> $node:[.$(echo "$remote" | tr a-z A-Z)]"
read -r _ _ HOST PORT USER WORKDIR SFTPDIR < <(awk -v n="$node" '$1==n' "$top/tools/nodes.conf")
manifest=$top/cache/pushed-$name-$node.sha
[ "${PUSH_ALL:-}" = 1 ] && rm -f "$manifest"
touch "$manifest"
(cd "$pack" && find "$remote" -type f -print0 | sort -z | xargs -0 sha256sum) > "$pack.sha"
changed=$(comm -23 <(awk '{print $2" "$1}' "$pack.sha" | sort) \
                   <(awk '{print $2" "$1}' "$manifest" | sort) | awk '{print $1}')
echo "push: $(echo "$changed" | grep -c . || true) changed of $(wc -l < "$pack.sha") files"
batch=$pack/sftp.batch
{
    echo "cd $SFTPDIR"
    (cd "$pack" && find "$remote" -type d) | sed 's/^/-mkdir /'
    for f in $changed; do echo "put $pack/$f $f"; done
} > "$batch"
sftp -P "$PORT" -i "${VMS_SSH_KEY:-$HOME/.ssh/vms_ed25519}" -o BatchMode=yes -b "$batch" "$USER@$HOST" \
    2>&1 >/dev/null | grep -vE '^ *Welcome to|^ *$|^remote mkdir .*Failure' >&2 || true
cp "$pack.sha" "$manifest"
echo "push: done"
