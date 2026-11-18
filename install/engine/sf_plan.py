# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""What the installer finds on this Mac and what it would do: facts, checks and plans.

Nothing here changes anything. `gather` runs read-only commands through the runner it is
given (tests give it recorded outputs); `check`, `plan_install`, `plan_uninstall` and
`plan_update` are pure functions of those facts. The limits on shrinking macOS follow the
Asahi Linux installer (src/main.py, MIT, "Copyright (c) 2021 The Asahi Linux
contributors"): keep 38 GB free in macOS, never go below `diskutil apfs resizeContainer
... limits`' MinimumSizePreferred, warn when snapshots make that minimum much larger.
"""
import re
from dataclasses import dataclass, field

from sf_disk import ALIGN, Layout, LayoutError, align_down, align_up, gb

STUB_BYTES = align_down(2_500_000_000, ALIGN)       # Asahi installer STUB_SIZE: 2,499,805,184
BOOT_BYTES = 524_288_000                             # SFBOOT, 500 MiB (FAT32)
MIN_FREE_MACOS = 38_000_000_000                      # Asahi installer MIN_FREE_OS
OVERHEAD_WARN = 16_000_000_000                       # Asahi installer: snapshot overhead warning
# Before a release exists the root image size is not known; these stand in and are marked as such.
PROVISIONAL_ROOT_MIN = 16 * (1 << 30)
PROVISIONAL_ROOT_DEFAULT = 48 * (1 << 30)


@dataclass
class Model:
    target: str
    hw_model: str
    device_class: str
    chip: str
    status: str
    macos_min: str
    macos_max_major: int
    stub_firmware: list
    name: str


def load_models(text):
    out = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        f = line.split('\t')
        if len(f) != 9:
            raise ValueError('models.tsv: 9 tab-separated fields expected: ' + line)
        out[f[0].upper()] = Model(f[0].upper(), f[1], f[2], f[3], f[4], f[5], int(f[6]), f[7].split(','), f[8])
    return out


def version_tuple(v):
    return tuple(int(x) for x in re.findall(r'\d+', v or '0')[:4]) or (0,)


@dataclass
class Finding:
    level: str          # 'refuse', 'warn' or 'info'
    code: str
    text: str


@dataclass
class Facts:
    macos_version: str = ''
    macos_build: str = ''
    target: str = ''
    hw_model: str = ''
    translated: bool = False
    console_user: str = ''
    is_admin: bool = False
    filevault: str = ''
    snapshots: int = 0
    on_ac: object = None
    default_boot: str = ''
    layout: object = None
    layout_error: str = ''
    limits: dict = field(default_factory=dict)


def _out(run, *argv):
    rc, out = run(list(argv))
    return out if rc == 0 else None


def gather(run):
    """run(argv) -> (returncode, stdout bytes). Read-only commands only."""
    import plistlib
    f = Facts()
    text = lambda *a: (_out(run, *a) or b'').decode('utf-8', 'replace').strip()
    f.macos_version = text('sw_vers', '-productVersion')
    f.macos_build = text('sw_vers', '-buildVersion')
    f.target = text('sysctl', '-n', 'hw.targettype').upper()
    f.hw_model = text('sysctl', '-n', 'hw.model')
    f.translated = text('sysctl', '-in', 'sysctl.proc_translated') == '1'
    f.console_user = text('stat', '-f', '%Su', '/dev/console')
    if f.console_user:
        f.is_admin = text('dseditgroup', '-o', 'checkmember', '-m', f.console_user, 'admin').startswith('yes ')
    f.filevault = text('fdesetup', 'status')
    snaps = text('tmutil', 'listlocalsnapshots', '/')
    f.snapshots = len([l for l in snaps.splitlines() if l.strip() and not l.startswith('Snapshots for')])
    batt = text('pmset', '-g', 'batt')
    f.on_ac = ("'AC Power'" in batt) if batt else None
    f.default_boot = text('bless', '--getBoot')
    lst = _out(run, 'diskutil', 'list', '-plist')
    apfs = _out(run, 'diskutil', 'apfs', 'list', '-plist')
    root = _out(run, 'diskutil', 'info', '-plist', '/')
    try:
        if lst is None or apfs is None or root is None:
            raise LayoutError('diskutil did not answer')
        infos = {}
        for entry in plistlib.loads(lst).get('AllDisksAndPartitions', []):
            if not entry.get('Partitions'):
                continue
            for dev in [entry['DeviceIdentifier']] + [p['DeviceIdentifier'] for p in entry['Partitions']]:
                infos[dev] = _out(run, 'diskutil', 'info', '-plist', dev) or b''
        infos = {k: v for k, v in infos.items() if v}
        f.layout = Layout.parse(lst, apfs, infos, root)
        mac = f.layout.macos_part()
        if mac is not None:
            lim = _out(run, 'diskutil', 'apfs', 'resizeContainer', mac.dev, 'limits', '-plist')
            f.limits = plistlib.loads(lim) if lim else {}
    except (LayoutError, KeyError, ValueError) as e:
        f.layout, f.layout_error = None, str(e)
    return f


# ---- checks --------------------------------------------------------------------------------
def check(f, models, manifest=None):
    out = []
    add = lambda level, code, text: out.append(Finding(level, code, text))
    if f.translated:
        add('refuse', 'rosetta', 'The installer is running under Rosetta (Intel emulation). Run it from a Terminal that is not set to "Open using Rosetta".')
    m = models.get(f.target)
    supported = ', '.join('%s (%s)' % (x.name, x.target) for x in models.values() if x.status == 'supported')
    if m is None:
        add('refuse', 'model', 'This Mac (%s, board %s) is not supported. SiliconForest runs only on: %s.' % (f.hw_model or '?', f.target or '?', supported))
    elif m.status != 'supported':
        add('refuse', 'model', 'This Mac (%s) is listed but not installable yet (status: %s).' % (m.name, m.status))
    else:
        add('info', 'model', 'Mac: %s (%s, board %s, %s).' % (m.name, f.hw_model, m.target, m.chip))
        if manifest is not None and m.target not in manifest['models']:
            add('refuse', 'model', 'Release %s was not built for this Mac (board %s).' % (manifest['release'], m.target))
        lo = manifest['macos']['min'] if manifest else m.macos_min
        hi = min(manifest['macos']['max_major'], m.macos_max_major) if manifest else m.macos_max_major
        v = version_tuple(f.macos_version)
        if v < version_tuple(lo):
            add('refuse', 'macos-old', 'macOS %s is too old: update macOS to %s or newer first.' % (f.macos_version, lo))
        elif v[0] > hi:
            add('refuse', 'macos-new', 'macOS %s is newer than any version SiliconForest was tested with (up to macOS %d). Wait for an installer that lists it.' % (f.macos_version, hi))
        else:
            add('info', 'macos', 'macOS %s (%s).' % (f.macos_version, f.macos_build))
    if not f.console_user or f.console_user in ('root', '_mbsetupuser', 'loginwindow'):
        add('refuse', 'console', 'Nobody is logged in at the Mac\'s screen. Log in there first (the installer asks that person for their password).')
    elif not f.is_admin:
        add('refuse', 'admin', 'The logged-in user (%s) is not an administrator of this Mac.' % f.console_user)
    fv = f.filevault.lower()
    if 'in progress' in fv or 'encryption' in fv and 'percent' in fv:
        add('refuse', 'filevault-busy', 'FileVault is encrypting or decrypting the disk (%s). Wait until it has finished.' % f.filevault.splitlines()[0])
    elif 'is on' in fv:
        add('info', 'filevault', 'FileVault is on. That is fine: macOS stays encrypted; SiliconForest\'s own partition is not encrypted.')
    if f.snapshots:
        add('info', 'snapshots', '%d local Time Machine snapshot(s) on the startup disk; they can keep macOS from shrinking (see docs/INSTALL.md).' % f.snapshots)
    if f.on_ac is False:
        add('warn', 'battery', 'The Mac is on battery. Connect power before installing.')
    if f.layout is None:
        add('refuse', 'disk', 'Could not read the internal disk\'s layout: %s.' % (f.layout_error or 'unknown'))
        return out
    if f.layout.macos_part() is None:
        add('refuse', 'disk', 'Could not find the APFS container of the running macOS on the internal disk (is macOS started from an external disk?).')
    ours = f.layout.find_ours()
    if ours is not None and ours.complete:
        add('info', 'installed', 'SiliconForest is installed (%s). Use --update or --uninstall.' % ', '.join(p.dev for p in ours.parts()))
    elif ours is not None:
        add('refuse', 'partial', 'An incomplete SiliconForest installation is on the disk: %s. Remove it with --uninstall before installing again.' % '; '.join(ours.problems))
    others = f.layout.other_systems()
    if others:
        add('info', 'others', 'Other systems on the disk (left as they are): ' + '; '.join(others) + '.')
    return out


def refusals(findings):
    return [x for x in findings if x.level == 'refuse']


class Refusal(Exception):
    def __init__(self, findings):
        self.findings = findings
        super().__init__('; '.join(x.text for x in findings))


# ---- plans ---------------------------------------------------------------------------------
def sizes(manifest):
    if manifest:
        r = manifest['root']
        return r['min_bytes'], r['default_bytes'], False
    return PROVISIONAL_ROOT_MIN, PROVISIONAL_ROOT_DEFAULT, True


def plan_install(f, models, manifest=None, total=None):
    findings = check(f, models, manifest)
    bad = refusals(findings)
    if any(x.code == 'installed' for x in findings):
        bad.append(Finding('refuse', 'installed', 'SiliconForest is already installed; use --update, or --uninstall first.'))
    if bad:
        raise Refusal(bad)
    lay = f.layout
    root_min, root_default, provisional = sizes(manifest)
    fixed = STUB_BYTES + BOOT_BYTES
    if total is None:
        root = align_down(root_default, ALIGN)
    else:
        root = align_down(total - fixed, ALIGN)
        if root < root_min:
            raise Refusal([Finding('refuse', 'size', 'Asked for %s; SiliconForest needs at least %s (%s for its startup volume and boot partition, %s for its root).' % (
                gb(total), gb(fixed + root_min), gb(fixed), gb(root_min)))])
    if manifest and manifest['root'].get('sizing') == 'fixed' and root != root_default:
        raise Refusal([Finding('refuse', 'size', 'This release uses a fixed %s root filesystem. Omit --size.' % gb(root_default))])
    need = fixed + root
    plan = dict(kind='install', layout_digest=lay.digest(), disk=lay.disk, block_size=lay.block_size,
                stub_bytes=STUB_BYTES, boot_bytes=BOOT_BYTES, root_bytes=root, total_bytes=need,
                provisional_sizes=provisional, release=manifest['release'] if manifest else None,
                resize=None, findings=[x.__dict__ for x in findings])
    mac = lay.macos_part()
    gap = next((g for g in lay.gaps() if g.size >= need), None)
    if gap is not None:
        plan.update(after=gap.dev, gap_offset=gap.offset, gap_bytes=gap.size, macos_free_after=mac.container.free)
    else:
        c = mac.container
        if not f.limits or 'MinimumSizePreferred' not in f.limits:
            raise Refusal([Finding('refuse', 'limits', 'diskutil did not say how far macOS\'s container can shrink.')])
        before = lay.gap_after(mac)
        have = before.size if before is not None else 0
        shrink = align_up(need - have, ALIGN)
        new = c.ceiling - shrink
        min_raw = align_up(c.ceiling - c.free + MIN_FREE_MACOS, ALIGN)
        min_safe = int(f.limits['MinimumSizePreferred'])
        min_size = max(min_raw, min_safe)
        overhead = min_size - min_raw
        if overhead > OVERHEAD_WARN:
            findings.append(Finding('warn', 'overhead', 'macOS cannot shrink below %s although only %s is in use: snapshots (Time Machine) or a pending macOS update hold %s. Deleting local snapshots frees it (docs/INSTALL.md).' % (
                gb(min_safe), gb(c.ceiling - c.free), gb(overhead))))
            plan['findings'] = [x.__dict__ for x in findings]
        if new < min_size:
            most = max(0, c.ceiling - min_size + have)
            room = 'At most %s can be made available' % gb(most) if most >= fixed + root_min else 'Not even the minimum (%s) can be made available' % gb(fixed + root_min)
            raise Refusal([x for x in findings if x.level == 'warn'] + [Finding('refuse', 'space', 'Not enough space: SiliconForest needs %s, and macOS must keep %s free (it has %s free now). %s; free space in macOS or ask for less with --size.' % (
                gb(need), gb(MIN_FREE_MACOS), gb(c.free), room))])
        plan['resize'] = dict(store=mac.dev, container=c.ref, from_bytes=c.ceiling, to_bytes=new, shrink_bytes=shrink, min_bytes=min_size)
        plan.update(after=mac.dev, gap_offset=mac.offset + new, gap_bytes=shrink + have, macos_free_after=c.free - shrink)
    plan['changes'] = describe_install(plan, mac)
    return plan


def describe_install(p, mac):
    lines = []
    if p['resize']:
        r = p['resize']
        lines.append('Shrink the macOS container %s (partition %s) from %s to %s, freeing %s directly after it. macOS keeps all its files and %s of free space.' % (
            r['container'], r['store'], gb(r['from_bytes']), gb(r['to_bytes']), gb(r['shrink_bytes']), gb(p['macos_free_after'])))
    else:
        lines.append('Use %s of the free space after %s (macOS is not resized).' % (gb(p['total_bytes']), p['after']))
    lines += [
        'Add a %s APFS container "SiliconForest" there: the startup volume that the startup picker shows, with its own recovery, made from Apple\'s macOS %s restore files for this Mac (downloaded from Apple).' % (gb(p['stub_bytes']), '13.5'),
        'Add a %s FAT32 partition "SFBOOT" behind it with SiliconForest\'s boot files (sf/boot.bin, sf/kernel.bin) and this Mac\'s Wi-Fi/Bluetooth firmware.' % gb(p['boot_bytes']),
        'Add a %s partition behind that and write the SiliconForest root filesystem into it.' % gb(p['root_bytes']),
        'Write this Mac\'s partition identifiers into sf/kernel.bin and copy the Wi-Fi/Bluetooth firmware into the root.',
        'Make SiliconForest the startup disk for the next start only so that its recovery can finish the setup; you set macOS back afterwards (the installer says how).',
        'Nothing else: macOS\'s volumes, your files and any other system on the disk are not written.',
    ]
    return lines


def plan_uninstall(f, models):
    lay = f.layout
    if lay is None:
        raise Refusal([Finding('refuse', 'disk', 'Could not read the disk layout: ' + f.layout_error)])
    ours = lay.find_ours()
    if ours is None:
        raise Refusal([Finding('refuse', 'not-installed', 'No SiliconForest installation was found on the internal disk. Nothing to remove.')])
    findings = []
    if ours.stub is not None:
        sub = re.match(r'^(/dev/)?(disk\d+)', f.default_boot or '')
        if sub and sub.group(2) == ours.stub.container.ref:
            raise Refusal([Finding('refuse', 'default', 'SiliconForest is the startup disk. Choose macOS first: System Settings > General > Startup Disk (or hold the power button, select macOS, hold Option and click "Always Use"), then run this again.')])
        if not sub:
            findings.append(Finding('warn', 'default-unknown', 'Could not read the current startup disk. Make sure it is macOS before you confirm.'))
    remove = []
    if ours.stub is not None:
        remove.append(dict(dev=ours.stub.dev, container=ours.stub.container.ref, what='SiliconForest startup volume (APFS container %s)' % ours.stub.container.ref,
                           offset=ours.stub.offset, bytes=ours.stub.size, uuid=ours.stub.uuid, action='deleteContainer'))
    for p, what in ((ours.boot, 'SFBOOT boot partition'), (ours.root, 'SiliconForest root partition (its files are lost)')):
        if p is not None:
            remove.append(dict(dev=p.dev, what=what, offset=p.offset, bytes=p.size, uuid=p.uuid, action='eraseVolume'))
    mac = lay.macos_part()
    # the space comes back to macOS only if nothing but free space lies between macOS and our first piece
    first = min(r['offset'] for r in remove)
    between = [p for p in lay.parts if mac.end <= p.offset < first and not p.free]
    grow = dict(store=mac.dev, container=mac.container.ref) if mac is not None and not between else None
    if grow is None:
        findings.append(Finding('info', 'no-grow', 'Another partition lies between macOS and SiliconForest; the space is left free instead of being given back to macOS.'))
    freed = sum(r['bytes'] for r in remove)
    plan = dict(kind='uninstall', layout_digest=lay.digest(), disk=lay.disk, remove=remove, grow=grow, freed_bytes=freed,
                findings=[x.__dict__ for x in findings])
    plan['changes'] = ['Delete %s: %s at %s, %s.' % (r['dev'], r['what'], gb(r['offset']), gb(r['bytes'])) for r in remove]
    plan['changes'].append('Give the %s back to macOS (grow container %s).' % (gb(freed), grow['container']) if grow else 'Leave the %s as free space.' % gb(freed))
    plan['changes'].append('Nothing else: macOS, your files and any other system are not touched.')
    return plan


def plan_update(f, models, manifest):
    findings = check(f, models, manifest)
    bad = [x for x in refusals(findings) if x.code not in ('battery',)]
    if bad:
        raise Refusal(bad)
    ours = f.layout.find_ours()
    if ours is None or not ours.complete:
        raise Refusal([Finding('refuse', 'not-installed', 'No complete SiliconForest installation found; nothing to update.')])
    bs = f.layout.block_size
    plan = dict(kind='update', layout_digest=f.layout.digest(), release=manifest['release'], boot_dev=ours.boot.dev,
                root=dict(dev=ours.root.dev, uuid=ours.root.uuid, first_block=ours.root.offset // bs, blocks=ours.root.size // bs),
                findings=[x.__dict__ for x in findings])
    plan['changes'] = ['Replace sf/boot.bin and sf/kernel.bin on %s with release %s; the current ones are kept as sf/boot.bin.old and sf/kernel.bin.old.' % (ours.boot.dev, manifest['release']),
                       'The root filesystem, the startup volume and macOS are not changed.']
    return plan
