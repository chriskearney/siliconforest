#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# The release root in QEMU (arm64 virt, TCG): a writable copy of the recipe's `qemu` disk with the
# QEMU desktop loop's own session (qemu-dev/guest: CPU renderer on ramfb, USB HID through the SFHID
# nodes) instead of the M1's (org.siliconforest.desktop drives the M1's display hardware), and
# sf-image-check started beside the desktop. Written with debugfs into the copy; nothing is mounted,
# the Nix output is not touched.
#   prepare-run.sh <qemu disk from release/image.nix> <run directory> [desktop seconds, default 900]
#                  [autopilot phases, default settle,type]
# Then: QD_NO_SHOTS=1 python3 integrations/siliconforest/qemu-dev/qd_run.py --image <run>/disk.img \
#         --out <run>/out --timeout 7200 --smp 4 --input-seen QDDESK_INPUT --shot-every 0
#       (QMP screen dumps hung QEMU on this host while the compositor drew), and afterwards
#       extract-shots.sh <run>: the desktop's own captures out of the disk copy
set -eu
src=$1; run=$2; seconds=${3:-900}; only=${4:-settle,type}
here=$(cd "$(dirname "$0")" && pwd)
guest=$here/../../../integrations/siliconforest/qemu-dev/guest
mkdir -p "$run"; rm -f "$run/disk.img"
cp --reflink=auto "$src" "$run/disk.img"; chmod 644 "$run/disk.img"
# the session: the QEMU loop's template with this run's values; @ENV@ (shell run before the compositor
# starts) gives the managed application and the autopilot longer to start under emulation (the
# compositor's defaults, 25 s and 15 s, are for real hardware), starts the dock as sf-session does on
# the M1, takes a picture of the composed screen every 30 s with the desktop's own screencapture
# (into /private/var/tmp/sfshots, read out of the disk afterwards), and runs sf-image-check beside it all
python3 - "$guest/qemu-desktop-session.in" "$run/qemu-desktop-session" "$seconds" "$only" <<'PY'
import sys
src, dst, seconds, only = sys.argv[1:5]
env = """export CHONKSTEP_DARWIN_APP_READY_SECONDS=180 CHONKSTEP_DARWIN_AUTOPILOT_ARM_SECONDS=240
( n=0; while [ ! -S "$runtime/wayland-0" ] && [ $n -lt 900 ]; do sleep 1; n=$((n+1)); done; sleep 1
  XDG_STATE_HOME=$state HOME=/var/root LANG=en_US.UTF-8 exec /usr/bin/chonkstep-dock > /var/log/chonkstep-dock.log 2>&1 ) &
( mkdir -p /private/var/tmp/sfshots; i=0; while [ $i -lt 60 ]; do sleep 30; i=$((i+1))
  /usr/bin/chonkstep-darwin-desktop --screencapture /private/var/tmp/sfshots/s$(printf %03d $i).png > /dev/null 2>&1; done ) &
( sleep 240; sh /usr/libexec/sf-image-check ) &"""
tok = dict(SECONDS=seconds, AUTOPILOT='1', STATS='1', SOUND='0', RENDERER='cpu', TERMINALS='1', FETCH='0',
           PERSIST='0', SCALE='1', THEME='sf-canopy', ONLY=only, ENV=env)
s = open(src).read()
for k, v in tok.items():
    s = s.replace('@%s@' % k, v)
open(dst, 'w').write(s)
PY
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
