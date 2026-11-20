#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""List the symbols a set of Mach-O images import that the SiliconForest
system images they name do not export.

  missing_symbols.py ROOT IMAGE...

ROOT is a copy of the M1's /System and /usr/lib. Re-exported libraries are
followed. Images loaded from DYLD_FRAMEWORK_PATH can be given with
--fw DIR (searched first, as dyld does)."""
import os, re, subprocess, sys
from functools import lru_cache

T = "/nix/store/p8x57y0mi788srcls95cpcf2nbjz6la8-darwin-cross-toolchain-nix/bin/arm64-apple-darwin20.4-"
args = sys.argv[1:]
fw = []
while args and args[0] == "--fw":
    fw.append(args[1]); args = args[2:]
ROOT, images = args[0], args[1:]

def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout

def local(path, base=None):
    """Map an install name to a file under ROOT, following symlinks inside ROOT."""
    if path.startswith("@loader_path/") and base:
        p = os.path.join(os.path.dirname(base), path[len("@loader_path/"):])
        return p if os.path.exists(p) else None
    m = re.match(r"/System/Library/Frameworks/([^/]+)\.framework/(.*)", path)
    if m:
        for d in fw:
            p = os.path.join(d, m.group(1) + ".framework", m.group(2))
            if os.path.exists(p):
                return os.path.realpath(p)
    p = ROOT + path
    for _ in range(40):
        if os.path.islink(p):
            t = os.readlink(p)
            p = ROOT + t if t.startswith("/") else os.path.join(os.path.dirname(p), t)
            continue
        parts = p[len(ROOT):].split("/")
        # resolve a symlinked directory component
        acc = ROOT
        changed = False
        for i, part in enumerate(parts[1:], 1):
            nxt = os.path.join(acc, part)
            if os.path.islink(nxt) and i < len(parts) - 1:
                t = os.readlink(nxt)
                acc = ROOT + t if t.startswith("/") else os.path.normpath(os.path.join(acc, t))
                p = os.path.join(acc, *parts[i + 1:])
                changed = True
                break
            acc = nxt
        if not changed:
            break
    return p if os.path.isfile(p) else None

def loads(path):
    out = run(T + "otool", "-l", path)
    res = []
    cmd = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("cmd "):
            cmd = line.split()[1]
        elif line.startswith("name ") and cmd in ("LC_LOAD_DYLIB", "LC_REEXPORT_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_LAZY_LOAD_DYLIB", "LC_LOAD_UPWARD_DYLIB"):
            res.append((cmd, line.split()[1]))
    return res

@lru_cache(None)
def exports(path):
    syms = set(l.split()[-1] for l in run(T + "nm", "-gU", "-j", path).splitlines() if l.strip())
    for l in run(T + "objdump", "--macho", "--exports-trie", path).splitlines():
        m = re.match(r"\s*\[re-export\]\s+(\S+)", l) or re.search(r"\s(_\S+)\s+\[re-export\]", l)
        if m: syms.add(m.group(1))
        m2 = re.match(r"\s*(?:0x[0-9A-Fa-f]+\s+)?(_\S+)", l)
        if m2: syms.add(m2.group(1))
    for cmd, name in loads(path):
        if cmd == "LC_REEXPORT_DYLIB":
            p = local(name, path)
            if p: syms |= exports(p)
    return frozenset(syms)

for img in images:
    deps = {}
    for cmd, name in loads(img):
        deps[os.path.basename(name).split(".")[0]] = (cmd, name)
    missing = {}
    for l in run(T + "nm", "-m", "-u", img).splitlines():
        m = re.search(r"external (\S+) \(from (\S+)\)", l)
        if not m: continue
        sym, lib = m.groups()
        weak = "weak" in l
        cmd, name = deps.get(lib, (None, None))
        if not name:
            missing.setdefault("?" + lib, []).append(sym); continue
        p = local(name, img)
        if not p:
            missing.setdefault("NOFILE " + name, []).append(sym); continue
        if sym not in exports(p):
            missing.setdefault(name + (" (weak)" if weak else ""), []).append(sym + (" [weak]" if weak else ""))
    print("==", os.path.basename(img))
    for k, v in sorted(missing.items()):
        print("  ", k, len(v))
        for s in sorted(v): print("      ", s)
