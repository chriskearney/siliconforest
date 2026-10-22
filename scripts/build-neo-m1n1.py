#!/usr/bin/env python3
"""Build the locked, uninstalled Neo loader candidate without switching checkouts."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

from sources import read_lock

ROOT = Path(__file__).resolve().parents[1]


def load_candidate():
    lock = read_lock()
    profile_path = ROOT / "release/neo-candidate.json"
    expected = lock["inputs"].get("release/neo-candidate.json")
    if hashlib.sha256(profile_path.read_bytes()).hexdigest() != expected:
        raise ValueError("Neo candidate profile differs from source lock")
    profile = json.loads(profile_path.read_text())
    if profile.get("schema") != 1 or profile.get("id") != "neo-first-candidate":
        raise ValueError("unexpected Neo candidate profile schema or id")
    if profile.get("public_installable") is not False or profile.get("hardware_qualified") is not False:
        raise ValueError("this builder accepts only the unqualified source-candidate profile")
    source = profile["sources"]["m1n1"]
    if source["url"] != "https://github.com/iconidentify/siliconforest-m1n1.git":
        raise ValueError("unexpected Neo source repository")
    if not re.fullmatch(r"[0-9a-f]{40}", source["commit"]):
        raise ValueError("Neo source requires a full commit SHA")
    entries = [p for p in lock["m1n1_profiles"] if p["branch"] == source["branch"]]
    if len(entries) != 1 or entries[0]["commit"] != source["commit"]:
        raise ValueError("Neo profile and experimental source lock disagree")
    for name in ("linux", "mesa"):
        paired = entries[0].get("paired_sources", {}).get(name)
        if not isinstance(paired, dict) or set(paired) != {"url", "commit"}:
            raise ValueError(f"Neo {name} pairing requires an explicit source lock")
        if paired["url"] != lock["sources"][name]["url"] or not isinstance(paired["commit"], str) or \
                not re.fullmatch(r"[0-9a-f]{40}", paired["commit"]):
            raise ValueError(f"Neo {name} pairing has an invalid repository or commit")
        if profile["sources"][name] != paired:
            raise ValueError(f"Neo {name} pairing differs from source lock")
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True,
                        help="clean Neo worktree at the locked SHA; never reset by this script")
    parser.add_argument("--artwork", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, choices=range(1, 17), default=4)
    parser.add_argument("--plan", action="store_true", help="print locked inputs without building")
    args = parser.parse_args()
    try:
        profile = load_candidate()
        source = args.source.resolve()
        expected = profile["sources"]["m1n1"]["commit"]
        command = [sys.executable, str(source / "tools/build_neo.py"),
                   "--source", str(source), "--expected-commit", expected,
                   "--artwork", str(args.artwork.resolve()), "--output", str(args.output.absolute()),
                   "--jobs", str(args.jobs)]
        if not args.plan:
            if subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain",
                                        "--untracked-files=all"], text=True).strip():
                raise ValueError("control worktree is dirty; commit the reviewed profile first")
            top = subprocess.check_output(["git", "-C", str(source), "rev-parse",
                                           "--show-toplevel"], text=True).strip()
            if Path(top).resolve() != source:
                raise ValueError("source must be the Neo worktree root")
            actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
            if actual != expected:
                raise ValueError("source is not at the locked Neo commit; checkout left unchanged")
            if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain",
                                        "--untracked-files=all"], text=True).strip():
                raise ValueError("Neo source is dirty; checkout left unchanged")
            subprocess.run(command, check=True)
        result = {"profile": profile["id"], "sources": profile["sources"], "command": command,
                  "planned_only": args.plan, "hardware_qualified": False, "public_installable": False}
        result["control_commit"] = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"build-neo-m1n1: {error}\n")


if __name__ == "__main__":
    main()
