# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""ui.py <tag> <step> ...   one lock hold; steps:
 start[:args,comma-separated]  sleep:<s>  cap:<name>  list  click:<x>,<y>  dclick:<x>,<y>  keys:<sf_keys item>  target:<id>  mine  stop  log:<n>"""
import sys, time, subprocess
sys.path.insert(0, '' + __import__('os').path.dirname(__import__('os').path.abspath(__file__)) + '')
from vlcw import *
KEYS = '' + __import__('os').path.join(__import__('os').path.dirname(__import__('os').path.abspath(__file__)), '../../../terminal-app/tools/sf_keys.py') + ''
def keys(*items):
    return subprocess.run([sys.executable, '-B', KEYS] + list(items), capture_output=True, text=True, check=True).stdout.strip().replace(';', '\n')
def vlcwins():
    return [w for w in wins() if 'vlc' in (w['app'] + w['title']).lower() or w['app'] not in ('chonk-terminal-darwin',)]
def main(tag, steps):
    tgt = ''
    with hold('VLC UI pass %s: %s' % (tag, ' '.join(steps)[:150])):
        for s in steps:
            k, _, v = s.partition(':')
            if k == 'start': print(launch(tag, *(v.split(',') if v else [])))
            elif k == 'sleep': time.sleep(float(v))
            elif k == 'cap': cap(v); small(v, width=1000)
            elif k == 'list':
                for w in wins(): print(w['id'], w['app'], repr(w['title']), w['x'], w['y'], w['w'], w['h'], 'focused' if w['focused'] else '')
            elif k == 'target': tgt = 'target %s\n' % v
            elif k == 'click': x, y = map(int, v.split(',')); print(inj(tgt + click(x, y)))
            elif k == 'dclick': x, y = map(int, v.split(',')); print(inj(tgt + click(x, y) + '\n' + click(x, y)))
            elif k == 'keys': print(inj(tgt + keys(v)))
            elif k == 'mine': print(mine())
            elif k == 'stop': print(stop())
            elif k == 'log': print(vlclog(tag, int(v)))
if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:])
