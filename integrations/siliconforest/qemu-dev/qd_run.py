#!/usr/bin/env python3
"""Boot a run image in QEMU (arm64 `virt`, TCG), start the desktop session from the serial
shell, and either leave a window up for a person or drive it unattended.

Everything written goes to --out: serial.log (QEMU's own capture of the guest console),
qemu.log, shots/*.png (QMP screendump of the guest framebuffer), result.json.
Exit status: 0 pass, 1 fail, 2 could not run.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

AAVMF = Path(os.environ.get('QD_AAVMF', '/nix/store/kkg3rig7vsynfa3gmafm0dj63inm5jh6-OVMF-aarch64-unknown-linux-gnu-202602-fd/FV'))
PROMPT = re.compile(rb'root@[^\r\n]*\r?\n?[^\r\n]*# ?(\x1b\[[0-9;?]*[a-zA-Z])*\s*$')


class Qmp:
    def __init__(self, path, deadline):
        while True:
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(str(path))
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.05)
        self.f = self.s.makefile('rwb')
        # A blocked QMP request must not defeat the whole-run deadline.
        self.s.settimeout(max(1.0, min(30.0, deadline - time.time())))
        self.f.readline()
        self.cmd('qmp_capabilities')

    def cmd(self, name, **args):
        self.f.write(json.dumps({'execute': name, 'arguments': args}).encode() + b'\n')
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError('QMP closed')
            r = json.loads(line)
            if 'return' in r or 'error' in r:
                return r

    def shot(self, path):
        # QD_NO_SHOTS=1: no QMP screendump (on a host where it hangs QEMU: seen on 17 November 2026 with QEMU 11.1.0)
        if os.environ.get('QD_NO_SHOTS'):
            return False
        # Pause before any live-state query: even query-status can stall while
        # ramfb is being updated. This runner captures its running guest only.
        self.cmd('stop')
        try:
            r = self.cmd('screendump', filename=str(path), format='png')
        finally:
            self.cmd('cont')
        return 'return' in r and Path(path).exists()

    def keys(self, *names, hold=0.08):
        for down in (True, False):
            for n in (names if down else reversed(names)):
                self.cmd('input-send-event', events=[{'type': 'key', 'data': {'down': down, 'key': {'type': 'qcode', 'data': n}}}])
            time.sleep(hold)

    def wake_input(self, pointer):
        self.keys('shift')
        if pointer == 'tablet':
            self.cmd('input-send-event', events=[{'type': 'abs', 'data': {'axis': 'x', 'value': 16384}},
                                                 {'type': 'abs', 'data': {'axis': 'y', 'value': 16384}}])
        else:
            self.move(1, 1)

    def move(self, dx, dy):
        self.cmd('input-send-event', events=[{'type': 'rel', 'data': {'axis': 'x', 'value': dx}},
                                             {'type': 'rel', 'data': {'axis': 'y', 'value': dy}}])

    def button(self, name, down):
        self.cmd('input-send-event', events=[{'type': 'btn', 'data': {'down': down, 'button': name}}])


class Serial:
    """The guest console: QEMU logs it to a file; we only write to the socket and read the file."""
    def __init__(self, sock, log, deadline):
        self.log = Path(log)
        while True:
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(str(sock))
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.05)
        self.s.setblocking(False)

    def drain(self):
        try:
            while self.s.recv(65536):
                pass
        except (BlockingIOError, OSError):
            pass

    def text(self):
        self.drain()
        return self.log.read_bytes() if self.log.exists() else b''

    def send(self, line):
        self.s.setblocking(True)
        for i in range(0, len(line), 16):          # the guest UART has a small FIFO and no flow control
            self.s.sendall(line[i:i + 16].encode())
            time.sleep(0.02)
        self.s.setblocking(False)

    def wait(self, pattern, deadline, proc, start=0):
        pattern = re.compile(pattern) if isinstance(pattern, (bytes, str)) else pattern
        while True:
            m = pattern.search(self.text(), start)
            if m:
                return m
            if time.time() > deadline or proc.poll() is not None:
                return None
            time.sleep(0.1)


def qemu_command(a, out):
    # A flake image is immutable. Keep each run's guest writes in its own overlay
    # so the same built image can be used again without retaining guest state.
    disk = out / 'system-overlay.qcow2'
    disk.unlink(missing_ok=True)
    qemu_img = str(Path(a.qemu).with_name('qemu-img'))
    subprocess.run([qemu_img, 'create', '-q', '-f', 'qcow2', '-F', 'raw',
                    '-b', str(a.image.resolve()), str(disk)], check=True)
    vars_fd = out / 'AAVMF_VARS.fd'
    shutil.copyfile(AAVMF / 'AAVMF_VARS.fd', vars_fd)
    os.chmod(vars_fd, 0o644)
    pointer = {'tablet': 'usb-tablet', 'mouse': 'usb-mouse'}[a.pointer]
    display = ['-display', 'none']
    if a.window:
        # No full screen, no grab on hover; with the tablet the pointer is never grabbed.
        display = ['-display', 'gtk,grab-on-hover=off,show-menubar=off,zoom-to-fit=off,window-close=on', '-name', 'SiliconForest (QEMU)']
    return [a.qemu, '-machine', 'virt,gic-version=3', '-accel', 'tcg,thread=multi,tb-size=1024', '-cpu', a.cpu,
            '-smp', str(a.smp), '-m', str(a.memory), '-boot', 'order=c,strict=on',
            '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=%s' % (AAVMF / 'AAVMF_CODE.fd'),
            '-drive', 'if=pflash,format=raw,unit=1,file=%s' % vars_fd,
            '-drive', 'if=none,id=system,file=%s,format=qcow2,cache=unsafe' % disk,
            '-device', 'virtio-blk-pci,drive=system,bootindex=1',
            '-device', 'ramfb',
            '-device', 'virtio-net-pci,netdev=net0', '-netdev', 'user,id=net0',
            '-device', 'qemu-xhci,id=xhci', '-device', 'usb-kbd,bus=xhci.0', '-device', pointer + ',bus=xhci.0',
            '-chardev', 'socket,id=ser,path=%s,server=on,wait=off,logfile=%s' % (out / 'serial.sock', out / 'serial.log'),
            '-serial', 'chardev:ser',
            '-qmp', 'unix:%s,server=on,wait=off' % (out / 'qmp.sock'),
            '-monitor', 'none', '-no-reboot'] + display + a.qemu_arg


def record_evidence(result, log):
    lines = [line.decode(errors='replace').strip() for line in log.splitlines()]
    result['wmauto'] = [line for line in lines if line.startswith('WMAUTO') and
                        'result=' in line and not line.startswith('WMAUTO check')]
    result['failed'] = [line[:300] for line in lines if re.search(
        r'result=(FAIL|NOT-|MISMATCH|INCOMPLETE)|panic\(|QDDESK_DESKTOP_RC=[1-9]|launch_failures=[1-9]', line)]
    # A clean compositor exit is insufficient if its applications never launched
    # or its unattended checks could not finish before the session deadline.
    if result['status'] == 'PASS' and (result['failed'] or not result.get('desktop_up')):
        result['status'] = 'FAILED'


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--image', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--command', help='guest command typed at the serial shell once its prompt is there '
                   '(default: none, the image starts its session from launchd)')
    p.add_argument('--begin', default=r'QDDESK_BEGIN', help='serial marker: the session is starting')
    p.add_argument('--input-seen', default='', help='serial marker that ends the input wake-up (e.g. QDDESK_INPUT); empty: no wake-up')
    p.add_argument('--up', default=r'WMAUTO armed|WMSCALE initial', help='serial marker: the desktop is drawing')
    p.add_argument('--settle', type=float, default=1.0, help='seconds between that marker and the first screenshot')
    p.add_argument('--end', default=r'QDDESK_END', help='serial marker: the session is over')
    p.add_argument('--passed', default=r'QDDESK_PASS', help='serial marker for a passed unattended session')
    p.add_argument('--window', action='store_true', help='show a QEMU window and wait until the session or the window ends')
    p.add_argument('--timeout', type=int, default=900, help='upper bound for the whole run, seconds')
    p.add_argument('--shot-every', type=float, default=10.0, help='seconds between screenshots (0: none)')
    p.add_argument('--qemu', default='qemu-system-aarch64')
    p.add_argument('--cpu', default='neoverse-n2')   #  stalls in the firmware
    p.add_argument('--smp', type=int, default=2)
    p.add_argument('--memory', type=int, default=1024)   # kernel start-up time grows with memory under TCG
    p.add_argument('--pointer', choices=('tablet', 'mouse'), default='mouse')
    p.add_argument('--qemu-arg', action='append', default=[])
    a = p.parse_args()
    out = a.out.resolve()
    (out / 'shots').mkdir(parents=True, exist_ok=True)
    for stale in ('serial.sock', 'qmp.sock', 'serial.log', 'result.json'):
        (out / stale).unlink(missing_ok=True)
    t0 = time.time()
    end_by = t0 + a.timeout
    times = {}
    env = dict(os.environ)
    if not a.window:
        for k in ('DISPLAY', 'WAYLAND_DISPLAY'):
            env.pop(k, None)
    proc = subprocess.Popen(qemu_command(a, out), stdin=subprocess.DEVNULL, stdout=open(out / 'qemu.log', 'wb'),
                            stderr=subprocess.STDOUT, env=env, cwd=out)
    result = dict(status='ERROR', times=times, shots=[], host_load=os.getloadavg()[0])
    shots = []

    def shot(name):
        path = out / 'shots' / (name + '.png')
        if qmp.shot(path):
            shots.append(str(path))
            return path

    def cpu_seconds():
        """Host CPU time QEMU has used: on a busy host the wall clock says little."""
        try:
            f = Path('/proc/%d/stat' % proc.pid).read_text().rsplit(')', 1)[1].split()
            return (int(f[11]) + int(f[12])) / os.sysconf('SC_CLK_TCK')
        except (OSError, IndexError, ValueError):
            return 0.0

    def mark(name):
        times[name] = round(time.time() - t0, 1)
        times[name + '_qemu_cpu'] = round(cpu_seconds(), 1)
        print('qemu-desktop: %-8s %6.1f s  (QEMU cpu %.1f s)' % (name, times[name], times[name + '_qemu_cpu']), flush=True)
    try:
        qmp = Qmp(out / 'qmp.sock', t0 + 20)
        ser = Serial(out / 'serial.sock', out / 'serial.log', t0 + 20)
        if a.command:
            if not ser.wait(PROMPT, end_by, proc):
                raise RuntimeError('no shell prompt on the serial console')
            mark('shell')
            ser.send(a.command + '\n')
        if not ser.wait(a.begin.encode(), end_by, proc):
            raise RuntimeError('the session did not start')
        mark('session')
        # The SFHID device nodes appear with the first event of each kind (upstream's USB HID
        # driver publishes them lazily): one Shift press and one pointer step, until the
        # session script has seen both nodes.
        if a.input_seen:
            while not ser.wait(a.input_seen.encode(), time.time() + 0.5, proc) and time.time() < end_by and proc.poll() is None:
                qmp.wake_input(a.pointer)
        up = ser.wait(a.up.encode(), min(end_by, time.time() + 180), proc)
        if up:
            mark('desktop')
            time.sleep(a.settle)
            shot('desktop')
        n, last = 0, time.time()
        end = re.compile(a.end.encode())
        while proc.poll() is None and time.time() < end_by:
            if end.search(ser.text()):
                break
            if a.shot_every and time.time() - last >= a.shot_every:
                n += 1
                last = time.time()
                shot('t%03d' % n)
            time.sleep(0.2)
        mark('end')
        text = ser.text()
        if proc.poll() is None and end.search(text):
            shot('final')
        ended = bool(end.search(text))
        passed = bool(re.search(a.passed.encode(), text))
        result.update(status='PASS' if ended and passed else ('ENDED' if ended else ('WINDOW_CLOSED' if proc.poll() is not None else 'TIMEOUT')),
                      desktop_up=bool(up))
    except Exception as e:                                    # noqa: BLE001 - reported, then exit 2
        result['error'] = str(e)
    finally:
        try:
            if proc.poll() is None:
                qmp.cmd('quit')
        except Exception:                                     # noqa: BLE001
            pass
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(10)
        for s in ('serial.sock', 'qmp.sock'):
            (out / s).unlink(missing_ok=True)
    result['shots'] = shots
    log = (out / 'serial.log').read_bytes() if (out / 'serial.log').exists() else b''
    record_evidence(result, log)
    (out / 'result.json').write_text(json.dumps(result, indent=1) + '\n')
    print('qemu-desktop: %s  (%s)' % (result['status'], out))
    if 'error' in result:
        print('qemu-desktop: ' + result['error'], file=sys.stderr)
        return 2
    if a.window:
        return 0 if result['status'] in ('PASS', 'ENDED', 'WINDOW_CLOSED') else 1
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
