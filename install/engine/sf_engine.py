#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""SiliconForest installer: the part that decides and the part that acts. install.sh runs it.

    sf_engine.py check     [--manifest M]                   what this Mac is and what is on its disk
    sf_engine.py install   [--dry-run] [--size N] --manifest M --artifacts D --engine E
    sf_engine.py uninstall [--dry-run]
    sf_engine.py update    [--dry-run] --manifest M --artifacts D

Everything runs read-only as the logged-in user until the plan has been shown and confirmed
once, by typing a word; then the same program runs again under sudo, reads the disk again,
makes the same plan again and acts only if both plans agree. Every change goes through
sf_gate.Gate. The install itself is done by the Asahi Linux installer's own code (the
engine, v0.9.2, unmodified, in --engine), driven step by step from here; the sequence follows
its main.py (action_install_into_free, do_install, step2), MIT, "Copyright (c) 2021 The
Asahi Linux contributors".
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sf_fwslot  # noqa: E402
import sf_gate  # noqa: E402
import sf_kernelcfg  # noqa: E402
import sf_manifest  # noqa: E402
import sf_plan  # noqa: E402
from sf_disk import Layout, gb  # noqa: E402

STATE_DIR = '/var/db/siliconforest-installer'
STAGE1_NAME = 'siliconforest-stage1.bin'
WORDS = {'install': 'install', 'uninstall': 'uninstall', 'update': 'update'}
LOG = None


def _read(path):
    with open(path, 'rb') as fd:
        return fd.read()


def say(*a):
    text = ' '.join(str(x) for x in a)
    print(text, flush=True)
    if LOG:
        with open(LOG, 'a') as fd:
            fd.write(time.strftime('%H:%M:%S ') + text + '\n')


def real_run(argv):
    try:
        r = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        return 127, b''
    return r.returncode, r.stdout


def load_models():
    for p in (os.path.join(HERE, 'models.tsv'), os.path.join(HERE, '..', 'models.tsv')):
        if os.path.exists(p):
            return sf_plan.load_models(_read(p).decode())
    raise SystemExit('models.tsv is missing')


def load_manifest(path, models, sums_path=None):
    """install.json, cross-checked against the signed SHA256SUMS beside it (install.sh has checked
    the signature, and this checks install.json's own digest in it again)."""
    if not path:
        return None
    supported = [t for t, m in models.items() if m.status == 'supported']
    sums_path = sums_path or os.path.join(os.path.dirname(path), 'SHA256SUMS')
    sums = sf_manifest.parse_sums(_read(sums_path))
    if sums.get(os.path.basename(path)) != hashlib.sha256(_read(path)).hexdigest():
        raise sf_manifest.ManifestError('%s is not in SHA256SUMS with its digest' % os.path.basename(path))
    return sf_manifest.check(_read(path), supported, sums)


def show_findings(findings):
    mark = {'refuse': 'NO  ', 'warn': 'NOTE', 'info': '    '}
    for x in findings:
        level, text = (x.level, x.text) if hasattr(x, 'level') else (x['level'], x['text'])
        say('  %s %s' % (mark[level], text))


def show_plan(plan, facts):
    say('')
    say('The disk now:')
    say(facts.layout.table())
    say('')
    if plan.get('provisional_sizes'):
        say('(No SiliconForest release exists yet: the root size is a placeholder until a release names its image size.)')
    say('What will change if you confirm:')
    for i, line in enumerate(plan['changes'], 1):
        say('  %d. %s' % (i, line))
    say('')


def confirm(word, tty='/dev/tty'):
    say('Type "%s" and press Return to make these changes; anything else stops here with nothing changed.' % word)
    try:
        with open(tty) as fd:
            answer = fd.readline().strip()
    except OSError:
        answer = ''
    say('answer: %r' % answer)
    return answer == word


def plan_for(cmd, facts, models, manifest, args):
    if cmd == 'install':
        return sf_plan.plan_install(facts, models, manifest, args.size)
    if cmd == 'uninstall':
        return sf_plan.plan_uninstall(facts, models)
    return sf_plan.plan_update(facts, models, manifest)


def same_plan(a, b):
    keys = ('kind', 'layout_digest', 'resize', 'after', 'gap_offset', 'total_bytes', 'root_bytes', 'remove', 'grow', 'boot_dev', 'root', 'release')
    return all(a.get(k) == b.get(k) for k in keys)


# ---- the Asahi engine, behind the gate -------------------------------------------------------
class AsahiEngine:
    """Imports the Asahi installer's modules from `engine_dir` and routes their changes through the gate."""

    def __init__(self, engine_dir, gate):
        self.dir, self.gate = engine_dir, gate
        sys.path.insert(0, engine_dir)
        os.chdir(engine_dir)
        import diskutil, osinstall, stub, osenum, system, bugs, m1n1  # noqa: E401
        import main as amain
        from asahi_firmware.core import FWPackage
        self.diskutil, self.osinstall, self.stub, self.osenum, self.system = diskutil, osinstall, stub, osenum, system
        self.amain, self.bugs, self.m1n1, self.FWPackage = amain, bugs, m1n1, FWPackage

        class GatedSubprocess:
            PIPE, STDOUT, DEVNULL = subprocess.PIPE, subprocess.STDOUT, subprocess.DEVNULL
            CalledProcessError, CompletedProcess = subprocess.CalledProcessError, subprocess.CompletedProcess

            @staticmethod
            def run(argv, **kw):
                if gate.classify([str(a) for a in argv]) is None and gate.execute is None:
                    return subprocess.run(argv, **kw)
                rc, out = gate.run(argv, why='engine', input=kw.get('input'))
                if kw.get('check') and rc != 0:
                    raise subprocess.CalledProcessError(rc, argv, out)
                return subprocess.CompletedProcess(argv, rc, out, b'')

        def action(du, *args, verbose=False):
            gate.run(['diskutil'] + list(args), why='engine diskutil')

        for mod in (diskutil, osinstall, stub, amain, osenum, system):
            mod.subprocess = GatedSubprocess
        diskutil.DiskUtil.action = action
        osinstall.open = gate.open
        os.system = gate.system

    def install(self, plan, manifest, artifacts, log):
        A = self.amain
        sysinfo = self.system.SystemInfo()
        im = A.InstallerMain(_read('version.tag').decode().strip())
        im.sysinfo, im.expert = sysinfo, False
        self.bugs.run_checks(im)
        im.device = A.DEVICES.get(sysinfo.device_class)
        if im.device is None or sysinfo.chip_id not in A.CHIP_MIN_VER:
            raise SystemExit('The Asahi engine does not know this Mac (%s).' % sysinfo.device_class)
        dutil = self.diskutil.DiskUtil()
        dutil.get_info()
        disk = dutil.find_system_disk()
        im.sys_disk = im.cur_disk = disk
        im.dutil = dutil
        im.parts = parts = dutil.get_partitions(disk)
        im.osinfo = osinfo = self.osenum.OSEnum(sysinfo, dutil, disk)
        osinfo.collect(parts)
        im.is_edu_128gb = False
        im.cur_os = find_cur_os(parts, sysinfo)
        im.check_cur_os()
        boot = unpack_boot(manifest, artifacts)
        shutil.copy(os.path.join(boot, 'sf-stage1.bin'), os.path.join(self.dir, 'boot', STAGE1_NAME))
        template = installer_template(manifest, plan, os_package(boot, artifacts))
        data = {'os_list': [template]}
        with open('installer_data.json', 'w') as fd:
            json.dump(data, fd, indent=1)
        ipsw = im.choose_ipsw(template['supported_fw'])
        if plan['resize']:
            r = plan['resize']
            say('Shrinking macOS (%s) to %s; the Mac may seem to stop for a minute.' % (r['store'], gb(r['to_bytes'])))
            dutil.resizeContainer(r['store'], r['to_bytes'])
            dutil.get_info()
            parts = dutil.get_partitions(disk)
        free = [p for p in parts if p.free and p.name == plan['after'] and p.offset == plan['gap_offset']]
        if len(free) != 1:
            raise sf_gate.Refused('the planned free space (after %s at byte %d) is not there' % (plan['after'], plan['gap_offset']))
        osins = im.osins = self.osinstall.OSInstaller(dutil, data, template)
        osins.load_package()
        osins.name = 'SiliconForest'
        im.part = dutil.addPartition(free[0].name, 'apfs', 'SiliconForest', plan['stub_bytes'])
        ins = im.ins = self.stub.StubInstaller(sysinfo, dutil, osinfo)
        ins.load_ipsw(ipsw)
        ins.prepare_volume(im.part)
        ins.check_volume()
        ins.install_files(im.cur_os)
        osins.partition_disk(im.part.name, plan['boot_bytes'] + plan['root_bytes'])
        os.makedirs('vendorfw', exist_ok=True)
        pkg = self.FWPackage('vendorfw')
        ins.collect_firmware(pkg)
        pkg.close()
        osins.firmware_package = pkg
        osins.install(ins)
        efi, root = osins.efi_part, osins.part_info[1]
        mount = dutil.mount(efi.name)
        bs = plan['block_size']
        finish(self.gate, manifest, artifacts, mount, root.name, root.uuid, root.offset // bs, root.size // bs, root.size, 'vendorfw/firmware.tar', log)
        with open(os.path.join(mount, 'sf', 'install.json'), 'w') as fd:
            json.dump(dict(release=manifest['release'], vgid=ins.osi.vgid, boot_partuuid=efi.uuid.lower(), root_partuuid=root.uuid.lower(),
                           root_first_block=root.offset // bs, root_blocks=root.size // bs, installed=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())), fd, indent=1)
        if log:
            shutil.copy(log, os.path.join(mount, 'sf', 'install.log'))
        say('')
        say('The first part is done. What follows are the Asahi Linux installer\'s own instructions for the second part, in recovery.')
        say('Afterwards: the first start of SiliconForest happens by itself; then set macOS back as the startup disk (docs/INSTALL.md, "After the first start").')
        im.step2(report=False)


def find_cur_os(parts, sysinfo):
    """The running macOS, as the Asahi installer's main_loop finds it."""
    cur, default = None, None
    for p in parts:
        for osi in (p.os or []):
            if not osi.version:
                continue
            if sysinfo.boot_vgid == osi.vgid and sysinfo.boot_uuid == osi.rec_vgid:
                if p.type == 'APFS':
                    cur = osi
            elif sysinfo.boot_uuid == osi.vgid:
                cur = osi
            if sysinfo.default_boot == osi.vgid:
                default = osi
    if cur is None and sysinfo.boot_mode != 'macOS':
        cur = default
    return cur


def installer_template(manifest, plan, package):
    """The Asahi installer's description of SiliconForest. The root partition has no `image`: the
    engine leaves it empty and write_root() fills it (from the release's xz parts, checked)."""
    r = manifest['root']
    return dict(name='SiliconForest', default_os_name='SiliconForest', boot_object=STAGE1_NAME, next_object='sf/boot.bin',
                package=package, icon='siliconforest.icns', supported_fw=list(manifest['stub_firmware']),
                partitions=[dict(name='SFBOOT', type='EFI', size='%dB' % plan['boot_bytes'], format='fat', source='esp', copy_firmware=True),
                            dict(name='Root', type='Linux', size='%dB' % r['min_bytes'], expand=True)])


def unpack_boot(manifest, artifacts):
    """The release's boot files, from its boot.tar.xz, into <artifacts>/boot (regular files only)."""
    import tarfile
    out = os.path.join(artifacts, 'boot')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    with tarfile.open(os.path.join(artifacts, manifest['boot']['file']), 'r:xz') as t:
        for m in t.getmembers():
            name = m.name[2:] if m.name.startswith('./') else m.name
            if m.isdir() and name in ('', '.'):
                continue
            if not m.isreg() or '/' in name or name not in sf_manifest.BOOT_FILES:
                raise sf_gate.Refused('boot files: unexpected member %r' % m.name)
            with t.extractfile(m) as src, open(os.path.join(out, name), 'wb') as dst:
                shutil.copyfileobj(src, dst)
    missing = [n for n in sf_manifest.BOOT_FILES if not os.path.exists(os.path.join(out, n))]
    if missing:
        raise sf_gate.Refused('boot files missing from the release: ' + ', '.join(missing))
    return out


def os_package(boot, artifacts):
    """The Asahi-format OS package the engine copies to SFBOOT: esp/sf/boot.bin and the icon."""
    import zipfile
    path = os.path.join(artifacts, 'os', 'siliconforest-local-os.zip')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_STORED) as z:
        for d in ('esp/', 'esp/sf/'):               # the engine's extract_tree makes directories from members
            info = zipfile.ZipInfo(d)
            info.external_attr = (0o40755 << 16) | 0x10
            z.writestr(info, b'')
        z.write(os.path.join(boot, 'boot.bin'), 'esp/sf/boot.bin')
        z.write(os.path.join(boot, 'siliconforest.icns'), 'siliconforest.icns')
    return os.path.basename(path)


def write_root(gate, manifest, artifacts, root_dev, root_bytes):
    """Stream the root image from its xz parts onto the new root partition, then read it back."""
    import lzma
    r = manifest['root']
    if r.get('sizing') == 'fixed' and r['image_bytes'] != root_bytes:
        raise sf_gate.Refused('the root partition must match the fixed %d-byte image' % r['image_bytes'])
    if r['image_bytes'] > root_bytes:
        raise sf_gate.Refused('the root image (%d bytes) is larger than its partition (%d)' % (r['image_bytes'], root_bytes))
    dec, written, chunk, pending = lzma.LZMADecompressor(format=lzma.FORMAT_XZ), 0, 4 << 20, b''
    with gate.open('/dev/r' + root_dev, 'r+b', buffering=0) as dev:
        for part in r['parts']:
            with open(os.path.join(artifacts, part['file']), 'rb') as src:
                while True:
                    data = src.read(chunk)
                    if not data:
                        break
                    if dec.eof:
                        raise sf_gate.Refused('trailing data after the root xz stream')
                    while True:
                        pending += dec.decompress(data, max_length=chunk)
                        cut = len(pending) // 4096 * 4096  # raw devices take whole 4 KiB blocks
                        if cut:
                            if written + cut > r['image_bytes']:
                                raise sf_gate.Refused('the root image is longer than the release says')
                            if dev.write(pending[:cut]) != cut:
                                raise sf_gate.Refused('short write to the root partition')
                            written += cut
                            pending = pending[cut:]
                        if dec.eof:
                            if dec.unused_data:
                                raise sf_gate.Refused('trailing data after the root xz stream')
                            break
                        if dec.needs_input:
                            break
                        data = b''
        if not dec.eof or pending or written != r['image_bytes']:
            raise sf_gate.Refused('the root image ended at %d bytes, not %d' % (written + len(pending), r['image_bytes']))
        dev.seek(0)
        h, left = hashlib.sha256(), written
        while left:
            data = dev.read(min(chunk, left))
            if not data:
                break
            h.update(data)
            left -= len(data)
    if left or h.hexdigest() != r['image_sha256']:
        raise sf_gate.Refused('the root partition does not read back as the release\'s image')
    say('Root filesystem: %d bytes written and read back (SHA-256 as the release names it).' % written)


def personal_boot_files(manifest, boot, artifacts, root_uuid, first, blocks):
    """sf/boot.bin and sf/kernel.bin for this Mac, made by the release's own sf_personalize.py,
    then checked here: the command line names exactly this root partition and the release's root."""
    out = os.path.join(artifacts, 'personal')
    shutil.rmtree(out, ignore_errors=True)
    res = subprocess.run([sys.executable, '-I', '-B', os.path.join(boot, 'sf_personalize.py'), boot, '--partuuid', root_uuid.lower(),
                          '--part-lba', str(first), '--part-blocks', str(blocks), '-o', out], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if res.returncode != 0:
        raise sf_gate.Refused('the release\'s sf_personalize.py refused: ' + res.stdout.decode('utf-8', 'replace').strip())
    kern, stage2 = _read(os.path.join(out, 'kernel.bin')), _read(os.path.join(out, 'boot.bin'))
    sf_kernelcfg.verify(kern, root_uuid, first, blocks, manifest['root']['fs_uuid'])
    if stage2 != _read(os.path.join(boot, 'boot.bin')):
        raise sf_gate.Refused('sf_personalize.py changed stage 2')
    return stage2, kern


def finish(gate, manifest, artifacts, mount, root_dev, root_uuid, first, blocks, root_bytes, firmware_tar, log):
    """Ours, after the engine has made the partitions: the root, this Mac's identifiers, its firmware."""
    boot = os.path.join(artifacts, 'boot')
    write_root(gate, manifest, artifacts, root_dev, root_bytes)
    stage2, kern = personal_boot_files(manifest, boot, artifacts, root_uuid, first, blocks)
    gate.write_dirs = (os.path.join(mount, 'sf'),)
    for name, data in (('boot.bin', stage2), ('kernel.bin', kern)):
        path = os.path.join(mount, 'sf', name)
        gate.write_file(path, data)
        if _read(path) != data:
            raise sf_gate.Refused('sf/%s does not read back as written' % name)
    say('sf/kernel.bin: root partition %s, first block %d, %d blocks.' % (root_uuid.lower(), first, blocks))
    blob, names = sf_fwslot.payload(firmware_tar)
    slot = manifest['firmware_slot']
    n = sf_fwslot.write('/dev/r' + root_dev, slot['offset'], slot['length'], blob, opener=gate.open)
    say('Wi-Fi/Bluetooth and Touch Bar firmware: %d files, %d bytes into the root\'s firmware slot.' % (len(names), n))


# ---- uninstall and update (no engine needed) --------------------------------------------------
def execute_uninstall(plan, gate, reader):
    for r in plan['remove']:
        if r['action'] == 'deleteContainer':
            gate.run(['diskutil', 'apfs', 'deleteContainer', r['container']], why='uninstall: startup volume')
            left = next((q for q in reader().real_parts() if q.uuid == r['uuid'] or q.offset == r['offset']), None)
            if left is not None:
                gate.run(['diskutil', 'eraseVolume', 'free', 'free', left.dev], why='uninstall: startup volume partition')
        else:
            cur = next((q for q in reader().real_parts() if q.uuid == r['uuid']), None)
            if cur is None:
                say('%s is already gone.' % r['dev'])
                continue
            gate.run(['diskutil', 'eraseVolume', 'free', 'free', cur.dev], why='uninstall: ' + r['what'])
    if plan['grow']:
        lay = reader()
        mac = lay.macos_part()
        if mac is not None and lay.gap_after(mac) is not None:
            gate.run(['diskutil', 'apfs', 'resizeContainer', mac.dev, '0'], why='uninstall: give the space back to macOS')
        else:
            say('The freed space is not directly after macOS; it stays free.')


def execute_update(plan, gate, manifest, artifacts, run=real_run):
    import plistlib
    rc, out = run(['diskutil', 'info', '-plist', plan['boot_dev']])
    info = plistlib.loads(out) if rc == 0 else {}
    mount = info.get('MountPoint')
    if not mount:
        gate.run(['diskutil', 'mount', plan['boot_dev']], why='update: mount SFBOOT')
        info = plistlib.loads(run(['diskutil', 'info', '-plist', plan['boot_dev']])[1])
        mount = info.get('MountPoint')
    if not mount or not os.path.isdir(os.path.join(mount, 'sf')):
        raise sf_gate.Refused('SFBOOT (%s) has no sf/ directory' % plan['boot_dev'])
    r = plan['root']
    boot = unpack_boot(manifest, artifacts)
    stage2, kern = personal_boot_files(manifest, boot, artifacts, r['uuid'], r['first_block'], r['blocks'])
    sf = os.path.join(mount, 'sf')
    gate.write_dirs = (sf,)
    for name, data in (('boot.bin', stage2), ('kernel.bin', kern)):
        path = os.path.join(sf, name)
        if os.path.exists(path) and _read(path) == data:
            say('sf/%s is already this release\'s.' % name)
            continue
        if os.path.exists(path):
            gate.write_file(path + '.old', _read(path))
        gate.write_file(path, data)
        if _read(path) != data:
            raise sf_gate.Refused('sf/%s does not read back as written' % name)
        say('sf/%s replaced (previous: sf/%s.old).' % (name, name))


def parse_size(text):
    t = text.strip().upper().rstrip('B')
    mult = 1e9
    if t.endswith('G'):
        t = t[:-1]
    elif t.endswith('T'):
        t, mult = t[:-1], 1e12
    value = float(t)
    if not 0 < value < 1e6:
        raise argparse.ArgumentTypeError('a size in GB, such as 60 or 60G')
    return int(value * mult)


def download_list(manifest):
    """Lines for install.sh: `<file> <bytes> <sha256>` (the base URL is install.sh's)."""
    return ['%s %d %s' % f for f in sf_manifest.downloads(manifest)]


# ---- main ----------------------------------------------------------------------------------
def main(argv=None):
    global LOG
    ap = argparse.ArgumentParser(description='SiliconForest installer engine (run by install.sh)')
    ap.add_argument('command', choices=('check', 'install', 'uninstall', 'update', 'files'))
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--size', type=parse_size, help='space for SiliconForest in GB (startup volume, boot partition and root)')
    ap.add_argument('--manifest')
    ap.add_argument('--artifacts')
    ap.add_argument('--engine')
    ap.add_argument('--log')
    ap.add_argument('--confirmed', help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    LOG = args.log
    models = load_models()
    manifest = load_manifest(args.manifest, models)
    if args.command == 'files':
        for line in download_list(manifest):
            print(line)
        return 0
    facts = sf_plan.gather(real_run)
    cmd = args.command
    if cmd == 'check':
        findings = sf_plan.check(facts, models, manifest)
        show_findings(findings)
        if facts.layout is not None:
            say('')
            say('The disk:')
            say(facts.layout.table())
        return 3 if sf_plan.refusals(findings) else 0
    if (cmd == 'install' and manifest is None and not args.dry_run) or (cmd == 'update' and manifest is None):
        say('There is no SiliconForest release yet, so there is nothing to install. Nothing was changed.')
        say('You can see what the installer would do with --dry-run.')
        return 4
    try:
        plan = plan_for(cmd, facts, models, manifest, args)
    except sf_plan.Refusal as e:
        show_findings(e.findings)
        say('Nothing was changed.')
        return 3
    show_findings(plan['findings'])
    show_plan(plan, facts)
    if args.dry_run:
        say('Dry run: nothing was changed.')
        return 0
    if args.confirmed is None:
        if os.geteuid() == 0:
            say('Run the installer as yourself, not as root: it asks for your password when it needs it.')
            return 2
        if not confirm(WORDS[cmd]):
            say('Stopped. Nothing was changed.')
            return 1
        path = os.path.join(args.artifacts or os.path.dirname(LOG or '/tmp/x'), 'plan-%s.json' % cmd)
        with open(path, 'w') as fd:
            json.dump(plan, fd, indent=1)
        say('Your macOS password is needed now (sudo).')
        again = ['sudo', sys.executable, '-I', os.path.abspath(__file__)] + (argv if argv is not None else sys.argv[1:]) + ['--confirmed', path]
        env = ['env', 'DYLD_LIBRARY_PATH=' + os.environ.get('DYLD_LIBRARY_PATH', ''), 'DYLD_FRAMEWORK_PATH=' + os.environ.get('DYLD_FRAMEWORK_PATH', ''),
               'SSL_CERT_FILE=' + os.environ.get('SSL_CERT_FILE', '')]
        os.execvp('caffeinate', ['caffeinate', '-dis'] + again[:1] + env + again[1:])
    # under sudo: the same plan again, or nothing
    if os.geteuid() != 0:
        say('This step must run under sudo.')
        return 2
    saved = json.loads(_read(args.confirmed))
    if not same_plan(saved, plan):
        say('The disk changed between the plan you confirmed and now. Nothing was changed; run the installer again.')
        return 5
    os.makedirs(STATE_DIR, exist_ok=True)
    journal = os.path.join(STATE_DIR, 'journal.jsonl')
    reader = lambda: sf_plan.gather(real_run).layout
    gate = sf_gate.Gate(plan, reader, journal=journal, log=say)
    gate.note(step='begin', kind=cmd, release=plan.get('release'), digest=plan['layout_digest'])
    try:
        if cmd == 'install':
            os.makedirs(os.path.join(args.engine, 'boot'), exist_ok=True)
            os.environ.update(DISTRO='SiliconForest', DISTRO_DOCS='https://github.com/chriskearney/siliconforest/blob/main/docs/INSTALL.md',
                              REPO_BASE=args.artifacts)
            for k in ('REPORT', 'REPORT_TAG', 'EXPERT', 'IPSW_BASE', 'INSTALLER_DATA', 'ALLOW_VM'):
                os.environ.pop(k, None)
            AsahiEngine(os.path.abspath(args.engine), gate).install(plan, manifest, args.artifacts, LOG)
        elif cmd == 'uninstall':
            execute_uninstall(plan, gate, reader)
            say('SiliconForest has been removed. The disk now:')
            say(reader().table())
        else:
            execute_update(plan, gate, manifest, args.artifacts)
            say('Update done: SiliconForest starts release %s the next time you choose it.' % manifest['release'])
    except sf_gate.Refused as e:
        gate.note(step='stopped', reason=str(e))
        say(str(e))
        say('Stopped. The journal of what was done is %s; the log is %s.' % (journal, LOG))
        return 6
    gate.note(step='end', kind=cmd)
    return 0


if __name__ == '__main__':
    sys.exit(main())
