# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Workstation side of the VLC tests: lock holds, virtual-seat input, captures of the compositor's picture.

SF_HOST names the machine; SF_KNOWN its known-hosts file. Everything sent is synthetic input into this
test's own VLC window; a pass is refused while the owner is at the machine.
"""
import fcntl, gzip, io, os, re, subprocess, sys, time
from contextlib import contextmanager
from pathlib import Path

REPO = Path(os.environ.get('SF_LAB') or Path.cwd())
LOG = REPO / 'runs/m1-coord/log.txt'
LOCK = REPO / 'runs/m1-coord/gui.lock'
CAPS = REPO / 'runs/vlc/caps'
HOST = os.environ['SF_HOST']    # the machine under test
SSH = ['ssh', '-o', 'UserKnownHostsFile=' + os.environ.get('SF_KNOWN', os.path.expanduser('~/.ssh/known_hosts_m1_siliconforest')),
       '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlias=m1-siliconforest',
       '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', 'root@' + HOST]
PREFIX = os.environ.get('SFVLC_PREFIX', '/private/var/db/sfvlc')
M1 = '/opt/homebrew/bin/python3 %s/tools/vlc_m1.py' % PREFIX
INJ = '/private/var/run/gpu-desktop/inject'
PANEL = (2560, 1600)


class OwnerActive(Exception):
    pass


def now():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def log(text):
    with LOG.open('a') as s:
        s.write('%s VLC %s\n' % (now(), text))


def sh(cmd, inp=None, timeout=120, check=False):
    r = subprocess.run(SSH + [cmd], input=inp, capture_output=True, text=inp is None or isinstance(inp, str), timeout=timeout)
    if check and r.returncode:
        raise RuntimeError('%s -> %d %s' % (cmd, r.returncode, r.stderr))
    return r


@contextmanager
def hold(what, wait=3600, idle=90, owner_wait=1500):
    f = LOCK.open('a')
    import signal as _s
    def _alarm(*a): raise TimeoutError('gui.lock busy')
    old = _s.signal(_s.SIGALRM, _alarm); _s.alarm(wait)
    try:
        fcntl.flock(f, fcntl.LOCK_EX)
    finally:
        _s.alarm(0); _s.signal(_s.SIGALRM, old)
    try:
        end = time.time() + owner_wait
        while True:
            r = sh(M1 + ' guard %d' % idle)
            print(r.stdout.strip(), flush=True)
            if not r.returncode:
                break
            if time.time() > end:
                raise OwnerActive(r.stdout)
            time.sleep(20)
        log('gui.lock: %s (own VLC as account sf, virtual seat, own window only)' % what)
        yield
    finally:
        log('gui.lock released')
        fcntl.flock(f, fcntl.LOCK_UN)
        f.close()


def inj(lines, timeout=30):
    r = sh(M1 + ' req %d' % timeout, inp=lines, timeout=timeout + 20)
    out = r.stdout.strip()
    if r.returncode == 3:
        raise OwnerActive(out)
    if r.returncode:
        raise RuntimeError('inject failed: ' + out + r.stderr)
    return out


def lst(name='vlc-l'):
    inj('list ' + name)
    return sh('cat %s/%s.txt; rm -f %s/%s.txt' % (INJ, name, INJ, name)).stdout


WIN_RE = re.compile(r'^window (\d+) app_id="([^"]*)" title="([^"]*)" mapped=(\w+) .*?focused=(\w+) content=Rect \{ pos: Point \{ x: (-?\d+), y: (-?\d+) \}, size: Size \{ w: (\d+), h: (\d+) \} \}')


def clear_modifiers(window_id):
    """Key-down and key-up of every modifier, to one of our own windows: a synthetic Command-Q that closed its target
    window left Command held on the virtual seat (the key-ups found no target), and the next key became a chord."""
    lines = ['target %d' % window_id]
    for code in ('e0', 'e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7'):
        lines += ['key %s down' % code, 'key %s up' % code]
    return inj('\n'.join(lines))


def wins(text=None):
    text = lst() if text is None else text
    out = []
    for line in text.splitlines():
        m = WIN_RE.match(line)
        if m:
            out.append(dict(id=int(m[1]), app=m[2], title=m[3], mapped=m[4] == 'true', focused=m[5] == 'true',
                            x=int(m[6]), y=int(m[7]), w=int(m[8]), h=int(m[9]), line=line))
    return out


def cap(name, wait_ms=0):
    # the display may be asleep: try, and on a timeout wake it with the virtual pointer's motion, then try again
    try:
        inj(('wait %d\n' % wait_ms if wait_ms else '') + 'capture ' + name)
    except RuntimeError as e:
        if 'no frame completed' not in str(e):
            raise
        inj(at(1300, 820) + '\nwait 30\n' + at(1302, 822) + '\nwait 600\ncapture ' + name)
    return fetch(name)


def fetch(name):
    from PIL import Image
    r = subprocess.run(SSH + ['gzip -1 -c %s/%s.ppm && rm -f %s/%s.ppm' % (INJ, name, INJ, name)], capture_output=True, timeout=120)
    if r.returncode:
        raise RuntimeError(r.stderr)
    im = Image.open(io.BytesIO(gzip.decompress(r.stdout)))
    CAPS.mkdir(parents=True, exist_ok=True)
    p = CAPS / (name + '.png')
    im.save(p)
    return p


def small(name, box=None, width=1280):
    from PIL import Image
    im = Image.open(CAPS / (name + '.png'))
    if box:
        im = im.crop(box)
    if im.width > width:
        im = im.resize((width, im.height * width // im.width), Image.LANCZOS)
    p = CAPS / (name + '-s.png'); im.save(p); return p


def at(x, y):
    return 'abs %d %d' % (round(x * 65535 / (PANEL[0] - 1)), round(y * 65535 / (PANEL[1] - 1)))


def click(x, y, button=1):
    return '\n'.join([at(x, y), 'wait 60', 'buttons %d' % button, 'wait 60', 'buttons 0', 'wait 60'])


def launch(tag, *args):
    import shlex
    r = sh(M1 + ' launch %s %s' % (tag, ' '.join(shlex.quote(a) for a in args)))
    print(r.stderr.strip()[-300:])
    if r.returncode == 3:
        raise OwnerActive(r.stdout)
    return r.stdout.strip()


def mine():
    return sh(M1 + ' mine').stdout


def stop():
    return sh(M1 + ' stop').stdout


def vlclog(tag, tail=40):
    return sh('tail -%d %s/logs/%s.log' % (tail, PREFIX, tag)).stdout


def shot(name):
    """The screen as the compositor shows it, through its own capture command (works without the test instrument)."""
    r = sh(M1 + ' shot ' + name)
    if r.returncode == 3:
        raise OwnerActive(r.stdout)
    if r.returncode:
        raise RuntimeError('capture failed: ' + r.stdout + r.stderr)
    d = subprocess.run(SSH + ['cat %s/caps/%s.png && rm -f %s/caps/%s.png' % (PREFIX, name, PREFIX, name)], capture_output=True, timeout=120)
    CAPS.mkdir(parents=True, exist_ok=True)
    p = CAPS / (name + '.png'); p.write_bytes(d.stdout)
    return p
