# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Prepare and verify an installer root using only an ordinary image file."""

import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

BLOCK = 4096
SLOT_SIZE = 32 << 20
ROOT_BYTES = 4 << 30
SLOT = "/private/var/db/sf-firmware-slot"
MAGIC = b"SFFWSLOT1\n"


def run(*args, cwd):
    return subprocess.check_output(args, cwd=cwd, text=True)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(base, output):
    raw = output / "siliconforest-root.ext4"
    base_manifest = (base / "root.manifest.tsv").read_text().splitlines()
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        image = work / "root.ext4"
        run("cp", "--sparse=always", str(base / raw.name), image.name, cwd=work)
        image.chmod(0o644)
        if image.stat().st_size > ROOT_BYTES:
            raise ValueError("base root exceeds the fixed installer partition size")
        run("resize2fs", image.name, "4G", cwd=work)
        if image.stat().st_size != ROOT_BYTES:
            raise ValueError("unexpected resized root size")

        sources = Path(__file__).resolve().parent
        entries = [
            (SLOT, "slot", 0o600, MAGIC + bytes(SLOT_SIZE - len(MAGIC))),
            ("/usr/libexec/sf-installer-firstboot", "firstboot", 0o755, (sources / "firstboot").read_bytes()),
            ("/usr/libexec/sf-unpack-firmware", "unpacker", 0o644, (sources / "unpack-firmware.pl").read_bytes()),
        ]
        for target, local, mode, data in entries:
            # Nonzero input forces debugfs to allocate initialized blocks, even
            # though the shipped slot is zero-filled after its magic.
            work.joinpath(local).write_bytes(b"\xff" * SLOT_SIZE if target == SLOT else data)
            run("debugfs", "-w", "-R", f"write {local} {target}", image.name, cwd=work)
            run("debugfs", "-w", "-R", f"set_inode_field {target} mode 0{0o100000 | mode:o}", image.name, cwd=work)

        extents = run("debugfs", "-R", f"extents {SLOT}", image.name, cwd=work)
        blocks = SLOT_SIZE // BLOCK
        rows = extents.splitlines()[1:]
        extent = re.fullmatch(r"\s*0/\s*0\s+1/\s*1\s+0\s*-\s*(\d+)\s+(\d+)\s*-\s*(\d+)\s+(\d+)\s*", rows[0]) if len(rows) == 1 else None
        if not extent:
            raise ValueError(f"firmware slot is not one initialized extent:\n{extents}")
        last, first_physical, last_physical, length = map(int, extent.groups())
        offset = first_physical * BLOCK
        if (last != blocks - 1 or length != blocks or last_physical - first_physical + 1 != blocks
                or first_physical == 0 or offset + SLOT_SIZE > ROOT_BYTES):
            raise ValueError("firmware extent outside expected root bounds")
        with image.open("r+b") as fd:
            fd.seek(offset)
            if fd.read(SLOT_SIZE) != b"\xff" * SLOT_SIZE:
                raise ValueError("physical slot bytes do not match the allocated file")
            fd.seek(offset)
            fd.write(entries[0][3])

        job = "/System/Library/LaunchDaemons/org.siliconforest.firstboot.plist"
        run("debugfs", "-R", f"dump {job} firstboot.plist", image.name, cwd=work)
        plist = work.joinpath("firstboot.plist")
        original = plist.read_bytes()
        command = b"<string>/usr/libexec/sf-firstboot</string>"
        if original.count(command) != 1:
            raise ValueError("firstboot plist command is missing or ambiguous")
        new_plist = original.replace(command, b"<string>/usr/libexec/sf-installer-firstboot</string>")
        plist.write_bytes(new_plist)
        run("debugfs", "-w", "-R", f"rm {job}", image.name, cwd=work)
        run("debugfs", "-w", "-R", f"write {plist.name} {job}", image.name, cwd=work)
        entries.append((job, plist.name, 0o644, new_plist))

        replacements = {}
        for target, _, mode, data in entries:
            run("debugfs", "-R", f"dump {target} readback", image.name, cwd=work)
            stat = run("debugfs", "-R", f"stat {target}", image.name, cwd=work)
            if (work.joinpath("readback").read_bytes() != data or
                    not re.search(rf"Mode:\s+{mode:04o}\b", stat) or
                    not re.search(r"User:\s+0\s+Group:\s+0\b", stat)):
                raise ValueError(f"image readback failed for {target}")
            replacements[target] = f"{target}\tf\t{mode:04o}\t0\t0\t{len(data)}\t{digest(data)}"
        run("e2fsck", "-fn", image.name, cwd=work)
        run("cp", "--reflink=auto", "--sparse=always", image.name, str(raw), cwd=work)

    unchanged = [row for row in base_manifest[1:] if row.split("\t", 1)[0] not in replacements]
    rows = sorted(unchanged + list(replacements.values()), key=lambda row: row.split("\t", 1)[0])
    (output / "root.manifest.tsv").write_text("\n".join([base_manifest[0], *rows, ""]))
    print(offset)


if __name__ == "__main__":
    os.environ["E2FSPROGS_FAKE_TIME"] = "1"
    prepare(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
