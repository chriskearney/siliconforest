# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""DEMO's corner drag (1280x813 <-> 1520x948, 40 moves 50 ms apart), N times, recorded by the compositor, with the
layer's per-render trace (SF_CAOGL_TRACE=2) and CGL's (SF_CGL_TRACE=1): black-picture frames found in the recording
and set beside the renders of the same moment."""
import sys, time, re, json, subprocess
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
import numpy as np
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
env = [e for e in extra if re.match(r'^[A-Z_][A-Z0-9_]*=', e)]; args = [e for e in extra if e not in env]
with hold('VLC: %d corner drags of the playing window, recorded by the compositor, layer trace (%s)' % (ndrags, tag)):
    print(stop()); sh('rm -f ' + RC + ' ' + REC)
    print(launch(tag, 'SFVLC_HARDWARE=1', 'SFVLC_NOCATCH=1', 'SF_CGL_TRACE=1', 'SF_CAOGL_TRACE=2', *env, '--glconv=none', '--start-time=60', *args, *RCARGS, '/Users/sf/Movies/Big Buck Bunny (3 min).mp4')); time.sleep(7)
    ww = [x for x in wins() if x['app'] == 'org.videolan.vlc' and x['mapped'] and x['title'] not in ('', 'Fullscreen Controls')]
    if ww: clear_modifiers(ww[0]['id'])   # no modifier left held on the virtual seat
    for attempt in range(4):
        rect, corner = main()
        if abs(rect[2] - 1280) < 8 and abs(rect[3] - 813) < 8: break
        drag(corner, (corner[0] - (rect[2] - 1280), corner[1] - (rect[3] - 813)), 20, 16); time.sleep(2.5)
    rect, corner = main(); print('start', rect)
    secs = 4 + ndrags * 3.2
    t_rec = float(sh("/opt/homebrew/bin/python3 -c 'import time; print(time.time())'; cd /; XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 nohup /usr/bin/chonkstep-darwin-desktop --screencapture -V %d -F %s > /private/var/db/sfvlc/logs/%s.rec.txt 2>&1 &" % (secs, REC, tag)).stdout.split()[0])
    time.sleep(2)
    for i in range(ndrags):
        rect, corner = main()
        d = (240, 135) if i % 2 == 0 else (-240, -135)
        drag(corner, (corner[0] + d[0], corner[1] + d[1]), 40, 50); time.sleep(0.8)
    time.sleep(max(0, secs - 2 - ndrags * 3.0 + 3))
    for _ in range(60):
        if 'chonkstep-darwin-desktop --screencapture' not in sh('ps ax -o command').stdout: break
        time.sleep(1)
    print(sh('tail -2 /private/var/db/sfvlc/logs/%s.rec.txt; ls -la %s' % (tag, REC)).stdout)
    print(stop())
local = str(REPO / 'runs/vlc') + '/%s.mov' % tag
subprocess.run(SSH + ['cat ' + REC], stdout=open(local, 'wb'))
log = subprocess.run(SSH + ['cat %s/logs/%s.log' % (PREFIX, tag)], capture_output=True).stdout.decode(errors='replace')
open(str(REPO / 'runs/vlc') + '/%s.log' % tag, 'w').write(log)
x, y, w, h = rect
def grab(crop, w, h):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-nostdin', '-i', local, '-vf', 'fps=60,crop=%s' % crop + (',scale=%d:%d' % (w, h) if w else ''), '-f', 'rawvideo', '-pix_fmt', 'gray', '-'], capture_output=True).stdout
    return np.frombuffer(raw, np.uint8)
pic = grab('800:500:%d:%d' % (x + 200, y + 140), 200, 125).reshape(-1, 125 * 200)
strip = grab('200:16:%d:%d' % (x + 300, y + 2), 0, 0).reshape(-1, 16 * 200).mean(axis=1)
row = grab('2560:1:0:%d' % (y + 10), 0, 0).reshape(-1, 2560)
fr = pic
width = [int(np.nonzero(r > 200)[0].max()) - x + 1 if (r > 200).any() else 0 for r in row]
black = [i for i in range(len(fr)) if pic[i].max() < 24 and strip[i] > 120]
runs = []
for i in black:
    if runs and i == runs[-1][1] + 1: runs[-1][1] = i
    else: runs.append([i, i])
print('recorded frames', len(fr), 'without the menu strip', sum(1 for s in strip if s < 120), 'black picture with the strip', len(black), 'episodes', len(runs))
renders = []
for l in log.splitlines():
    m = re.match(r'SFCAOGL (\d+\.\d+) (\S+) \S+ (\d+)x(\d+)(.*)', l)
    if m: renders.append((float(m[1]) - t_rec, m[2], int(m[3]), int(m[4]), m[5].strip()))
dark = [r for r in renders if 'luma=' in r[4] and re.search(r'luma=(-?\d+)', r[4]) and 0 <= int(re.search(r"luma=(-?\d+)", r[4])[1]) < 24]
print('renders traced', len(renders), 'renders read back dark (luma < 24)', len(dark), 'no-current', sum(1 for r in renders if 'no-current' in r[4]), 'kept (the drawing left the context)', sum(1 for r in renders if ' left' in r[4]))
for a, b in runs:
    t0, t1 = a / 60, (b + 1) / 60
    print('EPISODE frames %d-%d (%.2f-%.2f s of the recording), window %s px wide' % (a, b, t0, t1, sorted(set(width[a:b + 1]))))
    for r in renders:
        if t0 - 0.35 <= r[0] <= t1 + 0.2: print('   %.3f %s %dx%d %s' % r)
json.dump(dict(tag=tag, t_rec=t_rec, frames=len(fr), black=black, episodes=runs, width=width, renders=renders), open(str(REPO / 'runs/vlc') + '/%s-trace.json' % tag, 'w'))
