# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Corner drags of the playing window recorded by the compositor itself; each recorded frame checked for VLC's menu
strip and control bar (the full-window picture fault)."""
import sys, time, re, json, subprocess
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
import numpy as np
from PIL import Image
tag = sys.argv[1]; ndrags = int(sys.argv[2]); extra = sys.argv[3:]
def main():
    for l in lst().splitlines():
        if 'org.videolan.vlc' in l and 'mapped=true' in l and 'Fullscreen Controls' not in l and 'title=""' not in l:
            m = re.search(r'resize_se=Some\(\((\d+), (\d+)\)\)', l)
            c = re.search(r'content=Rect \{ pos: Point \{ x: (-?\d+), y: (-?\d+) \}, size: Size \{ w: (\d+), h: (\d+) \}', l)
            return [int(v) for v in c.groups()], (int(m[1]), int(m[2]))
def drag(a, b, steps, gap):
    lines = [at(*a), 'wait 60', 'buttons 1', 'wait 80']
    for i in range(1, steps + 1):
        lines += [at(a[0] + (b[0] - a[0]) * i // steps, a[1] + (b[1] - a[1]) * i // steps), 'wait %d' % gap]
    lines += ['wait 80', 'buttons 0', 'wait 60']
    return inj('\n'.join(lines), timeout=60)
REC = '/private/var/db/sfvlc/logs/%s.mov' % tag
with hold('VLC: %d corner drags of the playing window, recorded by the compositor (%s)' % (ndrags, tag)):
    print(stop()); sh('rm -f ' + RC + ' ' + REC)
    print(launch(tag, 'SFVLC_HARDWARE=1', 'SFVLC_NOCATCH=1', *extra, '--glconv=none', *RCARGS, '/Users/sf/Movies/Big Buck Bunny (3 min).mp4')); time.sleep(7)
    ww = [x for x in wins() if x['app'] == 'org.videolan.vlc' and x['mapped'] and x['title'] not in ('', 'Fullscreen Controls')]
    if ww: clear_modifiers(ww[0]['id'])   # no modifier left held on the virtual seat
    for attempt in range(4):
        rect, corner = main()
        if abs(rect[2] - 1280) < 8 and abs(rect[3] - 813) < 8: break
        drag(corner, (corner[0] - (rect[2] - 1280), corner[1] - (rect[3] - 813)), 20, 16); time.sleep(2.5)
    rect, corner = main(); print('start', rect)
    secs = 4 + ndrags * 3.2
    sh('cd /; XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 nohup /usr/bin/chonkstep-darwin-desktop --screencapture -V %d -F %s > /private/var/db/sfvlc/logs/%s.rec.txt 2>&1 &' % (secs, REC, tag))
    time.sleep(2)
    for i in range(ndrags):
        rect, corner = main()
        d = (240, 135) if i % 2 == 0 else (-240, -135)
        drag(corner, (corner[0] + d[0], corner[1] + d[1]), 40, 50); time.sleep(0.8)
    time.sleep(secs - 2 - ndrags * 3.0 + 3)
    for _ in range(60):
        if 'chonkstep-darwin-desktop --screencapture' not in sh('ps ax -o command').stdout: break
        time.sleep(1)
    print(sh('cat /private/var/db/sfvlc/logs/%s.rec.txt | tail -2; ls -la %s' % (tag, REC)).stdout)
    print(stop())
local = str(REPO / 'runs/vlc') + '/' + '%s.mov' % tag
subprocess.run(SSH + ['cat ' + REC], stdout=open(local, 'wb'))
x, y, w, h = rect
W, H = 2560, 1600
raw = subprocess.run(['ffmpeg', '-v', 'error', '-nostdin', '-i', local, '-vf', 'crop=200:%d:%d:%d' % (H - y, x + 10, y), '-f', 'rawvideo', '-pix_fmt', 'gray', '-'], capture_output=True).stdout
fh = H - y
frames = np.frombuffer(raw, np.uint8).reshape(-1, fh, 200).astype(float)
strip = frames[:, 2:18, :].mean(axis=(1, 2))           # the menu strip just below the title bar
bad = [i for i, s in enumerate(strip) if s < 120]
print('recorded frames', len(frames), 'frames without the menu strip', len(bad), 'first', bad[:20])
json.dump(dict(tag=tag, frames=len(frames), missing_menu=bad, strip=[round(float(s), 1) for s in strip]), open(str(REPO / 'runs/vlc') + '/' + '%s-rec.json' % tag, 'w'))
