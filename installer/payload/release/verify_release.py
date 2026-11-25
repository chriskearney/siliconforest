#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Verify a SiliconForest installer release before anything is written (ENGINE.md S10-S15).

    verify_release.py DIR --allowed-signers FILE [--allow-rehearsal] [--shallow]

In order, failing closed at the first problem:
1. SHA256SUMS.sig is a valid SSH signature over SHA256SUMS, namespace siliconforest-release, by a
   key in FILE (ssh-keygen -Y verify).
2. SHA256SUMS is well formed and lists every file in DIR, and only those, with no paths.
3. Every file has the listed SHA-256 (streamed).
4. install.json agrees with SHA256SUMS (every artifact, same size and hash), and its numbers are
   sane: slots inside the image, aligned, not overlapping; growth limit above the image.
5. Unless --shallow: the root parts concatenate to one xz stream whose output has the image's
   size and SHA-256.
A release signed by a TEST-ONLY key, or marked rehearsal, is refused unless --allow-rehearsal.
This is the reference the installer's Swift verifier (SFRelease) is tested against.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sfrelease as R  # noqa: E402
import kc_release as KC  # noqa: E402


def verify(d, allowed_signers, allow_rehearsal=False, shallow=False):
    d = Path(d)
    sums_path, sig_path = d / R.SUMS, d / R.SIG
    if not sums_path.is_file() or not sig_path.is_file():
        raise R.ReleaseError("SHA256SUMS or its signature is missing")
    with sums_path.open("rb") as stdin:
        p = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", str(allowed_signers), "-I", R.NAMESPACE, "-n", R.NAMESPACE,
                            "-s", str(sig_path)], stdin=stdin, capture_output=True, text=True)
    if p.returncode != 0:
        raise R.ReleaseError("signature does not verify: " + (p.stderr or p.stdout).strip().splitlines()[-1])
    signer = p.stdout.strip()
    entries = R.parse_sums(sums_path.read_text())
    present = {f.name for f in d.iterdir() if f.name not in (R.SUMS, R.SIG)}
    for f in d.iterdir():
        if f.is_symlink() or not f.is_file():
            raise R.ReleaseError(f"{f.name} is not a plain file")
    if present != set(entries):
        extra, missing = sorted(present - set(entries)), sorted(set(entries) - present)
        raise R.ReleaseError(f"files and SHA256SUMS differ: unlisted {extra}, missing {missing}")
    sizes = {}
    for name, digest in sorted(entries.items()):
        got, n = R.sha256_file(d / name)
        if got != digest:
            raise R.ReleaseError(f"{name} does not match its SHA-256")
        sizes[name] = n

    if "install.json" not in entries:
        raise R.ReleaseError("install.json is not in SHA256SUMS")
    inst = json.loads((d / "install.json").read_text())
    if inst.get("format") != R.INSTALL_FORMAT:
        raise R.ReleaseError(f"install.json format is {inst.get('format')!r}")
    listed = {a["name"]: a for a in inst["artifacts"]}
    if set(listed) != set(entries) - {"install.json"}:
        raise R.ReleaseError("install.json artifacts and SHA256SUMS differ")
    for name, a in listed.items():
        if a["sha256"] != entries[name] or a["bytes"] != sizes[name]:
            raise R.ReleaseError(f"install.json disagrees with SHA256SUMS about {name}")
    rehearsal = bool(inst.get("rehearsal")) or bool(inst.get("signing_key", {}).get("test_only"))
    if rehearsal and not allow_rehearsal:
        raise R.ReleaseError("this is a rehearsal release (TEST-ONLY key); refused")

    root = inst["root"]
    img = root["image_bytes"]
    if img % 4096 or root["min_bytes"] < img or root["grow"]["max_bytes"] < img:
        raise R.ReleaseError("root sizes are inconsistent")
    spans = []
    for key in ("firmware_slot", "receipt_slot"):
        s = inst[key]
        if s["offset"] % 4096 or s["offset"] <= 0 or s["offset"] + s["bytes"] > img:
            raise R.ReleaseError(f"{key} is outside the image or unaligned")
        spans.append((s["offset"], s["offset"] + s["bytes"]))
    spans.sort()
    if spans[0][1] > spans[1][0]:
        raise R.ReleaseError("slots overlap")
    for role in ("stage1", "stage2", "bootargs"):
        if inst["boot"].get(role) not in listed:
            raise R.ReleaseError(f"boot {role} is not a listed artifact")
    if "kernel" in inst["boot"]:
        raise R.ReleaseError("a prelinked kernel collection is not part of format 3")
    kc = inst["kernel_collection"]
    KC.check_section(kc, listed)
    if not rehearsal and kc["tool"]["signing"] != "developer-id":
        raise R.ReleaseError("a release's kc-builder must be Developer ID signed")
    for part in root["parts"]:
        if part not in listed or listed[part]["role"] != "root-part":
            raise R.ReleaseError(f"root part {part} is not a listed root part")
    for board, files in inst.get("firmware", {}).get("boards", {}).items():
        for fw in files:
            if not fw["name"].startswith(("brcm/", "apple/")) or ".." in fw["name"] or len(fw["sha256"]) != 64:
                raise R.ReleaseError(f"bad firmware entry for {board}")

    if not shallow:
        h, n = hashlib.sha256(), 0
        cat = subprocess.Popen(["xz", "-dc"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

        def feed():
            try:
                for part in root["parts"]:
                    with (d / part).open("rb") as f:
                        for chunk in iter(lambda: f.read(1 << 20), b""):
                            cat.stdin.write(chunk)
            except BrokenPipeError:
                pass
            finally:
                cat.stdin.close()
        t = threading.Thread(target=feed)
        t.start()
        for chunk in iter(lambda: cat.stdout.read(1 << 20), b""):
            h.update(chunk)
            n += len(chunk)
        t.join()
        if cat.wait() != 0:
            raise R.ReleaseError("root parts are not one valid xz stream")
        if n != img or h.hexdigest() != root["image_sha256"]:
            raise R.ReleaseError("decompressed root differs from image_sha256")
    return {"ok": True, "signer": signer, "release": inst["release"], "rehearsal": rehearsal,
            "files": len(entries), "root_checked": not shallow}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", type=Path)
    ap.add_argument("--allowed-signers", type=Path, required=True)
    ap.add_argument("--allow-rehearsal", action="store_true")
    ap.add_argument("--shallow", action="store_true")
    a = ap.parse_args(argv)
    try:
        print(json.dumps(verify(a.dir, a.allowed_signers, a.allow_rehearsal, a.shallow), indent=2))
    except (R.ReleaseError, KeyError, ValueError, OSError) as e:
        print(f"verify_release: REFUSED: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
