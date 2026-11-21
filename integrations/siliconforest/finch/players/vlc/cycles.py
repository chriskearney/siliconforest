# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""12 launch-play-quit cycles: /Applications/VLC.app with a file (open -a), play, quit by TERM (15 s before KILL)."""
import sys, time, re, json
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
from ui import keys
import numpy as np
from PIL import Image
CLIP = '/Users/sf/Movies/bbb-1080p-h264-aac-30s.mp4'
def avd():
    return int(re.search(r'jobs (\d+)', sh('sysctl -n kern.sf_avd.stats').stdout)[1])
def ca_lines():
    return int(sh('wc -l < /var/log/coreaudiod.log').stdout.strip())
res = []
for n in range(int(sys.argv[1]) if len(sys.argv) > 1 else 12):
    with hold('VLC cycle %d: open -a /Applications/VLC.app with a clip, play 8 s, Command-Q' % (n + 1)):
        assert not mine().strip(), 'a VLC is already running'
        j0, c0, t0 = avd(), ca_lines(), time.time()
        r = sh('XDG_RUNTIME_DIR=/private/var/run/gpu-desktop WAYLAND_DISPLAY=wayland-0 /usr/bin/open -a /Applications/VLC.app --args %s; echo rc=$?' % CLIP)
        time.sleep(8)
        procs = mine().strip()
        w = [x for x in wins() if x['app'] == 'org.videolan.vlc' and x['mapped'] and x['title'] not in ('', 'Fullscreen Controls')]
        name = 'cyc-%02d' % (n + 1); cap(name)
        A = np.asarray(Image.open(str(CAPS / (name + '.png'))).convert('RGB')).astype(float)
        pic = A[200:1400, 300:2100]
        j1 = avd()
        quit_ok = False
        if w:
            clear_modifiers(w[0]['id'])
        # quit by process, not by a synthetic Command-Q (which can leave Command held on the virtual seat): TERM, and
        # KILL only after 15 s; clean when VLC ended on TERM
        out = stop()
        quit_ok = bool(re.search(r'KILL \[\]', out or '')) and not mine().strip()
        left = mine().strip()
        audio = sh('tail -n +%d /var/log/coreaudiod.log | grep -o "it wrote [0-9]* frames" | sort -t" " -k3 -n | tail -1' % (c0 + 1)).stdout.strip()
        # recorded, not pass/fail: the underruns coreaudiod counted in the sessions of this cycle
        sessions = sh('tail -n +%d /var/log/coreaudiod.log | grep "Speakers: closed"' % (c0 + 1)).stdout.strip().splitlines()
        underruns = [int(m) for l in sessions for m in re.findall(r'(\d+) underruns', l)]
        fails = sh("grep -c -e 'Failure' -e 'SFCATCH' -e 'Assertion' -e 'exception' /var/root/Library/Logs/vlc-sf.log").stdout.strip()
        row = dict(cycle=n + 1, open=r.stdout.strip(), started=bool(procs), window=bool(w), picture_mean=round(float(pic.mean()), 1),
                   picture_std=round(float(pic.std()), 1), decoder_jobs=j1 - j0, audio=audio, quit_clean=quit_ok, left=left,
                   log_failures=fails, audio_sessions=len(sessions), underruns=underruns, seconds=round(time.time() - t0, 1))
        print(json.dumps(row), flush=True); res.append(row)
        if left:
            print(stop())
    time.sleep(2)
ok = [r for r in res if r['started'] and r['window'] and r['picture_std'] > 15 and r['decoder_jobs'] > 100 and r['quit_clean'] and r['log_failures'] in ('0', '')]
print('cycles passed: %d of %d' % (len(ok), len(res)))
print('coreaudiod underruns per cycle (recorded, not pass/fail):', [r['underruns'] for r in res])
json.dump(res, open(str(REPO / 'runs/vlc') + '/' + 'cycles-%s.json' % time.strftime('%H%M'), 'w'), indent=1)
