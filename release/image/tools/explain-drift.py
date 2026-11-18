#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Why a from-clone root differs from the M1 where another root does not.

    explain-drift.py A.ext4 B.ext4 COMPARE_A COMPARE_B EXPLAIN.tsv OUT.tsv

COMPARE_A and COMPARE_B are compare.py output directories of roots A and B against the M1's
classified listing; EXPLAIN.tsv is explain-builds.py's output for A against B. For each path where
B differs from the M1 and A does not, says: build noise (store paths, object timestamps, layout),
rename (only the old project name -> siliconforest, and store names), or source changed after the M1 install
(strings only in B, after both are removed; an inference from strings, not a proof). Needs debugfs.
"""
import subprocess, sys, re, collections, tempfile
ea, eb, cmpa, cmpb, expl, out = sys.argv[1:7]
col = lambda p: {l.split('\t')[0]: l.rstrip('\n').split('\t')[1:] for l in open(p) if l.strip()}
a, b = col(cmpa + '/content.tsv'), col(cmpb + '/content.tsv')
ex = {l.split('\t')[0]: l.rstrip('\n').split('\t')[1] for l in open(expl) if l.strip()}
tmp = tempfile.mkdtemp()
WORD = re.compile(rb'[\x20-\x7e]{10,}')
WORDCH = set(b'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./- :%()*,;')
def words(path):
    d = open(path, 'rb').read()
    s = set()
    for w in WORD.findall(d):
        if not re.search(rb'[A-Za-z_]{6}', w) or sum(c in WORDCH for c in w) < 0.8 * len(w): continue
        w = re.sub(rb'/nix/store/[a-z0-9]{32}', b'/nix/store/H', w)
        s.add(w)
    return s
OLD = b'pure' + b'darwin'   # the project's name before the rename (spelled in two parts for the name check)
RENAME = [(rb'/nix/store/H-[^/ ]*', b'/nix/store/H-NAME'), (OLD, b'siliconforest'), (OLD.capitalize().replace(b'darwin', b'Darwin'), b'SiliconForest'), (rb'_pd([A-Z])', rb'_sf\1')]
def norm(s):
    r = set()
    for w in s:
        for x, y in RENAME: w = re.sub(x, y, w)
        r.add(w)
    return r
rows = []; cnt = collections.Counter()
for p in sorted(b):
    if p in a: continue
    k = ex.get(p, '')
    if k.startswith('Mach-O: only') or k.startswith('text: only'):
        why = 'build noise: ' + k.split(': ', 1)[1]
    else:
        for side, img in (('a', ea), ('b', eb)):
            subprocess.run(['debugfs', '-R', 'dump "%s" %s/%s' % (p, tmp, side), img], capture_output=True)
        wa, wb = words(tmp + '/a'), words(tmp + '/b')
        if wa == wb:
            why = 'build noise: same strings, different layout (%s)' % (k or 'n/a')
        elif norm(wa) == norm(wb):
            why = 'rename: only the old project name -> siliconforest, and store names (store paths, source paths, fields)'
        else:
            na, nb = norm(wa), norm(wb)
            new = sorted(nb - na, key=len, reverse=True)
            why = 'source changed after the M1 install: %d strings only in the clone, e.g. %s' % (len(nb - na), (new[0][:90].decode('latin-1') if new else '-'))
    cnt[why.split(':')[0]] += 1
    rows.append('%s\t%s\t%s' % (p, b[p][1], why))
open(out, 'w').write('\n'.join(rows) + '\n')
for k, n in cnt.most_common(): print('%5d  %s' % (n, k))
