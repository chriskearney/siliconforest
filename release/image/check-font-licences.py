#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Fail when a font in the root has no licence text with it.

    check-font-licences.py ROOT

A font file (.ttf .otf .ttc .otc .pfb .pfa .pcf[.gz] .woff .woff2 .dfont) passes when a licence
text (a file whose name starts with or contains LICENSE/LICENCE, COPYING, OFL, NOTICE, LEGAL or
COPYRIGHT) is in its own directory, or in a directory above it that belongs to the font's
package: the shared directories (/, /System, /System/Library, /System/Library/Fonts, /usr,
/usr/share, /usr/share/fonts, /usr/local, /usr/local/share, /opt, /opt/homebrew, /Library,
/Library/Fonts) do not count, so a licence there never covers a font in a subdirectory.
Prints each directory without one and exits 1, or prints the count and exits 0.
"""
import os, re, sys

FONT = re.compile(r'\.(ttf|otf|ttc|otc|pfb|pfa|pcf(\.gz)?|woff2?|dfont)$', re.I)
LICENCE = re.compile(r'(licen[cs]e|copying|^ofl|notice|^legal|copyright)', re.I)
SHARED = {'/', '/System', '/System/Library', '/System/Library/Fonts', '/usr', '/usr/share',
          '/usr/share/fonts', '/usr/local', '/usr/local/share', '/opt', '/opt/homebrew',
          '/Library', '/Library/Fonts'}

def main():
    root = os.path.abspath(sys.argv[1])
    listing = {}
    for d, dirs, files in os.walk(root):
        listing['/' + os.path.relpath(d, root) if d != root else '/'] = files
    def has_licence(rel):
        return any(LICENCE.search(f) for f in listing.get(rel, ()))
    bad, fonts = [], 0
    for rel, files in sorted(listing.items()):
        found = [f for f in files if FONT.search(f)]
        if not found:
            continue
        fonts += len(found)
        d, ok = rel, has_licence(rel)
        while not ok and d not in SHARED:
            d = os.path.dirname(d)
            ok = d not in SHARED and has_licence(d)
        if not ok:
            bad.append((rel, len(found), found[0]))
    for rel, n, first in bad:
        print('font without a licence text: %s (%d fonts, e.g. %s)' % (rel, n, first))
    print('fonts: %d in %d directories without a licence text' % (fonts, len(bad)) if bad else
          'fonts: %d, every one with a licence text' % fonts)
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
