# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""Hardware decoding: the launcher's interim permission step, VLC's VideoToolbox decoder, the decoder's job counters."""
import sys, time, re
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from flow import *
tag = sys.argv[1]
def jobs():
    s = sh('sysctl -n kern.sf_avd.stats').stdout
    return int(re.search(r'jobs (\d+)', s)[1]), int(re.search(r'errors (\d+)', s)[1])
with hold('VLC: hardware decoding check %s' % tag):
    print(stop()); sh('rm -f ' + RC)
    print('before', jobs(), sh('ls -la /dev/sfavd').stdout.strip())
    print(launch(tag, 'SFVLC_HARDWARE=1', '-v', *sys.argv[2:], *RCARGS, '/Users/sf/Movies/Big Buck Bunny (3 min).mp4')); time.sleep(6)
    j1 = jobs(); time.sleep(3); j2 = jobs(); print('playing: jobs', j1, '->', j2, 'over 3 s')
    rc('pause'); time.sleep(1); p1 = jobs(); time.sleep(3); p2 = jobs(); print('paused: jobs', p1, '->', p2, 'over 3 s')
    rc('pause'); time.sleep(3); r = jobs(); print('resumed: jobs', p2, '->', r)
    cap(tag + '-a'); small(tag + '-a', width=1000)
    print(sh("grep -e 'using video decoder' -e 'videotoolbox' -e 'sfavd' -e 'AVD' %s/logs/%s.log | head -12" % (PREFIX, tag)).stdout)
    print(sh('ls -la /dev/sfavd; sysctl kern.sf_avd.state').stdout)
    print(stop())
