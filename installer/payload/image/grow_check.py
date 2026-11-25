#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Prove that an installer root grows in place without moving its slots (PAYLOAD.md section 6).

    grow_check.py INSTALLER_ROOT_DIR PARTITION_BYTES [--keep]

Copies the installer root into a sparse file of PARTITION_BYTES (standing in for the raw root
partition after S47), runs resize2fs then e2fsck -fn (the test oracle; S48 will run sf-ext4grow,
see EXT4GROW.md), and checks: the filesystem fills the partition to the block, e2fsck is clean,
both slots are still one initialised extent at the offsets root.json records, and their bytes are
unchanged. Works on an ordinary file only. This script is unchanged as a tool; only this wording
was updated when the resize2fs-in-the-dmg plan was retired.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_root import BLOCK, PrepareError, one_extent, run, superblock  # noqa: E402


def grow(root_dir, partition_bytes, keep=None):
    info = json.loads((root_dir / "root.json").read_text())
    src = root_dir / info["image"]
    if partition_bytes < info["image_bytes"]:
        raise PrepareError("partition is smaller than the image")
    if partition_bytes > info["grow"]["max_bytes"]:
        raise PrepareError("partition exceeds what the reserved GDT blocks can address")
    with tempfile.TemporaryDirectory(dir=keep or None) as tmp:
        part = Path(tmp) / "root-partition.raw"
        subprocess.run(["cp", "--sparse=always", str(src), str(part)], check=True)
        with part.open("r+b") as f:
            f.truncate(partition_bytes)
        before = {}
        with part.open("rb") as f:
            for key in ("firmware_slot", "receipt_slot"):
                f.seek(info[key]["offset"])
                before[key] = f.read(info[key]["bytes"])
        run("e2fsck", "-fn", str(part))
        run("resize2fs", str(part))           # no size: fill the device (the partition)
        fsck = run("e2fsck", "-fn", str(part))
        sb = superblock(part)
        blocks = int(sb["Block count"])
        if blocks != partition_bytes // BLOCK:
            raise PrepareError(f"filesystem has {blocks} blocks, partition holds {partition_bytes // BLOCK}")
        with part.open("rb") as f:
            for key in ("firmware_slot", "receipt_slot"):
                slot = info[key]
                if one_extent(part, slot["path"], slot["bytes"]) != slot["offset"]:
                    raise PrepareError(f"{key} moved during the grow")
                f.seek(slot["offset"])
                if f.read(slot["bytes"]) != before[key]:
                    raise PrepareError(f"{key} bytes changed during the grow")
        if sb["Filesystem UUID"] != info["fs_uuid"]:
            raise PrepareError("filesystem UUID changed")
        result = {"partition_bytes": partition_bytes, "blocks": blocks, "free_blocks": int(sb["Free blocks"]),
                  "inodes": int(sb["Inode count"]), "slots_unchanged": True, "e2fsck": fsck.strip().splitlines()[-1]}
        if keep:
            shutil.move(str(part), str(Path(keep) / "root-partition.raw"))
        return result


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("root_dir", type=Path)
    ap.add_argument("partition_bytes", type=int)
    ap.add_argument("--keep", type=Path)
    a = ap.parse_args()
    try:
        print(json.dumps(grow(a.root_dir, a.partition_bytes, a.keep), indent=2))
    except PrepareError as e:
        print(f"grow_check: {e}", file=sys.stderr)
        sys.exit(1)
