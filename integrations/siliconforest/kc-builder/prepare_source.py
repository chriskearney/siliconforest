#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare the kc-tools source the installer's kc-builder is built from, on any host without Nix.

  prepare_source.py OUT_DIR [--from DIR]

Clones PureDarwin kc-tools at the revision the SiliconForest tree locks (the `kc-tools` input of the
PureDarwin flake at rebase/pd.nix's tip), checks the commit id, then applies the same patches, in the
same order, as ./build-tools.nix:

  ../m1-bringup/kc-tools-arm64-text.patch   ARM64 layout fix
  ./kc-tools-sym-order.patch                 host-independent symbol order and duplicate binding

--from DIR copies an existing unpatched checkout (for example the Nix store source) instead of cloning.
kc-tools is BSD-3-Clause (Copyright (c) 2026, Vali0004); its LICENSE is kept in OUT_DIR.
"""
import argparse, shutil, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
URL = "https://github.com/PureDarwin/kc-tools"
REV = "05e5ed6a42533cfc4330559484e74b6dedeae51e"   # branch xnu-12377, flake.lock of the tip
PATCHES = [HERE.parent / "m1-bringup" / "kc-tools-arm64-text.patch", HERE / "kc-tools-sym-order.patch"]
FILES = ["CMakeLists.txt", "LICENSE", "README.md", "include", "lib", "src"]


def run(*cmd, cwd=None):
    subprocess.run(cmd, cwd=cwd, check=True)


def prepare(out: Path, source: Path | None = None) -> Path:
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    with tempfile.TemporaryDirectory() as td:
        if source is None:
            src = Path(td) / "kc-tools"
            run("git", "init", "-q", str(src))
            run("git", "-C", str(src), "fetch", "-q", "--depth", "1", URL, REV)
            run("git", "-C", str(src), "checkout", "-q", "FETCH_HEAD")
            head = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], check=True,
                                  capture_output=True, text=True).stdout.strip()
            if head != REV:
                sys.exit(f"kc-tools: fetched {head}, expected {REV}")
        else:
            src = source
        for name in FILES:
            p = src / name
            (shutil.copytree if p.is_dir() else shutil.copy2)(p, out / name)
    for patch in PATCHES:
        run("patch", "-s", "-p1", "--no-backup-if-mismatch", "-i", str(patch), cwd=out)
    for p in out.rglob("*"):
        if p.suffix in (".orig", ".rej"):
            sys.exit(f"kc-tools: patch left {p}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--from", dest="source", type=Path)
    a = ap.parse_args()
    print(prepare(a.out.resolve(), a.source))
