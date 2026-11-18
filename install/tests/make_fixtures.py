#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Write the SYNTHETIC disk-layout fixtures (install/tests/fixtures/m1-*) from FakeMac scenarios.

    make_fixtures.py            write them
    make_fixtures.py --check    exit 1 if a committed fixture differs from what this writes

Every value in them is made up (sizes chosen to be typical of a 512 GB M1 MacBook Pro, UUIDs
derived from the scenario name). The one recording from a real Mac is fixtures/real-m5-scrubbed
(scrub_recording.py); it is a Mac the installer must refuse.
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent / 'engine')]
from fakemac import FakeMac, install_asahi, install_sf  # noqa: E402

GB = 1_000_000_000


def stock():
    return FakeMac(name='m1-stock')


def asahi():
    m = FakeMac(name='m1-asahi', macos_bytes=300 * GB)
    mac = m.part('disk0s2')
    install_asahi(m, mac['offset'] + mac['size'], root_bytes=70 * GB)
    return m


def asahi_full():
    m = FakeMac(name='m1-asahi-no-free-space', macos_bytes=380 * GB)
    mac = m.part('disk0s2')
    rec = m.part('disk0s3')
    at = mac['offset'] + mac['size']
    install_asahi(m, at, root_bytes=rec['offset'] - at - 2_499_805_184 - 524_288_000)
    return m


def siliconforest():
    m = FakeMac(name='m1-siliconforest', macos_bytes=420 * GB)
    mac = m.part('disk0s2')
    install_sf(m, at=mac['offset'] + mac['size'])
    return m


def partial():
    m = FakeMac(name='m1-partial-siliconforest', macos_bytes=420 * GB)
    mac = m.part('disk0s2')
    install_sf(m, at=mac['offset'] + mac['size'], partial=True)
    return m


SCENARIOS = {
    'm1-stock': stock,
    'm1-filevault-on': lambda: FakeMac(name='m1-filevault-on', filevault='FileVault is On.'),
    'm1-too-little-space': lambda: FakeMac(name='m1-too-little-space', macos_used=430 * GB),
    'm1-snapshots': lambda: FakeMac(name='m1-snapshots', snapshots=6, snapshot_overhead=40 * GB),
    'm1-asahi': asahi,
    'm1-asahi-no-free-space': asahi_full,
    'm1-siliconforest': siliconforest,
    'm1-partial-siliconforest': partial,
}

FACT_COMMANDS = [
    ['sw_vers', '-productVersion'], ['sw_vers', '-buildVersion'], ['sysctl', '-n', 'hw.targettype'], ['sysctl', '-n', 'hw.model'],
    ['sysctl', '-in', 'sysctl.proc_translated'], ['stat', '-f', '%Su', '/dev/console'], ['dseditgroup', '-o', 'checkmember', '-m', 'user', 'admin'],
    ['fdesetup', 'status'], ['tmutil', 'listlocalsnapshots', '/'], ['pmset', '-g', 'batt'], ['bless', '--getBoot'],
]


def render(mac):
    files = {'list.plist': mac(['diskutil', 'list', '-plist'])[1], 'apfs.plist': mac(['diskutil', 'apfs', 'list', '-plist'])[1],
             'info-root.plist': mac(['diskutil', 'info', '-plist', '/'])[1], 'info-disk0.plist': mac(['diskutil', 'info', '-plist', 'disk0'])[1]}
    for p in mac.parts:
        files['info-%s.plist' % mac.dev(p)] = mac(['diskutil', 'info', '-plist', mac.dev(p)])[1]
    files['limits-disk0s2.plist'] = mac(['diskutil', 'apfs', 'resizeContainer', 'disk0s2', 'limits', '-plist'])[1]
    facts = {' '.join(c): mac(c)[1].decode().strip() for c in FACT_COMMANDS}
    files['facts.json'] = (json.dumps(facts, indent=1, sort_keys=True) + '\n').encode()
    return files


class Replay:
    """A runner that answers from a fixture directory (what the tests and the planner see)."""

    def __init__(self, path):
        self.path = pathlib.Path(path)
        self.facts = json.loads((self.path / 'facts.json').read_text())

    def __call__(self, argv):
        key = ' '.join(argv)
        if key in self.facts:
            return 0, self.facts[key].encode()
        if argv[:2] == ['dseditgroup', '-o']:
            return 0, ('no %s is NOT a member of admin' % argv[4]).encode()
        name = {'diskutil list -plist': 'list.plist', 'diskutil apfs list -plist': 'apfs.plist', 'diskutil info -plist /': 'info-root.plist'}.get(key)
        if name is None and argv[:3] == ['diskutil', 'info', '-plist']:
            name = 'info-%s.plist' % argv[3]
        if name is None and argv[:2] == ['diskutil', 'apfs'] and argv[2] == 'resizeContainer' and argv[4:] == ['limits', '-plist']:
            # diskutil accepts the container or its physical store; the fixture is stored under one of them
            for cand in ('limits-%s.plist' % argv[3], 'limits-disk0s2.plist', 'limits-disk3.plist'):
                if (self.path / cand).exists():
                    name = cand
                    break
        if name and (self.path / name).exists():
            return 0, (self.path / name).read_bytes()
        return 1, b''


def main(argv):
    out = HERE / 'fixtures'
    bad = []
    for name, make in SCENARIOS.items():
        files = render(make())
        d = out / name
        for fname, data in files.items():
            if '--check' in argv:
                if not (d / fname).exists() or (d / fname).read_bytes() != data:
                    bad.append('%s/%s' % (name, fname))
            else:
                d.mkdir(parents=True, exist_ok=True)
                (d / fname).write_bytes(data)
        if '--check' in argv and d.exists():
            extra = set(p.name for p in d.iterdir()) - set(files)
            bad += ['%s/%s (stale)' % (name, e) for e in sorted(extra)]
    if bad:
        print('fixtures out of date:', *bad, sep='\n  ')
        return 1
    print('fixtures %s' % ('up to date' if '--check' in argv else 'written'))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
