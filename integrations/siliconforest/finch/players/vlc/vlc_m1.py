#!/opt/homebrew/bin/python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Test helper on the machine: owner guard, virtual-seat requests, own VLC processes only.

vlc_m1.py guard [idle_s]             exit 0 when the owner has been idle that long (default 20), else 3
vlc_m1.py req [timeout_s] < lines    one request to the compositor's test instrument on its virtual seat
vlc_m1.py launch <tag> [args]        start VLC through the launcher; log in logs/<tag>.log
vlc_m1.py mine                       this helper's VLC processes
vlc_m1.py stop                       SIGTERM, then SIGKILL after 5 s, to this helper's VLC processes only
"""
import os, re, signal, subprocess, sys, time
from pathlib import Path

INJ = Path('/private/var/run/gpu-desktop/inject')
OWNER = Path('/private/var/run/gpu-desktop/owner-input')
BASE = Path(os.environ.get('SFVLC_PREFIX', '/private/var/db/sfvlc'))
LAUNCHER = os.environ.get('SFVLC_LAUNCHER', str(BASE / 'bin/vlc-sf'))


def owner_state():
    f = {k: int(v) for k, v in re.findall(r'^([a-z_]+)=(\d+)$', OWNER.read_text(), re.M)}
    return f.get('active', 1), (time.time() * 1000 - f.get('last_real_input_unix_ms', 0)) / 1000, f


def guard(need=20.0):
    active, idle, f = owner_state()
    ok = active == 0 and idle >= need
    print('owner active=%d idle=%.0fs real_pointer=%s real_key=%s %s' % (active, idle, f.get('real_pointer_records'), f.get('real_key_records'), 'OK' if ok else 'HANDS-OFF'))
    return ok


def req(lines, timeout=30.0):
    if not guard(20):
        return 3
    for p in ('request', 'request.part'):
        if (INJ / p).exists():
            print('another request pending'); return 4
    (INJ / 'done').unlink(missing_ok=True)
    with (INJ / 'request.part').open('x') as s:
        s.write('seat virtual\n' + lines.strip() + '\n')
    os.replace(INJ / 'request.part', INJ / 'request')
    end = time.monotonic() + timeout
    while not (INJ / 'done').exists() and time.monotonic() < end:
        time.sleep(0.05)
    if not (INJ / 'done').exists():
        print('timeout'); return 4
    time.sleep(0.05)
    d = (INJ / 'done').read_text().strip()
    print(d)
    if re.search(r'owner_seen_active=1\b', d):
        return 3
    return 0 if re.search(r'errors=0\b', d) else 4


def mine():
    out = subprocess.run(['ps', '-axo', 'pid=,user=,rss=,pcpu=,etime=,command='], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        p = line.split(None, 5)
        if len(p) == 6 and (str(BASE) + '/' in p[5] or '/Applications/VLC.app/' in p[5]) and '/MacOS/VLC' in p[5]:
            rows.append((int(p[0]), p[1], int(p[2]), p[3], p[4], p[5]))
    return rows


def launch(tag, args):
    if not guard(20):
        return 3
    env = os.environ.copy()
    env['XDG_RUNTIME_DIR'] = '/private/var/run/gpu-desktop'
    env['WAYLAND_DISPLAY'] = 'wayland-0'
    while args and re.match(r'^[A-Z_][A-Z0-9_]*=', args[0]):
        k, v = args.pop(0).split('=', 1); env[k] = v
    if (BASE / 'tools/sf-catch').exists() and not env.get('SFVLC_NOCATCH'):
        env['SFVLC_WRAP'] = str(BASE / 'tools/sf-catch')
    log = open(BASE / 'logs' / (tag + '.log'), 'wb')
    p = subprocess.Popen([LAUNCHER] + args, env=env, cwd='/', stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    print('pid', p.pid, int(time.time() * 1000))
    return 0


def stop():
    m = mine()
    for r in m:
        try: os.kill(r[0], signal.SIGTERM)
        except ProcessLookupError: pass
    # 15 s before KILL: VLC with its NSOpenGLView output takes 5-6 s to act on TERM, and a KILL during that
    # teardown left a process stuck in exit once (SF-AH item 25)
    end = time.time() + 15
    while time.time() < end and mine():
        time.sleep(0.2)
    left = mine()
    for r in left:
        try: os.kill(r[0], signal.SIGKILL)
        except ProcessLookupError: pass
    print('TERM', [r[0] for r in m], 'KILL', [r[0] for r in left])


def main():
    a = sys.argv[1:]
    if a[0] == 'guard':
        sys.exit(0 if guard(float(a[1]) if len(a) > 1 else 20) else 3)
    if a[0] == 'req':
        sys.exit(req(sys.stdin.read(), float(a[1]) if len(a) > 1 else 30))
    if a[0] == 'launch':
        sys.exit(launch(a[1], a[2:]))
    if a[0] == 'shot':
        # the compositor's own screen capture (same user only); no input involved
        if not guard(float(a[2]) if len(a) > 2 else 20):
            sys.exit(3)
        out = BASE / 'caps' / (a[1] + '.png'); out.parent.mkdir(exist_ok=True)
        env = dict(os.environ, XDG_RUNTIME_DIR='/private/var/run/gpu-desktop', WAYLAND_DISPLAY='wayland-0')
        r = subprocess.run(['/usr/bin/chonkstep-darwin-desktop', '--screencapture', str(out)], env=env, capture_output=True, text=True, timeout=30)
        print(r.returncode, r.stdout.strip(), r.stderr.strip()[-300:], int(time.time() * 1000))
        sys.exit(0 if r.returncode == 0 and out.exists() else 4)
    if a[0] == 'mine':
        for r in mine():
            print(*r)
        return
    if a[0] == 'stop':
        stop(); return
    raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
