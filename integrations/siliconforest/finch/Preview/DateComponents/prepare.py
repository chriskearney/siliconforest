#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare the pinned open DateComponents value slice in a new directory; never modify Data."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True,
                        help="Pinned swift-foundation checkout root")
    parser.add_argument("--output", type=Path, required=True,
                        help="Fresh, nonexistent output directory")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / "sources.json").read_text())
    sources = args.source / "Sources/FoundationEssentials"
    # Verify all inputs before creating any output. No repository writes/fetches.
    verified = {}
    for name, digest in manifest["files"].items():
        data = (sources / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError("Pinned source digest mismatch: " + name)
        verified[Path(name).name] = data
    args.output.mkdir()
    for name, data in verified.items():
        (args.output / name).write_bytes(data)
    subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-i",
                    str(here / "compatibility.patch")], cwd=args.output, check=True)
    shutil.copyfile(here / "CalendarValues.swift", args.output / "CalendarValues.swift")
    shutil.copytree(here / "include", args.output / "include")
    # Retain full provenance/license beside the prepared open sources.
    shutil.copyfile(here / "sources.json", args.output / "sources.json")
    license_path = here.parents[4] / "LICENSES/Swift-Foundation.txt"
    shutil.copyfile(license_path, args.output / "Swift-Foundation-LICENSE.txt")
    print(json.dumps({"revision": manifest["revision"], "source_files": len(verified),
                      "output": str(args.output), "scope": "No Data edits or execution"}))


if __name__ == "__main__":
    main()
