#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Extract a controlled private packet into a NEW root; verify bytes and literal links.

Native guest tar loses PAX linkpath beyond 100 bytes. Python reads the complete
linkname; create links with the OS API, after file extraction. Never repair an
existing active prefix. No app execution, framework installation, or networking.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile


def relative(name):
    p = PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError(f"archive path escapes stage: {name}")
    return Path(*p.parts)


def verify(root, regular_members, symlink_members):
    manifest_path = root / "SHA256SUMS.json"
    if not stat.S_ISREG(manifest_path.lstat().st_mode):
        raise ValueError("Manifest must be an extracted regular member.")
    manifest = json.loads(manifest_path.read_text())
    errors = []
    for name, expected in manifest["regular_files"].items():
        p = root / relative(name)
        if relative(name) not in regular_members:
            errors.append({"path": name, "problem": "not a verified regular archive member"})
            continue
        if not stat.S_ISREG(p.lstat().st_mode) or hashlib.sha256(p.read_bytes()).hexdigest() != expected:
            errors.append({"path": name, "problem": "regular-file digest differs"})
    for name, expected in manifest["symlinks"].items():
        p = root / relative(name)
        actual = os.readlink(p) if relative(name) in symlink_members and p.is_symlink() else None
        if actual != expected:
            errors.append({"path": name, "expected_link": expected, "actual_link": actual})
    return {"pass": not errors, "regular_files_checked": len(manifest["regular_files"]),
            "literal_links_checked": len(manifest["symlinks"]), "errors": errors,
            "scope": "Packet bytes/link strings only; target existence, ABI and execution are separate checks."}


def extract(archive, root):
    if root.is_symlink() or (root.exists() and (not root.is_dir() or any(root.iterdir()))):
        raise ValueError("Fresh empty stage required; active/nonempty roots are never repaired.")
    root.mkdir(mode=0o700, exist_ok=True)
    with tarfile.open(fileobj=archive, mode="r:*") as tar:
        members = tar.getmembers()
        names = [relative(m.name) for m in members]
        if len(set(names)) != len(names):
            raise ValueError("duplicate archive member names")
        links = {relative(m.name) for m in members if m.issym()}
        regular = {relative(m.name) for m in members if m.isfile()}
        if Path("SHA256SUMS.json") not in regular:
            raise ValueError("Manifest must itself be a regular archive member, not a link.")
        for m in members:
            name = relative(m.name)
            if any(parent in links for parent in name.parents):
                raise ValueError(f"archive member beneath symlink: {m.name}")
            if not (m.isdir() or m.isfile() or m.issym() or m.islnk()):
                raise ValueError(f"unsupported archive member: {m.name}")
        for m in members:
            dest = root / relative(m.name)
            if m.isdir():
                dest.mkdir(parents=True, exist_ok=True)
            elif m.isfile():
                dest.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(m) as source, dest.open("xb") as output:
                    shutil.copyfileobj(source, output)
                dest.chmod(m.mode & 0o777)
                os.utime(dest, (m.mtime, m.mtime))
        # Only members extracted above, or hardlinks verified from those members,
        # can supply an inode. Resolve forward chains without following symlinks.
        pending = [m for m in members if m.islnk()]
        while pending:
            remaining = []
            for m in pending:
                source_name = relative(m.linkname)
                if source_name not in regular:
                    remaining.append(m)
                    continue
                source = root / source_name
                if not stat.S_ISREG(source.lstat().st_mode):
                    raise ValueError(f"hardlink source is not regular: {m.name}")
                dest = root / relative(m.name)
                dest.parent.mkdir(parents=True, exist_ok=True)
                os.link(source, dest, follow_symlinks=False)
                if not stat.S_ISREG(dest.lstat().st_mode):
                    raise ValueError(f"hardlink result is not regular: {m.name}")
                regular.add(relative(m.name))
            if len(remaining) == len(pending):
                raise ValueError("hardlink target is not an extracted regular member or has a cycle")
            pending = remaining
        # No symlink exists during hardlink resolution.
        for m in members:
            if m.issym():
                dest = root / relative(m.name)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.symlink_to(m.linkname)
                if os.readlink(dest) != m.linkname:
                    raise ValueError(f"literal symlink readback differs: {m.name}")
        result = verify(root, regular, links)
        for m in reversed(members):
            if m.isdir() and relative(m.name) != Path("."):
                (root / relative(m.name)).chmod(m.mode & 0o777)
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", help="Controlled packet path, or - for stdin")
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.absolute()
    try:
        if args.archive == "-":
            # Owned stage parent, not a shared system temporary location.
            with tempfile.TemporaryFile(dir=root.parent, prefix="sf-preview-archive-") as file:
                shutil.copyfileobj(sys.stdin.buffer, file)
                file.seek(0)
                result = extract(file, root)
        else:
            with open(args.archive, "rb") as file:
                result = extract(file, root)
        result["root"] = str(root)
        print(json.dumps(result, indent=2))
        return int(not result["pass"])
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        print(json.dumps({"pass": False, "root": str(root), "error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
