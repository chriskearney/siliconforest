#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""SYSINSTALL: the compositor's recording of a VLC resize pass (m1/vlc.sh), after the VLC agent's dragtrace.py: every
recorded frame tested for VLC's menu strip and for a black picture area (window rect from the pass's RECT line).
   vlcrec.py <tag>     (work/out-<tag>.txt, M1 file /private/var/db/sfsysinst/<tag>.mov)"""
import os, re, subprocess, sys
import numpy as np
tag = sys.argv[1]
H = os.path.join(os.environ.get('SF_LAB') or subprocess.run(['git', '-C', os.path.dirname(os.path.abspath(__file__)), 'rev-parse', '--path-format=absolute', '--git-common-dir'], capture_output=True, text=True).stdout.strip() + '/..', 'runs/sysinstall')
SSH = ['ssh', '-o', 'UserKnownHostsFile=' + os.path.expanduser('~/.ssh/known_hosts_m1_siliconforest'), '-o', 'GlobalKnownHostsFile=/dev/null',
       '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlias=m1-siliconforest', '-o', 'BatchMode=yes', 'root@10.1.1.211']
out = open('%s/work/out-%s.txt' % (H, tag), errors='replace').read()
m = re.search(r'RECT (-?\d+) (-?\d+) (\d+) (\d+)', out)
if not m: sys.exit('no RECT line in the pass output')
x, y, w, h = map(int, m.groups())
local = '%s/work/%s.mov' % (H, tag)
import os
if subprocess.run(SSH + ['test -s /private/var/db/sfsysinst/%s.mov' % tag]).returncode == 0:
    with open(local + '.part', 'wb') as f:
        subprocess.run(SSH + ['cat /private/var/db/sfsysinst/%s.mov' % tag], stdout=f, check=True)
    os.replace(local + '.part', local)
dur = subprocess.run(['ffprobe', '-v', 'error', '-count_packets', '-select_streams', 'v:0', '-show_entries', 'stream=nb_read_packets:format=duration',
                      '-of', 'default=nw=1', local], capture_output=True, text=True).stdout.split()
def grab(crop, sw, sh):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-nostdin', '-i', local, '-fps_mode', 'passthrough', '-vf', 'crop=%s' % crop + (',scale=%d:%d' % (sw, sh) if sw else ''),
                          '-f', 'rawvideo', '-pix_fmt', 'gray', '-'], capture_output=True).stdout
    return np.frombuffer(raw, np.uint8)
# the picture's middle (60 % of the smallest window of the pass, its RECT) and a piece of the menu strip
pw, ph, sw = w * 3 // 5 // 2 * 2, h * 3 // 5 // 2 * 2, min(200, w * 2 // 5)
pic = grab('%d:%d:%d:%d' % (pw, ph, x + w // 5, y + h // 5), 200, 125).reshape(-1, 125 * 200)
strip = grab('%d:16:%d:%d' % (sw, x + w // 4, y + 2), 0, 0).reshape(-1, 16 * sw).mean(axis=1)
black = [i for i in range(len(pic)) if pic[i].max() < 24 and strip[i] > 120]
nostrip = [i for i in range(len(strip)) if strip[i] < 120]
runs = []
for i in black:
    if runs and i == runs[-1][1] + 1: runs[-1][1] = i
    else: runs.append([i, i])
moving = sum(1 for i in range(1, len(pic)) if np.abs(pic[i].astype(int) - pic[i - 1].astype(int)).mean() > 0.5)
print('VLCREC %s: %s; frames %d, picture changed in %d, without the menu strip %d, black picture with the strip %d (episodes %d) %s' % (
    tag, ' '.join(dur), len(pic), moving, len(nostrip), len(black), len(runs), runs[:8]))
subprocess.run(SSH + ['rm -f /private/var/db/sfsysinst/%s.mov' % tag])
