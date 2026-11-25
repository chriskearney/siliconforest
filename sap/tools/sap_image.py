#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""SAP in the SiliconForest root image (docs/sap/IMAGE.md): the files the image carries, and the
installed database seeded from the release's own channel (design 4.3, bootstrap).

Used by installer/payload/image/prepare_root.py (--sap-bin ...); also a command line for checks:

    sap_image.py files BIN_DIR        list what goes into the root (target, mode, bytes, sha256)

BIN_DIR is sap/tools/build_darwin.sh's output: sap, sf, sf-bootslot, sf-mount-sfboot
(aarch64-apple-darwin). Nothing here signs: an image's channel is published --unsigned (signed
offline on the M3, which does not change manifest.json) or with a TEST-ONLY key for rehearsals.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
IMAGE = HERE.parent / "image"
sys.path.insert(0, str(HERE))
import sap_build as SB  # noqa: E402

BINARIES = {
    "/usr/bin/sap": "sap",
    "/usr/bin/sf": "sf",
    "/usr/libexec/sf-bootslot": "sf-bootslot",
    "/usr/libexec/sap/sf-mount-sfboot": "sf-mount-sfboot",
}
# Optional: kc-tools' kc-builder for SiliconForest (build_darwin.sh SAP_KC_BUILDER=1), the tool the
# kernel-collection relink runs (design Q5), with its BSD licence next to it.
OPTIONAL = {
    "/usr/libexec/sap/kc-builder": ("kc-builder", 0o755, True),
    "/usr/libexec/sap/LICENSE.kc-tools": ("LICENSE.kc-tools", 0o644, False),
}
SCRIPTS = {
    "/usr/libexec/sap/sap-boot": "sap-boot",
    "/usr/libexec/sap/sap-mark-good": "sap-mark-good",
}
JOBS = {
    "/System/Library/LaunchDaemons/org.siliconforest.sap-boot.plist": "org.siliconforest.sap-boot.plist",
    "/System/Library/LaunchDaemons/org.siliconforest.sap-mark-good.plist": "org.siliconforest.sap-mark-good.plist",
}
CONF = "/etc/sap.conf"
# The package spec of the image's channel: SAP is its own package (it updates itself first,
# design 6.3); /etc/sap.conf is a config file (kept when changed locally).
SPEC = {
    "base": {"name": "sf-base", "summary": "SiliconForest base system"},
    "packages": [
        {"name": "sap", "summary": "SAP, the SiliconForest system updater",
         "paths": ["/usr/bin/sap", "/usr/bin/sf", "/usr/libexec/sf-bootslot", "/usr/libexec/sap/**"] + list(JOBS) + [CONF],
         "config_files": [CONF]},
    ],
}
MACHO_ARM64 = bytes.fromhex("cffaedfe0c000001")   # MH_MAGIC_64, CPU_TYPE_ARM64


class ImageError(Exception):
    pass


def conf_text(manifest_url=None):
    t = (IMAGE / "sap.conf").read_text()
    if manifest_url:
        if any(c in manifest_url for c in " \t\n#") or not manifest_url.startswith(("https://", "http://", "file://")):
            raise ImageError(f"bad manifest URL {manifest_url!r}")
        t = t.replace("# manifest_url = https://<the channel's host>/v1/stable/manifest.json   (set by the image build)",
                      f"manifest_url = {manifest_url}")
    return t.encode()


def files(bin_dir, manifest_url=None, allow_host_binaries=False):
    """[(target, data, mode)] for the root. The binaries must be arm64 Mach-O (build_darwin.sh)
    unless allow_host_binaries (synthetic tests)."""
    bin_dir = Path(bin_dir)
    out = []
    for target, name in BINARIES.items():
        p = bin_dir / name
        if not p.is_file():
            raise ImageError(f"{p} missing (sap/tools/build_darwin.sh builds it)")
        data = p.read_bytes()
        if not allow_host_binaries and data[:8] != MACHO_ARM64:
            raise ImageError(f"{p} is not an arm64 Mach-O executable")
        out.append((target, data, 0o755))
    for target, (name, mode, binary) in OPTIONAL.items():
        p = bin_dir / name
        if p.is_file():
            data = p.read_bytes()
            if binary and not allow_host_binaries and data[:8] != MACHO_ARM64:
                raise ImageError(f"{p} is not an arm64 Mach-O executable")
            out.append((target, data, mode))
    for target, name in SCRIPTS.items():
        out.append((target, (IMAGE / name).read_bytes(), 0o755))
    for target, name in JOBS.items():
        out.append((target, (IMAGE / name).read_bytes(), 0o644))
    out.append((CONF, conf_text(manifest_url), 0o644))
    return out


def publish_and_seed(tree, root_tsv, channel, release, sequence, key=None, expires_days=30):
    """Publish the image's channel from its tree (root packages only) and seed the database into
    tree/private/var/db/sap. Returns [(target, data, mode)] of the database files."""
    tree, channel = Path(tree), Path(channel)
    spec = channel.parent / (channel.name + ".spec.json")
    spec.parent.mkdir(parents=True, exist_ok=True)
    spec.write_text(json.dumps(SPEC, indent=1) + "\n")
    argv = ["publish", "--repo", str(channel), "--release", release, "--tree", str(tree), "--root-tsv", str(root_tsv),
            "--spec", str(spec), "--sequence", str(sequence), "--expires-days", str(expires_days)]
    argv += ["--key", str(key)] if key else ["--unsigned"]
    if SB.main(argv) not in (0, None):
        raise ImageError("sap_build publish failed")
    SB.seed_db(channel, tree)
    db = tree / "private/var/db/sap"
    out = []
    for p in sorted(db.rglob("*")):
        if p.is_file():
            out.append(("/" + str(p.relative_to(tree)), p.read_bytes(), 0o644))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("files")
    f.add_argument("bin_dir")
    f.add_argument("--manifest-url")
    a = ap.parse_args(argv)
    try:
        for target, data, mode in files(a.bin_dir, a.manifest_url):
            print(f"{target}\t{mode:04o}\t{len(data)}\t{hashlib.sha256(data).hexdigest()}")
    except ImageError as e:
        print(f"sap_image: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
