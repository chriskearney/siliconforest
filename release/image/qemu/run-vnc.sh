#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# run-vnc.sh <run directory> [timeout seconds] [text to type]: boot <run>/disk.img (prepare-run.sh) under QEMU with its
# VNC server on a Unix socket, and save a picture of the guest's screen every 30 s (<run>/shots/NNN.ppm,
# vnc-shot.py). No QMP screen dump is used: on this host it hung QEMU while the compositor drew, and the
# desktop's own screencapture ended the compositor with SIGBUS on QEMU's framebuffer once (run 7).
# With a text: TYPE_AFTER (default 60) seconds after the desktop's first frame (WMSCALE on the console) it is typed, with Return,
# on the guest's emulated USB keyboard through the same VNC server (vnc-shot.py --type).
# Four vCPUs. The console and result.json: <run>/out (qemu-dev/qd_run.py). QD_RUN: another command for
# qd_run.py, e.g. the flake's pinned QEMU and firmware (result-runner/bin/siliconforest-qemu); by default
# qd_run.py runs with the host's qemu-system-aarch64 and the firmware path QD_AAVMF names.
set -eu
run=$(cd "$1" && pwd); timeout=${2:-5400}; text=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
qd=$here/../../../integrations/siliconforest/qemu-dev/qd_run.py
sock=$run/vnc.sock; rm -f "$sock"
python3 -I "$here/vnc-shot.py" "$sock" "$run/shots" --every 30 > "$run/vnc-shot.log" 2>&1 &
shooter=$!
typist=
if [ -n "$text" ]; then
    ( until grep -aq 'WMSCALE initial' "$run/out/serial.log" 2>/dev/null; do sleep 5; done; sleep ${TYPE_AFTER:-60}
      python3 -I "$here/vnc-shot.py" "$sock" --type "$text" && echo "typed at $(date -u +%T)" ) > "$run/type.log" 2>&1 &
    typist=$!
fi
trap 'kill $shooter $typist 2>/dev/null || true' EXIT
QD_NO_SHOTS=1 ${QD_RUN:-python3 -I $qd} --image "$run/disk.img" --out "$run/out" --timeout "$timeout" --smp 4 \
    --input-seen QDDESK_INPUT --shot-every 0 --qemu-arg=-vnc --qemu-arg="unix:$sock" || true
