#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Classify every entry of a root listing (list-meta.pl output + sha256 list) into
#   tree     built from this repository's recipes (hash found in a lab-named Nix output)
#   base     upstream base image (hash equal to the base image's file)
#   fetched  third-party, fetched at build or at install/first run (Homebrew, Mozilla, fonts, nixpkgs)
#   noship   must not ship (owner's data, Apple, firmware, credentials, logs, leftovers, backups)
#   unknown  none of the above
# usage: classify.py meta.tsv hashes.tsv base.tsv store-index.tsv trees-index.tsv out.tsv
import re, sys, collections
meta, hashes, basef, storef, treesf, out = sys.argv[1:7]
LAB = re.compile(r'repo:|rebuild-tree:|siliconforest|darwin-lab|sffx|puredarwin|-pd-|-sf-|sf-gpu|chonk|finch|cocoa|homebrew-overlay', re.I)

EMPTY = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
# upstream PureDarwin packages (built by upstream's flake, not by a lab recipe) seen under their store names
UPSTREAM_PKG = re.compile(r'^puredarwin-(python|git|nano|openssl|gettext|xz|openssh|automake|json-c|librsvg|gnumake|libffi|pcre2|libpsl|cmake|kernel|app-frameworks|basesystem)-[0-9]')
FONT = re.compile(r'\.(ttf|otf|ttc|pcf(\.gz)?)$', re.I)

def unesc(s): return re.sub(r'\\x([0-9a-f]{2})', lambda m: chr(int(m.group(1), 16)), s)

# path rules for what must not ship: (regex, reason)
NOSHIP = [
    (r'^/(var/root|private/var/root)(/|$)', 'owner data: root home (shell history, agent state, keys)'),
    (r'^/Users/[^/]+(/|$)', 'owner data: user home'),
    (r'^/private/var/db/(?!dhcpclient$|launchd)', 'lab leftovers: test stages, packets, backups under /private/var/db'),
    (r'^/(private/)?var/(log|run)(/|$)', 'logs / runtime state'),
    (r'^/(private/)?tmp/.', 'temporary files'),
    (r'^/(private/)?var/tmp/.', 'temporary files'),
    (r'^/lost\+found(/|$)', 'filesystem'),
    (r'^/etc/ssh/ssh_host_', 'credentials: host keys (made at first boot)'),
    (r'wifi\.known$', 'remembered networks'),
    (r'^/Library/Firmware(/|$)', "firmware from the owner's machine"),
    (r'^/System/Applications/Utilities/Activity Monitor\.app(/|$)', 'Apple application'),
    (r'^/Applications/Utilities/Terminal\.app(/|$)', 'Apple application'),
    (r'\.(before|pre|old|prev|bak|orig|reverted|rolink)([-._][^/]*)?$', 'backup or previous copy'),
    (r'\.before-[^/]*$', 'backup or previous copy'),
    (r'\.next(\.[^/]*)?$', 'test variant (inject-capable compositor and its kin)'),
    (r'/Crash ?Reports?/|\.crash$|\.ips$|/DiagnosticReports/', 'crash reports'),
    (r'\.(old|before|prev|bak|safe)[0-9]+$|\.safe$', 'backup or previous copy'),
    (r'^/usr/local/lib/claude-code(/|$)|/\.claude(/|$)', "the owner's coding agent (not part of the system)"),
    (r'^/(private/)?var/cache/', 'cache made at run time'),
    (r'^/private/var/sf-[^/]*(/|$)', 'lab leftovers (test directories)'),
    (r'^/private/var/folders(/|$)', 'per-user runtime directories'),
    (r'\.(pd|disk|xnu)$', 'previous name / original kept beside a replacement'),
]
NOSHIP = [(re.compile(a), b) for a, b in NOSHIP]
FETCHED = [
    (r'^/opt/homebrew/(Cellar|Caskroom)/', 'Homebrew bottle'),
    (r'^/opt/homebrew/Library/', "Homebrew's own Ruby tree (git checkout)"),
    (r'^/opt/homebrew/', 'Homebrew links/prefix'),
    (r'^/Applications/Firefox\.app/', "Mozilla's Firefox bundle (first-run download)"),
    (r'/firefox/[^/]+/original/Firefox\.app/', "Mozilla's Firefox bundle (first-run download)"),
]
FETCHED = [(re.compile(a), b) for a, b in FETCHED]

h = {}
for line in open(hashes, encoding='utf-8', errors='surrogateescape'):
    d, p = line.rstrip('\n').split('\t', 1); h[p] = d
base_by_path, base_hashes = {}, set()
for line in open(basef, encoding='utf-8', errors='surrogateescape'):
    f = line.rstrip('\n').split('\t')
    base_by_path[unesc(f[6])] = (f[0], f[5], f[7] if len(f) > 7 else '')
    if f[5] != '-': base_hashes.add(f[5])
store = collections.defaultdict(list)
for fn in (storef, treesf):
    for line in open(fn, encoding='utf-8', errors='surrogateescape'):
        d, size, sp, rel = line.rstrip('\n').split('\t', 3); store[d].append((sp, rel))

def best(path, cands):
    rel = path.lstrip('/')
    exact = [c for c in cands if c[1] == rel or rel.endswith('/' + c[1]) or c[1].endswith(rel)]
    pool = exact or cands
    lab = [c for c in pool if LAB.search(c[0])]
    return (lab or pool)[0], bool(lab)

counts = collections.Counter(); sizes = collections.Counter(); reasons = collections.Counter()
with open(out, 'w', encoding='utf-8', errors='surrogateescape') as o:
    for line in open(meta, encoding='utf-8', errors='surrogateescape'):
        f = line.rstrip('\n').split('\t')
        t, mode, uid, gid, size, path, link = f[0], f[1], f[2], f[3], int(f[4]), f[8], f[9]
        upath = unesc(path); digest = h.get(path, '-')
        cls = why = None
        for rx, r in NOSHIP:
            if rx.search(upath): cls, why = 'noship', r; break
        if cls is None and t in 'dDl':
            for rx, r in FETCHED:
                if rx.search(upath): cls, why = 'fetched', r; break
        if cls is None and t in 'dD':
            cls, why = ('base', 'directory of the base image') if upath in base_by_path else ('tree', 'directory made by an install (layout)')
        if cls is None and t == 'l':
            b = base_by_path.get(upath)
            cls, why = ('base', 'link as in the base image') if b and b[0] == 'l' and b[2] == link else ('tree', 'link made by an install: -> ' + link)
        if cls is None and t == 'f':
            b = base_by_path.get(upath)
            cands = [] if digest == EMPTY else store.get(digest, [])
            if b and b[1] == digest:
                cls, why = 'base', 'same bytes as the base image'
            elif cands:
                (sp, rel), lab = best(upath, cands)
                name = sp.split('/')[-1][33:] if sp.startswith('/nix/store/') else sp
                if UPSTREAM_PKG.match(name):
                    cls, why = 'base', 'upstream package (not in the minimal image): ' + name
                elif FONT.search(upath) and not lab:
                    cls, why = 'fetched', 'font: ' + name
                elif lab:
                    cls, why = 'tree', name
                else:
                    cls, why = 'fetched', 'third-party build output: ' + name
            elif digest in base_hashes:
                cls, why = 'base', 'base image file at another path'
        if cls is None and t == 'f' and FONT.search(upath):
            cls, why = 'fetched', 'font (no build output matched)'
        if cls is None and t == 'f' and digest == EMPTY:
            cls, why = 'tree', 'empty file made by an install'
        if cls is None:
            for rx, r in FETCHED:
                if rx.search(upath): cls, why = 'fetched', r; break
        if cls is None:
            cls, why = 'unknown', ('base path, changed bytes' if upath in base_by_path else 'no match')
        counts[(cls, t)] += 1; sizes[cls] += size if t == 'f' else 0; reasons[(cls, why)] += 1
        o.write('\t'.join([cls, t, mode, uid, gid, str(size), digest, path, link, why]) + '\n')
for k in sorted(counts): print('%-8s %s %8d' % (k[0], k[1], counts[k]))
for k in sorted(sizes): print('%-8s %10.1f MiB' % (k, sizes[k] / 1048576))
print('--- reasons')
for (c, w), n in sorted(reasons.items(), key=lambda x: (x[0][0], -x[1])):
    print('%-8s %7d %s' % (c, n, w[:150]))
