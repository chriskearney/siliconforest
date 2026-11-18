#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Write release/image/homebrew.lock.json: the Homebrew bottles the SiliconForest root carries,
pinned by sha256, with what pouring them needs and each formula's licence.

    homebrew-lock.py RUNS_HOMEBREW BREW_REV BREW_SHA256 > homebrew.lock.json

RUNS_HOMEBREW is a directory homebrew/hb_fetch.py filled (api/formula.json, closure-<tag>.json)
for at least the formulae below. The set is the system's (m1-storage/tools/sf_userland_push.sh
SF_FORMULAE: what the root's own programs call, /bin/bash, make, sqlite3, Firefox's launcher on
python3, the brew client's git, and the tools of a usable shell) with its dependency closure, plus
portable-ruby for the brew client. Nothing here is downloaded.
"""
import json, sys
FORMULAE = ('bash git less nano grep gnu-sed gawk gnu-tar coreutils findutils tmux python@3.14 node jq '
            'ripgrep tree htop wget fzf bat fd make xz zstd sqlite gh portable-ruby').split()
TAG = 'arm64_tahoe'
runs, rev, sha = sys.argv[1:4]
closure = {r['name']: r for r in json.load(open('%s/closure-%s.json' % (runs, TAG)))}
index = {}
for f in json.load(open(runs + '/api/formula.json')):
    index[f['name']] = f
    for a in f.get('aliases', []) + f.get('oldnames', []):
        index.setdefault(a, f)
order = []
def visit(n):
    n = index[n]['name'] if n in index else n
    if n in order:
        return
    for d in closure[n]['dependencies']:
        visit(d)
    order.append(n)
for n in FORMULAE:
    visit(n)
out = {'_comment': 'SPDX-License-Identifier: MIT. Copyright (c) 2026 Chris Kearney and the SiliconForest contributors. '
                   'Written by release/image/tools/homebrew-lock.py; read by release/image/homebrew.nix.',
       'tag': TAG, 'requested': FORMULAE,
       'brew': {'owner': 'Homebrew', 'repo': 'brew', 'rev': rev, 'sha256': sha, 'license': 'BSD-2-Clause'},
       'formulae': []}
for n in order:
    r, f = closure[n], index.get(n, {})
    out['formulae'].append({
        'name': n, 'version': r['version'], 'bottle_tag': r['bottle_tag'], 'sha256': r['sha256'],
        'url': f['bottle']['stable']['files'][r['bottle_tag']]['url'],
        'dependencies': r['dependencies'], 'keg_only': r['keg_only'],
        'post_install_steps': f.get('post_install_steps'),
        'license': f.get('license') or ('Ruby' if n == 'portable-ruby' else None)})
json.dump(out, sys.stdout, indent=1)
sys.stdout.write('\n')
