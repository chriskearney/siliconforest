# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""CPU and dropped frames for 1080p30 H.264 with hardware decoding, over one minute of playback."""
import sys, time, re, json
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
def cpu_seconds(pattern):
    out = sh("ps -axo time=,command= | grep -e '%s' | grep -v grep" % pattern).stdout.strip().splitlines()
    tot = 0.0
    for l in out:
        t = l.split()[0]
        parts = [float(x) for x in re.split('[:]', t)]
        s = 0.0
        for p in parts: s = s * 60 + p
        tot += s
    return tot
def stats():
    out = rc('stats', wait=1.0)
    d = {}
    for key in ('frames displayed', 'frames lost', 'video decoded', 'audio decoded', 'buffers played', 'buffers lost', 'late'):
        m = re.search(r'\|\s*%s\s*:\s*(\d+)' % key, out)
        if m: d[key] = int(m[1])
    return d, out
with hold('VLC: one minute of 1080p hardware-decoded playback, CPU and frame statistics'):
    print(stop()); sh('rm -f ' + RC)
    print(launch('perf', 'SFVLC_HARDWARE=1', '--glconv=none', *RCARGS, '/Users/sf/Movies/Big Buck Bunny (3 min).mp4')); time.sleep(10)
    s0, raw0 = stats(); v0 = cpu_seconds('vendor/VLC.app/Contents/MacOS/VLC'); c0 = cpu_seconds('chonkstep-darwin-desktop'); a0 = cpu_seconds('coreaudiod')
    j0 = int(re.search(r'jobs (\d+)', sh('sysctl -n kern.sf_avd.stats').stdout)[1]); t0 = time.time()
    time.sleep(60)
    s1, raw1 = stats(); v1 = cpu_seconds('vendor/VLC.app/Contents/MacOS/VLC'); c1 = cpu_seconds('chonkstep-darwin-desktop'); a1 = cpu_seconds('coreaudiod')
    j1 = int(re.search(r'jobs (\d+)', sh('sysctl -n kern.sf_avd.stats').stdout)[1]); dt = time.time() - t0
    load = sh('sysctl -n vm.loadavg; sysctl -n hw.ncpu').stdout.strip()
    r = dict(seconds=round(dt, 1), vlc_cpu_pct_of_one_core=round(100 * (v1 - v0) / dt, 1), compositor_cpu_pct=round(100 * (c1 - c0) / dt, 1),
             coreaudiod_cpu_pct=round(100 * (a1 - a0) / dt, 1), decoder_jobs=j1 - j0, decoder_jobs_per_s=round((j1 - j0) / dt, 2),
             stats_delta={k: s1.get(k, 0) - s0.get(k, 0) for k in s1}, stats_end=s1, load=load)
    print(json.dumps(r, indent=1)); print(raw1[-900:])
    json.dump(r, open(str(REPO / 'runs/vlc') + '/' + 'perf-%s.json' % time.strftime('%H%M'), 'w'), indent=1)
    print(stop())
