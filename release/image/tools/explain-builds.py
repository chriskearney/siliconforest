#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Explain every content difference between two built roots.

    explain-builds.py A.manifest.tsv A.ext4 B.manifest.tsv B.ext4 OUT.tsv

For each path whose type or content differs, says whether only build-time store paths, object
timestamps (N_OSO) and the signature differ (macho-diff.py), or what else. Needs debugfs.
"""
import subprocess, sys, os, collections, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ma, ea, mb, eb, out = sys.argv[1:6]
def load(p):
    m = {}
    for l in open(p, encoding='utf-8', errors='surrogateescape'):
        if l.startswith('#'): continue
        f = l.rstrip('\n').split('\t'); m[f[0]] = (f[1], f[6])
    return m
a, b = load(ma), load(mb)
diff = sorted(p for p in a if p in b and a[p] != b[p])
tmp = tempfile.mkdtemp()
res = collections.Counter(); rows = []
for p in diff:
    if a[p][0] != 'f' or b[p][0] != 'f':
        k = 'link or type: %s -> %s' % (a[p][1][:60], b[p][1][:60]) if a[p][0] == b[p][0] == 'l' else 'type %s/%s' % (a[p][0], b[p][0])
    else:
        subprocess.run(['debugfs', '-R', 'dump "%s" %s/a' % (p, tmp), ea], capture_output=True)
        subprocess.run(['debugfs', '-R', 'dump "%s" %s/b' % (p, tmp), eb], capture_output=True)
        k = subprocess.run([sys.executable, os.path.join(HERE, 'macho-diff.py'), tmp + '/a', tmp + '/b'], capture_output=True, text=True).stdout.strip()
        if k.startswith('{') and "'other'" not in k:
            k = 'Mach-O: only build-time store paths (with the UUID and signature over them)' if 'masked' in k else 'Mach-O: only object timestamps (N_OSO) and signature'
        elif k.startswith('not Mach-O, 0 bytes differ'):
            k = 'text: only build-time store paths'
    res[k.split(':')[0] if k.startswith('link') else k] += 1
    rows.append('%s\t%s' % (p, k))
open(out, 'w').write('\n'.join(rows) + '\n')
print('differ:', len(diff), 'only A:', len([p for p in a if p not in b]), 'only B:', len([p for p in b if p not in a]))
for k, n in res.most_common(): print('%6d  %s' % (n, k))
