# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
import sys, time
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from vlcw import *
from ui import keys
def win(title, tries=20):
    for _ in range(tries):
        for w in wins():
            if w['app'] == 'org.videolan.vlc' and w['title'] == title and w['mapped']:
                return w
        time.sleep(0.5)
    raise RuntimeError('no window ' + title)
def cl(w, dx, dy, double=False):
    c = click(w['x'] + dx, w['y'] + dy)
    return inj(c + ('\n' + c if double else ''))
FILES = {'mkv': 121, 'mp4': 151, 'webm': 181, 'film': 211}
def open_rest(kind):
    o = win('Open Source'); cl(o, 777, 111); time.sleep(1.5)
    p = win('Open File'); cl(p, 75, 151, True); time.sleep(1.5)
    cl(p, 185, FILES[kind], True); time.sleep(1.5)
    o = win('Open Source'); cl(o, 807, 592); time.sleep(1)
def open_from_dialog(kind):
    """VLC's own Open dialog: Open media... -> Browse... -> Movies -> the file -> Open"""
    m = win('VLC media player')
    for attempt in range(3):                             # "Open media..." in the empty playlist
        cl(m, 1628, 904); time.sleep(1.5)
        try:
            o = win('Open Source', 4); break
        except RuntimeError:
            print('Open media: no dialog after click', attempt + 1)
    else:
        raise RuntimeError('Open media did not open the dialog')
    cl(o, 777, 111); time.sleep(1.5)                     # Browse...
    p = win('Open File'); cl(p, 75, 151, True); time.sleep(1.5)  # Movies
    cl(p, 185, FILES[kind], True); time.sleep(1.5)       # the file
    o = win('Open Source'); cl(o, 807, 592); time.sleep(1)     # Open

RC = PREFIX + '/logs/rc.sock'
RCARGS = ['--extraintf=oldrc', '--rc-unix=' + RC, '--rc-fake-tty']
def rc(*commands, wait=0.6):
    """VLC's own remote-control interface (a diagnostic, not user input): send commands, return the text"""
    code = "import socket,sys,time;s=socket.socket(socket.AF_UNIX);s.connect(%r);s.settimeout(%r);out=b''\nfor c in %r:\n s.sendall((c+'\\n').encode());time.sleep(%r)\n try:\n  while True:\n   d=s.recv(65536)\n   if not d:break\n   out+=d\n except Exception:pass\nsys.stdout.write(out.decode(errors='replace'))" % (RC, wait, list(commands), wait)
    return sh("/opt/homebrew/bin/python3 -c %s" % __import__('shlex').quote(code)).stdout
