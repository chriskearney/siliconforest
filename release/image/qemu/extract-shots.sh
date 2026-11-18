#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# extract-shots.sh <run directory>: after a QEMU run of prepare-run.sh's disk, copy the session's
# records and the dock's log out of the disk copy (debugfs, read only).
set -eu
run=$1
start=$(sfdisk --json "$run/disk.img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][1]["start"])')
t="$run/disk.img?offset=$((start * 512))"
mkdir -p "$run/records"
debugfs -R "rdump /private/var/run/qemu-desktop $run/records" "$t" 2>/dev/null || true
debugfs -R "dump /var/log/chonkstep-dock.log $run/chonkstep-dock.log" "$t" 2>/dev/null || true
