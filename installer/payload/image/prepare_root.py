#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Turn a SiliconForest release root (release/image.nix's rootfs output) into the installer's root.

    prepare_root.py BASE_DIR OUT_DIR [--slack-mib N]

BASE_DIR holds siliconforest-root.ext4 and root.manifest.tsv. OUT_DIR receives:

    siliconforest-root.ext4   the installer root (the base is never modified)
    root.manifest.tsv         the base manifest with the entries this script wrote
    root.json                 what the installer and the release manifest need: size, sha256,
                              fs UUID, both slots' physical offsets, the growth limit

What it adds (docs/installer/PAYLOAD.md section 3):
- /private/var/db/sf-firmware-slot   32 MiB, one contiguous initialised extent, header SFFWSLOT1
- /private/var/db/sf-boot-receipt    64 KiB, one contiguous initialised extent, all zeros (the
                                     installer writes the SFRCPT1 header and install ID at S52)
- /usr/libexec/sf-installer-firstboot, sf-boot-receipt, sf-unpack-firmware
- org.siliconforest.firstboot runs sf-installer-firstboot (which ends by running sf-firstboot)
- with --sap-bin: SAP, the system updater (sap/tools/sap_image.py, docs/sap/IMAGE.md): its binaries,
  boot jobs and /etc/sap.conf, the image's own SAP channel (--sap-channel, root packages) and the
  installed database seeded from it (/private/var/db/sap)

Only ordinary image files are touched, through debugfs. Nothing here opens a device. Each
written entry is read back, slot extents are checked from the extent tree and from the raw
bytes at the physical offset, and e2fsck -fn must be clean at the end.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BLOCK = 4096
FW_SLOT = "/private/var/db/sf-firmware-slot"
FW_SLOT_BYTES = 32 << 20
FW_MAGIC = b"SFFWSLOT1\n"
RECEIPT_SLOT = "/private/var/db/sf-boot-receipt"
RECEIPT_SLOT_BYTES = 64 << 10
FIRSTBOOT_JOB = "/System/Library/LaunchDaemons/org.siliconforest.firstboot.plist"
HERE = Path(__file__).resolve().parent
SAP_TOOLS = HERE.parents[2] / "sap" / "tools"
TOOLS = ["debugfs", "e2fsck", "resize2fs", "dumpe2fs"]


class PrepareError(Exception):
    pass


def tool(name):
    for d in os.environ.get("PATH", "").split(os.pathsep) + ["/sbin", "/usr/sbin"]:
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    raise PrepareError(f"{name} not found (e2fsprogs is needed on the build host)")


def run(*args, cwd=None, ok=(0,)):
    p = subprocess.run([tool(args[0]), *args[1:]], cwd=cwd, capture_output=True, text=True,
                       env={**os.environ, "E2FSPROGS_FAKE_TIME": "1", "LC_ALL": "C"})
    if p.returncode not in ok:
        raise PrepareError(f"{' '.join(args)} failed ({p.returncode}):\n{p.stdout}{p.stderr}")
    return p.stdout


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def superblock(image):
    out = run("dumpe2fs", "-h", str(image))
    fields = {}
    for line in out.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fields[k.strip()] = v.strip()
    return fields


def one_extent(image, path, nbytes):
    """Physical byte offset of a file that must be exactly one initialised extent."""
    out = run("debugfs", "-R", f"extents {path}", str(image))
    rows = [r for r in out.splitlines()[1:] if r.strip()]
    blocks = nbytes // BLOCK
    m = None
    if len(rows) == 1:
        m = re.fullmatch(r"\s*0/\s*0\s+1/\s*1\s+0\s*-\s*(\d+)\s+(\d+)\s*-\s*(\d+)\s+(\d+)\s*(\S*)\s*", rows[0])
    if not m:
        raise PrepareError(f"{path} is not one extent:\n{out}")
    last, first_phys, last_phys, length, flags = m.groups()
    last, first_phys, last_phys, length = map(int, (last, first_phys, last_phys, length))
    if "Uninit" in flags:
        raise PrepareError(f"{path} extent is unwritten (uninitialised)")
    if last != blocks - 1 or length != blocks or last_phys - first_phys + 1 != blocks or first_phys == 0:
        raise PrepareError(f"{path} extent has the wrong shape: {rows[0]}")
    return first_phys * BLOCK


def exists(image, path):
    out = run("debugfs", "-R", f"stat {path}", str(image), ok=(0, 1))
    return "Inode:" in out


def ensure_dir(image, path):
    """mkdir -p inside the image (debugfs mkdir on an existing name corrupts the directory tree)."""
    cur = ""
    for part in [p for p in path.split("/") if p]:
        cur += "/" + part
        if not exists(image, cur):
            run("debugfs", "-w", "-R", f"mkdir {cur}", str(image))


def write_entry(image, work, target, data, mode, alloc_fill=None):
    local = work / ("w" + hashlib.sha1(target.encode()).hexdigest()[:12])
    # Nonzero input makes debugfs allocate initialised blocks (a zero buffer would become a hole).
    local.write_bytes(alloc_fill * len(data) if alloc_fill else data)
    ensure_dir(image, os.path.dirname(target))
    if exists(image, target):
        run("debugfs", "-w", "-R", f"rm {target}", str(image))
    run("debugfs", "-w", "-R", f"write {local} {target}", str(image))
    for field, value in (("mode", f"0{0o100000 | mode:o}"), ("uid", "0"), ("gid", "0")):
        run("debugfs", "-w", "-R", f"set_inode_field {target} {field} {value}", str(image))
    local.unlink()


def readback(image, work, target, data, mode):
    out = work / "readback"
    run("debugfs", "-R", f"dump {target} {out}", str(image))
    stat = run("debugfs", "-R", f"stat {target}", str(image))
    if out.read_bytes() != data:
        raise PrepareError(f"readback of {target} differs")
    if not re.search(rf"Mode:\s+0?{mode:04o}\b", stat) or not re.search(r"User:\s+0\s+Group:\s+0\b", stat):
        raise PrepareError(f"{target} has the wrong mode or owner:\n{stat.splitlines()[:4]}")
    out.unlink()


def add_dir_rows(manifest_rows, rows):
    """Rows for the directories ensure_dir made for new entries (0755, root)."""
    known = {r.split("\t", 1)[0] for r in manifest_rows[1:]} | set(rows)
    for target in list(rows):
        d = os.path.dirname(target)
        while d not in ("", "/") and d not in known:
            rows[d] = f"{d}\td\t0755\t0\t0\t0\t-"
            known.add(d)
            d = os.path.dirname(d)


def prepare(base, output, slack_mib=0, sap=None):
    src = base / "siliconforest-root.ext4"
    if not src.is_file():
        raise PrepareError(f"{src} missing")
    manifest_rows = (base / "root.manifest.tsv").read_text().splitlines()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as tmp:
        work = Path(tmp)
        image = work / "root.ext4"
        subprocess.run(["cp", "--sparse=always", str(src), str(image)], check=True)
        image.chmod(0o644)
        sb = superblock(image)
        if int(sb["Block size"]) != BLOCK:
            raise PrepareError("block size must be 4096")
        for feature in ("resize_inode", "extent", "64bit", "flex_bg"):
            if feature not in sb["Filesystem features"].split():
                raise PrepareError(f"base root lacks {feature}; it could not be grown in place")
        if slack_mib:
            new_blocks = int(sb["Block count"]) + slack_mib * (1 << 20) // BLOCK
            run("e2fsck", "-fy", str(image), ok=(0, 1))
            run("resize2fs", str(image), f"{new_blocks}")

        job = run("debugfs", "-R", f"cat {FIRSTBOOT_JOB}", str(image))
        command = "<string>/usr/libexec/sf-firstboot</string>"
        if job.count(command) != 1:
            raise PrepareError("the base root's firstboot job does not run /usr/libexec/sf-firstboot exactly once")
        job_new = job.replace(command, "<string>/usr/libexec/sf-installer-firstboot</string>").encode()

        fw_slot = FW_MAGIC + bytes(FW_SLOT_BYTES - len(FW_MAGIC))
        receipt_slot = bytes(RECEIPT_SLOT_BYTES)
        entries = [
            (FW_SLOT, fw_slot, 0o600, b"\xff"),
            (RECEIPT_SLOT, receipt_slot, 0o600, b"\xff"),
            ("/usr/libexec/sf-installer-firstboot", (HERE / "sf-installer-firstboot").read_bytes(), 0o755, None),
            ("/usr/libexec/sf-boot-receipt", (HERE / "sf-boot-receipt").read_bytes(), 0o755, None),
            ("/usr/libexec/sf-unpack-firmware", (HERE / "sf-unpack-firmware").read_bytes(), 0o755, None),
            (FIRSTBOOT_JOB, job_new, 0o644, None),
        ]
        if sap:
            sys.path.insert(0, str(SAP_TOOLS))
            import sap_image  # noqa: E402
            entries += [(t, d, m, None) for t, d, m in sap_image.files(sap["bin"], sap.get("manifest_url"), sap.get("host_binaries", False))]
        for target, data, mode, fill in entries:
            write_entry(image, work, target, data, mode, fill)

        offsets = {}
        with image.open("r+b") as fd:
            for target, data, _, fill in entries:
                if not fill:
                    continue
                off = one_extent(image, target, len(data))
                fd.seek(off)
                if fd.read(len(data)) != fill * len(data):
                    raise PrepareError(f"bytes at {target}'s physical offset are not the file's")
                fd.seek(off)
                fd.write(data)
                offsets[target] = off
            fd.flush()
            os.fsync(fd.fileno())

        rows = {}
        for target, data, mode, _ in entries:
            readback(image, work, target, data, mode)
            rows[target] = f"{target}\tf\t{mode:04o}\t0\t0\t{len(data)}\t{hashlib.sha256(data).hexdigest()}"
        add_dir_rows(manifest_rows, rows)
        if sap:
            # The image's channel is published from this very root, then the database is seeded
            # from it and written in (design 4.3): SAP starts with every file accounted for.
            header, body = manifest_rows[0], manifest_rows[1:]
            merged = sorted([r for r in body if r.split("\t", 1)[0] not in rows] + list(rows.values()), key=lambda r: r.split("\t", 1)[0])
            tsv = work / "root.manifest.tsv"
            tsv.write_text("\n".join([header, *merged, ""]))
            tree = work / "tree"
            tree.mkdir()
            run("debugfs", "-R", f"rdump / {tree}", str(image))
            db = sap_image.publish_and_seed(tree, tsv, sap["channel"], sap["release"], sap.get("sequence", 1), sap.get("key"))
            for target, data, mode in db:
                write_entry(image, work, target, data, mode)
            for target, data, mode in db:
                readback(image, work, target, data, mode)
                rows[target] = f"{target}\tf\t{mode:04o}\t0\t0\t{len(data)}\t{hashlib.sha256(data).hexdigest()}"
            shutil.rmtree(tree)
        add_dir_rows(manifest_rows, rows)
        fsck = run("e2fsck", "-fn", str(image))
        sb = superblock(image)
        final = output / "siliconforest-root.ext4"
        shutil.move(str(image), str(final))

    header, body = manifest_rows[0], manifest_rows[1:]
    body = [r for r in body if r.split("\t", 1)[0] not in rows] + list(rows.values())
    body.sort(key=lambda r: r.split("\t", 1)[0])
    (output / "root.manifest.tsv").write_text("\n".join([header, *body, ""]))

    size = final.stat().st_size
    # resize2fs can grow into the reserved GDT blocks without moving anything: the groups their
    # descriptors can address bound the size the installer may grow this root to.
    per_gdt_block = BLOCK // int(sb.get("Group descriptor size", "64"))
    groups = -(-int(sb["Block count"]) // int(sb["Blocks per group"]))
    gdt_blocks = -(-groups // per_gdt_block)
    max_groups = (gdt_blocks + int(sb.get("Reserved GDT blocks", "0"))) * per_gdt_block
    info = {
        "format": "siliconforest-installer-root/1",
        "image": final.name,
        "image_bytes": size,
        "image_sha256": sha256_file(final),
        "fs_uuid": sb["Filesystem UUID"],
        "fs_label": sb.get("Filesystem volume name", ""),
        "block_size": BLOCK,
        "features": sb["Filesystem features"].split(),
        "grow": {
            "method": "resize2fs-offline",
            "max_bytes": max_groups * int(sb["Blocks per group"]) * BLOCK,
            "reserved_gdt_blocks": int(sb.get("Reserved GDT blocks", "0")),
        },
        "firmware_slot": {"path": FW_SLOT, "offset": offsets[FW_SLOT], "bytes": FW_SLOT_BYTES,
                          "magic": FW_MAGIC.decode().strip()},
        "receipt_slot": {"path": RECEIPT_SLOT, "offset": offsets[RECEIPT_SLOT], "bytes": RECEIPT_SLOT_BYTES,
                         "magic": "SFRCPT1"},
        "e2fsck": fsck.strip().splitlines()[-1] if fsck.strip() else "",
        "base_sha256": sha256_file(src),
    }
    (output / "root.json").write_text(json.dumps(info, indent=2) + "\n")
    return info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("base", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--slack-mib", type=int, default=0, help="grow the base by this much before adding files")
    ap.add_argument("--sap-bin", type=Path, help="sap/tools/build_darwin.sh output: put SAP into the root")
    ap.add_argument("--sap-channel", type=Path, help="with --sap-bin: where the image's SAP channel is published")
    ap.add_argument("--sap-release", help="with --sap-bin: the channel's release (default: the base's image.json version)")
    ap.add_argument("--sap-sequence", type=int, default=1)
    ap.add_argument("--sap-key", type=Path, help="TEST-ONLY key for a rehearsal; default --unsigned (sign offline on the M3)")
    ap.add_argument("--sap-manifest-url", help="manifest_url written into /etc/sap.conf")
    ap.add_argument("--sap-host-binaries", action="store_true", help=argparse.SUPPRESS)  # synthetic tests only
    a = ap.parse_args(argv)
    sap = None
    if a.sap_bin:
        if not a.sap_channel:
            ap.error("--sap-bin needs --sap-channel")
        release = a.sap_release
        if not release and (a.base / "image.json").is_file():
            release = json.loads((a.base / "image.json").read_text()).get("version")
        if not release:
            ap.error("--sap-bin needs --sap-release (the base has no image.json)")
        sap = {"bin": a.sap_bin.resolve(), "channel": a.sap_channel.resolve(), "release": release, "sequence": a.sap_sequence,
               "key": a.sap_key.resolve() if a.sap_key else None, "manifest_url": a.sap_manifest_url, "host_binaries": a.sap_host_binaries}
    try:
        info = prepare(a.base.resolve(), a.output.resolve(), a.slack_mib, sap)
    except PrepareError as e:
        print(f"prepare_root: {e}", file=sys.stderr)
        return 1
    print(json.dumps({k: info[k] for k in ("image_bytes", "image_sha256", "firmware_slot", "receipt_slot")}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
