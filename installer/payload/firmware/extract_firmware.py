#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Extract a Mac's firmware from Apple's restore image, on a Mac (DESIGN.md D7, PAYLOAD.md section 8).

    extract_firmware.py --profile installer/profiles/J313.json --work DIR [--ipsw PATH_OR_URL]
                        [--names-out NAMES.tsv]

1. Opens the profile's restore image (default: its URL; only the needed byte ranges are fetched,
   and the remote size must equal the profile's) and reads BuildManifest.plist.
2. Picks the build identity the profile names (board, chip, device class, behaviour, variant)
   and checks the build number.
3. Streams that identity's BaseSystem dmg into DIR (CRC-32 and size checked) and attaches it
   read-only, without mounting it in Finder (hdiutil attach -readonly -nobrowse). It is a disk
   image; no disk of this Mac is touched.
4. Names the Wi-Fi firmware with the port of Asahi's collector (wifi.py) and keeps the files the
   profile's firmware items ask for.
5. Writes DIR/firmware-slot.bin (SFFWSLOT1 header + the tar sf-unpack-firmware accepts) and a
   names file: board, name, size, SHA-256. Detaches the image.

The firmware is Apple's: DIR is never committed or published, and nothing here uploads anything.
The names file holds names and hashes only; it is what a release's install.json carries so the
installer can check its own extraction before writing (S15).
"""

import argparse
import fnmatch
import hashlib
import io
import json
import os
import plistlib
import subprocess
import sys
import tarfile
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from remote_zip import HTTPSource, LocalSource, RemoteZip, ZipError  # noqa: E402
from wifi import WiFiFWCollection  # noqa: E402

SLOT_BYTES = 32 << 20
HEADER = 4096


class ExtractError(Exception):
    pass


def select_identity(manifest, ident):
    want = (ident["ap_board_id"].lower(), ident["ap_chip_id"].lower(), ident["device_class"],
            ident["restore_behavior"], ident["variant"])
    found = []
    for bi in manifest["BuildIdentities"]:
        got = (bi["ApBoardID"].lower(), bi["ApChipID"].lower(), bi["Info"]["DeviceClass"],
               bi["Info"]["RestoreBehavior"], bi["Info"]["Variant"])
        if got == want:
            found.append(bi)
    if len(found) != 1:
        raise ExtractError("expected one build identity for %s, found %d" % (want, len(found)))
    return found[0]


def slot_payload(files):
    """files: sorted [(name, bytes)]. Deterministic ustar; duplicates become hard links."""
    buf = io.BytesIO()
    seen = {}
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name, data in files:
            ti = tarfile.TarInfo(name)
            ti.mtime, ti.uid, ti.gid, ti.uname, ti.gname, ti.mode = 0, 0, 0, "", "", 0o644
            digest = hashlib.sha256(data).hexdigest()
            if digest in seen:
                ti.type, ti.linkname = tarfile.LNKTYPE, seen[digest]
                tar.addfile(ti)
            else:
                ti.size = len(data)
                seen[digest] = name
                tar.addfile(ti, io.BytesIO(data))
    payload = buf.getvalue()
    if len(payload) > SLOT_BYTES - HEADER:
        raise ExtractError("firmware payload does not fit the slot")
    head = b"SFFWSLOT1\nlength=%d\nsha256=%s\n" % (len(payload), hashlib.sha256(payload).hexdigest().encode())
    return head + bytes(HEADER - len(head)) + payload


def wanted(profile):
    pats = []
    for item in profile["firmware"]["items"]:
        if item["class"] == "wifi":
            pat = item["install_as"]
            if not pat.startswith("/Library/Firmware/"):
                raise ExtractError("unexpected install_as %s" % pat)
            pats.append(pat[len("/Library/Firmware/"):])
        else:
            raise ExtractError("firmware class %s has no extractor yet" % item["class"])
    return pats


def extract(profile_path, work, ipsw=None, names_out=None, keep_mounted=False):
    profile = json.load(open(profile_path))
    stub = profile["stub"]
    board = profile["id"]
    os.makedirs(work, exist_ok=True)
    src_name = ipsw or stub["restore_image"]["url"]
    if src_name.startswith("https://"):
        src = HTTPSource(src_name, expected_size=stub["restore_image"]["bytes"])
    else:
        src = LocalSource(src_name)
        if src.size != stub["restore_image"]["bytes"]:
            raise ExtractError("local restore image has the wrong size")
    z = RemoteZip(src)
    bm_bytes = z.read("BuildManifest.plist")
    manifest = plistlib.loads(bm_bytes)
    if manifest.get("ProductBuildVersion") != stub["build"] or manifest.get("ProductVersion") != stub["version"]:
        raise ExtractError("restore image is %s %s, profile wants %s %s" % (
            manifest.get("ProductVersion"), manifest.get("ProductBuildVersion"), stub["version"], stub["build"]))
    identity = select_identity(manifest, stub["identity"])
    bs_path = identity["Manifest"]["BaseSystem"]["Info"]["Path"]
    dmg = os.path.join(work, os.path.basename(bs_path))
    m = z.members[bs_path]
    if not (os.path.exists(dmg) and os.path.getsize(dmg) == m.usize and os.path.exists(dmg + ".ok")):
        h = hashlib.sha256()
        with open(dmg + ".part", "wb") as f:
            for chunk in z.stream(bs_path):
                f.write(chunk)
                h.update(chunk)
        os.replace(dmg + ".part", dmg)
        with open(dmg + ".ok", "w") as f:
            f.write(h.hexdigest() + "\n")
    dmg_sha = open(dmg + ".ok").read().strip()

    mnt = tempfile.mkdtemp(prefix="sf-basesystem-", dir=work)
    subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-quiet", "-mountpoint", mnt, dmg], check=True)
    try:
        col = WiFiFWCollection(os.path.join(mnt, "usr/share/firmware/wifi"))
        pats = wanted(profile)
        files = sorted((name, fw.data) for name, fw in col.files() if any(fnmatch.fnmatchcase(name, p) for p in pats))
    finally:
        if not keep_mounted:
            subprocess.run(["hdiutil", "detach", "-quiet", mnt], check=False)
            os.rmdir(mnt)
    if not files:
        raise ExtractError("no firmware matched %s" % pats)
    slot = slot_payload(files)
    with open(os.path.join(work, "firmware-slot-%s.bin" % board), "wb") as f:
        f.write(slot)
    rows = ["%s\t%s\t%d\t%s" % (board, n, len(d), hashlib.sha256(d).hexdigest()) for n, d in files]
    meta = {
        "board": board, "version": stub["version"], "build": stub["build"], "url": stub["restore_image"]["url"],
        "bytes": stub["restore_image"]["bytes"], "build_manifest_sha256": hashlib.sha256(bm_bytes).hexdigest(),
        "basesystem_member": bs_path, "basesystem_bytes": m.usize, "basesystem_sha256": dmg_sha,
        "files": len(files), "slot_payload_sha256": hashlib.sha256(slot[HEADER:]).hexdigest(),
        "fetched_bytes": getattr(src, "bytes_fetched", None),
    }
    text = "".join("# %s: %s\n" % (k, meta[k]) for k in ("version", "build", "url", "bytes", "build_manifest_sha256",
                                                         "basesystem_member", "basesystem_bytes", "basesystem_sha256"))
    text = "# Apple firmware names and hashes only (never the files). Made by extract_firmware.py.\n" + text
    text += "# board\tname\tbytes\tsha256\n" + "\n".join(rows) + "\n"
    if names_out:
        with open(names_out, "w") as f:
            f.write(text)
    return meta, text


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--ipsw")
    ap.add_argument("--names-out")
    a = ap.parse_args(argv)
    if sys.platform != "darwin":
        print("extract_firmware: runs on a Mac (hdiutil)", file=sys.stderr)
        return 2
    try:
        meta, _ = extract(a.profile, a.work, a.ipsw, a.names_out)
    except (ExtractError, ZipError, subprocess.CalledProcessError, KeyError) as e:
        print("extract_firmware: %s" % e, file=sys.stderr)
        return 1
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
