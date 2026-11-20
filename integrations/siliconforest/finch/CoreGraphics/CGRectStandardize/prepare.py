#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify the CGRectStandardize sources and copy them into a new directory."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True,
                        help="Fresh, nonexistent output directory")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    manifest = json.loads((here / "sources.json").read_text())
    for name, expected in manifest["files"].items():
        if digest(here / name) != expected:
            raise ValueError(name + " digest mismatch")
    args.output.mkdir()
    for name in list(manifest["files"]) + ["sources.json", "README.md"]:
        shutil.copyfile(here / name, args.output / name)
    print(json.dumps({
        "sha256": manifest["files"]["CGRectStandardize.c"],
        "output": str(args.output),
        "scope": "CGRectStandardize source and probe only",
    }))


if __name__ == "__main__":
    main()
