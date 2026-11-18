# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The libraries AppKit, QuartzCore and VLC's main binary need (load commands, transitively) that the rehearsal root
lacks, found in copies of the M1 (first match wins); prints 'src=/dest' for files and 'LINK dest target' for links."""
import struct, sys, os, subprocess
img, vlcapp = sys.argv[1], sys.argv[2]
SOURCES = sys.argv[3:]
def present(p):
    r = subprocess.run(['debugfs', '-R', 'stat ' + p, img], capture_output=True, text=True)
    return 'Inode:' in r.stdout
def deps(path):
    """The libraries a Mach-O loads (not weak ones); @rpath/ names resolved with its LC_RPATH entries (@loader_path is
    the binary's directory in the root) and, failing those, /lib, /usr/lib, /usr/local/lib."""
    try: d = open(path, 'rb').read()
    except Exception: return []
    if len(d) < 32: return []
    base = 0
    if struct.unpack_from('>I', d, 0)[0] == 0xcafebabe:            # universal: the arm64 slice
        n = struct.unpack_from('>I', d, 4)[0]
        for i in range(n):
            cpu, sub, offset, size, align = struct.unpack_from('>iiIII', d, 8 + 20 * i)
            if cpu == 0x0100000c: base = offset
        if base == 0: return []
    magic = struct.unpack_from('<I', d, base)[0]
    if magic != 0xfeedfacf: return []
    ncmds = struct.unpack_from('<I', d, base + 16)[0]; off = base + 32; names = []; rpaths = []
    for _ in range(ncmds):
        cmd, cs = struct.unpack_from('<II', d, off)
        if cmd in (0xc, 0x8000001f, 0x80000023, 0x8000001c):   # load, reexport, load upward, rpath
            so = struct.unpack_from('<I', d, off + 8)[0]
            name = d[off + so:off + cs].split(b'\0')[0].decode()
            (rpaths if cmd == 0x8000001c else names).append(name)
        off += cs
    root_dir = '/' + os.path.relpath(os.path.dirname(path), ROOTS.get(path, '/')) if path in ROOTS else None
    out = []
    for n in names:
        if n.startswith('@rpath/'):
            leaf = n[len('@rpath/'):]
            cands = []
            for r in rpaths:
                if r.startswith('@loader_path') and root_dir: r = os.path.normpath(root_dir + r[len('@loader_path'):])
                if r.startswith('/'): cands.append(os.path.join(r, leaf))
            cands += ['/usr/lib/' + leaf, '/usr/local/lib/' + leaf, '/lib/' + leaf]   # dyld's fallback order here
            hit = next((c for c in cands if present(c) or find(c)[1]), None)
            out.append(hit or cands[0])
        else:
            out.append(n)
    return out
ROOTS = {}
def find(p):
    for s in SOURCES:
        q = s + p
        if os.path.lexists(q):
            ROOTS[q] = s
            return s, q
    return None, None
seen = set(); todo = []
BUNDLE = [os.path.join(r, f) for r, _, fs in os.walk(vlcapp + '/Contents') for f in fs if (f.endswith('.dylib') or os.path.basename(r) in ('MacOS',) or '.framework/Versions/A' in r) and not os.path.islink(os.path.join(r, f))]
for start in BUNDLE + [vlcapp + '/Contents/MacOS/VLC'] + [s + '/System/Library/Frameworks/AppKit.framework/Versions/A/AppKit' for s in SOURCES[:1]] + [s + '/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore.pd' for s in SOURCES[:1]]:
    todo += deps(start)
files = {}; links = {}; missing = []
while todo:
    p = todo.pop()
    if p in seen or p.startswith('@'): continue
    seen.add(p)
    if present(p):
        s, q = find(p)
        if q and not os.path.islink(q): todo += deps(q)
        continue
    s, q = find(p)
    if q is None: missing.append(p); continue
    # resolve links inside the source tree
    cur = p
    while os.path.islink(s + cur):
        t = os.readlink(s + cur)
        links[cur] = t
        cur = os.path.normpath(os.path.join(os.path.dirname(cur), t))
        if present(cur): break
        s2, q2 = find(cur)
        if q2 is None: missing.append(cur); break
        s = s2
    else:
        files[cur] = s + cur
    if cur in files: todo += deps(files[cur])
    elif present(cur):
        s3, q3 = find(cur)
        if q3: todo += deps(q3)
for d, src in sorted(files.items()): print('%s=%s' % (src, d))
for d, t in sorted(links.items()): print('LINK %s %s' % (d, t))
for m in sorted(set(missing)): print('MISSING', m)
