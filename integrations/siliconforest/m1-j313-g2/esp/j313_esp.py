#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Swap the J313 stage 2 on the Air's ESP for the G2 test, and put the original back.

Every command is a dry run unless --execute and the exact --confirm text are given.

  status                         report what is on the ESP; changes nothing
  install --candidate FILE       keep the original as boot.bin.pre-g2, install the window build
  restore                        put the kept original back and verify it
  finalize                       after a reboot on the original: delete the kept copy

This program writes only three names, all in m1n1/ on the ESP: boot.bin, boot.bin.pre-g2 and a
temporary file. It keeps no state anywhere else, so it needs no space on the Linux root. It never
touches stage 1, NVRAM, boot policy, partitions, the Limine menu or any other file.

FAT has no journal. The rename is atomic for a running system, but a power cut during it can
leave the directory needing repair. The kept copy stays on the ESP so recovery is always possible.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys

ORIGINAL_SHA = '54fa07e4f5cbeecd90e67e335657c40b33c25aede7015a84afb1427333b4f923'
ORIGINAL_BYTES = 10107602
ORIGINAL_STAGE2 = 'f5a82fdb-dirty'
CANDIDATE_SHA = 'c688793a85af45b1a71254798da10f56c4f861584b1dc1e606b559f964f5664c'
CANDIDATE_BYTES = 10238674
TARGET = 'm1n1/boot.bin'
KEPT = 'm1n1/boot.bin.pre-g2'
TEMP = 'm1n1/.boot.bin.g2-tmp'
CONFIRM = 'J313_G2_ESP_SWAP_APPROVED_BY_CHRIS'
MARGIN = 1 << 20
EXIT_REFUSED = 2


class Refused(Exception):
    """The ESP is left as it was when this is raised before a write."""


def need(condition, message):
    if not condition:
        raise Refused(message)


def digest(path):
    value = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            value.update(block)
    return value.hexdigest()


def uncached_digest(path):
    """Hash what the filesystem gives back after the page cache for this file is dropped."""
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
        os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
    finally:
        os.close(fd)
    return digest(path)


def regular(path):
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return False
    need(stat.S_ISREG(info.st_mode), f'{path} is not a regular file')
    return True


def describe(path):
    if not regular(path):
        return None
    return {'bytes': os.path.getsize(path), 'sha256': digest(path)}


def unescape_mount(text):
    return re.sub(r'\\([0-7]{3})', lambda match: chr(int(match[1], 8)), text)


def parse_mount(mountinfo, path):
    """The mount whose mount point is exactly path, from /proc/self/mountinfo text."""
    found = None
    for line in mountinfo.splitlines():
        left, separator, right = line.partition(' - ')
        if not separator:
            continue
        fields, tail = left.split(), right.split()
        if len(fields) < 6 or len(tail) < 3:
            continue
        if unescape_mount(fields[4]) == path:
            found = dict(fstype=tail[0], source=unescape_mount(tail[1]),
                         options=set(fields[5].split(',')) | set(tail[2].split(',')))
    return found


def read_property(root, name):
    return (Path(root) / name).read_bytes().rstrip(b'\0').decode('ascii')


def compatible(root):
    return (Path(root) / 'compatible').read_bytes().rstrip(b'\0').decode('ascii').split('\0')


def check_board(root):
    names = compatible(root)
    need('apple,j313' in names and 'apple,t8103' in names, 'this machine is not a J313 (T8103)')


def check_identity(mount, partuuid, resolve):
    """The mounted filesystem must be the partition the firmware chain booted from."""
    need(re.fullmatch('[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', partuuid or '') is not None,
         'the device tree names no ESP')
    expected = resolve('/dev/disk/by-partuuid/' + partuuid.lower())
    need(expected is not None and expected == resolve(mount['source']),
         'the mounted filesystem is not the ESP this machine booted from')


def check_target(args):
    esp = os.path.realpath(args.esp)
    need(esp == os.path.abspath(args.esp), '--esp must not go through a symbolic link')
    os.path.isdir(os.path.join(esp, 'm1n1'))  # an automounted ESP is mounted by this first access
    with open('/proc/self/mountinfo') as stream:
        mount = parse_mount(stream.read(), esp)
    need(mount is not None, f'{esp} is not a mount point')
    need(mount['fstype'] == 'vfat', f'{esp} is not a FAT filesystem')
    if args.execute:
        need('rw' in mount['options'] and 'ro' not in mount['options'], f'{esp} is mounted read-only')
        need(os.geteuid() == 0, '--execute needs root')
    if args.loop_test:
        # Test images only: this mode cannot be pointed at a disk partition.
        need(re.fullmatch(r'/dev/loop[0-9]+', mount['source']) is not None, '--loop-test needs a loop device')
        need(args.dt_root is not None, '--loop-test needs --dt-root')
        check_board(args.dt_root)
    else:
        need(args.dt_root is None, '--dt-root is only for --loop-test')
        root = '/sys/firmware/devicetree/base'
        check_board(root)
        def resolve(path):
            return os.path.realpath(path) if os.path.exists(path) else None
        check_identity(mount, read_property(root, 'chosen/asahi,efi-system-partition'), resolve)
    need(os.path.isdir(os.path.join(esp, 'm1n1')), 'the ESP has no m1n1 directory')
    return esp


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_verified(source, destination, sha, size):
    """Copy to the temporary name, flush, check the bytes that came back, then rename."""
    temporary = os.path.join(os.path.dirname(destination), os.path.basename(TEMP))
    if os.path.lexists(temporary):
        need(regular(temporary), 'the temporary name is not a file')
        os.unlink(temporary)
    written = hashlib.sha256()
    count = 0
    with open(source, 'rb') as reader:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o755)
        with os.fdopen(fd, 'wb') as writer:
            for block in iter(lambda: reader.read(1 << 20), b''):
                written.update(block)
                count += len(block)
                writer.write(block)
            writer.flush()
            os.fsync(writer.fileno())
    need(written.hexdigest() == sha and count == size, f'{source} changed while it was copied')
    need(uncached_digest(temporary) == sha, 'the copy on the ESP does not match; nothing was replaced')
    os.replace(temporary, destination)
    sync_directory(os.path.dirname(destination))
    need(uncached_digest(destination) == sha and os.path.getsize(destination) == size,
         f'{destination} does not match after the rename')


def paths(esp):
    return tuple(os.path.join(esp, name) for name in (TARGET, KEPT, TEMP))


def state(esp):
    target, kept, temporary = paths(esp)
    return dict(target=describe(target), kept=describe(kept), temporary=describe(temporary))


def sha_of(item):
    return item['sha256'] if item else None


def label(item):
    value = sha_of(item)
    return {ORIGINAL_SHA: 'original', CANDIDATE_SHA: 'window build', None: 'absent'}.get(value, 'UNKNOWN')


def plan_install(esp, current, candidate):
    need(candidate is not None, 'install needs --candidate')
    need(regular(candidate), 'the candidate is not a file')
    need(os.path.getsize(candidate) == CANDIDATE_BYTES and digest(candidate) == CANDIDATE_SHA,
         'the candidate is not the reviewed window build')
    target, kept = sha_of(current['target']), sha_of(current['kept'])
    need(kept in (None, ORIGINAL_SHA), 'boot.bin.pre-g2 exists and is not the original')
    if target == CANDIDATE_SHA:
        need(kept == ORIGINAL_SHA, 'the window build is installed but the original is not kept')
        return []
    need(target == ORIGINAL_SHA, "the ESP's boot.bin is not the backed-up original")
    required = CANDIDATE_BYTES + MARGIN + (0 if kept else 2 * ORIGINAL_BYTES)
    info = os.statvfs(esp)
    need(info.f_bavail * info.f_frsize >= required, 'not enough free space on the ESP')
    steps = [] if kept else ['keep the original as ' + KEPT]
    return steps + ['install the window build as ' + TARGET]


def do_install(esp, current, candidate):
    target, kept, _ = paths(esp)
    if current['kept'] is None:
        write_verified(target, kept, ORIGINAL_SHA, ORIGINAL_BYTES)
    need(digest(kept) == ORIGINAL_SHA, 'the kept copy does not match')
    write_verified(candidate, target, CANDIDATE_SHA, CANDIDATE_BYTES)


def plan_restore(current, unknown_target):
    need(sha_of(current['kept']) == ORIGINAL_SHA, 'there is no verified original in boot.bin.pre-g2')
    target = sha_of(current['target'])
    if target == ORIGINAL_SHA:
        return []
    need(target in (CANDIDATE_SHA, None) or unknown_target,
         "boot.bin is neither build; inspect it, or pass --replace-unknown-target")
    return ['put the kept original back as ' + TARGET]


def do_restore(esp):
    target, kept, _ = paths(esp)
    write_verified(kept, target, ORIGINAL_SHA, ORIGINAL_BYTES)
    need(digest(kept) == ORIGINAL_SHA, 'the kept copy changed during restore')


def plan_finalize(args, current):
    need(sha_of(current['target']) == ORIGINAL_SHA, 'boot.bin is not the original')
    if current['kept'] is None:
        return []
    need(sha_of(current['kept']) == ORIGINAL_SHA, 'boot.bin.pre-g2 is not the original')
    root = args.dt_root or '/sys/firmware/devicetree/base'
    running = read_property(root, 'chosen/asahi,m1n1-stage2-version')
    need(running == ORIGINAL_STAGE2, f'reboot first: this boot used stage 2 {running}')
    return ['delete ' + KEPT]


def do_finalize(esp):
    _, kept, _ = paths(esp)
    os.unlink(kept)
    sync_directory(os.path.dirname(kept))


def run(args):
    esp = check_target(args)
    current = state(esp)
    if args.command == 'status':
        steps = []
    elif args.command == 'install':
        steps = plan_install(esp, current, args.candidate)
    elif args.command == 'restore':
        steps = plan_restore(current, args.replace_unknown_target)
    else:
        steps = plan_finalize(args, current)
    report = dict(command=args.command, esp=esp, boot_bin=label(current['target']), kept=label(current['kept']),
                  steps=steps, executed=False)
    if not args.execute or args.command == 'status':
        report['status'] = 'DRY_RUN_NOTHING_WRITTEN' if steps else 'NOTHING_TO_DO'
        return report
    need(args.confirm == CONFIRM, 'the exact --confirm text is required')
    if steps:
        if args.command == 'install':
            do_install(esp, current, args.candidate)
        elif args.command == 'restore':
            do_restore(esp)
        else:
            do_finalize(esp)
        os.sync()
    after = state(esp)
    report.update(executed=bool(steps), status='DONE' if steps else 'NOTHING_TO_DO',
                  boot_bin=label(after['target']), kept=label(after['kept']))
    return report


def parser():
    value = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    value.add_argument('command', choices=('status', 'install', 'restore', 'finalize'))
    value.add_argument('--esp', default='/boot/efi')
    value.add_argument('--candidate')
    value.add_argument('--execute', action='store_true')
    value.add_argument('--confirm')
    value.add_argument('--replace-unknown-target', action='store_true')
    value.add_argument('--loop-test', action='store_true', help=argparse.SUPPRESS)
    value.add_argument('--dt-root', help=argparse.SUPPRESS)
    return value


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        report = run(args)
    except Refused as error:
        print(json.dumps(dict(status='REFUSED', command=args.command, reason=str(error))))
        return EXIT_REFUSED
    print(json.dumps(report))
    return 0


if __name__ == '__main__':
    sys.exit(main())
