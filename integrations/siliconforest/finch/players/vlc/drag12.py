# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""DEMO's drag, repeated: VLC playing with hardware decoding; its window's corner dragged 1280x813 <-> 1520x948
(40 moves 50 ms apart), 12 drags; a capture in the middle of each drag; failures counted from the logs."""
import sys, time, re
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
import numpy as np
from PIL import Image
tag = sys.argv[1] if len(sys.argv) > 1 else 'x'; extra = sys.argv[2:]
def main():
    for l in lst().splitlines():
        if 'org.videolan.vlc' in l and 'mapped=true' in l and 'Fullscreen Controls' not in l and 'title=""' not in l:
            m = re.search(r'resize_se=Some\(\((\d+), (\d+)\)\)', l)
            c = re.search(r'content=Rect \{ pos: Point \{ x: (-?\d+), y: (-?\d+) \}, size: Size \{ w: (\d+), h: (\d+) \}', l)
            return [int(v) for v in c.groups()], (int(m[1]), int(m[2]))
def drag(a, b, steps, gap, capname=None):
    lines = [at(*a), 'wait 60', 'buttons 1', 'wait 80']
    for i in range(1, steps + 1):
        lines += [at(a[0] + (b[0] - a[0]) * i // steps, a[1] + (b[1] - a[1]) * i // steps), 'wait %d' % gap]
        if capname and i == steps // 2:
            lines += ['capture ' + capname]
    lines += ['wait 80', 'buttons 0', 'wait 60']
    return inj('\n'.join(lines), timeout=60)
def logcount(pattern):
    return int(sh("grep -c -e '%s' %s/logs/%s.log" % (pattern, PREFIX, tag)).stdout.strip() or 0)
def run(tag, extra, ndrags=12):
    global TAG
if __name__ == '__main__':
    with hold('VLC: 12 drags of the playing window (%s)' % tag):
        print(stop()); sh('rm -f ' + RC)
        print(launch(tag, 'SFVLC_HARDWARE=1', 'SFVLC_NOCATCH=1', 'SF_CGL_TRACE=1', 'SF_CAOGL_TRACE=1', *extra, '--glconv=none', *RCARGS, '/Users/sf/Movies/Big Buck Bunny (3 min).mp4')); time.sleep(7)
        ww = [x for x in wins() if x['app'] == 'org.videolan.vlc' and x['mapped'] and x['title'] not in ('', 'Fullscreen Controls')]
        if ww: clear_modifiers(ww[0]['id'])   # no modifier left held on the virtual seat
        for attempt in range(4):
            rect, corner = main()
            if abs(rect[2] - 1280) < 8 and abs(rect[3] - 813) < 8:
                break
            drag(corner, (corner[0] - (rect[2] - 1280), corner[1] - (rect[3] - 813)), 20, 16); time.sleep(2.5)
        rect, corner = main(); print('start', rect)
        if abs(rect[2] - 1280) > 8: raise SystemExit('could not size the window to 1280x813')
        base = logcount('Failure setting current CGLContext')
        res = []
        for i in range(12):
            rect, corner = main()
            d = (240, 135) if i % 2 == 0 else (-240, -135)
            f0 = logcount('Failure setting current CGLContext')
            name = '%s-d%02d' % (tag, i)
            drag(corner, (corner[0] + d[0], corner[1] + d[1]), 40, 50, name); fetch(name)
            time.sleep(1.0)
            f1 = logcount('Failure setting current CGLContext')
            A = np.asarray(Image.open(str(CAPS / (name + '.png'))).convert('RGB')).astype(float)
            x, y, w, h = rect
            area = A[y + 140:y + h - 120, x + 40:x + min(w, 1200) - 40]
            res.append((i, d, f1 - f0, round(float(area.mean()), 1), round(float(area.std()), 1)))
            print('drag', i, d, 'VLC context failures', f1 - f0, 'mid-drag picture mean/std', res[-1][3], res[-1][4], flush=True)
        print('total VLC context failures in the 12 drags:', sum(r[2] for r in res), '(at start-up:', base, ')')
        print('mid-drag captures with a black picture (mean < 8):', sum(1 for r in res if r[3] < 8))
        print(sh("grep -c 'current on another thread 1' %s/logs/%s.log; grep -c 'waited' %s/logs/%s.log; grep -c 'could not be made current' %s/logs/%s.log; grep 'CGL: make current' %s/logs/%s.log | head -5" % ((PREFIX, tag) * 4)).stdout)
        print(rc('get_time'))
        print(stop())
