#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the localizedDescription sources and copy them into a new directory."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True,
                        help="Pinned swift-foundation checkout root")
    parser.add_argument("--output", type=Path, required=True,
                        help="Fresh, nonexistent output directory")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / "sources.json").read_text())
    license_path = args.source / "LICENSE.md"
    if digest(license_path) != manifest["license_sha256"]:
        raise ValueError("Pin LICENSE.md digest mismatch")
    cocoa = list(args.source.rglob("CocoaError.swift"))
    if not cocoa:
        raise ValueError("Pin has no CocoaError.swift")
    for name, expected in manifest["files"].items():
        if digest(here / name) != expected:
            raise ValueError(name + " digest mismatch")
    args.output.mkdir()
    for name in manifest["files"]:
        shutil.copyfile(here / name, args.output / name)
    shutil.copyfile(here / "sources.json", args.output / "sources.json")
    shutil.copyfile(here / "README.md", args.output / "README.md")
    shutil.copyfile(license_path, args.output / "Swift-Foundation-LICENSE.txt")
    print(json.dumps({
        "pin": manifest["pin"],
        "sha256": manifest["files"]["LocalizedDescription.swift"],
        "output": str(args.output),
        "scope": "Error.localizedDescription source and probe only",
        "leave_uncompiled": [str(path.relative_to(args.source)) for path in cocoa],
    }))


if __name__ == "__main__":
    main()
