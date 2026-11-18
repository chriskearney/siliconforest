#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Turn a recording of read-only commands on a real Mac into a fixture that identifies nobody.

    scrub_recording.py <recording.txt>... <output directory>

The recording is the output of a shell loop that prints `=====CMD <command>`, the command's
output and `=====RC <code>` for: diskutil list -plist, diskutil apfs list -plist, diskutil
info -plist disk0 / disk0sN / /, diskutil apfs resizeContainer <c> limits -plist, sw_vers,
sysctl, fdesetup status, tmutil listlocalsnapshots /, pmset -g batt, bless --getBoot. The
recording itself is never committed. Scrubbing:
  * every UUID is replaced, in order of first appearance, by 00000000-0000-4000-8000-<n>;
  * volume names that are not Apple's defaults are replaced (`--rename old=new`, and the
    defaults below), also inside mount points and the list of volume names;
  * the console user's name becomes "user"; drive statistics (SMART keys) are dropped;
  * the result is searched for every original UUID and name; any hit is an error.
"""
import json
import pathlib
import plistlib
import re
import sys

UUID = re.compile(r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}')
DROP = {'SMARTDeviceSpecificKeysMayVaryNotGuaranteed', 'SMARTStatus'}


def commands(paths):
    out = {}
    for p in paths:
        parts = re.split(r'^=====CMD (.*)$', pathlib.Path(p).read_text(), flags=re.M)
        for i in range(1, len(parts), 2):
            body, _, rc = parts[i + 1].rpartition('=====RC ')
            out[parts[i].strip()] = (int(rc.split()[0]) if rc.strip() else 0, body.strip('\n'))
    return out


def main(argv):
    renames = {}
    args = []
    for a in argv:
        if a.startswith('--rename='):
            old, new = a[len('--rename='):].split('=', 1)
            renames[old] = new
        else:
            args.append(a)
    *inputs, outdir = args
    cmds = commands(inputs)
    user = cmds.get('stat -f %Su /dev/console', (0, ''))[1].strip()
    seen = {}

    def uuid_sub(m):
        k = m.group(0).upper()
        if k not in seen:
            seen[k] = '00000000-0000-4000-8000-%012d' % (len(seen) + 1)
        return seen[k]

    def scrub_obj(o):
        if isinstance(o, dict):
            return {k: scrub_obj(v) for k, v in o.items() if k not in DROP}
        if isinstance(o, list):
            return [scrub_obj(v) for v in o]
        if isinstance(o, str):
            s = UUID.sub(uuid_sub, o)
            s = re.sub(r'[0-9A-Fa-f]{32,}', lambda m: '0' * len(m.group(0)), s)     # snapshot seals and other long hashes
            for old in sorted(renames, key=len, reverse=True):
                if s == old or s.endswith('/' + old) or s.startswith(old + ' - '):
                    s = s.replace(old, renames[old])
            return s
        return o

    out = pathlib.Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    names = {
        'diskutil list -plist': 'list.plist', 'diskutil apfs list -plist': 'apfs.plist',
        'diskutil info -plist /': 'info-root.plist', 'diskutil info -plist disk0': 'info-disk0.plist',
    }
    for cmd, (rc, body) in cmds.items():
        m = re.match(r'^diskutil info -plist (disk0s\d+)$', cmd)
        if m:
            names[cmd] = 'info-%s.plist' % m.group(1)
        m = re.match(r'^diskutil apfs resizeContainer (disk\d+(s\d+)?) limits -plist$', cmd)
        if m:
            names[cmd] = 'limits-%s.plist' % m.group(1)
    written = []
    for cmd, fname in names.items():
        if cmd not in cmds or cmds[cmd][0] != 0:
            continue
        data = scrub_obj(plistlib.loads(cmds[cmd][1].encode()))
        (out / fname).write_bytes(plistlib.dumps(data))
        written.append(fname)
    text = lambda c: cmds.get(c, (1, ''))[1].strip()
    facts = {
        'sw_vers -productVersion': [l.split(':')[1].strip() for l in text('sw_vers').splitlines() if l.startswith('ProductVersion')][0],
        'sw_vers -buildVersion': [l.split(':')[1].strip() for l in text('sw_vers').splitlines() if l.startswith('BuildVersion')][0],
        'sysctl -n hw.model': text('sysctl -n hw.model hw.targettype machdep.cpu.brand_string hw.memsize').splitlines()[0],
        'sysctl -n hw.targettype': text('sysctl -n hw.model hw.targettype machdep.cpu.brand_string hw.memsize').splitlines()[1],
        'sysctl -in sysctl.proc_translated': text('sysctl -in sysctl.proc_translated'),
        'stat -f %Su /dev/console': 'user',
        'dseditgroup -o checkmember -m user admin': text('dseditgroup -o checkmember -m %s admin' % user).replace(user, 'user'),
        'fdesetup status': text('fdesetup status'),
        'tmutil listlocalsnapshots /': text('tmutil listlocalsnapshots /'),
        'pmset -g batt': text('pmset -g batt').splitlines()[0],
        'bless --getBoot': text('bless --getBoot'),
    }
    (out / 'facts.json').write_text(json.dumps(facts, indent=1, sort_keys=True) + '\n')
    written.append('facts.json')
    # nothing of the original may be left
    blob = b''.join((out / f).read_bytes() for f in written).decode()
    leaks = [u for u in seen if u in blob.upper()] + [n for n in list(renames) + ([user] if user else []) if n and re.search(r'\b%s\b' % re.escape(n), blob)]
    if leaks:
        raise SystemExit('scrub failed, still present: %r' % leaks)
    print('wrote %s: %s (%d UUIDs replaced)' % (out, ', '.join(written), len(seen)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
