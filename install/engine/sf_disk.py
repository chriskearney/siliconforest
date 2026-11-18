# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The Mac's internal disk as diskutil describes it. Parsing only: nothing here runs a command.

Inputs are the property lists of `diskutil list -plist`, `diskutil apfs list -plist`,
`diskutil info -plist <disk or partition>` and `diskutil info -plist /`. The way the system
disk and the free areas are found follows the Asahi Linux installer (src/diskutil.py,
MIT, "Copyright (c) 2021 The Asahi Linux contributors"): the internal physical disk whose
first partition is the iBoot system container, usable range 40 to size-34 sectors of 512
bytes, gaps under 16 MiB ignored.
"""
import hashlib
import json
import plistlib
from dataclasses import dataclass, field

FREE_THRESHOLD = 16 << 20
ALIGN = 1 << 20
LINUX_TYPES = {'Linux Filesystem', 'Linux', '0FC63DAF-8483-4772-8E79-3D69D8477DE4'}
EFI_TYPES = {'EFI', 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'}
APPLE_SYSTEM_TYPES = {'Apple_APFS_ISC', 'Apple_APFS_Recovery'}
STUB_NAME = 'SiliconForest'
BOOT_LABEL = 'SFBOOT'


def align_up(v, a=ALIGN):
    return (v + a - 1) // a * a


def align_down(v, a=ALIGN):
    return v // a * a


def gb(v):
    return '%.1f GB' % (v / 1e9)


@dataclass
class Volume:
    dev: str
    name: str
    roles: list
    filevault: bool = False
    locked: bool = False


@dataclass
class Container:
    ref: str
    store: str
    ceiling: int
    free: int
    volumes: list = field(default_factory=list)

    def system_names(self):
        return [v.name for v in self.volumes if v.roles == ['System']]


@dataclass
class Part:
    dev: str
    offset: int
    size: int
    content: str = ''
    uuid: str = ''
    label: str = ''
    free: bool = False
    container: object = None

    @property
    def end(self):
        return self.offset + self.size

    def kind(self):
        if self.free:
            return 'free'
        if self.content in APPLE_SYSTEM_TYPES:
            return 'apple-system'
        if self.content == 'Apple_APFS':
            return 'apfs'
        if self.content in EFI_TYPES:
            return 'efi'
        if self.content in LINUX_TYPES:
            return 'linux'
        return 'other'


@dataclass
class Install:
    """SiliconForest's pieces as found: the stub container, SFBOOT, the root partition."""
    stub: object = None
    boot: object = None
    root: object = None
    problems: list = field(default_factory=list)

    @property
    def complete(self):
        return bool(self.stub and self.boot and self.root and not self.problems)

    def parts(self):
        return [p for p in (self.stub, self.boot, self.root) if p is not None]


class LayoutError(Exception):
    pass


class Layout:
    def __init__(self, disk, size, block_size, parts, containers, macos_ref, internal=True):
        self.disk, self.size, self.block_size = disk, size, block_size
        self.parts, self.containers, self.macos_ref, self.internal = parts, containers, macos_ref, internal

    # ---- construction -------------------------------------------------------------------
    @classmethod
    def parse(cls, list_plist, apfs_plist, infos, root_info):
        """infos: {device identifier: `diskutil info -plist` output} for the disk and its partitions."""
        lst = plistlib.loads(list_plist)
        apfs = plistlib.loads(apfs_plist)
        infos = {k: plistlib.loads(v) for k, v in infos.items()}
        root = plistlib.loads(root_info)
        containers = {}
        for c in apfs.get('Containers', []):
            vols = [Volume(v['DeviceIdentifier'], v.get('Name', ''), list(v.get('Roles', [])),
                           bool(v.get('FileVault', False)), bool(v.get('Locked', False)))
                    for v in c.get('Volumes', [])]
            containers[c['ContainerReference']] = Container(
                c['ContainerReference'], c['DesignatedPhysicalStore'], int(c['CapacityCeiling']),
                int(c['CapacityFree']), vols)
        by_store = {c.store: c for c in containers.values()}
        disk = None
        for entry in lst.get('AllDisksAndPartitions', []):
            name = entry.get('DeviceIdentifier')
            info = infos.get(name)
            parts = entry.get('Partitions', [])
            if not info or not parts:
                continue
            if info.get('VirtualOrPhysical', 'Physical') == 'Virtual' or not info.get('Internal', False):
                continue
            if parts[0].get('Content') == 'Apple_APFS_ISC':
                disk = entry
                break
        if disk is None:
            raise LayoutError('no internal disk that starts with the iBoot system container')
        name = disk['DeviceIdentifier']
        dinfo = infos[name]
        size = int(dinfo.get('Size', disk.get('Size')))
        block = int(dinfo.get('DeviceBlockSize', 4096))
        found = []
        for p in disk['Partitions']:
            dev = p['DeviceIdentifier']
            pi = infos.get(dev)
            if pi is None:
                raise LayoutError('no diskutil info for ' + dev)
            found.append(Part(dev, int(pi['PartitionMapPartitionOffset']), int(pi['Size']), pi.get('Content', p.get('Content', '')),
                              pi.get('DiskUUID', ''), pi.get('VolumeName', '') or '', False, by_store.get(dev)))
        found.sort(key=lambda q: q.offset)
        pos, end = 40 * 512, align_down(size - 34 * 512, 4096)
        out, prev = [], name
        for q in found:
            if q.offset - pos > FREE_THRESHOLD:
                out.append(Part(prev, pos, q.offset - pos, free=True))
            out.append(q)
            prev, pos = q.dev, q.end
        if end - pos > FREE_THRESHOLD:
            out.append(Part(prev, pos, end - pos, free=True))
        macos_ref = root.get('APFSContainerReference')
        return cls(name, size, block, out, containers, macos_ref, bool(dinfo.get('Internal', False)))

    # ---- questions ------------------------------------------------------------------------
    def real_parts(self):
        return [p for p in self.parts if not p.free]

    def gaps(self):
        return [p for p in self.parts if p.free]

    def macos_part(self):
        for p in self.parts:
            if p.container is not None and p.container.ref == self.macos_ref:
                return p
        return None

    def after(self, part):
        i = self.parts.index(part)
        return self.parts[i + 1] if i + 1 < len(self.parts) else None

    def gap_after(self, part):
        nxt = self.after(part)
        return nxt if nxt is not None and nxt.free else None

    def find_ours(self):
        """SiliconForest as the installer lays it out: stub container, then SFBOOT, then root."""
        inst = Install()
        def ours(c):
            # complete: a System volume named SiliconForest; interrupted early: the first volume
            # diskutil made ("SiliconForest", no role yet) or the renamed "SiliconForest - Data"
            return any(v.name == STUB_NAME or v.name == STUB_NAME + ' - Data' for v in c.volumes)
        stubs = [p for p in self.parts if p.container is not None and p.container.ref != self.macos_ref and ours(p.container)]
        if not stubs:
            boots = [p for p in self.parts if p.kind() == 'efi' and p.label.upper().startswith(BOOT_LABEL)]
            if boots:
                inst.boot = boots[0]
                inst.problems.append('a %s partition (%s) without the SiliconForest startup volume' % (BOOT_LABEL, boots[0].dev))
                nxt = self.after(boots[0])
                if nxt is not None and nxt.kind() == 'linux':
                    inst.root = nxt
            return inst if inst.boot else None
        if len(stubs) > 1:
            inst.problems.append('more than one startup volume named %s (%s)' % (STUB_NAME, ', '.join(p.dev for p in stubs)))
        inst.stub = stubs[0]
        nxt = self.after(inst.stub)
        if nxt is not None and nxt.kind() == 'efi' and nxt.label.upper().startswith(BOOT_LABEL):
            inst.boot = nxt
            nxt = self.after(nxt)
            if nxt is not None and nxt.kind() == 'linux':
                inst.root = nxt
            else:
                inst.problems.append('no Linux-type root partition directly after %s' % inst.boot.dev)
        else:
            inst.problems.append('no %s partition directly after the startup volume %s' % (BOOT_LABEL, inst.stub.dev))
        return inst

    def other_systems(self):
        """Startup volumes that are neither macOS's own container nor ours (Asahi Linux and the like)."""
        out = []
        for p in self.parts:
            c = p.container
            if c is None or c.ref == self.macos_ref or p.content in APPLE_SYSTEM_TYPES:
                continue
            names = c.system_names()
            if names and STUB_NAME not in names:
                out.append('%s: %s (%s)' % (p.dev, ', '.join(names), gb(p.size)))
        for p in self.parts:
            if p.kind() in ('efi', 'linux') and not p.label.upper().startswith(BOOT_LABEL):
                out.append('%s: %s partition %s(%s)' % (p.dev, p.kind().upper() if p.kind() == 'efi' else 'Linux',
                                                         (p.label + ' ') if p.label else '', gb(p.size)))
        return out

    def digest(self):
        """Identity of the partition table as the plan saw it. Free space inside containers is left out
        (macOS changes it all the time); it is checked again before any change."""
        rows = [(p.dev, p.offset, p.size, p.content, p.uuid, bool(p.free)) for p in self.parts]
        rows.append(('macos', self.macos_ref, self.size, self.block_size))
        return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()

    def table(self):
        lines = []
        mac = self.macos_part()
        ours = self.find_ours()
        mine = set(p.dev for p in ours.parts()) if ours else set()
        for p in self.parts:
            if p.free:
                what = 'free space'
            elif p is mac:
                what = 'macOS (%s), %s free inside' % (', '.join(p.container.system_names()) or 'APFS', gb(p.container.free))
            elif p.dev in mine:
                what = 'SiliconForest ' + {'apfs': 'startup volume', 'efi': 'boot partition', 'linux': 'root'}.get(p.kind(), p.kind())
            elif p.content == 'Apple_APFS_ISC':
                what = 'Apple system container (iBoot)'
            elif p.content == 'Apple_APFS_Recovery':
                what = 'Apple system recovery'
            elif p.container is not None:
                what = 'APFS: ' + (', '.join(p.container.system_names()) or 'no system volume')
            else:
                what = '%s%s' % (p.content, (' "%s"' % p.label) if p.label else '')
            lines.append('  %-10s %12s  %s' % ('' if p.free else p.dev, gb(p.size), what))
        return '\n'.join(lines)
