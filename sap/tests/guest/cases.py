#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""What SAP assumes of SiliconForest, checked in the QEMU guest (sap_guest.py): no Apple hardware,
no real disks; every disk is a file under WORK (runs/sap-guest, never committed).

  cases.py --bin DIR [CASE ...]      CASE: durable, sap-cut, sfboot, kc (default: all)

DIR holds sap/tools/build_darwin.sh's output built with SAP_FEATURES=testing and
SAP_EXTRA_C=sap/tests/guest/sapg-durable.c (and kc-builder for the kc case, --kc-builder).

  durable  sapg-durable writes, fsyncs and renames in a loop on the root (ext4 through
           SiliconForest's ext4.kext); the power is cut at "ACK k" (--cuts). The state file must be
           whole and >= the last ACK shown, both after e2fsck on the host and when the guest itself boots the cut disk.
  sap-cut  sap installs 0.1.0 into /sapg/root, then upgrades to 0.1.1 and is stopped for good at a
           journal record or swap (SAP_FAULT=halt:...), and the power is cut. The guest boots
           again on the cut disk: `sap recover` then `sap verify` must both succeed.
  sfboot   a second disk with a GPT FAT32 partition labelled SFBOOT, holding stage 2 and the A/B
           record from a host `sf-bootslot init`. Boot 1: sf-mount-sfboot mounts it read-write,
           sf-bootslot stages slot B and arms it, umount; the host reads the record back. Boot 2
           with sf_slot=b and SAP's launchd jobs in the image: sap-boot runs `early`, sap-mark-good
           waits for the health service and marks B good; the record must say default=b.
  kc       kc-builder (built for SiliconForest) links the release's kernel-collection inputs in
           the guest; the collection must be byte-identical to the host kc-builder's.
Writes WORK/cases.json.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import sap_guest as G  # noqa: E402
import qd_image  # noqa: E402

WORK = G.WORK
NOW = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def sh(*a, **k):
    return subprocess.run([str(x) for x in a], check=True, **k)


def host_cc(src, out):
    sh(shutil.which('cc') or 'gcc', '-std=c11', '-O1', *src, '-o', out)
    return out


def image(name, overlay, bootargs=''):
    out = WORK / 'img' / (name + '.img')
    G.build(argparse.Namespace(out=out, file=[], data=[], link=[], bootargs=bootargs, overlay=[str(overlay)]))
    return out


def boot(img, name, command, kill_on='', drives=(), timeout=900):
    out = WORK / 'runs' / name
    rc = G.run(argparse.Namespace(image=img, out=out, command=command, kill_on=kill_on, drive=list(drives), cache='directsync',
                                  timeout=timeout, smp=2, memory=1024))
    res = json.loads((out / 'result.json').read_text())
    log = (out / 'serial.log').read_text(errors='replace')
    return rc, res, log


def after(log, command):
    """The serial output after the typed command (its echo excluded)."""
    i = log.rfind(command)
    return log[i + len(command):] if i >= 0 else log


def copy(img, name):
    dst = img.with_name(name + '.img')
    sh('cp', '--reflink=auto', img, dst)
    return dst


def script(tree, path, text):
    p = tree / path.lstrip('/')
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    p.chmod(0o755)


# ---- durable ----

def case_durable(a):
    ov = Path(tempfile.mkdtemp(dir=WORK))
    (ov / 'sapg/d').mkdir(parents=True)
    shutil.copy(a.bin / 'sapg-durable', ov / 'sapg/sapg-durable'); (ov / 'sapg/d/.keep').write_text('')
    chk = host_cc([HERE / 'sapg-durable.c'], Path(tempfile.mkdtemp(dir=WORK)) / 'chk')
    results, ok = {}, True
    for k in a.cuts:
        img = image('durable-%d' % k, ov)
        rc, res, log = boot(img, 'durable-cut-%d' % k, '/sapg/sapg-durable /sapg/d 100000', kill_on=r'(?m)^ACK %d\r*$' % k, timeout=900)
        out = {'cut': res}
        results[k] = out
        if res['status'] != 'KILLED':
            ok = False
            continue
        # every ACK the console showed was acknowledged before the cut
        acked = max(int(x) for x in re.findall(r'(?m)^ACK (\d+)', log))
        out['acked_on_console'] = acked
        # A: host e2fsck (journal replay), then the file from the image
        ia = copy(img, 'durable-%d-hostfsck' % k)
        out['host_e2fsck_exit'] = qd_image.fsck_root(ia)
        d = Path(tempfile.mkdtemp(dir=WORK))
        (d / 'state').write_bytes(qd_image.read_root(ia, '/sapg/d/state'))
        r = subprocess.run([chk, '--check', d, str(acked)], capture_output=True, text=True)
        out['host_check'] = r.stdout.strip()
        # B: the guest boots the cut disk itself (its ext4 driver's own recovery)
        gb = copy(img, 'durable-%d-guestboot' % k)
        sh_text = '/sapg/sapg-durable --check /sapg/d %d && echo SAPG_PASS\n' % acked
        qd_image.write_root(gb, {'/sapg/check.sh': (write_tmp(sh_text), True)})
        rc2, res2, log2 = boot(gb, 'durable-reboot-%d' % k, 'sh /sapg/check.sh; echo SAPG_""END', timeout=600)
        out['guest_check'] = (re.findall(r'DURABLE_\w+[^\r\n]*', after(log2, 'check.sh')) or ['(none)'])[-1]
        out['guest_boot'] = res2
        ok = ok and r.returncode == 0 and res2['status'] == 'PASS'
    return ok, results


def write_tmp(text):
    p = Path(tempfile.mkdtemp(dir=WORK)) / 'f'
    p.write_text(text)
    return p


# ---- sap-cut ----

def sap_channels(root):
    import saptest as T
    import test_sap_e2e as E
    keys = T.Keys(root)
    repo = root / 'repo'
    def publish(rel, tree, spec):
        sp = root / ('spec-%s.json' % rel); sp.write_text(json.dumps(spec))
        import contextlib, io
        with contextlib.redirect_stdout(io.StringIO()):
            assert T.SB.main(['publish', '--repo', str(repo), '--release', rel, '--tree', str(tree), '--spec', str(sp), '--key', str(keys.key)]) == 0
    publish('0.1.0', E.tree_v1(root / 't1'), E.SPEC)
    shutil.copytree(repo, root / 'repo1', symlinks=True)
    publish('0.1.1', E.tree_v2(root / 't2'), E.V2)
    shutil.copytree(repo, root / 'repo2', symlinks=True)
    return keys


def case_sap_cut(a):
    prep = Path(tempfile.mkdtemp(dir=WORK))
    keys = sap_channels(prep)
    ov = prep / 'ov'
    for r in ('repo1', 'repo2'):
        shutil.copytree(prep / r, ov / 'sapg' / r, symlinks=True)
    (ov / 'sapg/keys').mkdir(parents=True)
    shutil.copy(keys.signers, ov / 'sapg/keys/allowed_signers')
    shutil.copy(a.bin / 'sap', ov / 'sapg/sap')
    (ov / 'sapg/root').mkdir(); (ov / 'sapg/root/.sapg').write_text('')
    (ov / 'sapg/sfboot/sf').mkdir(parents=True); (ov / 'sapg/sfboot/sf/.keep').write_text('')
    pre = ('export SAP_NOW=%s SAP_LAUNCHCTL=/bin/echo; S="/sapg/sap --root /sapg/root --sfboot /sapg/sfboot '
           '--trust-anchor /sapg/keys/allowed_signers --manifest-url file:///sapg/%%s/v1/stable/manifest.json"\n' % NOW)
    results, ok = {}, True
    for fault in a.faults:
        tag = fault.replace(':', '-')
        script(ov, '/sapg/cut.sh', pre + '$(printf "$S" repo1) install --all -y; echo "install=$?"\n'
               'SAP_FAULT=halt:%s $(printf "$S" repo2) upgrade -y; echo "upgrade=$?"\n' % fault)
        script(ov, '/sapg/recover.sh', pre + 'R=$(printf "$S" repo2)\n$R recover; r=$?; echo "recover=$r"\n'
               '$R verify; v=$?; echo "verify=$v"\n$R list --installed\n'
               '[ $r = 0 ] && [ $v = 0 ] && echo SAPG_PASS\n')
        img = image('sapcut-' + tag, ov)
        rc, res, log = boot(img, 'sapcut-%s-1' % tag, 'sh /sapg/cut.sh', kill_on=r'SAPG_HALT ' + re.escape(fault))
        r = {'cut': res}
        if res['status'] != 'KILLED':
            r['tail'] = after(log, 'cut.sh')[-600:]
            results[fault] = r; ok = False
            continue
        rc2, res2, log2 = boot(img, 'sapcut-%s-2' % tag, 'sh /sapg/recover.sh; echo SAPG_""END')
        t = after(log2, 'recover.sh; echo')
        r.update(reboot=res2, recover=re.findall(r'recover=\d+', t), verify=re.findall(r'verify=\d+', t),
                 installed=re.findall(r'(?m)^(vim\s+\S+)', t), recover_output=t[-900:])
        r['host_e2fsck_after'] = qd_image.fsck_root(copy(img, 'sapcut-%s-after' % tag))
        ok = ok and res2['status'] == 'PASS'
        results[fault] = r
    return ok, results


# ---- sfboot ----

def fat_disk(path, files):
    """A 64 MiB disk: GPT, one partition at 1 MiB, FAT32 labelled SFBOOT, holding files."""
    mib = 1 << 20
    with open(path, 'wb') as f:
        f.truncate(64 * mib)
    sh('sfdisk', '-q', path, input=b'label: gpt\nstart=2048, size=126976, type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name=SFBOOT\n')
    part = path.with_suffix('.part')
    part.unlink(missing_ok=True)
    sh('mkfs.vfat', '-F', '32', '-s', '1', '-n', 'SFBOOT', '-C', part, str(126976 // 2))
    mmd, mcopy = qd_image.tool('mmd'), qd_image.tool('mcopy')
    dirs = sorted({str(Path(p).parent) for p in files if str(Path(p).parent) not in ('.', '/')}, key=len)
    for d in dirs:
        sh(mmd, '-i', part, '::/' + d)
    for p, src in files.items():
        sh(mcopy, '-o', '-i', part, src, '::/' + p)
    with open(path, 'r+b') as f, open(part, 'rb') as p:
        f.seek(mib); shutil.copyfileobj(p, f)
    part.unlink()


def fat_read(disk, p, out):
    sh(qd_image.tool('mcopy'), '-o', '-i', '%s@@%d' % (disk, 1 << 20), '::/' + p, out)


def case_sfboot(a):
    import saptest as T
    work = Path(tempfile.mkdtemp(dir=WORK))
    boot_bin = work / 'boot.bin'; boot_bin.write_bytes(b'SF stage 2 slot A\n' * 500)
    kern = work / 'kernel.bin'; kern.write_bytes(b'SF kernel slot A\n' * 500)
    init = work / 'init'; (init / 'sf').mkdir(parents=True)
    shutil.copy(boot_bin, init / 'sf/boot.bin'); shutil.copy(kern, init / 'sf/kernel.bin')
    T.slot_tool(init, '--running', 'a', '--generation', '1', 'init')
    disk = work / 'sfboot.img'
    fat_disk(disk, {'sf/boot.bin': boot_bin, 'sf/kernel.bin': kern, 'sf/bootstate.bin': init / 'sf/bootstate.bin'})
    ov = work / 'ov'
    for n in ('sf-bootslot', 'sf-mount-sfboot'):
        (ov / 'sapg').mkdir(parents=True, exist_ok=True); shutil.copy(a.bin / n, ov / 'sapg' / n)
    (ov / 'sapg/b-boot.bin').write_bytes(b'SF stage 2 slot B\n' * 600)
    (ov / 'sapg/b-kernel.bin').write_bytes(b'SF kernel slot B\n' * 600)
    script(ov, '/sapg/s1.sh', '''launchctl list > /sapg/launchctl.txt 2>&1; echo "launchctl=$?"
/sapg/sf-mount-sfboot --dry-run /Volumes/SFBOOT; echo "dry=$?"
mkdir -p /Volumes/SFBOOT; /sapg/sf-mount-sfboot /Volumes/SFBOOT; m=$?; echo "mount=$m"
mount | grep -i msdos
T="/sapg/sf-bootslot --boot /Volumes/SFBOOT"
$T status
$T begin-stage b; b=$?; echo "begin=$b"
mkdir -p /Volumes/SFBOOT/sf/b && cp /sapg/b-boot.bin /Volumes/SFBOOT/sf/b/boot.bin && cp /sapg/b-kernel.bin /Volumes/SFBOOT/sf/b/kernel.bin; c=$?; echo "copy=$c"
$T arm b; r=$?; echo "arm=$r"
$T status
sync; umount /Volumes/SFBOOT; u=$?; echo "umount=$u"
[ $m = 0 ] && [ $b = 0 ] && [ $c = 0 ] && [ $r = 0 ] && [ $u = 0 ] && echo SAPG_PASS
''')
    img = image('sfboot-1', ov)
    rc, res, log = boot(img, 'sfboot-1', 'sh /sapg/s1.sh; echo SAPG_""END', drives=[disk])
    out = {'boot1': res, 'boot1_output': after(log, 's1.sh; echo')[-1500:]}
    lc = qd_image.read_root(img, '/sapg/launchctl.txt').decode(errors='replace')
    out['launchctl_list_head'] = lc.splitlines()[:6]
    if res['status'] != 'PASS':
        return False, out
    rb = work / 'readback'; (rb / 'sf/b').mkdir(parents=True)
    for p in ('sf/bootstate.bin', 'sf/boot.bin', 'sf/kernel.bin', 'sf/b/boot.bin', 'sf/b/kernel.bin'):
        fat_read(disk, p, rb / p)
    st = T.slot_status(rb, running='a')
    out['host_status_after_boot1'] = st
    armed = st.get('trial') == 'b' and st.get('trial_state') == 'armed'
    # a running service for the health check
    label = None
    for line in lc.splitlines()[1:]:
        c = line.split('\t') if '\t' in line else line.split()
        if len(c) >= 3 and c[0].isdigit() and c[2].startswith(('com.', 'org.')):
            label = c[2]; break
    out['health_label'] = label
    ov2 = work / 'ov2'
    import sap_image as SI
    bins = work / 'bins'; bins.mkdir()
    for n in ('sap', 'sf', 'sf-bootslot', 'sf-mount-sfboot'):
        shutil.copy(a.bin / n, bins / n)
    for target, data, mode in SI.files(bins):
        p = ov2 / target.lstrip('/'); p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(data); p.chmod(mode)
    conf = (ov2 / 'etc/sap.conf').read_text() + ('health_services = %s\n' % label if label else '')
    (ov2 / 'etc/sap.conf').write_text(conf)
    script(ov2, '/sapg/s2.sh', '''n=0; while [ $n -lt 300 ] && ! grep -q "sap-mark-good: exit" /var/log/sap-boot.log 2>/dev/null; do sleep 2; n=$((n+2)); done
cat /var/log/sap-boot.log; cat /var/run/sap-boot.done
S=$(/usr/libexec/sf-bootslot --boot /Volumes/SFBOOT status); echo "$S"
echo "$S" | grep -q "^default=b" && echo SAPG_PASS
''')
    img2 = image('sfboot-2', ov2, bootargs='sf_slot=b')
    rc2, res2, log2 = boot(img2, 'sfboot-2', 'sh /sapg/s2.sh; echo SAPG_""END', drives=[disk])
    out.update(boot2=res2, boot2_output=after(log2, 's2.sh; echo')[-2500:])
    rb2 = work / 'readback2'; (rb2 / 'sf').mkdir(parents=True)
    fat_read(disk, 'sf/bootstate.bin', rb2 / 'sf/bootstate.bin')
    shutil.copy(rb / 'sf/boot.bin', rb2 / 'sf/boot.bin'); shutil.copytree(rb / 'sf/b', rb2 / 'sf/b')
    shutil.copy(rb / 'sf/kernel.bin', rb2 / 'sf/kernel.bin')
    out['host_status_after_boot2'] = T.slot_status(rb2, running='b')
    return armed and res2['status'] == 'PASS' and out['host_status_after_boot2'].get('default') == 'b', out


# ---- kc ----

def case_kc(a):
    inputs = Path(a.kc_inputs)
    args = [l for l in (inputs / 'link-args.txt').read_text().splitlines() if l]
    sys.path.insert(0, str(G.REPO / 'installer/payload/release'))
    import kc_release as KC
    work = Path(tempfile.mkdtemp(dir=WORK))
    ref = work / 'host.kc'
    digest, n = KC.link_reference(inputs, a.kc_host_builder, ref)
    ov = work / 'ov'
    shutil.copytree(inputs, ov / 'sapg/kc', symlinks=False)
    shutil.copy(a.kc_builder, ov / 'sapg/kc-builder')
    gargs = ' '.join("'%s'" % ('/sapg/kc.out' if x == KC.OUTPUT else x) for x in args)
    script(ov, '/sapg/kc.sh', 'cd /sapg/kc && /sapg/kc-builder %s; r=$?; echo "kc=$r"; /bin/sync; ls -l /sapg/kc.out; [ $r = 0 ] && echo SAPG_PASS\n' % gargs)
    img = image('kc', ov)
    rc, res, log = boot(img, 'kc', 'sh /sapg/kc.sh; echo SAPG_""END', timeout=1800)
    out = {'boot': res, 'output': after(log, 'kc.sh; echo')[-800:], 'host_sha256': digest, 'host_bytes': n}
    if res['status'] != 'PASS':
        return False, out
    qd_image.fsck_root(img)
    got = qd_image.read_root(img, '/sapg/kc.out')
    import hashlib
    out['guest_sha256'], out['guest_bytes'] = hashlib.sha256(got).hexdigest(), len(got)
    return out['guest_sha256'] == digest, out


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--bin', type=Path, required=True)
    p.add_argument('--faults', nargs='*', default=['rec:3', 'op:1', 'op:4'])
    p.add_argument('--cuts', nargs='*', type=int, default=[40, 333, 1201])
    p.add_argument('--kc-inputs'); p.add_argument('--kc-builder'); p.add_argument('--kc-host-builder')
    p.add_argument('cases', nargs='*', default=['durable', 'sap-cut', 'sfboot', 'kc'])
    a = p.parse_args()
    a.bin = a.bin.resolve()
    sys.path.insert(0, str(G.REPO / 'sap/tools'))
    WORK.mkdir(parents=True, exist_ok=True)
    report_path = WORK / 'cases.json'
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    fns = {'durable': case_durable, 'sap-cut': case_sap_cut, 'sfboot': case_sfboot, 'kc': case_kc}
    for c in a.cases:
        if c == 'kc' and not (a.kc_inputs and a.kc_builder and a.kc_host_builder):
            report[c] = {'ok': None, 'skipped': 'needs --kc-inputs, --kc-builder and --kc-host-builder'}
            continue
        try:
            ok, detail = fns[c](a)
        except Exception as e:  # noqa: BLE001 - reported
            ok, detail = False, {'error': repr(e)}
        report[c] = {'ok': ok, 'at': NOW, **({'detail': detail})}
        print(c, 'OK' if ok else 'FAILED', flush=True)
        report_path.write_text(json.dumps(report, indent=1, default=str) + '\n')
    return 0 if all(r.get('ok') is not False for r in report.values()) else 1


if __name__ == '__main__':
    sys.exit(main())
