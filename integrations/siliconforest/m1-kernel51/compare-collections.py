#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Entry-by-entry proof that two linked kernel collections differ only in the members named.

  compare-collections.py OLD NEW OUT.tsv [--members OLD_MEMBERS NEW_MEMBERS] [--changed ID ...]
      OLD, NEW      the collection files ($out/kernel), or the store paths that hold them
      *_MEMBERS     nix-build <recipe> -A members of each (symbol tables for pointer targets)
      --changed     bundle identifiers allowed to differ (the replaced members)

For every fileset entry (the kernel and each kext): its bundle identifier, the vmaddr and size of
each segment, and the SHA-256 of each segment's bytes in each collection. An entry is
"identical" when every segment is at the same address with the same bytes. When only 8-byte words
of a data segment differ, each such word is decoded as a kernel-collection chained-fixup rebase
(target: low 30 bits, an offset from the collection's base; the other 34 bits: next, key,
diversity, cache level, which must be equal): when both targets name the same symbol at the same
offset (a pointer into the replaced kernel, which moved), the entry is "rebound" with the count of
such words; any other difference is "differs". The kernel entry's __LINKEDIT is the collection's
shared one and is reported as the collection row. Exit status 0 only if every entry not named by
--changed is identical or rebound, and no entry moved, appeared or went away.
"""
import hashlib, importlib.util, os, struct, sys

LC_SEGMENT_64, LC_FILESET_ENTRY = 0x19, 0x80000035


def commands(data, at):
    magic, _, _, _, ncmds = struct.unpack_from('<IiiII', data, at)
    assert magic == 0xfeedfacf, 'not a 64-bit Mach-O at 0x%x' % at
    o = at + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, o)
        yield o, cmd, size
        o += size


def segments(data, at):
    out = []
    for o, cmd, _ in commands(data, at):
        if cmd == LC_SEGMENT_64:
            name = data[o + 8:o + 24].rstrip(b'\0').decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', data, o + 24)
            out.append((name, vmaddr, vmsize, fileoff, filesize))
    return out


def entries(data):
    out = {}
    for o, cmd, _ in commands(data, 0):
        if cmd == LC_FILESET_ENTRY:
            vmaddr, fileoff, name_off = struct.unpack_from('<QQI', data, o + 8)
            name = data[o + name_off:data.index(b'\0', o + name_off)].decode()
            # a kext's segment offsets are relative to its entry, the kernel's are the file's
            base = 0 if name == 'com.apple.kernel' else fileoff
            segs = []
            for seg, va, vs, fo, fs in segments(data, fileoff):
                segs.append((seg, va, vs, hashlib.sha256(data[base + fo:base + fo + fs]).hexdigest(), fs))
            out[name] = (vmaddr, segs)
    return out


def symbolicator():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'm1-exit-waits', 'symbolicate.py')
    spec = importlib.util.spec_from_file_location('sf_symbolicate', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def kc_base(data):
    return min(seg[1] for seg in segments(data, 0) if seg[2])


def entry_ranges(data, name):
    for o, cmd, _ in commands(data, 0):
        if cmd == LC_FILESET_ENTRY:
            _, fileoff, name_off = struct.unpack_from('<QQI', data, o + 8)
            if data[o + name_off:data.index(b'\0', o + name_off)].decode() == name:
                base = 0 if name == 'com.apple.kernel' else fileoff
                return {seg: (va, base + fo, fs) for seg, va, vs, fo, fs in segments(data, fileoff)}
    return {}


def rebound(a, b, name, seg, names):
    """(rebound words, other differing words) of one segment that differs in bytes only"""
    ra, rb = entry_ranges(a, name)[seg], entry_ranges(b, name)[seg]
    if ra[0] != rb[0] or ra[2] != rb[2] or names is None:
        return 0, -1
    (oa, ob), n = names, ra[2] // 8
    base_a, base_b = kc_base(a), kc_base(b)
    wa = struct.unpack_from('<%dQ' % n, a, ra[1])
    wb = struct.unpack_from('<%dQ' % n, b, rb[1])
    good = bad = 0
    for x, y in zip(wa, wb):
        if x == y:
            continue
        if x >> 30 == y >> 30:
            sx = oa.name(base_a + (x & 0x3fffffff))
            sy = ob.name(base_b + (y & 0x3fffffff))
            if sx is not None and sx == sy:
                good += 1
                continue
        bad += 1
    if a[ra[1] + 8 * n:ra[1] + ra[2]] != b[rb[1] + 8 * n:rb[1] + rb[2]]:
        bad += 1
    return good, bad


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, 'kernel')
    return open(path, 'rb').read()


def main():
    args = sys.argv[1:]
    changed, names = set(), None
    if '--changed' in args:
        i = args.index('--changed')
        changed = set(args[i + 1:])
        args = args[:i]
    if '--members' in args:
        i = args.index('--members')
        sym = symbolicator()
        names = (sym.Collection(args[0], args[i + 1]), sym.Collection(args[1], args[i + 2]))
        args = args[:i]
    old, new, out = args
    a, b = load(old), load(new)
    ea, eb = entries(a), entries(b)
    rows, ok = [], True
    order = list(ea) + [n for n in eb if n not in ea]
    for name in order:
        if name not in ea or name not in eb:
            rows.append((name, 'only in ' + ('new' if name in eb else 'old'), '', ''))
            ok = False
            continue
        (va, sa), (vb, sb) = ea[name], eb[name]
        if name == 'com.apple.kernel':
            # its __LINKEDIT is the collection's own, compared as the collection row
            sa = [x for x in sa if x[0] != '__LINKEDIT']
            sb = [x for x in sb if x[0] != '__LINKEDIT']
        pos_same = va == vb and [(s[0], s[1], s[2]) for s in sa] == [(s[0], s[1], s[2]) for s in sb]
        bytes_same = [(s[0], s[3]) for s in sa] == [(s[0], s[3]) for s in sb]
        size = sum(s[4] for s in sb)
        diff = ','.join(s[0] for s, t in zip(sa, sb) if s[3] != t[3] or s[1] != t[1]) or '-'
        if pos_same and bytes_same:
            result = 'identical'
        elif bytes_same:
            result = 'moved'
        else:
            result = 'differs'
            if pos_same and name not in changed:
                words = [rebound(a, b, name, s[0], names) for s, t in zip(sa, sb) if s[3] != t[3]]
                if words and all(bad == 0 for _, bad in words):
                    result = 'rebound'
                    diff += ' (%d pointer words, same symbols)' % sum(g for g, _ in words)
        rows.append((name, result, '%d bytes' % size, diff))
        if name in changed:
            ok &= result != 'moved'
        else:
            ok &= result in ('identical', 'rebound')
    # everything of the collection that is not inside an entry: its own segments
    for (seg, va, vs, fo, fs), (seg2, vb, vsb, fob, fsb) in zip(segments(a, 0), segments(b, 0)):
        same = seg == seg2 and va == vb and vs == vsb and a[fo:fo + fs] == b[fob:fob + fsb]
        rows.append(('collection ' + seg, 'identical' if same else 'differs', '%d bytes' % fsb, '-'))
    with open(out, 'w') as f:
        f.write('entry\tresult\tsize\tsegments that differ\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    counts = {}
    for r in rows:
        counts[r[1]] = counts.get(r[1], 0) + 1
    print('entries old %d new %d; %s; changed allowed: %s -> %s' % (
        len(ea), len(eb), ', '.join('%s %d' % kv for kv in sorted(counts.items())),
        ' '.join(sorted(changed)) or '-', 'PASS' if ok else 'FAIL'))
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
