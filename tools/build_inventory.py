#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
"""Inventory tracked build inputs without reading ignored lab data.

Classification describes the current source tree, not an executed build. The
release derivation closure must additionally be checked with Nix in isolation.
"""
import argparse
import json
import re
import subprocess
from pathlib import Path


PATTERNS = {
    "local_fetch": re.compile(r"(?:git\+)?file://|fetchGit\s*\{"),
    "home_path": re.compile(r"/(?:home|Users)/[A-Za-z0-9_.-]+/"),
    "store_literal": re.compile(r"/nix/store/[a-z0-9]{32}-"),
    "lab_input": re.compile(r"(?:^|[/\s\"'=])(?:sources|artifacts|private|runs)/"),
    "fetch": re.compile(r"fetch(?:Git|Tree|Tarball|FromGitHub|FromGitLab|url|zip)\b|getFlake\b"),
}
FROZEN = {"reports", "archive", "planning", "revisions", "attempts", "build-recipes", "implementation-revisions"}


def inventory(root):
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    records = []
    for name in sorted(filter(None, files)):
        path = root / name
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        hits = {key: [n for n, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1)
                      if pattern.search(line)] for key, pattern in PATTERNS.items()}
        hits = {key: lines for key, lines in hits.items() if lines}
        if not hits:
            continue
        parts = path.relative_to(root).parts
        frozen = (name == "AGENTS.md" or bool(FROZEN.intersection(parts))
                  or any(p.startswith(("validation", "host-revision")) for p in parts)
                  or name.endswith(("host_console.py", "normal_image.py")))
        if frozen:
            category = "frozen-evidence"
        elif name.endswith(".nix") or name.startswith("release/") or name == "flake.nix":
            category = "build-recipe-review"
        else:
            category = "bench-tool-or-documentation"
        records.append({"path": name, "category": category, "matches": hits})
    return {
        "schema": 1,
        "method": "tracked text only; line numbers, no matching private values; recipe classification is conservative",
        "counts": {key: sum(key in r["matches"] for r in records) for key in PATTERNS},
        "records": records,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    result = inventory(root)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result["counts"], indent=2))


if __name__ == "__main__":
    main()
