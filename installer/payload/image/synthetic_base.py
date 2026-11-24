#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""A small stand-in for release/image.nix's rootfs output, for tests and CI rehearsals.

    synthetic_base.py OUT_DIR [--mib 64]

Writes OUT_DIR/siliconforest-root.ext4 and OUT_DIR/root.manifest.tsv. The filesystem has the
release root's features (64bit, flex_bg, resize_inode, metadata_csum, 4 KiB blocks), its label,
and the files prepare_root.py edits: the firstboot job and /usr/libexec/sf-firstboot. It contains
no SiliconForest binaries; it is never a release.
"""

import argparse
import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_root import tool  # noqa: E402

FEATURES = "has_journal,ext_attr,resize_inode,dir_index,filetype,extent,64bit,flex_bg,sparse_super,large_file,huge_file,dir_nlink,extra_isize,metadata_csum,metadata_csum_seed,^orphan_file"
UUID = "37215ab4-59b9-8afb-ab76-394c5ee48edf"
JOB = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>org.siliconforest.firstboot</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>/usr/libexec/sf-firstboot</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
"""
FIRSTBOOT = "#!/bin/sh\n# synthetic stand-in for the release's sf-firstboot\necho synthetic-firstboot >> /var/log/sf-firstboot.log\nexit 0\n"


def build(out, mib=64):
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tree = Path(tmp) / "tree"
        files = {
            "System/Library/LaunchDaemons/org.siliconforest.firstboot.plist": (JOB, 0o644),
            "usr/libexec/sf-firstboot": (FIRSTBOOT, 0o755),
            "etc/passwd": ("root:*:0:0:System Administrator:/var/root:/bin/zsh\nsf:*:501:20:SiliconForest User:/Users/sf:/bin/zsh\n", 0o644),
            "usr/share/sf-synthetic/filler.bin": (os.urandom(1) * 0 + bytes(range(256)) * 4096, 0o644),
        }
        for d in ("private/var/db", "private/var/run", "var/log", "Library/Firmware/apple", "Library/Firmware/brcm", "Users/sf"):
            (tree / d).mkdir(parents=True, exist_ok=True)
        rows = []
        for rel, (data, mode) in files.items():
            p = tree / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            b = data.encode() if isinstance(data, str) else data
            p.write_bytes(b)
            p.chmod(mode)
            rows.append(f"/{rel}\tf\t{mode:04o}\t0\t0\t{len(b)}\t{hashlib.sha256(b).hexdigest()}")
        image = out / "siliconforest-root.ext4"
        if image.exists():
            image.unlink()
        env = {**os.environ, "E2FSPROGS_FAKE_TIME": "1"}
        subprocess.run([tool("mke2fs"), "-q", "-F", "-t", "ext4", "-b", "4096", "-O", FEATURES, "-L", "SiliconForest",
                        "-U", UUID, "-E", "root_owner=0:0,hash_seed=" + UUID + ",lazy_itable_init=0", "-N", "4096",
                        "-d", str(tree), str(image), f"{mib}M"], check=True, env=env)
    (out / "root.manifest.tsv").write_text("# path\ttype\tmode\tuid\tgid\tsize\tsha256 or link target\n" + "\n".join(sorted(rows)) + "\n")
    return image


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--mib", type=int, default=64)
    a = ap.parse_args()
    print(build(a.out, a.mib))
