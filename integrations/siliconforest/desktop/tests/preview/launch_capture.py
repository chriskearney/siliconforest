#!/usr/bin/env python3
"""Stage the existing Preview overlay stack into a fresh scratch root, open
reading.pdf, capture, then open siliconforest-notes.pdf and capture.

Does not edit overlay sources, does not reboot, and removes the scratch
root when it finishes. Holds runs/m1-coord/gui.lock for the session.
"""
import fcntl
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path("/home/chrisk/src/darwin-lab")
sys.path.insert(0, str(ROOT / "runs/preview/retained"))
import run_swiftui_hello_full as rsh  # noqa: E402

LOCK = ROOT / "runs/m1-coord/gui.lock"
REMOTE = "/private/var/db/sfpreview-demo-capture.t3"
Q = "/private/var/db/sfqtp/load-20261118T091237Z"
P = "/private/var/db/sfpreview-app/p44-diagnostic-01"
PY = "/opt/homebrew/bin/python3"
PDF = ROOT / "runs/preview/retained/demo-pdf/siliconforest-notes.pdf"
CAP = ROOT / "runs/preview/retained/captures"
SSH = [
    "ssh", "-i", "/home/chrisk/.ssh/id_rsa", "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "GlobalKnownHostsFile=/dev/null", "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "root@10.1.1.211",
]
SCP = [
    "scp", "-i", "/home/chrisk/.ssh/id_rsa", "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "GlobalKnownHostsFile=/dev/null", "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
]

EXTRACT = f'''import pathlib, shutil, sys, tarfile
root = pathlib.Path({REMOTE!r})
if root.exists():
    shutil.rmtree(root)
root.mkdir(parents=True)
t = tarfile.open(fileobj=sys.stdin.buffer, mode="r|")
for m in t:
    p = root / m.name
    p.parent.mkdir(parents=True, exist_ok=True)
    if m.issym():
        if p.is_symlink() or p.exists():
            p.unlink()
        p.symlink_to(m.linkname)
    elif m.isfile():
        p.write_bytes(t.extractfile(m).read())
        p.chmod(m.mode & 0o777)
print("EXTRACT_OK", root)
'''

RUN = r'''
import hashlib, os, shutil, signal, subprocess, time
from pathlib import Path
R = Path("/private/var/db/sfpreview-demo-capture.t3")
P = "/private/var/db/sfpreview-app/p44-diagnostic-01"
EXPECTED = "b0403a45bc454625aaa7a035f4ede247ef2c2bdd23b294e3dfa319800df1ebcd"

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

(R / "home").mkdir(exist_ok=True)
(R / "tmp").mkdir(exist_ok=True)
(R / "logs").mkdir(exist_ok=True)
(R / "fixtures").mkdir(exist_ok=True)
env = {
    "PATH": "/usr/bin:/bin",
    "HOME": str(R / "home"),
    "CFFIXED_USER_HOME": str(R / "home"),
    "TMPDIR": str(R / "tmp") + "/",
    "USER": "root",
    "LOGNAME": "root",
    "XDG_RUNTIME_DIR": "/private/var/run/gpu-desktop",
    "WAYLAND_DISPLAY": "wayland-0",
    "SF_METAL_ENABLE_REAL_DEVICE": "0",
    "DYLD_FRAMEWORK_PATH": f"{R}/Frameworks:{P}/prefix/System/Library/PrivateFrameworks:{P}/prefix/System/Library/Frameworks",
    "DYLD_LIBRARY_PATH": f"{R}/lib:{P}/core:{P}/prefix/usr/lib:{P}/prefix/usr/lib/swift",
    "LANG": "en_US.UTF-8",
}
cap_env = {
    "PATH": "/usr/bin:/bin",
    "XDG_RUNTIME_DIR": "/private/var/run/gpu-desktop",
    "WAYLAND_DISPLAY": "wayland-0",
}
comp = subprocess.run(["pgrep", "-f", "/usr/bin/chonkstep-darwin-desktop"], capture_output=True, text=True)
print("COMPOSITOR", comp.stdout.strip().splitlines()[:1], flush=True)

shutil.copytree(P + "/Applications/Preview.app", R / "Applications/Preview.app", symlinks=True, dirs_exist_ok=True)
shutil.copy2(P + "/fixtures/reading.pdf", R / "fixtures/reading.pdf")
shutil.copy2("/tmp/siliconforest-notes.pdf", R / "fixtures/siliconforest-notes.pdf")
exe = R / "Applications/Preview.app/Contents/MacOS/Preview"
print("BYTES_BEFORE", sha(exe) == EXPECTED, sha(exe), flush=True)

def launch(pdf, tag, wait):
    err_path = R / "logs" / f"{tag}.err"
    err = open(err_path, "wb")
    proc = subprocess.Popen(
        [str(exe), str(pdf)],
        cwd=str(R / "home"),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=err,
        start_new_session=True,
    )
    time.sleep(wait)
    alive = proc.poll() is None
    print(f"{tag}_PID", proc.pid, "ALIVE", alive, "RC", proc.poll(), flush=True)
    shot = R / "logs" / f"{tag}.png"
    sc = subprocess.run(
        ["/usr/bin/chonkstep-darwin-desktop", "--screencapture", str(shot)],
        env=cap_env, capture_output=True, text=True, timeout=20,
    )
    print(f"{tag}_SHOT", sc.returncode, "bytes", shot.stat().st_size if shot.exists() else 0, flush=True)
    if sc.stderr.strip():
        print(f"{tag}_SHOT_ERR", sc.stderr.strip()[-400:], flush=True)
    if alive:
        os.kill(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            os.kill(proc.pid, signal.SIGKILL)
            proc.wait(timeout=3)
    err.close()
    tail = err_path.read_bytes()[-1500:]
    print(f"{tag}_ERR_TAIL_BEGIN", flush=True)
    sys.stdout.buffer.write(tail)
    sys.stdout.buffer.write(b"\n")
    print(f"{tag}_ERR_TAIL_END", flush=True)
    return alive

import sys
ok1 = launch(R / "fixtures/reading.pdf", "READING", 6)
time.sleep(1)
ok2 = launch(R / "fixtures/siliconforest-notes.pdf", "DEMO", 8)
print("BYTES_AFTER", sha(exe) == EXPECTED, flush=True)
print("READING_OK" if ok1 else "READING_DEAD", flush=True)
print("DEMO_OK" if ok2 else "DEMO_DEAD", flush=True)
'''


def main():
    if not PDF.is_file():
        raise SystemExit(f"missing {PDF}")
    blob = rsh.build_tar()
    print(f"TAR_BYTES {len(blob)}", flush=True)
    with LOCK.open("a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            subprocess.run(SSH + [f"{PY} -c " + shlex.quote(EXTRACT)], input=blob, check=True, timeout=180)
            subprocess.run(SCP + [str(PDF), "root@10.1.1.211:/tmp/siliconforest-notes.pdf"], check=True, timeout=60)
            r = subprocess.run(SSH + [f"{PY} -c " + shlex.quote(RUN)], capture_output=True, timeout=90)
            sys.stdout.buffer.write(r.stdout)
            if r.stderr:
                print("SSH_STDERR", r.stderr[-1500:].decode("utf-8", "replace"), flush=True)
            print("REMOTE_RC", r.returncode, flush=True)
            CAP.mkdir(parents=True, exist_ok=True)
            for remote, local in (
                (f"{REMOTE}/logs/READING.png", CAP / "preview-reading-pdf-fresh.png"),
                (f"{REMOTE}/logs/DEMO.png", CAP / "preview-siliconforest-notes.png"),
            ):
                got = subprocess.run(SCP + [f"root@10.1.1.211:{remote}", str(local)], capture_output=True, text=True, timeout=60)
                print("SCP", local.name, got.returncode, local.stat().st_size if local.exists() else 0, got.stderr.strip()[-200:], flush=True)
            subprocess.run(SSH + [f"rm -rf {REMOTE} /tmp/siliconforest-notes.pdf"], check=False, timeout=30)
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)


if __name__ == "__main__":
    main()
