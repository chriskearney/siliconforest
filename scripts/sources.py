#!/usr/bin/env python3
"""Fetch pinned personally maintained sources without changing existing checkouts."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def git(path, *args, capture=False):
    result = subprocess.run(
        ["git", "-C", str(path), *args], check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.rstrip() if capture else None


def read_lock():
    lock = json.loads((ROOT / "sources.lock.json").read_text())
    if lock["schema"] != 1:
        raise SystemExit("Unsupported source lock schema")
    for name, item in lock["sources"].items():
        if not re.fullmatch(r"[a-z0-9-]+", name):
            raise SystemExit(f"Invalid source name: {name}")
        if not re.fullmatch(r"[0-9a-f]{40}", item["commit"]):
            raise SystemExit(f"{name}: require a full commit SHA")
        if not item["url"].startswith("https://github.com/iconidentify/"):
            raise SystemExit(f"{name}: require a personally maintained source URL")
    for name, expected in lock["inputs"].items():
        path = (ROOT / name).resolve()
        if not path.is_relative_to(ROOT):
            raise SystemExit(f"Invalid input path: {name}")
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f"{name}: hash differs from sources.lock.json")
    return lock


def verify(name, item):
    path = ROOT / "sources" / name
    if not path.exists():
        raise SystemExit(f"{name}: missing checkout; run scripts/sources.py fetch {name}")
    if git(path, "rev-parse", "--show-toplevel", capture=True) != str(path.resolve()):
        raise SystemExit(f"{name}: path is not a source checkout root")
    actual = git(path, "rev-parse", "HEAD", capture=True)
    if actual != item["commit"]:
        raise SystemExit(f"{name}: HEAD {actual} differs from lock {item['commit']}")
    if git(path, "status", "--porcelain", "--untracked-files=normal", capture=True):
        raise SystemExit(f"{name}: source has local changes; preserve or commit them before building")
    if (path / ".gitmodules").exists():
        states = git(path, "submodule", "status", "--recursive", capture=True)
        if any(line[0] != " " for line in states.splitlines()):
            raise SystemExit(f"{name}: submodules must be initialized at their pinned commits")
    print(f"{name}: {actual} (clean)")


def fetch(name, item):
    path = ROOT / "sources" / name
    if path.exists():
        verify(name, item)
        return
    if name == "m1n1" and item.get("policy", "").startswith("pending"):
        raise SystemExit("m1n1: inherited policy decision pending; see sources.lock.json")
    path.parent.mkdir(parents=True, exist_ok=True)
    # Never reset, clean or switch a checkout that already exists.
    subprocess.run(["git", "init", str(path)], check=True)
    git(path, "remote", "add", "origin", item["url"])
    git(path, "fetch", "--depth=1", "origin", item["commit"])
    git(path, "checkout", "-b", item["branch"], "FETCH_HEAD")
    if (path / ".gitmodules").exists():
        git(path, "submodule", "update", "--init", "--recursive")
    verify(name, item)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["lock", "fetch", "verify"])
    parser.add_argument("source", nargs="?", choices=["linux", "m1n1", "all"], default="all")
    args = parser.parse_args()
    lock = read_lock()
    if args.command == "lock":
        print("Source lock and input hashes: OK")
        return
    for name, item in lock["sources"].items():
        if args.source in (name, "all"):
            (fetch if args.command == "fetch" else verify)(name, item)


if __name__ == "__main__":
    main()
