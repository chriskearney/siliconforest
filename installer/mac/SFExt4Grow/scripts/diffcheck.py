#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Block-level checks of one grow (test oracle side; reads images only).

    diffcheck.py ORIGINAL GROWN --map WRITE_MAP [--reference OTHER_GROWN] [--root-json root.json]

1. Every block of the original filesystem that differs in GROWN is one sf-ext4grow says it wrote, and
   a "fresh" write only ever lands on a block that was free before (checked by the grower; here we
   check that no unlisted block changed).
2. With --root-json: the firmware and receipt slots are byte-identical and no write touched them.
3. With --reference (resize2fs's result from the same original): which written blocks differ.
Prints one JSON object; exits 1 if 1 or 2 fails.
"""
import argparse, json, sys

BS = 4096

def blocks_of(path):
    with open(path, "rb") as f:
        f.seek(1024 + 4)
        lo = int.from_bytes(f.read(4), "little")
        f.seek(1024 + 0x150)
        hi = int.from_bytes(f.read(4), "little")
    return lo | hi << 32

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("original"); ap.add_argument("grown")
    ap.add_argument("--map", required=True); ap.add_argument("--reference"); ap.add_argument("--root-json")
    a = ap.parse_args()
    written = {}
    for line in open(a.map):
        if not line.strip():
            continue
        start, count, phase, what = line.rstrip("\n").split("\t", 3)
        for b in range(int(start), int(start) + int(count)):
            written[b] = phase
    old_blocks = blocks_of(a.original)
    out = {"old_blocks": old_blocks, "new_blocks": blocks_of(a.grown), "written_blocks": len(written)}
    changed, unlisted = [], []
    with open(a.original, "rb") as fo, open(a.grown, "rb") as fg:
        chunk = 256
        for base in range(0, old_blocks, chunk):
            n = min(chunk, old_blocks - base)
            x, y = fo.read(n * BS), fg.read(n * BS)
            if x == y:
                continue
            for i in range(n):
                if x[i * BS:(i + 1) * BS] != y[i * BS:(i + 1) * BS]:
                    changed.append(base + i)
                    if base + i not in written:
                        unlisted.append(base + i)
    out["changed_in_old_range"] = len(changed)
    out["changed_by_phase"] = {p: sum(1 for b in changed if written.get(b) == p) for p in ("fresh", "commit", "superblock")}
    out["unlisted_changes"] = unlisted[:20]
    ok = not unlisted
    if a.root_json:
        info = json.load(open(a.root_json))
        slots = {}
        for key in ("firmware_slot", "receipt_slot"):
            s = info[key]
            first, last = s["offset"] // BS, (s["offset"] + s["bytes"] - 1) // BS
            touched = [b for b in written if first <= b <= last]
            with open(a.original, "rb") as fo, open(a.grown, "rb") as fg:
                fo.seek(s["offset"]); fg.seek(s["offset"])
                same = fo.read(s["bytes"]) == fg.read(s["bytes"])
            slots[key] = {"offset": s["offset"], "bytes": s["bytes"], "identical": same, "writes_inside": len(touched)}
            ok = ok and same and not touched
        out["slots"] = slots
    if a.reference:
        diff = []
        with open(a.grown, "rb") as fg, open(a.reference, "rb") as fr:
            for b in sorted(set(written) | set(changed)):
                fg.seek(b * BS); fr.seek(b * BS)
                if fg.read(BS) != fr.read(BS):
                    diff.append(b)
        out["differs_from_reference"] = {"count": len(diff), "blocks": diff[:40]}
    out["ok"] = ok
    print(json.dumps(out, indent=1))
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
