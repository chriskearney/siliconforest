#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""SAP in a SiliconForest/PureDarwin QEMU guest (arm64 `virt`, TCG): the Darwin ext4 driver, the
Darwin userland and the aarch64-apple-darwin builds, without Apple hardware.

Uses integrations/siliconforest/qemu-dev (qd_image: base image, debugfs writes; qd_run: QEMU
command line, serial console). Everything goes under WORK (default: runs/sap-guest, never
committed). Linux host with nix, qemu-system-aarch64, debugfs/e2fsck and mtools.

  sap_guest.py image  --out IMG [--file SRC=/DEST ...] [--data SRC=/DEST ...] [--overlay TREE ...] [--bootargs ...]
  sap_guest.py run    --image IMG --out DIR --command 'sh /sapg/run.sh'
                      [--kill-on REGEX] [--drive FILE ...] [--timeout S]
       boots, types the command at the root shell, waits for SAPG_END (or, with --kill-on, kills
       QEMU with SIGKILL the moment the regex shows on the serial console: a power cut as the
       guest sees it). Writes DIR/serial.log and DIR/result.json; exit 0 when SAPG_PASS showed.
  sap_guest.py fsck   --image IMG       e2fsck -fy of the root (replays the journal)
  sap_guest.py cat    --image IMG PATH  a file of the root, to stdout
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[3]
QD = REPO / 'integrations/siliconforest/qemu-dev'
sys.path.insert(0, str(QD))
import qd_image  # noqa: E402
import qd_run  # noqa: E402

WORK = Path(os.environ.get('SAPG_WORK', REPO / 'runs/sap-guest'))


def build(a):
    base = qd_image.base_image('release')
    out = a.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    subprocess.run(['cp', '--reflink=auto', str(base), str(out)], check=True)
    os.chmod(out, 0o644)
    esp = '%s@@%d' % (out, qd_image.partitions(out)[0][0])
    tmp = out.parent / (out.name + '.esp')
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir()
    mcopy = qd_image.tool('mcopy')
    subprocess.run([mcopy, '-n', '-i', esp, '::/EFI/BOOT/kernel', str(tmp / 'kernel')], check=True)
    kernel, _ = qd_image.patch_time_waits((tmp / 'kernel').read_bytes(), 1, 2)
    (tmp / 'kernel').write_bytes(kernel)
    (tmp / 'boot-args.txt').write_text(qd_image.BOOTARGS['release'] + (' ' + a.bootargs if a.bootargs else ''))
    for f in ('kernel', 'boot-args.txt'):
        subprocess.run([mcopy, '-o', '-i', esp, str(tmp / f), '::/EFI/BOOT/' + f], check=True)
    shutil.rmtree(tmp)
    files = {}
    for items, x in ((a.file, True), (a.data, False)):
        for item in items:
            src, dest = item.split('=', 1)
            files[dest] = (Path(src).resolve(strict=True), x)
    links = [tuple(i.split('=', 1)) for i in a.link]
    for ov in a.overlay:
        f, l = qd_image.overlay_entries(ov)
        files.update(f)
        links += l
    if files or links:
        qd_image.write_root(out, files, links=links)
    print(json.dumps({'image': str(out), 'base': str(base), 'files': sorted(files)}))


def run(a):
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    for stale in ('serial.sock', 'qmp.sock', 'serial.log', 'result.json'):
        (out / stale).unlink(missing_ok=True)
    qa = argparse.Namespace(image=a.image, pointer='mouse', window=False, qemu='qemu-system-aarch64', cpu='neoverse-n2',
                            smp=a.smp, memory=a.memory, qemu_arg=[])
    for i, d in enumerate(a.drive):
        qa.qemu_arg += ['-drive', 'if=none,id=extra%d,file=%s,format=raw,cache=%s' % (i, Path(d).resolve(), a.cache),
                        '-device', 'virtio-blk-pci,drive=extra%d' % i]
    cmd = qd_run.qemu_command(qa, out)
    if a.cache != 'unsafe':
        cmd = [c.replace('cache=unsafe', 'cache=' + a.cache) for c in cmd]
    t0 = time.time()
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=open(out / 'qemu.log', 'wb'), stderr=subprocess.STDOUT, cwd=out,
                            env={k: v for k, v in os.environ.items() if k not in ('DISPLAY', 'WAYLAND_DISPLAY')})
    result = {'status': 'ERROR', 'cache': a.cache}
    try:
        ser = qd_run.Serial(out / 'serial.sock', out / 'serial.log', t0 + 30)
        end_by = t0 + a.timeout
        if not ser.wait(qd_run.PROMPT, end_by, proc):
            raise RuntimeError('no shell prompt on the serial console')
        result['shell_s'] = round(time.time() - t0, 1)
        start = len(ser.text())
        ser.send(a.command + '\n')
        if a.kill_on:
            m = ser.wait(re.compile(a.kill_on.encode()), end_by, proc, start)
            if not m:
                raise RuntimeError('kill marker never showed')
            os.kill(proc.pid, signal.SIGKILL)
            proc.wait()
            result.update(status='KILLED', killed_at=m.group(0).decode(errors='replace'))
        else:
            m = ser.wait(re.compile(rb'(?m)^SAPG_END'), end_by, proc, start)
            text = ser.text()[start:]
            passed = bool(re.search(rb'(?m)^SAPG_PASS', text))
            result.update(status='PASS' if passed else ('ENDED' if m else 'TIMEOUT'))
    except Exception as e:  # noqa: BLE001 - reported, exit 2
        result['error'] = str(e)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        for s in ('serial.sock', 'qmp.sock'):
            (out / s).unlink(missing_ok=True)
    result['seconds'] = round(time.time() - t0, 1)
    (out / 'result.json').write_text(json.dumps(result, indent=1) + '\n')
    print(json.dumps(result))
    return 0 if result['status'] in ('PASS', 'KILLED') else (2 if 'error' in result else 1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='what', required=True)
    i = sub.add_parser('image')
    i.add_argument('--out', type=Path, required=True)
    i.add_argument('--file', action='append', default=[])
    i.add_argument('--data', action='append', default=[])
    i.add_argument('--link', action='append', default=[], metavar='/PATH=TARGET')
    i.add_argument('--bootargs', default='')
    i.add_argument('--overlay', action='append', default=[], help='a tree rooted at / to add (qd_image.overlay_entries)')
    r = sub.add_parser('run')
    r.add_argument('--image', type=Path, required=True)
    r.add_argument('--out', type=Path, required=True)
    r.add_argument('--command', required=True)
    r.add_argument('--kill-on', default='')
    r.add_argument('--drive', action='append', default=[])
    r.add_argument('--cache', default='unsafe', help='QEMU cache mode of every disk (directsync: no host cache at all)')
    r.add_argument('--timeout', type=int, default=900)
    r.add_argument('--smp', type=int, default=2)
    r.add_argument('--memory', type=int, default=1024)
    f = sub.add_parser('fsck')
    f.add_argument('--image', type=Path, required=True)
    c = sub.add_parser('cat')
    c.add_argument('--image', type=Path, required=True)
    c.add_argument('path')
    a = p.parse_args()
    if a.what == 'image':
        build(a)
    elif a.what == 'run':
        return run(a)
    elif a.what == 'fsck':
        print(json.dumps({'e2fsck_exit': qd_image.fsck_root(a.image)}))
    else:
        sys.stdout.buffer.write(qd_image.read_root(a.image, a.path))
    return 0


if __name__ == '__main__':
    sys.exit(main())
