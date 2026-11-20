#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the PersonNameComponents overlay and copy it into a new directory."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True,
                        help="Pinned swift-foundation checkout root")
    parser.add_argument("--output", type=Path, required=True,
                        help="Fresh, nonexistent output directory")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / "sources.json").read_text())
    pin_file = args.source / "Sources/FoundationEssentials/PersonNameComponents.swift"
    if pin_file.exists():
        raise ValueError("Pin unexpectedly contains PersonNameComponents.swift")
    data = (here / "PersonNameComponents.swift").read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != manifest["files"]["PersonNameComponents.swift"]:
        raise ValueError("Overlay digest mismatch")
    patch = (here / "compatibility.patch").read_bytes()
    patch_digest = hashlib.sha256(patch).hexdigest()
    if patch_digest != manifest["files"]["compatibility.patch"]:
        raise ValueError("Compatibility patch digest mismatch")
    args.output.mkdir()
    (args.output / "PersonNameComponents.swift").write_bytes(data)
    (args.output / "compatibility.patch").write_bytes(patch)
    shutil.copytree(here / "include", args.output / "include")
    shutil.copyfile(here / "sources.json", args.output / "sources.json")
    license_path = here.parents[4] / "LICENSES/Swift-Foundation.txt"
    shutil.copyfile(license_path, args.output / "Swift-Foundation-LICENSE.txt")
    print(json.dumps({"pin": manifest["pin"], "sha256": digest,
                      "output": str(args.output), "scope": "No Data or AttributedString edits"}))


if __name__ == "__main__":
    main()
