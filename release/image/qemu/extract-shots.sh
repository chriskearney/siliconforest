#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# extract-shots.sh <run directory>: after a QEMU run of prepare-run.sh's disk, copy the session's
# records and the dock's log out of the disk copy (debugfs, read only).
set -eu
run=$1
disk=$run/disk.img
# The public runner keeps the base immutable and writes a per-run overlay.
if [ -f "$run/out/system-overlay.qcow2" ]; then
    disk=$run/inspect.img
    qemu-img convert -f qcow2 -O raw "$run/out/system-overlay.qcow2" "$disk"
fi
start=$(sfdisk --json "$disk" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][1]["start"])')
t="$disk?offset=$((start * 512))"
mkdir -p "$run/records"
debugfs -R "rdump /private/var/run/qemu-desktop $run/records" "$t" 2>/dev/null || true
debugfs -R "dump /var/log/chonkstep-dock.log $run/chonkstep-dock.log" "$t" 2>/dev/null || true
