#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
"""Inventory tracked build inputs without reading ignored lab data.

Classification describes the current source tree, not an executed build. The
release derivation closure must additionally be checked with Nix in isolation.
"""
import argparse
import fnmatch
import json
import os
import re
import subprocess
from pathlib import Path


PATTERNS = {
    "local_fetch": re.compile(r"(?:git\+)?file://"),
    "home_path": re.compile(r"/(?:home|Users)/[A-Za-z0-9_.-]+/"),
    "store_literal": re.compile(r"/nix/store/[a-z0-9]{32}-"),
    "lab_input": re.compile(r"(?:^|[/\s\"'=])(?:sources|artifacts|private|runs)/"),
    "fetch": re.compile(r"fetch(?:Git|Tree|Tarball|FromGitHub|FromGitLab|url|zip)\b|getFlake\b"),
}
FROZEN = {"reports", "archive", "planning", "revisions", "attempts", "build-recipes", "implementation-revisions"}


def release_candidates(root, files):
    """Conservative static source graph; Nix isolation is the execution proof.

    Follow recipe imports and literal source paths, including inactive branches.
    Do not treat a variable naming the entire integration tree as an import of
    every historical experiment. The recipe() wrapper has an explicit base.
    """
    known = set(files)
    pending = [
        "flake.nix", "release/packages.nix", "tools/sf_rename.py", "tools/sf_rename_data.json",
        # The mandatory Homebrew layer executes these native Python helpers.
        "integrations/siliconforest/homebrew/hb_pour.py",
        "integrations/siliconforest/homebrew/hb_macho.py",
    ]
    seen = set()
    while pending:
        name = pending.pop()
        if name in seen or name not in known:
            continue
        seen.add(name)
        path = root / name
        if path.suffix != ".nix":
            continue
        text = re.sub(r"^\s*#.*$", "", path.read_text(), flags=re.M)
        refs = re.findall(r"(?<![A-Za-z0-9_/])((?:\.\.?/)[A-Za-z0-9_./-]+)", text)
        for recipe in re.findall(r'recipe\s+"([^"]+)"', text):
            pattern = "integrations/siliconforest/" + re.sub(r'\$\{[^}]+\}', '*', recipe)
            refs += [str(root / p) for p in fnmatch.filter(files, pattern)]
        if name == "release/image/firefox-runtime.nix":
            refs += [str(root / "integrations/siliconforest/firefox" / recipe)
                     for recipe in re.findall(r'file\s*=\s*"([^"]+\.nix)"', text)]
        if name.startswith("release/"):
            refs += [str(root / "integrations/siliconforest" / p)
                     for p in re.findall(r'(?:sf|tree)\s*\+\s*"/([^"]+)"', text)]
        for ref in refs:
            candidate = Path(ref) if ref.startswith("/") else path.parent / ref
            candidate = Path(os.path.normpath(candidate))
            try:
                rel = candidate.relative_to(root).as_posix().rstrip("/")
            except ValueError:
                continue
            if rel in known:
                pending.append(rel)
            elif rel + "/default.nix" in known:
                pending.append(rel + "/default.nix")
            elif (rel not in (".", "integrations", "integrations/siliconforest", "tools", "release")
                  and not any(f.startswith(rel + "/") and f.endswith(".nix")
                              and f.count("/") == rel.count("/") + 1 for f in known)):
                pending.extend(f for f in known if f.startswith(rel + "/"))
    return seen


def inventory(root):
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    release = release_candidates(root, files)
    records = []
    for name in sorted(filter(None, files)):
        path = root / name
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        lines = data.decode("utf-8", "replace").splitlines()
        hits = {key: [n for n, line in enumerate(lines, 1)
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
        elif name in release:
            category = "release-source-candidate"
        else:
            category = "bench-or-documentation-outside-static-release-graph"
        records.append({"path": name, "category": category, "matches": hits})
    return {
        "schema": 1,
        "method": "tracked text only; line numbers without matched values; conservative static release graph includes inactive branches; only an isolated Nix build proves the executed closure",
        "release_candidate_files": len(release),
        "classifications": {category: sum(r["category"] == category for r in records)
                            for category in sorted({r["category"] for r in records})},
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
