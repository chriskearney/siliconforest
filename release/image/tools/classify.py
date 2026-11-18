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
# Build outputs made before the SiliconForest rename (17 November 2026) carry upstream's project name
# as their store-name prefix; an installed root still holds some of them, so the classifier must
# recognise that prefix. It is assembled here so that the tree's naming check (tools/sf_rename.py)
# keeps meaning what it says: no old name in anything SiliconForest ships or runs.
OLD = 'pure' + 'darwin'
LAB = re.compile(r'repo:|rebuild-tree:|siliconforest|darwin-lab|sffx|' + OLD + r'|-pd-|-sf-|sf-gpu|chonk|finch|cocoa|homebrew-overlay', re.I)

EMPTY = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
# upstream PureDarwin packages (built by upstream's flake, not by a lab recipe) seen under their store names
UPSTREAM_PKG = re.compile('^' + OLD + r'-(python|git|nano|openssl|gettext|xz|openssh|automake|json-c|librsvg|gnumake|libffi|pcre2|libpsl|cmake|kernel|app-frameworks|basesystem)-[0-9]')
FONT = re.compile(r'\.(ttf|otf|ttc|pcf(\.gz)?)$', re.I)

def unesc(s): return re.sub(r'\\x([0-9a-f]{2})', lambda m: chr(int(m.group(1), 16)), s)

# path rules for what must not ship: (regex, reason)
NOSHIP = [
    (r'^/(var/root|private/var/root)(/|$)', 'owner data: root home (shell history, agent state, keys)'),
    (r'^/Users/[^/]+(/|$)', 'owner data: user home'),
    (r'^/private/var/db/desktop-state/chonkstep/dock$', None),   # decided by content, below
    (r'^/private/var/db/desktop-state(/|$)', "the owner's desktop choices (theme, scale, wallpaper)"),
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
    (r'\.(pd|disk)$', 'previous name / original kept beside a replacement'),
    (r'/__pycache__(/|$)', 'Python bytecode cache made at run time'),
    (r'/firefox/[^/]+/(maintenance-[^/]*|activation-backup)(/|$)|/firefox/[^/]+/[^/]*\.build\.log$|/firefox/[^/]+/(installation|dock-qualification|maintenance-pin-preservation-v1)\.json$|/firefox/[^/]+/(OWNER-INSTALL\.txt|\.graphics-maintenance\.lock|bootstrap-before-diag\.py)$|/(install-ledger|cold-verified)\.json$|/Firefox\.app/Contents/siliconforest-install\.json$', 'install receipts, logs and rollback copies of the Firefox runtime'),
    (r'/firefox/[^/]+/fonts/cache/', 'font cache made at run time'),
    (r'/firefox/[^/]+/overrides/(glyph-generation-v1|memory-font-v1|nv12-v1|surface-lookup-v1|video-shared-v1|frame-id-diagnostic-v1)(/|$)', 'a Firefox override that was tried and is not selected'),
    (r'^/etc/resolv\.conf$', 'run-time state (written by the network service)'),
    (r'^/(private/)?var/db/launchd/com\.apple\.launchd\.peruser\.', 'run-time state (made by launchd)'),
]
NOSHIP = [(re.compile(a), b) for a, b in NOSHIP]
FETCHED = [
    (r'^/opt/homebrew/(Cellar|Caskroom)/', 'Homebrew bottle'),
    (r'^/opt/homebrew/Library/', "Homebrew's own Ruby tree (git checkout)"),
    (r'^/opt/homebrew/', 'Homebrew links/prefix'),
    (r'^/Applications/Firefox\.app/Contents/Resources/Mozilla\.app/', "Mozilla's Firefox bundle (fetched at install time)"),
    (r'^/Applications/Firefox\.app/Contents/Info\.plist$', "the outer bundle's Info.plist: keys copied from Mozilla's, written at install time"),
    (r'/firefox/[^/]+/original/Firefox\.app/', "Mozilla's Firefox bundle (first-run download)"),
]
FETCHED = [(re.compile(a), b) for a, b in FETCHED]

# files that match no build output, identified one by one (docs/release/IMAGE.md, "The installed root")
KNOWN = [(re.compile(a), b, c) for a, b, c in [
    (r'^/usr/share/icons/default(/|$)', 'tree', 'the pointer set, written by the compositor itself (--write-cursor-theme); in a release: sf-firstboot'),
    (r'^/usr/lib/dyld$', 'tree', 'macos-apps-root dyld with executed pages lowered by the kernel in the page cache (pac-lower.py)'),
    (r'^/etc/(passwd|master\.passwd|profile|zshenv)$', 'tree', 'the base file as m1-storage/userland/sf-userland-install.sh edits it'),
    (r'^/(System/Library/(Private)?Frameworks/(OpenCL|SecurityFoundation|UniformTypeIdentifiers|AssetCacheServicesExtensions|CoreSymbolication|CrashReporterSupport|NetworkStatistics|RemoteServiceDiscovery|SafeEjectGPU|Suggestions)\.framework/|usr/lib/lib(IOReport|LaunchServicesSupport|quit|sysmon|systemstats)\.dylib$|usr/bin/sample$|usr/sbin/lsof$)', 'tree', "Activity Monitor's support libraries and tools: activity-monitor/libs/build.sh and tools/ (no Nix recipe yet)"),
    (r'^/usr/bin/(chonkstep-darwin|darwin-wayland-client(-ssd)?|rust-hello|darwin-wayland-terminal-native-startup|darwin-native-input-inventory|darwin-apcie-port-observe|darwin-desktop-test\.staged)$', 'noship', 'test programs of earlier work streams (their build outputs are gone)'),
    (r'^/Library/Preferences/org\.(siliconforest|' + OLD + r')\.audio\.plist$', 'noship', "the owner's audio levels"),
    (r'^/usr/local/lib/siliconforest/firefox/[^/]+/release\.json$', 'tree', 'the Firefox selection record: written by release/image/firefox-runtime.nix'),
    (r'^/usr/local/lib/siliconforest/firefox/[^/]+/(install-system\.py|org\.mozilla\.firefox\.desktop)$|^/usr/local/lib/siliconforest/opengl/v1/canonical-install\.json$', 'noship', 'install receipts and installer copies'),
    (r'^/usr/share/applications/org\.mozilla\.firefox\.desktop$|^/Applications/Firefox\.app/Contents/MacOS/system-runtime\.json$', 'tree', 'release/image/firefox-runtime.nix'),
    (r'^/usr/share/darwin-desktop/LICENSE-DejaVu\.txt$', 'fetched', "the DejaVu fonts' licence"),
    (r'^/System/Library/LaunchDaemons/org\.siliconforest\.sf-netd\.plist$', 'tree', "netd's job with --live-after 0 added by hand on 17 November; sf-netd.c's default is 0 since, so the release's job behaves the same"),
    (r'^/usr/local/bin/neofetch$|^/usr/local/libexec/sf-gtar$', 'noship', 'copied in by hand (a third-party script; a GNU tar for transfers): not part of the system'),
]]

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
            if rx.search(upath):
                if r is not None: cls, why = 'noship', r
                break
        # files that sf-install.sh itself makes: the base's reboot/halt/poweroff/shutdown kept as *.xnu,
        # and the dock's pins, which are the tree's defaults unless the person changed them
        if cls is None and re.search(r'^/bin/(reboot|halt|poweroff|shutdown)\.xnu$', upath):
            b = base_by_path.get(upath[:-4])
            cls, why = 'tree', ("the base's %s, kept by sf-install.sh" % upath[5:-4]) + ('' if b and b[1] == digest else ' (from an older base build)')
        if cls is None and upath == '/private/var/db/desktop-state/chonkstep/dock':
            cands = store.get(digest, [])
            cls, why = ('tree', 'the default dock pins (desktop/system/dock-pins, by sf-install.sh)') if any(c[0].startswith('repo:') for c in cands) else ('noship', "the owner's own dock pins")
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
            for rx, c, r in KNOWN:
                if rx.search(upath): cls, why = c, r; break
        if cls is None:
            cls, why = 'unknown', ('base path, changed bytes' if upath in base_by_path else 'no match')
        counts[(cls, t)] += 1; sizes[cls] += size if t == 'f' else 0; reasons[(cls, why)] += 1
        o.write('\t'.join([cls, t, mode, uid, gid, str(size), digest, path, link, why]) + '\n')
for k in sorted(counts): print('%-8s %s %8d' % (k[0], k[1], counts[k]))
for k in sorted(sizes): print('%-8s %10.1f MiB' % (k, sizes[k] / 1048576))
print('--- reasons')
for (c, w), n in sorted(reasons.items(), key=lambda x: (x[0][0], -x[1])):
    print('%-8s %7d %s' % (c, n, w[:150]))
