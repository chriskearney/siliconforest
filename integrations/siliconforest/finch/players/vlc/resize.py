# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Windowed playback through resizes by the window's corner (the compositor's frame), captures after each."""
import sys, time, re
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
import numpy as np
from PIL import Image
tag = sys.argv[1]; extra = sys.argv[2:]
def main_win():
    for l in lst().splitlines():
        if 'org.videolan.vlc' in l and 'mapped=true' in l and 'Fullscreen Controls' not in l and 'title=""' not in l:
            m = re.search(r'resize_se=Some\(\((\d+), (\d+)\)\)', l)
            c = re.search(r'content=Rect \{ pos: Point \{ x: (-?\d+), y: (-?\d+) \}, size: Size \{ w: (\d+), h: (\d+) \}', l)
            return [int(v) for v in c.groups()], (int(m[1]), int(m[2])) if m else None
def drag(a, b, steps=12):
    lines = [at(*a), 'wait 60', 'buttons 1', 'wait 80']
    for i in range(1, steps + 1):
        lines += [at(a[0] + (b[0] - a[0]) * i // steps, a[1] + (b[1] - a[1]) * i // steps), 'wait 40']
    lines += ['wait 80', 'buttons 0', 'wait 60']
    return inj('\n'.join(lines), timeout=40)
def blank(name, rect):
    A = np.asarray(Image.open(str(CAPS / (name + '.png'))).convert('RGB')).astype(float)
    x, y, w, h = rect
    area = A[y + 120:y + h - 80, x + 20:x + w - 20]
    return round(float(area.mean()), 1), round(float(area.std()), 1)
with hold('VLC: windowed playback through resizes %s' % tag):
    print(stop()); sh('rm -f ' + RC)
    print(launch(tag, *extra, *RCARGS, '/Users/sf/Movies/Big Buck Bunny (3 min).mp4')); time.sleep(7)
    rect, corner = main_win(); print('start', rect, corner); cap(tag + '-0'); print('picture mean/std', blank(tag + '-0', rect))
    for i, (dx, dy) in enumerate([(-900, -500), (500, 300), (-300, -400), (600, 500)]):
        rect, corner = main_win()
        drag(corner, (corner[0] + dx, corner[1] + dy)); time.sleep(1.5)
        rect, corner = main_win(); n = '%s-%d' % (tag, i + 1); cap(n)
        print('resize', i + 1, (dx, dy), 'window', rect, 'picture mean/std', blank(n, rect))
        time.sleep(0.5); cap(n + 'b'); print('   +0.5 s picture mean/std', blank(n + 'b', rect))
    print(rc('get_time'))
    print(stop())
