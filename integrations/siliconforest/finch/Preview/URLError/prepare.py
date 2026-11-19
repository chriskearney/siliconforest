#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the URLError sources and copy them into a new directory."""
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
    if list(args.source.rglob("URLError.swift")):
        raise ValueError("Pin unexpectedly contains URLError.swift")
    license_path = args.source / "LICENSE.md"
    if digest(license_path) != manifest["license_sha256"]:
        raise ValueError("Pin LICENSE.md digest mismatch")
    for name, expected in manifest["files"].items():
        if digest(here / name) != expected:
            raise ValueError(name + " digest mismatch")
    args.output.mkdir()
    for name in manifest["files"]:
        shutil.copyfile(here / name, args.output / name)
    shutil.copyfile(here / "sources.json", args.output / "sources.json")
    shutil.copyfile(license_path, args.output / "Swift-Foundation-LICENSE.txt")
    print(json.dumps({
        "pin": manifest["pin"],
        "sha256": manifest["files"]["URLError.swift"],
        "output": str(args.output),
        "scope": "URLError source and probe only",
    }))


if __name__ == "__main__":
    main()
