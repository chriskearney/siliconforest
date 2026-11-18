#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Public-input QEMU smoke image. Helpers retain the qemu-dev image editor's
# GPT/debugfs behavior; no bench mapping, cache or source discovery is used.
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import struct
import subprocess
import sys

SECTOR = 512

def partitions(image):
    """[(first byte, bytes)] of the GPT partitions, in table order."""
    with open(image, 'rb') as f:
        f.seek(SECTOR)
        header = f.read(92)
        assert header[:8] == b'EFI PART', 'not a GPT image'
        lba, count, size = struct.unpack_from('<QII', header, 72)
        f.seek(lba * SECTOR)
        out = []
        for _ in range(count):
            entry = f.read(size)
            if entry[:16] != bytes(16):
                first, last = struct.unpack_from('<QQ', entry, 32)
                out.append((first * SECTOR, (last - first + 1) * SECTOR))
    return out

def quote(value):
    value = str(value)
    assert not any(c in value for c in '\n\r\x00"'), value
    return '"' + value + '"'

def overlay_entries(overlay):
    """(files, links) of a tree rooted at /: regular files as write_root takes them (a .dylib
    or a file with an execute bit is executable), symbolic links as (path, target)."""
    files, links = {}, []
    overlay = Path(overlay)
    for dirpath, dirs, names in os.walk(overlay):
        for n in names + [d for d in dirs if (Path(dirpath) / d).is_symlink()]:
            src = Path(dirpath) / n
            dest = '/' + str(src.relative_to(overlay))
            if src.is_symlink():
                links.append((dest, os.readlink(src)))
            else:
                files[dest] = (src.resolve(), os.access(src, os.X_OK) or n.endswith('.dylib'))
    return files, links

def write_root(image, files, dirs=(), remove=(), links=()):
    """Add or replace regular files in the image's ext4 root with debugfs (no mount).
    dirs: (path, uid, gid) directories to make; remove: paths to delete; links: (path, target)
    symbolic links to make (replacing what is at the path)."""
    offset, _ = partitions(image)[1]
    target = '%s?offset=%d' % (image, offset)
    existing_dirs, commands = set(), []

    def exists(path):
        r = subprocess.run(['debugfs', '-R', 'stat ' + quote(path), target], capture_output=True, text=True)
        return 'Type:' in r.stdout
    for dest in sorted(list(files) + [l[0] for l in links]):
        for parent in reversed(PurePosixPath(dest).parents):
            p = str(parent)
            if p != '/' and p not in existing_dirs:
                if not exists(p):
                    commands.append('mkdir ' + quote(p))
                existing_dirs.add(p)
    for path in remove:
        commands.append('rm ' + quote(path))
    for path, uid, gid in dirs:
        for parent in list(reversed(PurePosixPath(path).parents)) + [PurePosixPath(path)]:
            if str(parent) != '/' and str(parent) not in existing_dirs:
                if not exists(str(parent)):
                    commands.append('mkdir ' + quote(parent))
                existing_dirs.add(str(parent))
        commands += ['sif %s uid %d' % (quote(path), uid), 'sif %s gid %d' % (quote(path), gid)]
    for dest, (source, executable) in sorted(files.items()):
        commands += ['rm ' + quote(dest), 'write %s %s' % (quote(source), quote(dest)),
                     'sif %s mode 0%o' % (quote(dest), 0o100000 | (0o755 if executable else 0o644))]
    for dest, to in links:
        commands += ['rm ' + quote(dest), 'symlink %s %s' % (quote(dest), quote(to))]
    r = subprocess.run(['debugfs', '-w', '-f', '-', target], input='\n'.join(commands) + '\n',
                       capture_output=True, text=True, check=True)
    bad = [l for l in (r.stdout + r.stderr).splitlines()
           if l.strip() and not l.startswith(('debugfs', 'Allocated inode')) and 'File not found by ext2_lookup' not in l]
    if bad:
        raise SystemExit('debugfs: ' + '\n'.join(bad[:10]))

def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    base = next(Path(config["base"]).glob("*.img"))
    image = out / "siliconforest-qemu-smoke.img"
    shutil.copyfile(base, image)
    image.chmod(0o644)
    files, links = {}, []
    for overlay in config["overlays"]:
        added, aliases = overlay_entries(overlay)
        files.update(added)
        links.extend(aliases)
    for destination, entry in config["files"].items():
        files[destination] = (Path(entry["source"]), entry["executable"])
    directories = [("/private/tmp", 0, 0), ("/private/var/run", 0, 0),
                   ("/private/var/db", 0, 0), ("/var/log", 0, 0)]
    write_root(image, files, dirs=directories, links=links)
    esp = "%s@@%d" % (image, partitions(image)[0][0])
    args = out / "boot-args.txt"
    args.write_text("serial=3 gopconsole=1 serial_video_mirror=0 -noprogress keepsyms=1 no_lock_timeouts=1 sfgopmode=1280x800")
    subprocess.run(["mcopy", "-o", "-i", esp, str(args), "::/EFI/BOOT/boot-args.txt"], check=True)
    offset, _ = partitions(image)[1]
    subprocess.run(["e2fsck", "-fn", "%s?offset=%d" % (image, offset)], check=True)
    (out / "scope.txt").write_text("QEMU smoke root: public minimal image, desktop and terminal; not the complete release image.\n")


if __name__ == "__main__":
    main()
