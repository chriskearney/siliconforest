#!/usr/bin/env python3
"""Capture the full-desktop SiliconForest Preview.app showcase screenshot.

Opens siliconforest-dense.pdf (Page 2), fig-cadence.png, and fig-calibration.jpg
simultaneously in unmodified Apple Preview.app on M1, arranges all three windows
neatly alongside the left launcher (showing the Preview icon) and right widgets
with zero overlap and zero clipping, captures full-resolution 2560x1600 PNG + JPG.
"""
import base64
import fcntl
import io
import shlex
import subprocess
import sys
import tarfile
from pathlib import Path
from PIL import Image

ROOT = Path("/home/chrisk/src/darwin-lab")
sys.path.insert(0, str(ROOT / "runs/preview/retained"))
import run_swiftui_hello_full as rsh  # noqa: E402

LOCK = ROOT / "runs/m1-coord/gui.lock"
REMOTE = "/private/var/db/sfpreview-showcase.t3"
DEMO = ROOT / "runs/preview/retained/demo-pdf"
OUT_PNG = ROOT / "runs/preview/retained/captures/preview-showcase.png"
OUT_JPG = ROOT / "runs/preview/retained/captures/preview-showcase.jpg"
PY = "/opt/homebrew/bin/python3"
SSH = [
    "ssh", "-i", "/home/chrisk/.ssh/id_rsa", "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "GlobalKnownHostsFile=/dev/null", "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "root@10.1.1.211",
]

REMOTE_SCRIPT = r'''
import base64, hashlib, os, pathlib, re, shutil, signal, subprocess, sys, tarfile, time

R = pathlib.Path(sys.argv[1])
P = "/private/var/db/sfpreview-app/p44-diagnostic-01"
Q = "/private/var/db/sfqtp/load-20261118T091237Z"
INJ = pathlib.Path("/private/var/run/gpu-desktop/inject")
EXPECTED = "b0403a45bc454625aaa7a035f4ede247ef2c2bdd23b294e3dfa319800df1ebcd"

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def req(lines, timeout="12"):
    x = subprocess.run(
        ["/opt/homebrew/bin/python3", Q + "/qtp_m1.py", "req", timeout],
        input=lines.strip() + "\n",
        env={"PATH": "/usr/bin:/bin", "QTP_BUNDLE": Q},
        capture_output=True, text=True, timeout=float(timeout) + 5,
    )
    return x.returncode, x.stdout

def list_windows(tag):
    rc, out = req(f"list {tag}")
    p = INJ / f"{tag}.txt"
    txt = ""
    if p.exists():
        txt = p.read_text(errors="replace")
        p.unlink()
    return txt

def parse_windows(txt):
    # Example format: window <id> ... rect/pos/size ...
    wins = []
    for line in txt.splitlines():
        if line.startswith("window "):
            wins.append(line)
    return wins

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

for sub in ("home_pdf", "home_png", "home_jpg", "tmp", "logs"):
    (R / sub).mkdir(exist_ok=True)

shutil.copytree(P + "/Applications/Preview.app", R / "Applications/Preview.app", symlinks=True, dirs_exist_ok=True)
exe = R / "Applications/Preview.app/Contents/MacOS/Preview"
sha_before = sha(exe)
print(f"BYTES_BEFORE {sha_before == EXPECTED} {sha_before}", flush=True)

base_env = {
    "PATH": "/usr/bin:/bin",
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

def drag_titlebar(x0, y0, x1, y1):
    # Convert screen pixels (2560x1600) to 0..32767 absolute inject coords
    def to_abs(x, y):
        ax = max(0, min(32767, int(round(x * 32767.0 / 2560.0))))
        ay = max(0, min(32767, int(round(y * 32767.0 / 1600.0))))
        return ax, ay
    ax0, ay0 = to_abs(x0, y0)
    ax1, ay1 = to_abs(x1, y1)
    lines = [f"abs {ax0} {ay0}", "wait 80", "buttons 1", "wait 120"]
    steps = 8
    for s in range(1, steps + 1):
        ix = ax0 + (ax1 - ax0) * s // steps
        iy = ay0 + (ay1 - ay0) * s // steps
        lines.append(f"abs {ix} {iy}")
        lines.append("wait 35")
    lines.extend(["wait 80", "buttons 0", "wait 250"])
    rc, out = req("\n".join(lines), timeout="12")
    return rc

def parse_win_geom(txt):
    # Parse lines from Chonkstep list output
    out = {}
    for ln in txt.splitlines():
        m = re.match(r"^window\s+(\d+)\s+(.*)$", ln)
        if not m:
            continue
        wid = m.group(1)
        rest = m.group(2)
        # Look for x= y= w= h= or (x,y wxh) or at x,y size w,h
        g = {"raw": ln}
        m_xywh = re.search(r"x=(-?\d+)\s+y=(-?\d+)\s+w=(\d+)\s+h=(\d+)", rest)
        if not m_xywh:
            m_xywh = re.search(r"(\d+),(\d+)\s+(\d+)x(\d+)", rest)
        if not m_xywh:
            m_xywh = re.search(r"(-?\d+),(-?\d+)\s+(\d+)x(\d+)", rest)
        if m_xywh:
            g["x"] = int(m_xywh.group(1))
            g["y"] = int(m_xywh.group(2))
            g["w"] = int(m_xywh.group(3))
            g["h"] = int(m_xywh.group(4))
        out[wid] = g
    return out

procs = []
try:
    base_txt = list_windows("sc_base")
    base_ids = set(parse_win_geom(base_txt).keys())
    print("BASE_LIST:", repr(base_txt.strip()[:400]), flush=True)

    # Launch 1: PDF (left window, 860x880 logical -> ~1290x1320 px on 1.5x or ~860x880 on 1x)
    # Earlier 1080x860 occupied 1620x1310 px on 2560x1600 -> exact scale is 1.5x (or logical 1706x1066)!
    # Let's check exact pixel bounds from list_windows!
    specs = [
        ("pdf", "siliconforest-dense.pdf", "home_pdf", {"SF_PREVIEW_START_PAGE": "2", "SF_PREVIEW_FIT_PAGE": "1", "SF_WINDOW_SIZE": "880,860"}, (140, 60)),
        ("png", "fig-cadence.png", "home_png", {"SF_WINDOW_SIZE": "620,420"}, (1460, 60)),
        ("jpg", "fig-calibration.jpg", "home_jpg", {"SF_WINDOW_SIZE": "620,420"}, (1460, 770)),
    ]
    seen_ids = set(base_ids)
    win_by_tag = {}
    for tag, fname, hdir, extra, target_xy in specs:
        env = dict(base_env)
        env["HOME"] = str(R / hdir)
        env["CFFIXED_USER_HOME"] = str(R / hdir)
        env.update(extra)
        err_f = open(R / "logs" / f"{tag}.err", "wb")
        proc = subprocess.Popen(
            [str(exe), str(R / "fixtures" / fname)],
            cwd=str(R / hdir), env=env,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=err_f,
            start_new_session=True,
        )
        procs.append((tag, proc, err_f))
        time.sleep(5.5)
        alive = proc.poll() is None
        print(f"LAUNCH {tag} PID={proc.pid} ALIVE={alive} RC={proc.poll()}", flush=True)
        txt = list_windows(f"sc_{tag}")
        geom = parse_win_geom(txt)
        new_ids = sorted(set(geom.keys()) - seen_ids)
        print(f"LIST_AFTER_{tag} new={new_ids}:", flush=True)
        for wid in new_ids:
            print("  ", geom[wid]["raw"], flush=True)
        if new_ids:
            wid = new_ids[-1]
            win_by_tag[tag] = (wid, geom[wid], target_xy)
            seen_ids.update(new_ids)

    # Arrange all 3 windows using their actual reported coordinates from Chonkstep list!
    # Check if Chonkstep list coordinates are logical or physical by inspecting the first window width.
    for tag in ("pdf", "png", "jpg"):
        if tag not in win_by_tag:
            continue
        wid, g, (tx, ty) = win_by_tag[tag]
        if "x" not in g:
            print(f"NO_GEOM for {tag}: {g['raw']}", flush=True)
            continue
        # Detect coordinate units: if PDF width ~ 860, Chonkstep reports logical coords on 1706x1066 (scale=1.5)
        # Wait: let's check both physical & logical cleanly by inspecting g['w'] vs requested w!
        req_w = 860 if tag == "pdf" else 640
        scale = 2560.0 / 1706.6667 if g["w"] < req_w * 1.25 else 1.0
        # Grab center of titlebar (18 px below top edge in physical px)
        cur_x_px = g["x"] * scale
        cur_y_px = g["y"] * scale
        cur_w_px = g["w"] * scale
        grab_x = cur_x_px + cur_w_px * 0.5
        grab_y = cur_y_px + 18.0
        dst_x = tx + cur_w_px * 0.5
        dst_y = ty + 18.0
        print(f"DRAG {tag} scale={scale:.3f} cur=({cur_x_px:.0f},{cur_y_px:.0f} {cur_w_px:.0f}w) grab=({grab_x:.0f},{grab_y:.0f}) -> dst=({dst_x:.0f},{dst_y:.0f})", flush=True)
        drag_titlebar(grab_x, grab_y, dst_x, dst_y)
        time.sleep(0.5)

    # Park cursor cleanly in lower-right wallpaper area (away from windows/launcher)
    req("abs 32000 31500\nwait 150", timeout="6")
    time.sleep(0.6)

    final_txt = list_windows("sc_final")
    print("FINAL_LIST:\n" + final_txt.strip(), flush=True)

    for tag, proc, _ in procs:
        print(f"FINAL_ALIVE {tag} PID={proc.pid} ALIVE={proc.poll() is None}", flush=True)

    shot = R / "logs/showcase.png"
    sc = subprocess.run(
        ["/usr/bin/chonkstep-darwin-desktop", "--screencapture", str(shot)],
        env=cap_env, capture_output=True, text=True, timeout=20,
    )
    print(f"SHOT_RC={sc.returncode} SHOT_BYTES={shot.stat().st_size if shot.exists() else 0}", flush=True)
    if shot.exists():
        print("PNG_BEGIN", flush=True)
        print(base64.b64encode(shot.read_bytes()).decode("ascii"), flush=True)
        print("PNG_END", flush=True)
finally:
    for tag, proc, err_f in procs:
        if proc.poll() is None:
            try:
                os.kill(proc.pid, signal.SIGTERM)
                proc.wait(timeout=3)
            except Exception:
                try:
                    os.kill(proc.pid, signal.SIGKILL)
                    proc.wait(timeout=2)
                except Exception:
                    pass
        err_f.close()
    sha_after = sha(exe)
    print(f"BYTES_AFTER {sha_after == EXPECTED} {sha_after}", flush=True)
    shutil.rmtree(R, ignore_errors=True)
    print("CLEANUP_DONE", flush=True)
'''


def main():
    base_tar = rsh.build_tar()
    buf = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(base_tar), mode="r:") as src_tf, \
         tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as dst_tf:
        for m in src_tf.getmembers():
            if m.isfile():
                dst_tf.addfile(m, src_tf.extractfile(m))
            else:
                dst_tf.addfile(m)
        for fname in ("siliconforest-dense.pdf", "fig-cadence.png", "fig-calibration.jpg"):
            data = (DEMO / fname).read_bytes()
            ti = tarfile.TarInfo(f"fixtures/{fname}")
            ti.size = len(data)
            ti.mode = 0o644
            ti.mtime = 0
            dst_tf.addfile(ti, io.BytesIO(data))

    payload = buf.getvalue()
    print(f"Streaming {len(payload)} bytes for 3-window showcase capture...", flush=True)
    cmd = f"{PY} -c {shlex.quote(REMOTE_SCRIPT)} {shlex.quote(REMOTE)}"
    with LOCK.open("a") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            res = subprocess.run(SSH + [cmd], input=payload, capture_output=True, timeout=240)
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)

    if res.stderr:
        sys.stderr.write(res.stderr.decode("utf-8", "replace")[-2000:])

    in_png = False
    chunks = []
    for line in res.stdout.decode("utf-8", "replace").splitlines():
        if line == "PNG_BEGIN":
            in_png = True
            chunks = []
        elif line == "PNG_END":
            in_png = False
            raw = base64.b64decode("".join(chunks))
            OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
            OUT_PNG.write_bytes(raw)
            im = Image.open(OUT_PNG).convert("RGB")
            im.save(OUT_JPG, "JPEG", quality=92, optimize=True)
            print(f"SAVED {OUT_PNG} ({len(raw)} B, {im.size[0]}x{im.size[1]})", flush=True)
            print(f"SAVED {OUT_JPG} ({OUT_JPG.stat().st_size} B)", flush=True)
        elif in_png:
            chunks.append(line.strip())
        else:
            print(line, flush=True)
    if res.returncode != 0:
        raise SystemExit(res.returncode)


if __name__ == "__main__":
    main()
