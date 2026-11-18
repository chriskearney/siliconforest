#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Compare a built root (root.manifest.tsv) with a classified listing of an installed root.

    compare.py root.manifest.tsv classified.tsv [--out DIR]

classified.tsv is the output of tools/root-inventory/classify.py for the installed machine:
    class type mode uid gid size sha256 path link reason
Entries classed `noship` are expected to be absent from the image and are only counted.
Everything else falls in exactly one group, written to DIR/<group>.tsv:
    same            same type and content (sha256 or link target)
    content         both have the path, bytes or link target differ
    type            both have the path with a different type
    only-installed  the installed root has it, the image does not
    only-image      the image has it, the installed root does not
    mode / owner    (counted for `same` and `content` entries) mode or uid:gid differ
Prints the counts by group and by the installed entry's class and reason.
"""
import argparse, collections, os, re

def unesc(s):
    return re.sub(r'\\x([0-9a-f]{2})', lambda m: chr(int(m.group(1), 16)), s)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('manifest'); ap.add_argument('classified'); ap.add_argument('--out')
    a = ap.parse_args()
    img = {}
    for line in open(a.manifest, encoding='utf-8', errors='surrogateescape'):
        if line.startswith('#'):
            continue
        p, t, mode, uid, gid, size, what = line.rstrip('\n').split('\t')
        img[p] = (t, mode, uid, gid, what)
    inst, noship = {}, collections.Counter()
    for line in open(a.classified, encoding='utf-8', errors='surrogateescape'):
        f = line.rstrip('\n').split('\t')
        cls, t, mode, uid, gid, size, digest, path, link, why = f
        path = unesc(path)
        t = 'd' if t == 'D' else t
        if cls == 'noship':
            noship[why] += 1
            continue
        inst[path] = (cls, t, mode, uid, gid, digest if t == 'f' else unesc(link) if t == 'l' else '-', why)
    groups = collections.defaultdict(list)
    attr = collections.Counter()
    for p, (cls, t, mode, uid, gid, what, why) in inst.items():
        if p not in img:
            groups['only-installed'].append((p, cls, why)); continue
        it, imode, iuid, igid, iwhat = img[p]
        if it != t:
            groups['type'].append((p, cls, '%s -> %s' % (t, it))); continue
        g = 'same' if iwhat == what else 'content'
        groups[g].append((p, cls, why))
        if t != 'l' and imode != mode:
            attr['mode %s -> %s' % (mode, imode)] += 1
        if (uid, gid) != (iuid, igid):
            attr['owner %s:%s -> %s:%s' % (uid, gid, iuid, igid)] += 1
    for p in img:
        if p not in inst and p != '/':
            groups['only-image'].append((p, '-', img[p][0]))
    print('noship entries (expected absent): %d' % sum(noship.values()))
    for g in ('same', 'content', 'type', 'only-installed', 'only-image'):
        rows = groups.get(g, [])
        print('%-15s %7d' % (g, len(rows)))
        by = collections.Counter((r[1], r[2] if g != 'only-image' else r[2]) for r in rows)
        if g != 'same':
            for (c, w), n in by.most_common(12):
                print('    %6d  %-8s %s' % (n, c, w[:110]))
    print('attribute differences on paths present in both:')
    for k, n in attr.most_common(15):
        print('    %6d  %s' % (n, k))
    if a.out:
        os.makedirs(a.out, exist_ok=True)
        for g, rows in groups.items():
            with open(os.path.join(a.out, g + '.tsv'), 'w', encoding='utf-8', errors='surrogateescape') as o:
                for r in sorted(rows):
                    o.write('\t'.join(r) + '\n')

if __name__ == '__main__':
    main()
