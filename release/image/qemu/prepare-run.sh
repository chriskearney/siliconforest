#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# The release root in QEMU (arm64 virt, TCG): a writable copy of the recipe's `qemu` disk with the
# QEMU desktop loop's own session (qemu-dev/guest: CPU renderer on ramfb, USB HID through the SFHID
# nodes) instead of the M1's (org.siliconforest.desktop drives the M1's display hardware), and
# sf-image-check started beside the desktop. Written with debugfs into the copy; nothing is mounted,
# the Nix output is not touched.
#   prepare-run.sh <qemu disk from release/image.nix> <run directory> [desktop seconds, default 900]
# Then: python3 integrations/siliconforest/qemu-dev/qd_run.py --image <run>/disk.img --out <run>/out \
#         --timeout 7200 --input-seen QDDESK_INPUT
set -eu
src=$1; run=$2; seconds=${3:-900}
here=$(cd "$(dirname "$0")" && pwd)
guest=$here/../../../integrations/siliconforest/qemu-dev/guest
mkdir -p "$run"; rm -f "$run/disk.img"
cp --reflink=auto "$src" "$run/disk.img"; chmod 644 "$run/disk.img"
sed -e "s/@SECONDS@/$seconds/g" -e 's/@AUTOPILOT@/1/g' -e 's/@STATS@/1/g' -e 's/@SOUND@/0/g' -e 's/@RENDERER@/cpu/g' \
    -e 's/@TERMINALS@/1/g' -e 's/@FETCH@/0/g' -e 's/@PERSIST@/0/g' -e 's/@SCALE@/1/g' -e 's/@THEME@/sf-canopy/g' \
    -e 's/@ONLY@/settle/g' -e 's|@ENV@|( sleep 240; sh /usr/libexec/sf-image-check ) \&|' \
    "$guest/qemu-desktop-session.in" > "$run/qemu-desktop-session"
! grep -q '@[A-Z]*@' "$run/qemu-desktop-session"
start=$(sfdisk --json "$run/disk.img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][1]["start"])')
t="$run/disk.img?offset=$((start * 512))"
put() {  # <source> <path> <mode>
    printf 'write %s %s\nsif %s mode 0100%s\nsif %s uid 0\nsif %s gid 0\n' "$1" "$2" "$2" "$3" "$2" "$2"
}
{
    echo 'rm /System/Library/LaunchDaemons/org.siliconforest.desktop.plist'
    put "$run/qemu-desktop-session" /usr/bin/qemu-desktop-session 755
    put "$guest/org.siliconforest.qemu-desktop.plist" /System/Library/LaunchDaemons/org.siliconforest.qemu-desktop.plist 644
    put "$here/sf-image-check" /usr/libexec/sf-image-check 755
} | debugfs -w -f - "$t" > "$run/debugfs.log" 2>&1
e2fsck -fn "$t" > "$run/fsck.log" 2>&1 || { echo "e2fsck after preparing:"; tail "$run/fsck.log"; exit 1; }
echo "prepared $run/disk.img"
