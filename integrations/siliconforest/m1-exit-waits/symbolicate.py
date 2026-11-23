#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Names for the addresses in a kern.sf_exitwait report (../m1-exit-waits/kernel.patch).

  symbolicate.py COLLECTION MEMBERS [REPORT] [--map LINKMAP]...
      COLLECTION  the kernel collection the M1 booted ($out/kernel of build-kc.nix, or the
                  store path that holds it)
      MEMBERS     nix-build build-kc.nix -A members: kernel/ and kexts/ as built, with their
                  symbol tables (local symbols included: Rust and static C functions)
      REPORT      the report (sysctl kern.sf_exitwait.report, or dmesg lines); stdin if absent
      LINKMAP     a kext's ld64 link map (nix-support/<kext>.map of its derivation, e.g. SFAgx,
                  SFDcp): its symbols are added to that member's, which names the functions
                  a kext binary built without local symbols does not (the Rust and C of SFAgx)

Every 0x... word of a "bt" or "continuation" line, and every "event 0x..." that lies in the
collection, gets " <bundle> <symbol>+0x<offset>" after it. The report's addresses are unslid,
so they are the collection's own addresses: the fileset entry that contains one names the
member; the same section of the member's own binary gives the address its symbol table uses.
Host only; reads files, writes stdout.
"""
import bisect, os, plistlib, re, struct, sys

LC_SYMTAB, LC_SEGMENT_64, LC_FILESET_ENTRY = 0x2, 0x19, 0x80000035


def commands(data, at):
    magic, _, _, _, ncmds = struct.unpack_from('<IiiII', data, at)
    assert magic == 0xfeedfacf, 'not a 64-bit Mach-O at 0x%x' % at
    o = at + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, o)
        yield o, cmd
        o += size


def sections(data, at):
    """(segment, section) -> (addr, size) of the Mach-O header at file offset at"""
    out = {}
    for o, cmd in commands(data, at):
        if cmd != LC_SEGMENT_64:
            continue
        nsects = struct.unpack_from('<I', data, o + 64)[0]
        for i in range(nsects):
            s = o + 72 + 80 * i
            sect = data[s:s + 16].rstrip(b'\0').decode()
            seg = data[s + 16:s + 32].rstrip(b'\0').decode()
            addr, size = struct.unpack_from('<QQ', data, s + 32)
            out[(seg, sect)] = (addr, size)
    return out


def symbols(data):
    """sorted (address, name) of a member's own binary: defined section symbols, no stabs"""
    out = []
    for o, cmd in commands(data, 0):
        if cmd != LC_SYMTAB:
            continue
        symoff, nsyms, stroff, _ = struct.unpack_from('<IIII', data, o + 8)
        for i in range(nsyms):
            strx, typ, sect, _, value = struct.unpack_from('<IBBHQ', data, symoff + 16 * i)
            if typ & 0xe0 or typ & 0x0e != 0x0e or sect == 0 or not value:
                continue
            end = data.index(b'\0', stroff + strx)
            out.append((value, data[stroff + strx:end].decode(errors='replace')))
    return sorted(set(out))


def demangle(name):
    """legacy Rust and simple Itanium nested names, enough to read a frame"""
    m = re.match(r'^__?ZN(\d.*?)E(.*)$', name)
    if not m:
        return name[1:] if name.startswith('_') else name
    rest, parts, args = m.group(1), [], m.group(2)
    while rest and rest[0].isdigit():
        n = re.match(r'\d+', rest).group(0)
        rest = rest[len(n):]
        parts.append(rest[:int(n)])
        rest = rest[int(n):]
    if parts and re.fullmatch(r'h[0-9a-f]{16}', parts[-1]):
        parts.pop()
    text = ('::'.join(parts) + ('()' if args and not name.endswith('E') else '')) if parts else name
    for a, b in (('$LT$', '<'), ('$GT$', '>'), ('$RF$', '&'), ('$BP$', '*'), ('$u20$', ' '),
                 ('$u27$', "'"), ('$u5b$', '['), ('$u5d$', ']'), ('$C$', ','), ('..', '::')):
        text = text.replace(a, b)
    return text


def link_map(path):
    """(kext directory name, [(address, name)]) of an ld64 map file"""
    kext, syms, live = None, [], False
    for line in open(path, errors='replace'):
        if line.startswith('# Path:'):
            m = re.search(r'([^/]+\.kext)/', line)
            kext = m.group(1) if m else None
        elif line.startswith('# Symbols:'):
            live = True
        elif line.startswith('# Dead Stripped'):
            break
        elif live:
            m = re.match(r'0x([0-9A-Fa-f]+)\s+0x([0-9A-Fa-f]+)\s+\[\s*\d+\]\s+(.+)', line)
            if m and int(m.group(2), 16):
                syms.append((int(m.group(1), 16), m.group(3).strip()))
    return kext, syms


def member_binaries(members):
    """bundle identifier -> binary path of every member under MEMBERS"""
    out = {}
    kdir = os.path.join(members, 'kernel')
    for f in sorted(os.listdir(kdir)) if os.path.isdir(kdir) else []:
        if f.startswith('kernel') and not f.endswith('.dSYM'):
            out.setdefault('com.apple.kernel', os.path.join(kdir, f))
    kexts = os.path.join(members, 'kexts')
    for b in sorted(os.listdir(kexts)) if os.path.isdir(kexts) else []:
        plist = os.path.join(kexts, b, 'Contents', 'Info.plist')
        if not os.path.exists(plist):
            continue
        info = plistlib.load(open(plist, 'rb'))
        exe = os.path.join(kexts, b, 'Contents', 'MacOS', info.get('CFBundleExecutable', ''))
        if os.path.isfile(exe):
            out[info['CFBundleIdentifier']] = exe
    return out


class Collection:
    def __init__(self, path, members, maps=()):
        if os.path.isdir(path):
            path = os.path.join(path, 'kernel')
        self.data = open(path, 'rb').read()
        self.binaries = member_binaries(members)
        self.ranges = []        # (start, end, bundle, member section start)
        self.syms = {}
        for o, cmd in commands(self.data, 0):
            if cmd != LC_FILESET_ENTRY:
                continue
            _, fileoff, name_off = struct.unpack_from('<QQI', self.data, o + 8)
            bundle = self.data[o + name_off:self.data.index(b'\0', o + name_off)].decode()
            own = None
            if bundle in self.binaries:
                mdata = open(self.binaries[bundle], 'rb').read()
                own = sections(mdata, 0)
                syms = symbols(mdata)
                self.syms[bundle] = (syms, [x[0] for x in syms])
            for key, (addr, size) in sections(self.data, fileoff).items():
                if size:
                    base = own[key][0] if own and key in own else None
                    self.ranges.append((addr, addr + size, bundle, base, key))
        self.ranges.sort()
        self.starts = [r[0] for r in self.ranges]
        # link maps: matched to a member by the .kext directory the map names
        bydir = {os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(v)))): k
                 for k, v in self.binaries.items()}
        for mp in maps:
            kext, syms = link_map(mp)
            bundle = bydir.get(kext)
            if bundle is None:
                sys.exit('%s: no member %s' % (mp, kext))
            merged = sorted(set(self.syms.get(bundle, ([], []))[0]) | set(syms))
            self.syms[bundle] = (merged, [x[0] for x in merged])

    def name(self, addr):
        i = bisect.bisect_right(self.starts, addr) - 1
        if i < 0 or addr >= self.ranges[i][1]:
            return None
        start, _, bundle, base, key = self.ranges[i]
        short = [w for w in bundle.split('.') if w != 'kext'][-1]
        if base is None:
            return '%s %s,%s+0x%x' % (short, key[0], key[1], addr - start)
        own = base + (addr - start)
        syms, addrs = self.syms.get(bundle, ([], []))
        j = bisect.bisect_right(addrs, own) - 1 if syms else -1
        if j < 0:
            return '%s 0x%x' % (short, own)
        return '%s %s+0x%x' % (short, demangle(syms[j][1]), own - syms[j][0])


def main():
    args, maps = sys.argv[1:], []
    while '--map' in args:
        i = args.index('--map')
        maps.append(args[i + 1])
        del args[i:i + 2]
    if len(args) not in (2, 3):
        sys.exit(__doc__)
    kc = Collection(args[0], args[1], maps)
    report = open(args[2]) if len(args) == 3 else sys.stdin
    for line in report:
        line = line.rstrip('\n')
        if re.search(r'(^|: )\s+(bt|continuation)\b', line):
            line = re.sub(r'0x([0-9a-f]+)', lambda m: '%s [%s]' % (m.group(0), kc.name(int(m.group(1), 16)) or '?'), line)
        elif ' event 0x' in line:
            line = re.sub(r'event 0x([0-9a-f]+)', lambda m: m.group(0) + (' [%s]' % kc.name(int(m.group(1), 16)) if kc.name(int(m.group(1), 16)) else ''), line)
        print(line)


if __name__ == '__main__':
    main()
