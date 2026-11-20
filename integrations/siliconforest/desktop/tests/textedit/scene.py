#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Open unmodified TextEdit and Terminal, then capture the desk.

Does not modify Apple bundles. Holds the workstation gui.lock. Turns
window_position on for the launch and back off before returning. Leaves
the built-in theme sf-wafer in place. Hides the menu strip of the
Terminal process only. Terminal is the system binary plus the tab
insert. It does not get the TextEdit overlay: that library path aborts
dyld inside Terminal.
"""
import base64
import fcntl
import hashlib
import io
import os
import tarfile
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path("/home/chrisk/.t3/worktrees/darwin-lab/textedit-91e34f57c2e18057")
SRC = Path("/home/chrisk/src/darwin-lab/private/mac-apps/m5-26.5.2/TextEdit.app")
EXE = SRC / "Contents/MacOS/TextEdit"
EXPECTED = "98db1c6a0170fd624cee7b1f06a5f396f24e56bcd00831cf8e7cb17de6f0a13f"
MANIFEST = "71348ff33b71b71191619662832d0126ac6c759a701b2a48b9b05f0324ef579c"
FRONT = Path("/tmp/sf-te-appkit/front")
RECAP = Path("/tmp/sf-te-appkit/recap")
TERM_DYLIB = Path("/tmp/sf-te-term/libSFTermPlace.dylib")
LOCK = Path("/home/chrisk/src/darwin-lab/runs/m1-coord/gui.lock")
OUT = ROOT / "runs/textedit"
PY = "/opt/homebrew/bin/python3"
SSH = [
    "ssh", "-i", "/home/chrisk/.ssh/id_rsa", "-o", "IdentitiesOnly=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "UserKnownHostsFile=/home/chrisk/.ssh/known_hosts_m1_siliconforest",
    "-o", "GlobalKnownHostsFile=/dev/null", "-o", "HostKeyAlias=m1-siliconforest",
    "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "root@10.1.1.211",
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def bundle_manifest(root):
    files = []
    nbytes = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        filenames.sort()
        for fn in filenames:
            path = Path(dirpath) / fn
            rel = path.relative_to(root).as_posix()
            if path.is_symlink():
                target = os.readlink(path)
                digest = hashlib.sha256(b"symlink:" + target.encode()).hexdigest()
                size = len(target.encode())
                kind = "symlink"
            else:
                data = path.read_bytes()
                digest = hashlib.sha256(data).hexdigest()
                size = len(data)
                kind = "file"
                nbytes += size
            files.append(f"{digest}  {size}  {kind}  {rel}")
    manifest = hashlib.sha256("\n".join(files).encode()).hexdigest()
    return manifest, len(files), nbytes


def add_bytes(tar, name, data, mode=0o755):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = mode
    info.mtime = int(time.time())
    tar.addfile(info, io.BytesIO(data))


def add_link(tar, name, target):
    info = tarfile.TarInfo(name)
    info.type = tarfile.SYMTYPE
    info.linkname = target
    info.mtime = int(time.time())
    tar.addfile(info)


def build_tar():
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        appkit = "Frameworks/AppKit.framework/Versions/A"
        for part in ("AppKit", "AppKit.sf-base", "AppKit.sf-p44", "AppKit.sf-missing", "AppKit.sf-under"):
            add_bytes(tar, f"{appkit}/{part}", (FRONT / part).read_bytes())
        current = "Frameworks/AppKit.framework/Versions/C"
        for part in ("AppKit", "AppKit.sf-base", "AppKit.sf-p44", "AppKit.sf-missing", "AppKit.sf-under"):
            add_link(tar, f"{current}/{part}", f"../A/{part}")
        add_link(tar, "Frameworks/AppKit.framework/Versions/Current", "C")
        add_link(tar, "Frameworks/AppKit.framework/AppKit", "Versions/Current/AppKit")
        recap = "PrivateFrameworks/RecapPerformanceTesting.framework/Versions/A"
        for part in ("RecapPerformanceTesting", "RecapPerformanceTesting.sf-under"):
            add_bytes(tar, f"{recap}/{part}", (RECAP / part).read_bytes())
        add_link(tar, "PrivateFrameworks/RecapPerformanceTesting.framework/Versions/Current", "A")
        add_link(tar, "PrivateFrameworks/RecapPerformanceTesting.framework/RecapPerformanceTesting",
                 "Versions/Current/RecapPerformanceTesting")
        add_bytes(tar, "libSFTermPlace.dylib", TERM_DYLIB.read_bytes())
        docs = ROOT / "integrations/siliconforest/desktop/tests/textedit/docs"
        for doc in sorted(docs.glob("*.rtf")):
            add_bytes(tar, f"docs/{doc.name}", doc.read_bytes(), 0o644)
        for dirpath, dirnames, filenames in os.walk(SRC):
            dirnames.sort()
            filenames.sort()
            for fn in filenames:
                path = Path(dirpath) / fn
                rel = "TextEdit.app/" + path.relative_to(SRC).as_posix()
                if path.is_symlink():
                    add_link(tar, rel, os.readlink(path))
                else:
                    add_bytes(tar, rel, path.read_bytes(), path.stat().st_mode & 0o777)
    return buf.getvalue()


REMOTE_PY = r'''
import fcntl, hashlib, os, shutil, signal, socket, subprocess, sys, tarfile, time
from pathlib import Path

TE = Path("/private/var/db/sftextedit")
TERM = Path("/private/var/db/sfterminal")
P = "/private/var/db/sfpreview-app/p44-diagnostic-01"
DOCK = "/private/var/db/sfpreview-dock"
POLICY = Path("/private/var/db/desktop-state/chonkstep/policy")
PIDFILE = Path("/private/var/db/sftextedit-scene.pids")
EXPECTED = "98db1c6a0170fd624cee7b1f06a5f396f24e56bcd00831cf8e7cb17de6f0a13f"
TERM_APP = Path("/Applications/Utilities/Terminal.app")
TERM_EXE = TERM_APP / "Contents/MacOS/Terminal"
RUNTIME = "/private/var/run/gpu-desktop"

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def manifest(root):
    files = []
    nbytes = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        filenames.sort()
        for fn in filenames:
            path = Path(dirpath) / fn
            rel = path.relative_to(root).as_posix()
            if path.is_symlink():
                target = os.readlink(path)
                digest = hashlib.sha256(b"symlink:" + target.encode()).hexdigest()
                size = len(target.encode())
                kind = "symlink"
            else:
                data = path.read_bytes()
                digest = hashlib.sha256(data).hexdigest()
                size = len(data)
                kind = "file"
                nbytes += size
            files.append("%s  %d  %s  %s" % (digest, size, kind, rel))
    blob = hashlib.sha256(("\n".join(files)).encode()).hexdigest()
    return blob, len(files), nbytes

def policy_set(on):
    lines = []
    if POLICY.exists():
        lines = [ln for ln in POLICY.read_text().splitlines() if ln and not ln.startswith("window_position=")]
    if on:
        lines.append("window_position=on")
    else:
        lines.append("window_position=off")
    POLICY.write_text("\n".join(lines) + "\n")

def kill_previous():
    if not PIDFILE.exists():
        return
    for word in PIDFILE.read_text().split():
        try:
            os.kill(int(word), signal.SIGTERM)
        except OSError:
            pass
    time.sleep(0.4)

TIOCSTI = 0x80017472

def tab_command(title, lines):
    body = " ".join("echo '%s';" % line for line in lines)
    return (
        "precmd_functions=(); preexec_functions=(); "
        "precmd() { printf '\\033]0;%s\\007'; }; "
        "printf '\\033[H\\033[2J'; %s\n" % (title, body)
    )

TAB_TEXT = [
    tab_command("forest", [
        " SiliconForest",
        " Darwin arm64   T8103",
        " chonkstep-darwin-desktop",
    ]),
    tab_command("wafer", [
        " theme   sf-wafer",
        " revert  desk_m1.sh theme sf-canopy",
    ]),
    tab_command("menu", [
        " Terminal 2.15",
        " tabs    forest | wafer | menu",
        " strip   hidden on this process",
        " TextEdit keeps its menu",
    ]),
]

def descendant_ttys(pid):
    text = subprocess.check_output(["ps", "-ax", "-o", "pid=,ppid=,tty="], text=True)
    children = {}
    tty_of = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            p = int(parts[0])
            pp = int(parts[1])
        except ValueError:
            continue
        children.setdefault(pp, []).append(p)
        if parts[2].startswith("ttys"):
            tty_of[p] = parts[2]
    seen = set()
    stack = [pid]
    found = []
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        if cur != pid and cur in tty_of:
            found.append(tty_of[cur])
        stack.extend(children.get(cur, []))
    return sorted(set(found))[:3]

def fill_tabs(pid):
    # The insert opens the tabs. It cannot see the pty fds, and zsh's
    # _title_precmd puts the user@host title back. Write the three panes
    # here, after the shells exist, and clear that hook.
    ttys = descendant_ttys(pid)
    print("TTYS", ttys, flush=True)
    for tty, command in zip(ttys, TAB_TEXT):
        try:
            fd = os.open("/dev/" + tty, os.O_RDWR | os.O_NOCTTY)
        except OSError as exc:
            print("TTY_OPEN", tty, exc, flush=True)
            continue
        try:
            for ch in command:
                fcntl.ioctl(fd, TIOCSTI, bytearray(ch.encode()))
            print("TTY_FILL", tty, len(command), flush=True)
        except OSError as exc:
            print("TTY_STI", tty, exc, flush=True)
        finally:
            os.close(fd)

def menu(pid, command):
    sock_path = "%s/app-menu/%s" % (RUNTIME, pid)
    for _ in range(30):
        if os.path.exists(sock_path):
            break
        time.sleep(0.2)
    else:
        print("MENU_MISSING", pid, flush=True)
        return
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(2)
    try:
        client.connect(sock_path)
        client.sendall((command + "\n").encode())
        data = client.recv(200)
        print("MENU", pid, command, data.decode("utf-8", "replace").strip(), flush=True)
    except OSError as exc:
        print("MENU_ERR", pid, exc, flush=True)
    finally:
        client.close()

def launch(argv, home, env_extra, err_name):
    home.mkdir(parents=True, exist_ok=True)
    (home.parent / "tmp").mkdir(parents=True, exist_ok=True)
    (home.parent / "logs").mkdir(parents=True, exist_ok=True)
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": str(home),
        "CFFIXED_USER_HOME": str(home),
        "TMPDIR": str(home.parent / "tmp") + "/",
        "USER": "root",
        "LOGNAME": "root",
        "XDG_RUNTIME_DIR": RUNTIME,
        "WAYLAND_DISPLAY": "wayland-0",
        "SF_METAL_ENABLE_REAL_DEVICE": "0",
        "SF_LOG_EXC": "1",
        "LANG": "en_US.UTF-8",
    }
    env.update(env_extra)
    err = open(home.parent / "logs" / err_name, "wb")
    proc = subprocess.Popen(argv, cwd=str(home), env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=err, start_new_session=True)
    return proc, err

kill_previous()
term_before = sha(TERM_EXE)
term_size = TERM_EXE.stat().st_size
term_manifest = manifest(TERM_APP)
print("TERM_BEFORE", term_before, term_size, "MANIFEST", term_manifest[0], term_manifest[1], term_manifest[2], flush=True)

if TE.exists():
    shutil.rmtree(TE)
if TERM.exists():
    shutil.rmtree(TERM)
TE.mkdir(parents=True)
tf = tarfile.open(fileobj=sys.stdin.buffer, mode="r|")
for member in tf:
    dest = TE / member.name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if member.issym():
        if dest.is_symlink() or dest.exists():
            dest.unlink()
        dest.symlink_to(member.linkname)
    elif member.isfile():
        dest.write_bytes(tf.extractfile(member).read())
        dest.chmod(member.mode & 0o777)
print("EXTRACT_OK", flush=True)
exe = TE / "TextEdit.app/Contents/MacOS/TextEdit"
print("BYTES_BEFORE", sha(exe) == EXPECTED, sha(exe), exe.stat().st_size, flush=True)
print("TEXT_MANIFEST_BEFORE", "%s %d %d" % manifest(TE / "TextEdit.app"), flush=True)

policy_set(True)
time.sleep(0.6)
try:
    docs = sorted(str(p) for p in (TE / "docs").glob("*.rtf"))
    print("DOCS", docs, flush=True)
    text_env = {
        "SF_TE_PLACE": "1",
        "DYLD_FRAMEWORK_PATH": "%s/Frameworks:%s/PrivateFrameworks:%s/Frameworks:%s/prefix/System/Library/PrivateFrameworks:%s/prefix/System/Library/Frameworks" % (TE, TE, DOCK, P, P),
        "DYLD_LIBRARY_PATH": "%s/lib:%s/core:%s/prefix/usr/lib:%s/prefix/usr/lib/swift" % (DOCK, P, P, P),
    }
    term_env = {
        "DYLD_INSERT_LIBRARIES": str(TE / "libSFTermPlace.dylib"),
    }
    text, text_err = launch([str(exe)] + docs, TE / "home", text_env, "textedit.err")
    term, term_err = launch([str(TERM_EXE)], TERM / "home", term_env, "terminal.err")
    print("PIDS", text.pid, term.pid, flush=True)
    theme_now = Path("/private/var/db/desktop-state/chonkstep/theme")
    if theme_now.read_text().strip() != "sf-wafer":
        theme = subprocess.run(
            ["/usr/bin/chonkstep-darwin-desktop", "--desktop-request", "theme", "sf-wafer"],
            env={"PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": RUNTIME, "WAYLAND_DISPLAY": "wayland-0"},
            capture_output=True, text=True, timeout=20)
        print("THEME", theme.returncode, (theme.stdout or "")[-200:], (theme.stderr or "")[-300:], flush=True)
        time.sleep(5.0)
    else:
        print("THEME already sf-wafer", flush=True)
    time.sleep(4.0)
    menu(term.pid, "menubar hide")
    fill_tabs(term.pid)
    time.sleep(1.5)
    shot = TE / "logs/scene.png"
    cap = subprocess.run(
        ["/usr/bin/chonkstep-darwin-desktop", "--screencapture", str(shot)],
        env={"PATH": "/usr/bin:/bin", "XDG_RUNTIME_DIR": RUNTIME, "WAYLAND_DISPLAY": "wayland-0"},
        capture_output=True, text=True, timeout=30)
    print("SHOT", cap.returncode, shot.stat().st_size if shot.exists() else 0, flush=True)
    text_err.close()
    term_err.close()
    print("TEXT_ALIVE", text.poll() is None, "RC", text.poll(), flush=True)
    print("TERM_ALIVE", term.poll() is None, "RC", term.poll(), flush=True)
    print("TEXT_ERR_BEGIN", flush=True)
    sys.stdout.buffer.write((TE / "logs/textedit.err").read_bytes()[-6000:])
    sys.stdout.buffer.write(b"\nTEXT_ERR_END\n")
    print("TERM_ERR_BEGIN", flush=True)
    sys.stdout.buffer.write((TERM / "logs/terminal.err").read_bytes()[-4000:])
    sys.stdout.buffer.write(b"\nTERM_ERR_END\n")
    print("BYTES_AFTER", sha(exe) == EXPECTED, sha(exe), exe.stat().st_size, flush=True)
    print("TEXT_MANIFEST_AFTER", "%s %d %d" % manifest(TE / "TextEdit.app"), flush=True)
    term_after = manifest(TERM_APP)
    print("TERM_AFTER", sha(TERM_EXE), TERM_EXE.stat().st_size, "MANIFEST", term_after[0], term_after[1], term_after[2], flush=True)
    same = (sha(TERM_EXE), TERM_EXE.stat().st_size, term_after) == (term_before, term_size, term_manifest)
    print("TERM_UNCHANGED", same, flush=True)
    PIDFILE.write_text("%s %s\n" % (text.pid, term.pid))
finally:
    policy_set(False)
    print("POLICY_OFF", flush=True)
print("DONE", flush=True)
'''


def main():
    got = sha(EXE)
    manifest, count, nbytes = bundle_manifest(SRC)
    print("SRC_BEFORE", got == EXPECTED, got, EXE.stat().st_size, flush=True)
    print("SRC_MANIFEST", manifest == MANIFEST, manifest, count, nbytes, flush=True)
    if got != EXPECTED or manifest != MANIFEST or count != 69 or nbytes != 1926987:
        raise SystemExit("source TextEdit bundle does not match the recorded checksum")
    for path in (FRONT / "AppKit", RECAP / "RecapPerformanceTesting", TERM_DYLIB):
        if not path.exists():
            raise SystemExit("missing build output %s" % path)
    blob = build_tar()
    print("TAR", len(blob), flush=True)
    OUT.mkdir(parents=True, exist_ok=True)
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    encoded = base64.b64encode(REMOTE_PY.encode()).decode()
    remote = "%s -c \"import base64; exec(base64.b64decode('%s'))\"" % (PY, encoded)
    with LOCK.open("a") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX)
        try:
            result = subprocess.run(SSH + [remote], input=blob, capture_output=True, timeout=180)
            sys.stdout.buffer.write(result.stdout)
            if result.stderr:
                print("SSH_ERR", result.stderr[-2000:].decode("utf-8", "replace"), flush=True)
            print("REMOTE_RC", result.returncode, flush=True)
            got_png = subprocess.run(SSH + ["cat /private/var/db/sftextedit/logs/scene.png"],
                                     capture_output=True, timeout=30)
            png = OUT / "scene.png"
            if got_png.returncode == 0 and got_png.stdout[:8] == b"\x89PNG\r\n\x1a\n":
                png.write_bytes(got_png.stdout)
                print("PNG", png, len(got_png.stdout), flush=True)
            else:
                print("PNG_FAIL", got_png.returncode, got_png.stderr[-200:], flush=True)
        finally:
            fcntl.flock(lockf, fcntl.LOCK_UN)
    got = sha(EXE)
    manifest, count, nbytes = bundle_manifest(SRC)
    print("SRC_AFTER", got == EXPECTED, got, EXE.stat().st_size, flush=True)
    print("SRC_MANIFEST_AFTER", manifest == MANIFEST, manifest, count, nbytes, flush=True)


if __name__ == "__main__":
    main()
