#!/usr/bin/env python3
"""Render dense PDF test documents in unmodified Apple Preview.app on M1.

Single-SSH-session design (avoids M1 SSH rate limiting): streams the overlay
tarball + PDFs over stdin, runs unmodified Preview.app under gui.lock, verifies
the Preview binary SHA-256 before and after, captures full-window PNGs, and
retrieves them cleanly.
"""
import argparse
import base64
import fcntl
import io
import json
import shlex
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path("/home/chrisk/src/darwin-lab")
sys.path.insert(0, str(ROOT / "runs/preview/retained"))
import run_swiftui_hello_full as rsh  # noqa: E402

LOCK = ROOT / "runs/m1-coord/gui.lock"
REMOTE = "/private/var/db/sfpreview-dense.t3"
P = "/private/var/db/sfpreview-app/p44-diagnostic-01"
PY = "/opt/homebrew/bin/python3"
SSH = [
    "ssh", "-i", "/home/chrisk/.ssh/id_rsa", "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "GlobalKnownHostsFile=/dev/null", "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "root@10.1.1.211",
]

REMOTE_SCRIPT = r'''
import base64, hashlib, json, os, pathlib, shutil, signal, subprocess, sys, tarfile, time

R = pathlib.Path(sys.argv[1])
JOBS = json.loads(sys.argv[2])
P = "/private/var/db/sfpreview-app/p44-diagnostic-01"
EXPECTED = "b0403a45bc454625aaa7a035f4ede247ef2c2bdd23b294e3dfa319800df1ebcd"

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

if R.exists():
    shutil.rmtree(R)
R.mkdir(parents=True)

t = tarfile.open(fileobj=sys.stdin.buffer, mode="r|")
for m in t:
    p = R / m.name
    p.parent.mkdir(parents=True, exist_ok=True)
    if m.issym():
        if p.is_symlink() or p.exists():
            p.unlink()
        p.symlink_to(m.linkname)
    elif m.isfile():
        p.write_bytes(t.extractfile(m).read())
        p.chmod(m.mode & 0o777)

(R / "home").mkdir(exist_ok=True)
(R / "tmp").mkdir(exist_ok=True)
(R / "logs").mkdir(exist_ok=True)

shutil.copytree(P + "/Applications/Preview.app", R / "Applications/Preview.app", symlinks=True, dirs_exist_ok=True)
exe = R / "Applications/Preview.app/Contents/MacOS/Preview"
sha_before = sha(exe)
print(f"BYTES_BEFORE {sha_before == EXPECTED} {sha_before}", flush=True)

comp = subprocess.run(["pgrep", "-f", "/usr/bin/chonkstep-darwin-desktop"], capture_output=True, text=True)
print("COMPOSITOR", comp.stdout.strip().splitlines()[:1], flush=True)

base_env = {
    "PATH": "/usr/bin:/bin",
    "HOME": str(R / "home"),
    "CFFIXED_USER_HOME": str(R / "home"),
    "TMPDIR": str(R / "tmp") + "/",
    "USER": "root",
    "LOGNAME": "root",
    "XDG_RUNTIME_DIR": "/private/var/run/gpu-desktop",
    "WAYLAND_DISPLAY": "wayland-0",
    "SF_METAL_ENABLE_REAL_DEVICE": "0",
    "SF_LOG_EXC": "1",
    "DYLD_FRAMEWORK_PATH": f"{R}/Frameworks:{P}/prefix/System/Library/PrivateFrameworks:{P}/prefix/System/Library/Frameworks",
    "DYLD_LIBRARY_PATH": f"{R}/lib:{P}/core:{P}/prefix/usr/lib:{P}/prefix/usr/lib/swift",
    "LANG": "en_US.UTF-8",
}
cap_env = {
    "PATH": "/usr/bin:/bin",
    "XDG_RUNTIME_DIR": "/private/var/run/gpu-desktop",
    "WAYLAND_DISPLAY": "wayland-0",
}

for idx, job in enumerate(JOBS):
    tag = job["tag"]
    pdf_path = R / "fixtures" / job["pdf_name"]
    wait = float(job.get("wait", 7.0))
    page = job.get("page")
    fit = job.get("fit")
    env = dict(base_env)
    if page is not None:
        env["SF_PREVIEW_START_PAGE"] = str(page)
    if fit:
        env["SF_PREVIEW_FIT_PAGE"] = "1"
    err_path = R / "logs" / f"{tag}.err"
    err_f = open(err_path, "wb")
    proc = subprocess.Popen(
        [str(exe), str(pdf_path)],
        cwd=str(R / "home"),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=err_f,
        start_new_session=True,
    )
    time.sleep(wait)
    alive = proc.poll() is None
    rc = proc.poll()
    shot = R / "logs" / f"{tag}.png"
    sc = subprocess.run(
        ["/usr/bin/chonkstep-darwin-desktop", "--screencapture", str(shot)],
        env=cap_env, capture_output=True, text=True, timeout=20,
    )
    if alive:
        os.kill(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=4)
        except subprocess.TimeoutExpired:
            os.kill(proc.pid, signal.SIGKILL)
            proc.wait(timeout=3)
    err_f.close()
    err_bytes = err_path.read_bytes()
    err_lines = [ln for ln in err_bytes.decode("utf-8", "replace").splitlines()
                 if any(k in ln for k in ("ERROR", "O2", "PD-", "Exception", "SIG", "Invalid", "SF_", "crash", "fatal", "assert"))]
    print(f"JOB {tag} PID={proc.pid} ALIVE={alive} RC={rc} SHOT_RC={sc.returncode} SHOT_BYTES={shot.stat().st_size if shot.exists() else 0}", flush=True)
    if err_lines:
        print(f"JOB_DIAG {tag}: " + " | ".join(err_lines[:12]), flush=True)
    if not alive:
        tail = "\n".join(err_bytes.decode("utf-8", "replace").splitlines()[-25:])
        print(f"JOB_CRASH_TAIL {tag}:\n{tail}", flush=True)
    if shot.exists():
        b64 = base64.b64encode(shot.read_bytes()).decode("ascii")
        print(f"PNG_BEGIN {tag}", flush=True)
        print(b64, flush=True)
        print(f"PNG_END {tag}", flush=True)
    time.sleep(0.8)

sha_after = sha(exe)
print(f"BYTES_AFTER {sha_after == EXPECTED} {sha_after}", flush=True)
shutil.rmtree(R, ignore_errors=True)
print("CLEANUP_DONE", flush=True)
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--job", action="append", required=True,
                    help="tag:pdf_path:out_png[:wait[:page]]")
    args = ap.parse_args()

    jobs = []
    out_map = {}
    pdfs = {}
    for spec in args.job:
        parts = spec.split(":")
        tag, pdf_s, out_s = parts[0], parts[1], parts[2]
        wait = float(parts[3]) if len(parts) > 3 and parts[3] else 7.0
        page = int(parts[4]) if len(parts) > 4 and parts[4] else None
        fit = bool(int(parts[5])) if len(parts) > 5 and parts[5] else False
        pdf_p = Path(pdf_s)
        if not pdf_p.is_file():
            raise SystemExit(f"Missing PDF: {pdf_p}")
        pdfs[pdf_p.name] = pdf_p
        jobs.append({"tag": tag, "pdf_name": pdf_p.name, "wait": wait, "page": page, "fit": fit})
        out_map[tag] = Path(out_s)

    base_tar = rsh.build_tar()
    buf = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(base_tar), mode="r:") as src_tf, \
         tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as dst_tf:
        for m in src_tf.getmembers():
            if m.isfile():
                dst_tf.addfile(m, src_tf.extractfile(m))
            else:
                dst_tf.addfile(m)
        for name, pdf_p in pdfs.items():
            data = pdf_p.read_bytes()
            ti = tarfile.TarInfo(f"fixtures/{name}")
            ti.size = len(data)
            ti.mode = 0o644
            ti.mtime = 0
            dst_tf.addfile(ti, io.BytesIO(data))

    payload = buf.getvalue()
    print(f"Streaming {len(payload)} bytes ({len(jobs)} jobs) in single SSH session...", flush=True)

    cmd = f"{PY} -c {shlex.quote(REMOTE_SCRIPT)} {shlex.quote(REMOTE)} {shlex.quote(json.dumps(jobs))}"
    with LOCK.open("a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            res = subprocess.run(SSH + [cmd], input=payload, capture_output=True, timeout=300)
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)

    if res.stderr:
        sys.stderr.write(res.stderr.decode("utf-8", "replace")[-2000:])
    cur_tag = None
    b64_chunks = []
    for line in res.stdout.decode("utf-8", "replace").splitlines():
        if line.startswith("PNG_BEGIN "):
            cur_tag = line.split(" ", 1)[1].strip()
            b64_chunks = []
        elif line.startswith("PNG_END "):
            tag = line.split(" ", 1)[1].strip()
            if tag == cur_tag and tag in out_map:
                raw = base64.b64decode("".join(b64_chunks))
                out_map[tag].parent.mkdir(parents=True, exist_ok=True)
                out_map[tag].write_bytes(raw)
                print(f"SAVED {out_map[tag]} ({len(raw)} bytes)", flush=True)
            cur_tag = None
            b64_chunks = []
        elif cur_tag is not None:
            b64_chunks.append(line.strip())
        else:
            print(line, flush=True)
    if res.returncode != 0:
        raise SystemExit(res.returncode)


if __name__ == "__main__":
    main()
