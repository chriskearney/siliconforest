#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Run the QEMU desktop checks on the M6 with HVF.

From the workstation:

    m6-hvf-check.py --disk PREPARED.img --run probeN --out DIR

PREPARED.img is a prepare-run.sh disk (1500 none). The script copies it to
~/sf/runs/<run>/ on chrisk@10.1.1.92 and never writes the local file. SSH uses
~/.ssh/known_hosts_m6 and HostKeyAlias=m6, with StrictHostKeyChecking left on.
10.1.1.91 is refused.

HVF reports ID_AA64PFR0_EL1.GIC as 0, so an unpatched guest takes the GICv2
CPU-interface path. This virt machine is GICv3. On the disposable copy only,
the two detection sites change the first instruction from mrs to
movz x8, #0x100, lsl #16 (the GICv3 system-register value). The scan is the
64 MiB window at offset 1 MiB. Each site must occur once.

The terminal PTY is not the serial console. Pass requires the session and
desktop serial marks, two full VNC frames, and a WMOWNER real-input line after
the USB keystrokes. Read the second frame for arm64, typed-in-qemu, and the
returned prompt. Fetched serial lines that mention a host key are dropped.
"""
import argparse
import hashlib
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

HOST = "chrisk@10.1.1.92"
REFUSED = "10.1.1.91"
ESP = 512 * 2048
SCAN = 64 * 1024 * 1024
MRS = bytes.fromhex("080438d5")
MOVZ = bytes.fromhex("0820a0d2")  # movz x8, #0x100, lsl #16
TAILS = (
    bytes.fromhex("e80700f9e80740f908fd58d3080d40f2e0179f1a"),
    bytes.fromhex("1f0d68f240000054c0035fd6"),
)
def run_name_ok(name):
    if not name or len(name) > 41 or not name[0].isalnum():
        return False
    return all(ch.isalnum() or ch in "._-" for ch in name)


def find_all(buf, needle):
    found = []
    start = 0
    while True:
        at = buf.find(needle, start)
        if at < 0:
            return found
        found.append(at)
        start = at + 1


def ssh_base(host):
    if REFUSED in host:
        raise SystemExit("refused host")
    known = Path.home() / ".ssh" / "known_hosts_m6"
    return [
        "ssh",
        "-o", "UserKnownHostsFile=%s" % known,
        "-o", "HostKeyAlias=m6",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=15",
        host,
    ]


def rsync_e():
    known = Path.home() / ".ssh" / "known_hosts_m6"
    return "ssh -o UserKnownHostsFile=%s -o HostKeyAlias=m6 -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15" % known


def patch_window(window):
    """Return (new_window, note). new_window is None when the bytes already match."""
    changed = False
    notes = []
    for tail in TAILS:
        raw = MRS + tail
        done = MOVZ + tail
        raw_at = find_all(window, raw)
        done_at = find_all(window, done)
        if len(raw_at) + len(done_at) != 1:
            raise SystemExit("GIC site count raw=%d patched=%d" % (len(raw_at), len(done_at)))
        if done_at:
            notes.append("already 0x%x" % (ESP + done_at[0]))
            continue
        at = raw_at[0]
        window[at:at + 4] = MOVZ
        changed = True
        notes.append("patched 0x%x" % (ESP + at))
    return (window if changed else None), ", ".join(notes)


def patch_disk(path):
    path = Path(path)
    with path.open("r+b") as fh:
        fh.seek(ESP)
        window = bytearray(fh.read(SCAN))
        if len(window) != SCAN:
            raise SystemExit("disk is smaller than the scan window")
        updated, note = patch_window(window)
        if updated is not None:
            fh.seek(ESP)
            fh.write(updated)
            fh.flush()
            os.fsync(fh.fileno())
        print(note)
    return 0


def self_test():
    blob = bytearray(SCAN)
    spots = (0x1000, 0x2000)
    for tail, at in zip(TAILS, spots):
        blob[at:at + 4 + len(tail)] = MRS + tail
    updated, note = patch_window(bytearray(blob))
    if updated is None or "patched" not in note:
        raise SystemExit("self-test: patch did not write")
    for tail, at in zip(TAILS, spots):
        if updated[at:at + 4] != MOVZ or updated[at + 4:at + 4 + len(tail)] != tail:
            raise SystemExit("self-test: replacement bytes mismatch")
    again, note2 = patch_window(bytearray(updated))
    if again is not None or "already" not in note2:
        raise SystemExit("self-test: second pass was not idempotent")
    doubled = bytearray(updated)
    doubled[0x3000:0x3000 + 4 + len(TAILS[0])] = MOVZ + TAILS[0]
    try:
        patch_window(doubled)
    except SystemExit as exc:
        if "count" not in str(exc.code):
            raise
    else:
        raise SystemExit("self-test: duplicate site was accepted")
    print("self-test ok")
    return 0


def supervise():
    run = Path.cwd()
    fw = Path("/opt/homebrew/share/qemu")
    qemu = "/opt/homebrew/bin/qemu-system-aarch64"
    shot_py = run / "vnc-shot.py"
    vars_fd = run / "vars.fd"
    if not vars_fd.exists():
        vars_fd.write_bytes((fw / "edk2-arm-vars.fd").read_bytes())
        vars_fd.chmod(0o644)
    for stale in ("vnc.sock", "mon.sock"):
        try:
            (run / stale).unlink()
        except FileNotFoundError:
            pass
    cmd = [
        qemu,
        "-machine", "virt,gic-version=3",
        "-accel", "hvf,kernel-irqchip=off",
        "-cpu", "host",
        "-smp", "4",
        "-m", "1024",
        "-boot", "order=c,strict=on",
        "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=%s" % (fw / "edk2-aarch64-code.fd"),
        "-drive", "if=pflash,format=raw,unit=1,file=%s" % vars_fd,
        "-drive", "if=none,id=system,file=disk.img,format=raw,cache=unsafe",
        "-device", "virtio-blk-pci,drive=system,bootindex=1",
        "-device", "ramfb",
        "-device", "virtio-net-pci,netdev=net0",
        "-netdev", "user,id=net0",
        "-device", "qemu-xhci,id=xhci",
        "-device", "usb-kbd,bus=xhci.0",
        "-device", "usb-mouse,bus=xhci.0",
        "-vnc", "unix:%s" % (run / "vnc.sock"),
        "-monitor", "unix:%s,server=on,wait=off" % (run / "mon.sock"),
        "-serial", "stdio",
        "-display", "none",
        "-no-reboot",
    ]
    timed = (run / "serial.timed").open("w")
    raw = (run / "serial.log").open("wb")
    err = (run / "qemu.log").open("wb")
    t0 = time.time()
    (run / "t0").write_text("%.3f\n" % t0)
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (run / "pid").write_text("%s\n" % proc.pid)
    marks = {}
    lines = []
    lock = threading.Lock()

    def pump_err():
        while True:
            chunk = proc.stderr.read(4096)
            if not chunk:
                break
            err.write(chunk)
            err.flush()

    def pump_out():
        buf = b""
        while True:
            chunk = proc.stdout.read(1)
            if not chunk:
                break
            raw.write(chunk)
            raw.flush()
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                now = time.time() - t0
                text = line.replace(b"\r", b"").decode("utf-8", "replace")
                timed.write("%8.3f %s\n" % (now, text))
                timed.flush()
                with lock:
                    lines.append((now, text))
                    if "QDDESK_BEGIN" in text and "session" not in marks:
                        marks["session"] = now
                        print("MARK session %.3f" % now, flush=True)
                    if "WMSCALE initial" in text and "desktop" not in marks:
                        marks["desktop"] = now
                        print("MARK desktop %.3f" % now, flush=True)

    threading.Thread(target=pump_err, daemon=True).start()
    threading.Thread(target=pump_out, daemon=True).start()
    before = run / "shots" / "before"
    after = run / "shots" / "after"
    r1 = subprocess.CompletedProcess([], 1)
    r2 = subprocess.CompletedProcess([], 1)
    type_at = None
    owned = False
    try:
        deadline = time.time() + 240
        while time.time() < deadline and "desktop" not in marks and proc.poll() is None:
            time.sleep(0.2)
        if "desktop" not in marks:
            print("NO_DESKTOP", flush=True)
            (run / "marks.txt").write_text("desktop missing\n")
            return 2
        desktop_at = marks["desktop"]
        time.sleep(15)
        before.mkdir(parents=True, exist_ok=True)
        r1 = subprocess.run(
            ["python3", "-I", str(shot_py), str(run / "vnc.sock"), str(before), "--count", "1", "--every", "1"],
            check=False, timeout=90)
        print("SHOT %s" % r1.returncode, flush=True)
        remain = 150 - (time.time() - t0 - desktop_at)
        if remain > 0:
            time.sleep(remain)
        type_at = time.time() - t0
        subprocess.run(
            ["python3", "-I", str(shot_py), str(run / "vnc.sock"), "--type", "uname -m; echo typed-in-qemu"],
            check=False, timeout=60)
        print("TYPED %.3f" % type_at, flush=True)
        time.sleep(3)
        after.mkdir(parents=True, exist_ok=True)
        r2 = subprocess.run(
            ["python3", "-I", str(shot_py), str(run / "vnc.sock"), str(after), "--count", "1", "--every", "1"],
            check=False, timeout=90)
        print("SHOT2 %s" % r2.returncode, flush=True)
        with lock:
            owned = any(when >= type_at - 1 and "WMOWNER real input" in text for when, text in lines)
    finally:
        if proc.poll() is None:
            cpu = subprocess.run(["ps", "-o", "time=", "-p", str(proc.pid)], capture_output=True, text=True).stdout.strip()
            proc.terminate()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
        else:
            cpu = ""
    if "desktop" not in marks:
        return 2
    text = "\n".join("%s %.3f" % (key, marks[key]) for key in ("session", "desktop") if key in marks)
    text += "\ntyped_at %s\nowner_input %d\nshot %d\nshot2 %d\nqemu_cpu %s\n" % (
        ("%.3f" % type_at) if type_at is not None else "missing", int(owned), r1.returncode, r2.returncode, cpu)
    (run / "marks.txt").write_text(text)
    print(text, flush=True)
    full = 1024 * 768 * 3
    frames_ok = r1.returncode == 0 and r2.returncode == 0 and type_at is not None
    frames_ok = frames_ok and (before / "001.ppm").is_file() and (before / "001.ppm").stat().st_size > full
    frames_ok = frames_ok and (after / "001.ppm").is_file() and (after / "001.ppm").stat().st_size > full
    ok = frames_ok and owned
    print("DONE" if ok else "FAILED_CHECK", flush=True)
    return 0 if ok else 3


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def orchestrate(args):
    if not run_name_ok(args.run):
        raise SystemExit("run name must be a short token")
    disk = Path(args.disk).resolve()
    if not disk.is_file():
        raise SystemExit("disk not found")
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    vnc = Path(__file__).resolve().with_name("vnc-shot.py")
    if not vnc.is_file():
        raise SystemExit("vnc-shot.py not found at %s" % vnc)
    local_hash = sha256(disk)
    print("local %s" % local_hash)
    remote = "$HOME/sf/runs/%s" % args.run
    base = ssh_base(args.host)
    subprocess.run(base + ["mkdir -p %s" % remote], check=True)
    subprocess.run([
        "rsync", "-a", "--partial", "-e", rsync_e(),
        str(disk), str(Path(__file__).resolve()), str(vnc),
        "%s:sf/runs/%s/" % (args.host, args.run),
    ], check=True)
    shown = subprocess.run(base + ["cd %s && shasum -a 256 disk.img" % remote], check=True, capture_output=True, text=True)
    print(shown.stdout.strip())
    if not shown.stdout.startswith(local_hash):
        raise SystemExit("remote hash mismatch")
    patch = subprocess.run(base + ["cd %s && python3 m6-hvf-check.py --patch-disk disk.img" % remote], check=False)
    if patch.returncode != 0:
        return patch.returncode
    print("BOOT", flush=True)
    status = subprocess.run(base + ["cd %s && exec python3 -u m6-hvf-check.py --supervise" % remote]).returncode
    scp = [
        "scp",
        "-o", "UserKnownHostsFile=%s" % (Path.home() / ".ssh" / "known_hosts_m6"),
        "-o", "HostKeyAlias=m6",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=15",
    ]
    for remote_name, local_name in (
        ("marks.txt", "marks.txt"),
        ("shots/before/001.ppm", "before.ppm"),
        ("shots/after/001.ppm", "after.ppm"),
    ):
        subprocess.run(scp + ["%s:sf/runs/%s/%s" % (args.host, args.run, remote_name), str(out / local_name)], check=False)
    excerpt = subprocess.run(
        base + ["cd %s && grep -E 'QDDESK_|WMSCALE initial|sf-console-login: exec|WMOWNER real input' serial.timed" % remote],
        check=False, capture_output=True, text=True)
    kept = [line for line in excerpt.stdout.splitlines() if "host key" not in line.lower()]
    (out / "serial-marks.txt").write_text("\n".join(kept) + ("\n" if kept else ""))
    print("\n".join(kept))
    return status


def main():
    ap = argparse.ArgumentParser(description="HVF desktop check on the authorized M6")
    ap.add_argument("--disk")
    ap.add_argument("--run")
    ap.add_argument("--out")
    ap.add_argument("--host", default=HOST)
    ap.add_argument("--patch-disk")
    ap.add_argument("--supervise", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if args.patch_disk:
        return patch_disk(args.patch_disk)
    if args.supervise:
        return supervise()
    if not args.disk or not args.run or not args.out:
        ap.error("--disk, --run, and --out are required")
    return orchestrate(args)


if __name__ == "__main__":
    sys.exit(main())
