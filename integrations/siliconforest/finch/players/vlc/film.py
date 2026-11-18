# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The film's sequence, end to end, with a capture after each step (synthetic input on the virtual seat)."""
import sys, time
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
from ui import keys
T = sys.argv[1] if len(sys.argv) > 1 else 'film'
def shot(n):
    cap('%s-%s' % (T, n)); small('%s-%s' % (T, n), width=1000)
def vlcwins():
    return [(w['id'], w['title'][:30], w['x'], w['y'], w['w'], w['h']) for w in wins() if w['app'] == 'org.videolan.vlc' and w['mapped']]
with hold('VLC film rehearsal %s: start from the desktop, File > Open File, play, pause, resume, seek, fullscreen, back, quit' % T):
    print(stop())
    sh('XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 /usr/bin/chonkstep-darwin-desktop --desktop-request application org.videolan.vlc')
    time.sleep(8); shot('1-started'); print('started', vlcwins())
    m = win('VLC media player')
    cl(m, 99, 16); time.sleep(1.2); shot('2-filemenu')
    cl(m, 141, 56); time.sleep(2)
    p = win('Open File'); cl(p, 75, 151, True); time.sleep(1.5); shot('3-panel')
    cl(p, 185, FILES['film'], True); time.sleep(5); shot('4-playing'); print('playing', vlcwins())
    inj(click(87, 1567)); time.sleep(1.5); shot('5-paused')
    inj(click(87, 1567)); time.sleep(2); shot('6-resumed')
    inj(click(1408, 1567)); time.sleep(2); shot('7-seeked')
    inj(click(2409, 1569)); time.sleep(3); shot('8-fullscreen'); print('fullscreen', vlcwins())
    fs = [w for w in wins() if w['app'] == 'org.videolan.vlc' and w['mapped'] and w['title'] == '']
    if fs:
        inj('target %d\n' % fs[0]['id'] + keys('key:esc')); time.sleep(2.5)
    shot('9-windowed'); print('windowed', vlcwins())
    m = [w for w in wins() if w['app'] == 'org.videolan.vlc' and w['mapped'] and w['title'] != 'Fullscreen Controls'][0]
    inj('target %d\n' % m['id'] + keys('chord:cmd+q')); time.sleep(4)
    shot('10-quit'); print('after quit: processes', mine().strip() or 'none', 'windows', vlcwins())
