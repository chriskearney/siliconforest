# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""A model of a Mac's internal disk that answers the installer's commands. Tests only.

FakeMac renders `diskutil list/info/apfs list -plist` and the other read-only answers from
its state, with the keys and shapes of real output (compared in the tests with a scrubbed
recording from a real Mac, fixtures/real-m5-scrubbed), and applies the changing commands
(resizeContainer, addPartition, newfs_msdos, eraseVolume, deleteContainer, bless, ...) to
that state. It is SYNTHETIC: it behaves as diskutil's manual and the Asahi installer's use
of it say, not as a measured diskutil does in every corner.

SimulatedAsahi issues, through the gate, the same commands in the same order as the Asahi
installer v0.9.2 does for "install into free space" (main.py, stub.py, osinstall.py, read
for this; checked against the real code's commands, fixtures/asahi-v0.9.2-commands.txt), and
copies the boot partition's files like it; the root is written by sf_engine.finish.
"""
import io
import json
import os
import pathlib
import plistlib
import re
import tarfile
import tempfile
import uuid as uuidlib
import zipfile

MiB = 1 << 20


def fake_uuid(*parts):
    return str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, 'siliconforest-test:' + ':'.join(str(p) for p in parts))).upper()


class FakeMac:
    def __init__(self, disk_bytes=500_107_862_016, macos_bytes=None, macos_used=120e9, target='J293', hw_model='MacBookPro17,1',
                 macos='15.6.1', build='24G90', filevault='FileVault is Off.', snapshots=0, on_ac=True, console='user', admin=True,
                 snapshot_overhead=0, translated=False, delete_leaves_partition=False, name='stock'):
        self.name, self.block = name, 4096
        self.disk_bytes = disk_bytes
        self.cmd = {
            ('sw_vers', '-productVersion'): macos, ('sw_vers', '-buildVersion'): build,
            ('sysctl', '-n', 'hw.targettype'): target, ('sysctl', '-n', 'hw.model'): hw_model,
            ('sysctl', '-in', 'sysctl.proc_translated'): '1' if translated else '0',
            ('stat', '-f', '%Su', '/dev/console'): console,
            ('fdesetup', 'status'): filevault,
            ('tmutil', 'listlocalsnapshots', '/'): 'Snapshots for disk /:\n' + ''.join(
                'com.apple.TimeMachine.2026-11-%02d-120000.local\n' % (i + 1) for i in range(snapshots)),
            ('pmset', '-g', 'batt'): ("Now drawing from 'AC Power'\n" if on_ac else "Now drawing from 'Battery Power'\n"),
        }
        self.admin = {console} if admin else set()
        self.overhead = snapshot_overhead
        self.delete_leaves_partition = delete_leaves_partition
        self.tmp = tempfile.mkdtemp(prefix='fakemac-')
        self.parts, self.containers = [], {}
        self.next_disk = 4
        self.events = []
        self.mounts = {}
        # the stock layout of an Apple silicon Mac with macOS 12 or later
        isc = 524_288_000
        rec = 5_368_664_064
        usable_end = (disk_bytes - 34 * 512) // 4096 * 4096
        start = 40 * 512 // 4096 * 4096 + 4096 * 5
        mac = macos_bytes or (usable_end - rec - isc - start)
        self._add_part(start, isc, 'Apple_APFS_ISC', container='disk1', volumes=[('iSCPreboot', ['Preboot']), ('xART', ['xART']), ('Hardware', ['Hardware']), ('Recovery', ['Recovery'])], used=50e6)
        self._add_part(start + isc, mac, 'Apple_APFS', container='disk3', volumes=[('Macintosh HD', ['System']), ('Preboot', ['Preboot']), ('Recovery', ['Recovery']), ('Update', ['Update']), ('VM', ['VM']), ('Macintosh HD - Data', ['Data'])],
                       used=macos_used, filevault='is on' in filevault.lower())
        self._add_part(usable_end - rec, rec, 'Apple_APFS_Recovery', container='disk2', volumes=[('Recovery', ['Recovery']), ('Update', ['Update'])], used=1.4e9)
        self.macos_ref = 'disk3'
        self.default_boot = '/dev/disk3s1'

    # ---- state helpers --------------------------------------------------------------------
    def _add_part(self, offset, size, content, label='', container=None, volumes=(), used=0, filevault=False, n=None):
        n = n or (max([p['n'] for p in self.parts] or [0]) + 1)
        p = dict(n=n, offset=int(offset), size=int(size), content=content, label=label, uuid=fake_uuid(self.name, 'part', n, offset), container=container)
        self.parts.append(p)
        if container:
            vols = [dict(dev='%ss%d' % (container, i + 1), name=v[0], roles=list(v[1]), fv=filevault and v[1] in (['System'], ['Data']),
                         uuid=fake_uuid(self.name, container, i)) for i, v in enumerate(volumes)]
            self.containers[container] = dict(store='disk0s%d' % n, ceiling=int(size), used=int(used), volumes=vols, uuid=fake_uuid(self.name, 'ctnr', container))
        self.parts.sort(key=lambda q: q['offset'])
        return p

    def dev(self, p):
        return 'disk0s%d' % p['n']

    def part(self, dev):
        dev = re.sub(r'^/dev/r?', '', dev)
        return next((p for p in self.parts if self.dev(p) == dev), None)

    def ctnr_by_ref(self, ref):
        return self.containers.get(re.sub(r'^/dev/', '', ref))

    def usable(self):
        return 40 * 512, (self.disk_bytes - 34 * 512) // 4096 * 4096

    def add_stub(self, name, at, size, label='SiliconForest', complete=True):
        """An existing second system (Asahi Linux's stub, or ours) at byte `at`."""
        ref = 'disk%d' % self.next_disk
        self.next_disk += 1
        vols = [(label + ' - Data', ['Data']), (label, ['System']), ('Preboot', ['Preboot']), ('Recovery', ['Recovery'])] if complete else [(label, [])]
        return self._add_part(at, size, 'Apple_APFS', container=ref, volumes=vols, used=1.8e9)

    # ---- renderings ---------------------------------------------------------------------
    def list_plist(self):
        whole = dict(Content='GUID_partition_scheme', DeviceIdentifier='disk0', OSInternal=False, Size=self.disk_bytes,
                     Partitions=[dict(Content=p['content'], DeviceIdentifier=self.dev(p), DiskUUID=p['uuid'], Size=p['size'],
                                      **({'VolumeName': p['label']} if p['label'] else {})) for p in self.parts])
        out = [whole]
        for ref, c in sorted(self.containers.items(), key=lambda kv: int(kv[0][4:])):
            out.append(dict(Content='Apple_APFS_Container', DeviceIdentifier=ref, OSInternal=False, Size=c['ceiling'], Partitions=[],
                            APFSPhysicalStores=[dict(DeviceIdentifier=c['store'])],
                            APFSVolumes=[dict(CapacityInUse=0, DeviceIdentifier=v['dev'], DiskUUID=v['uuid'], OSInternal=False, Size=c['ceiling'],
                                              VolumeName=v['name'], VolumeUUID=v['uuid']) for v in c['volumes']]))
        return plistlib.dumps(dict(AllDisks=['disk0'] + [self.dev(p) for p in self.parts], AllDisksAndPartitions=out,
                                   VolumesFromDisks=[v['name'] for c in self.containers.values() for v in c['volumes']],
                                   WholeDisks=['disk0'] + sorted(self.containers)))

    def apfs_plist(self, only=None):
        cs = []
        for ref, c in sorted(self.containers.items(), key=lambda kv: int(kv[0][4:])):
            if only is not None and ref != only:
                continue
            p = self.part(c['store'])
            cs.append(dict(APFSContainerUUID=c['uuid'], CapacityCeiling=c['ceiling'], CapacityFree=max(0, c['ceiling'] - c['used']),
                           ContainerReference=ref, DesignatedPhysicalStore=c['store'],
                           PhysicalStores=[dict(DeviceIdentifier=c['store'], DiskUUID=p['uuid'], Size=p['size'])],
                           Volumes=[dict(APFSVolumeUUID=v['uuid'], CapacityInUse=0, CapacityQuota=0, CapacityReserve=0, CryptoMigrationOn=False,
                                         DeviceIdentifier=v['dev'], Encryption=v['fv'], FileVault=v['fv'], Locked=False, Name=v['name'], Roles=v['roles'])
                                    for v in c['volumes']]))
        return plistlib.dumps(dict(Containers=cs))

    def info_plist(self, dev):
        if dev == '/':
            c = self.containers[self.macos_ref]
            return plistlib.dumps(dict(APFSContainerReference=self.macos_ref, DeviceIdentifier=self.macos_ref + 's1s1', MountPoint='/',
                                       ParentWholeDisk=self.macos_ref, VolumeName=c['volumes'][0]['name'], Internal=True, Content='41504653-0000-11AA-AA11-00306543ECAC'))
        if dev == 'disk0':
            return plistlib.dumps(dict(Content='GUID_partition_scheme', DeviceBlockSize=self.block, DeviceIdentifier='disk0', Internal=True,
                                       VirtualOrPhysical='Physical', WholeDisk=True, Size=self.disk_bytes, BusProtocol='Apple Fabric',
                                       MediaName='APPLE SSD (synthetic)', SolidState=True))
        p = self.part(dev)
        if p is None:
            c = self.ctnr_by_ref(dev)
            if c is None:
                return None
            return plistlib.dumps(dict(DeviceIdentifier=dev, APFSContainerReference=dev, Size=c['ceiling']))
        d = dict(Content=p['content'], DeviceBlockSize=self.block, DeviceIdentifier=self.dev(p), DeviceNode='/dev/' + self.dev(p), DiskUUID=p['uuid'],
                 Internal=True, ParentWholeDisk='disk0', PartitionMapPartition=True, PartitionMapPartitionOffset=p['offset'], Size=p['size'],
                 TotalSize=p['size'], WholeDisk=False, VolumeName=p['label'], MountPoint=self.mounts.get(self.dev(p), ''))
        if p['container']:
            d['APFSContainerReference'] = p['container']
        return plistlib.dumps(d)

    def limits_plist(self, dev):
        p = self.part(dev)
        c = self.containers[p['container']]
        mn = int(c['used'] + self.overhead + 10e9)
        return plistlib.dumps(dict(ContainerCurrentSize=c['ceiling'], CurrentSize=c['ceiling'], MaximumSize=c['ceiling'],
                                   MinimumSizeNoGuard=mn - int(2e9), MinimumSizePreferred=mn, Type='APFSContainerReference'))

    # ---- the commands -------------------------------------------------------------------
    def __call__(self, argv, input=None):
        argv = [str(a) for a in argv]
        self.events.append(argv)
        t = tuple(argv)
        if t in self.cmd:
            return 0, self.cmd[t].encode()
        a = argv
        if a[:4] == ['dseditgroup', '-o', 'checkmember', '-m']:
            u = a[4]
            return (0, ('yes %s is a member of admin\n' % u).encode()) if u in self.admin else (0, ('no %s is NOT a member of admin\n' % u).encode())
        if a == ['bless', '--getBoot']:
            return 0, (self.default_boot + '\n').encode()
        if a[0] == 'diskutil':
            return self.diskutil(a[1:])
        if a[0] == 'newfs_msdos':
            p = self.part(a[-1])
            if p is None:
                return 1, b'no such device'
            p['label'] = a[a.index('-v') + 1] if '-v' in a else 'NO NAME'
            p['formatted'] = 'fat'
            return 0, b''
        if a[0] == 'bless' and '--setBoot' in a:
            self.default_boot = a[a.index('--device') + 1]
            return 0, b''
        if a[0] in ('shutdown', 'reboot'):
            self.events.append(['POWER', a[1]])
            return 0, b''
        return 127, ('fakemac: no answer for %r' % (argv,)).encode()

    def diskutil(self, a):
        if a == ['list', '-plist']:
            return 0, self.list_plist()
        if a == ['apfs', 'list', '-plist']:
            return 0, self.apfs_plist()
        if a[:2] == ['apfs', 'list'] and len(a) == 4 and a[3] == '-plist':
            return (0, self.apfs_plist(a[2])) if a[2] in self.containers else (1, b'no such container')
        if a[:2] == ['info', '-plist']:
            out = self.info_plist(a[2])
            return (0, out) if out else (1, b'Could not find disk')
        if a[:2] == ['apfs', 'listVolumeGroups']:
            c = self.ctnr_by_ref(a[2])
            if c is None:
                return 1, b'no such container'
            sysv = [v for v in c['volumes'] if v['roles'] == ['System']]
            data = [v for v in c['volumes'] if v['roles'] == ['Data']]
            groups = [dict(APFSVolumeGroupUUID=fake_uuid(self.name, 'vg', a[2]),
                           Volumes=[dict(DeviceIdentifier=v['dev'], DiskUUID=v['uuid'], NoBrowseRole=False, Role=v['roles'][0]) for v in (sysv[0], data[0])])] if sysv and data else []
            return 0, plistlib.dumps(dict(Containers=[dict(APFSContainerUUID=c['uuid'], ContainerReference=a[2], VolumeGroups=groups)]))
        if a[:2] == ['apfs', 'resizeContainer'] and a[3:] == ['limits', '-plist']:
            return 0, self.limits_plist(a[2])
        if a[0] == 'mount':
            p = self.part(a[1])
            if p is None:
                return 1, b'no such volume'
            d = self.mounts.setdefault(self.dev(p), os.path.join(self.tmp, 'mnt-' + self.dev(p)))
            os.makedirs(d, exist_ok=True)
            return 0, b'mounted'
        if a[:2] == ['apfs', 'resizeContainer']:
            p = self.part(a[2])
            c = self.containers[p['container']]
            size = int(a[3])
            if size == 0:
                nxt = [q for q in self.parts if q['offset'] >= p['offset'] + p['size']]
                size = (nxt[0]['offset'] if nxt else self.usable()[1]) - p['offset']
            elif size < int(c['used'] + self.overhead + 10e9):
                return 1, b'Error: the target size is below the minimum'
            p['size'] = c['ceiling'] = size
            return 0, b'Finished APFS operation'
        if a[0] == 'addPartition':
            after, ptype, label, size = a[1], a[2], a[3], int(a[4])
            prev = self.part(after)
            start = (prev['offset'] + prev['size']) if prev else self.usable()[0]
            start = (start + 4095) // 4096 * 4096
            nxt = [q for q in self.parts if q['offset'] >= start]
            limit = nxt[0]['offset'] if nxt else self.usable()[1]
            if start + size > limit:
                return 1, b'Error: not enough free space'
            if ptype.lower() == 'apfs':
                ref = 'disk%d' % self.next_disk
                self.next_disk += 1
                self._add_part(start, size, 'Apple_APFS', container=ref, volumes=[(label, [])], used=1e6)
            else:
                content = {'%EFI%': 'EFI', '%Linux%': 'Linux Filesystem'}.get(ptype, ptype)
                self._add_part(start, size, content)
            return 0, b'Finished partitioning'
        if a[:2] == ['apfs', 'addVolume']:
            c = self.containers[a[2]]
            role = {'D': 'Data', 'S': 'System', 'B': 'Preboot', 'R': 'Recovery'}[a[a.index('-role') + 1]]
            c['volumes'].append(dict(dev='%ss%d' % (a[2], len(c['volumes']) + 1), name=a[4], roles=[role], fv=False, uuid=fake_uuid(self.name, a[2], len(c['volumes']))))
            return 0, b''
        if a[:2] == ['apfs', 'changeVolumeRole']:
            v = self.volume(a[2])
            v['roles'] = [{'D': 'Data', 'S': 'System'}[a[3]]]
            return 0, b''
        if a[0] == 'rename':
            self.volume(a[1])['name'] = a[2]
            return 0, b''
        if a[:3] == ['eraseVolume', 'free', 'free']:
            p = self.part(a[3])
            if p is None:
                return 1, b'no such partition'
            self.parts.remove(p)
            if p['container']:
                self.containers.pop(p['container'], None)
            return 0, b''
        if a[:2] == ['apfs', 'deleteContainer']:
            ref = a[2]
            c = self.containers.pop(ref, None)
            if c is None:
                return 1, b'no such container'
            p = self.part(c['store'])
            if self.delete_leaves_partition:
                p['container'], p['content'] = None, 'Apple_HFS'
            else:
                self.parts.remove(p)
            return 0, b''
        return 127, ('fakemac: no diskutil answer for %r' % (a,)).encode()

    def volume(self, dev):
        for c in self.containers.values():
            for v in c['volumes']:
                if v['dev'] == dev:
                    return v
        raise KeyError(dev)

    def open_device(self, path, mode='rb', *args, **kw):
        dev = re.sub(r'^/dev/r?', '', path)
        p = self.part(dev)
        f = os.path.join(self.tmp, 'dev-' + dev)
        if not os.path.exists(f):
            with open(f, 'wb') as fd:
                fd.truncate(p['size'])
        return open(f, mode.replace('w', 'r+') if 'w' in mode else mode, *args, **kw)

    def device_file(self, dev):
        return os.path.join(self.tmp, 'dev-' + dev)

    def runner(self, argv):
        return self(argv)


def install_sf(mac, at=None, root_bytes=48 * (1 << 30), partial=False):
    """Put a SiliconForest installation (as the installer makes it) on the model."""
    from sf_plan import BOOT_BYTES, STUB_BYTES
    if at is None:
        rec = next(p for p in mac.parts if p['content'] == 'Apple_APFS_Recovery')
        at = rec['offset'] - STUB_BYTES - BOOT_BYTES - root_bytes - 64 * MiB
    mac.add_stub('SiliconForest', at, STUB_BYTES)
    if partial:
        return
    mac._add_part(at + STUB_BYTES, BOOT_BYTES, 'EFI', label='SFBOOT - Si')
    mac._add_part(at + STUB_BYTES + BOOT_BYTES, root_bytes, 'Linux Filesystem')


def install_asahi(mac, at, root_bytes=60e9):
    mac.add_stub('Asahi Linux', at, 2_499_805_184, label='Asahi Linux')
    mac._add_part(at + 2_499_805_184, 524_288_000, 'EFI', label='EFI - ASAHI')
    mac._add_part(at + 2_499_805_184 + 524_288_000, root_bytes, 'Linux Filesystem')


# ---- a synthetic release, built in a temporary directory ----------------------------------------
# A stand-in for the release's own sf_personalize.py (release/image/ on the release-image branch):
# the same command line and outputs, made with the release's pdsf_pack.py. SYNTHETIC.
PERSONALIZE = r'''
import argparse, json, os, re, subprocess, sys
ap = argparse.ArgumentParser()
ap.add_argument('bootdir'); ap.add_argument('--partuuid', required=True)
ap.add_argument('--part-lba', type=int, required=True); ap.add_argument('--part-blocks', type=int, required=True)
ap.add_argument('-o', '--out', required=True)
a = ap.parse_args()
if not re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', a.partuuid):
    sys.exit('sf_personalize: --partuuid: expected a lower-case UUID')
meta = json.load(open(os.path.join(a.bootdir, 'boot.json')))
args = ' '.join(l.strip() for l in open(os.path.join(a.bootdir, 'bootargs.template')) if l.strip() and not l.startswith('#'))
for k, v in {'@SF_FSUUID@': meta['root_uuid'], '@SF_PARTUUID@': a.partuuid, '@SF_PART_LBA@': str(a.part_lba), '@SF_PART_BLOCKS@': str(a.part_blocks)}.items():
    if args.count(k) != 1:
        sys.exit('sf_personalize: %s occurs %d times' % (k, args.count(k)))
    args = args.replace(k, v)
os.makedirs(a.out, exist_ok=True)
open(os.path.join(a.out, 'boot.bin'), 'wb').write(open(os.path.join(a.bootdir, 'boot.bin'), 'rb').read())
cmd = [sys.executable, '-I', '-B', os.path.join(a.bootdir, 'pdsf_pack.py'), 'pack', '--kernel', os.path.join(a.bootdir, 'kernel.kc'),
       '--bootargs', args, '-o', os.path.join(a.out, 'kernel.bin')]
for kv in meta['pack_set']:
    cmd += ['--set', kv]
subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
'''


def make_release(tmp, root_image_bytes=8 * MiB, slot_offset=4 * MiB, slot_len=2 * MiB, root_min=16 * (1 << 30), parts=2):
    """SHA256SUMS, install.json, boot.tar.xz and root.ext4.xz parts as the release-image work defines them."""
    import hashlib
    import lzma
    import shutil
    b1 = pathlib.Path(__file__).resolve().parents[2] / 'integrations' / 'siliconforest' / 'm1-native-boot' / 'b1'
    fs_uuid = fake_uuid('release-root-fs').lower()
    v = 'test-1'
    boot = os.path.join(tmp, 'bootsrc')
    os.makedirs(boot)
    files = {
        'boot.bin': b'SYNTHETIC STAGE 2 for ' + fs_uuid.encode() + b'\n' + bytes(4096),
        'kernel.kc': b'SYNTHETIC KERNEL COLLECTION, NOT A KERNEL\n' * 1000,
        'bootargs.template': ('# synthetic\n-v rd=uuid boot-uuid=@SF_FSUUID@ sfnvme=3 sfnvme_ttl=0\nsfnvme_part=@SF_PARTUUID@ '
                              'sfnvme_part_lba=@SF_PART_LBA@ sfnvme_part_blocks=@SF_PART_BLOCKS@ sfnvme_write=1 sfnvme_readfence=1\n').encode(),
        'pdsf_pack.py': (b1 / 'pdsf_pack.py').read_bytes(),
        'sf_personalize.py': PERSONALIZE.encode(),
        'sf-stage1.bin': b'SYNTHETIC STAGE 1 ##m1n1_ver##test\0' + bytes(100),
        'siliconforest.icns': b'icns',
    }
    for n, d in files.items():
        pathlib.Path(boot, n).write_bytes(d)
    meta = dict(root_uuid=fs_uuid, pack_set=['display=1', 'sprr=1'],
                files={n: dict(sha256=hashlib.sha256(d).hexdigest()) for n, d in files.items()})
    pathlib.Path(boot, 'boot.json').write_text(json.dumps(meta))
    btar = os.path.join(tmp, 'siliconforest-%s-boot.tar.xz' % v)
    with tarfile.open(btar, 'w:xz') as t:
        for n in sorted(os.listdir(boot)):
            t.add(os.path.join(boot, n), n)
    shutil.rmtree(boot)
    root = bytearray(root_image_bytes)
    root[slot_offset:slot_offset + 10] = b'SFFWSLOT1\n'
    root[0:16] = b'SYNTHETIC ROOT\n\0'
    xz = lzma.compress(bytes(root), format=lzma.FORMAT_XZ)
    step = len(xz) // parts + 1
    part_files = []
    for i in range(parts):
        name = 'siliconforest-%s-root.ext4.xz.%02d' % (v, i + 1)
        pathlib.Path(tmp, name).write_bytes(xz[i * step:(i + 1) * step])
        part_files.append(name)
    f = lambda n: dict(file=n, bytes=os.path.getsize(os.path.join(tmp, n)), sha256=hashlib.sha256(pathlib.Path(tmp, n).read_bytes()).hexdigest())
    m = {
        'format': 'siliconforest-install/1', 'release': v, 'models': ['J293'], 'macos': {'min': '13.5', 'max_major': 26},
        'stub_firmware': ['13.5'], 'boot': f(os.path.basename(btar)),
        'root': dict(fs_uuid=fs_uuid, compression='xz', image_bytes=root_image_bytes, image_sha256=hashlib.sha256(bytes(root)).hexdigest(),
                     min_bytes=root_min, default_bytes=48 * (1 << 30), parts=[f(n) for n in part_files]),
        'firmware_slot': dict(offset=slot_offset, length=slot_len),
    }
    mp = os.path.join(tmp, 'siliconforest-%s-install.json' % v)
    pathlib.Path(mp).write_text(json.dumps(m, indent=1))
    names = [os.path.basename(mp), os.path.basename(btar)] + part_files
    pathlib.Path(tmp, 'SHA256SUMS').write_text(''.join('%s  %s\n' % (f(n)['sha256'], n) for n in sorted(names)))
    return m, mp, None


def firmware_tar(path):
    """A stand-in for the engine's vendorfw/firmware.tar: made-up bytes under Asahi-style names."""
    with tarfile.open(path, 'w') as t:
        for name, data in (('brcm/brcmfmac4378b1-pcie.apple,shikoku-SYNTHETIC.bin', b'not firmware' * 100),
                           ('brcm/brcmfmac4378b1-pcie.apple,shikoku-SYNTHETIC.txt', b'synthetic=1\n'),
                           ('brcm/brcmbt4378b1-shikoku-SYNTHETIC.bin', b'not bt firmware'),
                           ('apple/dfrmtfw-j293.bin', b'not touch bar firmware'),
                           ('apple/isp_SYNTHETIC.dat', b'not wanted')):
            ti = tarfile.TarInfo(name)
            ti.size = len(data)
            t.addfile(ti, io.BytesIO(data))
        ti = tarfile.TarInfo('brcm/brcmfmac4378b1-pcie.apple,shikoku-SYNTHETIC-2.bin')
        ti.type, ti.linkname = tarfile.LNKTYPE, 'brcm/brcmfmac4378b1-pcie.apple,shikoku-SYNTHETIC.bin'
        t.addfile(ti)


class SimulatedAsahi:
    """What the Asahi installer v0.9.2 asks of the disk for one "install into free space", via the gate."""

    def __init__(self, mac, gate):
        self.mac, self.gate = mac, gate

    def install(self, plan, manifest, artifacts, log, finish):
        g, mac = self.gate, self.mac
        if plan['resize']:
            r = plan['resize']
            g.run(['diskutil', 'apfs', 'resizeContainer', r['store'], str(r['to_bytes'])], why='engine')       # main.py action_resize
        g.run(['diskutil', 'addPartition', plan['after'], 'apfs', 'SiliconForest', str(plan['stub_bytes'])], why='engine')  # action_install_into_free
        stub = next(p for p in mac.parts if p['container'] and p['offset'] == plan['gap_offset'] + (-plan['gap_offset'] % 4096))
        ref, sdev = stub['container'], mac.dev(stub)
        v0 = mac.containers[ref]['volumes'][0]['dev']
        g.run(['diskutil', 'apfs', 'changeVolumeRole', v0, 'D'], why='engine')                              # stub.py prepare_volume
        g.run(['diskutil', 'rename', v0, 'SiliconForest - Data'], why='engine')
        g.run(['diskutil', 'apfs', 'addVolume', ref, 'apfs', 'SiliconForest', '-role', 'S', '-groupWith', v0], why='engine')
        g.run(['diskutil', 'apfs', 'addVolume', ref, 'apfs', 'Preboot', '-role', 'B'], why='engine')
        g.run(['diskutil', 'apfs', 'addVolume', ref, 'apfs', 'Recovery', '-role', 'R'], why='engine')
        g.run(['diskutil', 'addPartition', sdev, '%EFI%', '%noformat%', str(plan['boot_bytes'])], why='engine')   # osinstall.py partition_disk
        efi = mac.parts[mac.parts.index(stub) + 1]
        g.run(['newfs_msdos', '-F', '32', '-v', 'SFBOOT - Si', '/dev/r' + mac.dev(efi)], why='engine')
        g.run(['diskutil', 'addPartition', mac.dev(efi), '%Linux%', '%noformat%', str(plan['root_bytes'])], why='engine')
        root = mac.parts[mac.parts.index(efi) + 1]
        import sf_engine
        boot = sf_engine.unpack_boot(manifest, artifacts)
        pkg = zipfile.ZipFile(os.path.join(artifacts, 'os', sf_engine.os_package(boot, artifacts)))
        g.run(['diskutil', 'mount', mac.dev(efi)], why='engine')
        mnt = mac.mounts[mac.dev(efi)]
        for n in pkg.namelist():                                                                              # osinstall.py install: source esp
            if n.startswith('esp/') and not n.endswith('/'):
                dst = os.path.join(mnt, n[4:])
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                with open(dst, 'wb') as fd:
                    fd.write(pkg.read(n))
        pkg.close()
        fw = os.path.join(mac.tmp, 'firmware.tar')
        firmware_tar(fw)
        finish(g, manifest, artifacts, mnt, mac.dev(root), root['uuid'], root['offset'] // mac.block, root['size'] // mac.block, root['size'], fw, log)
        vol = next(v['dev'] for v in mac.containers[ref]['volumes'] if v['roles'] == ['System'])
        g.run(['bless', '--setBoot', '--device', '/dev/' + vol, '--user', 'user', '--stdinpass'], why='engine', input=b'not-a-password')  # main.py bless
        g.system('shutdown -h now')                                                                          # main.py step2_indirect
        return dict(efi=mac.dev(efi), root=mac.dev(root), stub=sdev, mount=mnt)
