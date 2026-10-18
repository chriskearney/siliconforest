# SPDX-License-Identifier: MIT
"""Preserve a legacy M3 desktop setup while adopting the native Mesa session."""
import configparser
import json
import os
from pathlib import Path
import pwd
import subprocess

OVERRIDE = Path('/etc/sddm.conf.d/zz-siliconforest-session.conf')

# User files are inspected and replaced as their owner, never as root. This
# code is part of the verified installer; no user configuration is evaluated.
USER_FILE = '''import base64,hashlib,json,os,pathlib,sys,tempfile
d=json.load(sys.stdin)
home=pathlib.Path.home()
p=home/'.config/chonkstep/m3gpu-session.env'
for parent in [home,home/'.config',p.parent,p]:
 if parent.is_symlink(): raise RuntimeError('Refuse a symlink session configuration')
if not p.exists():
 if d['action']=='inspect': print('null');sys.exit(0)
 raise RuntimeError('Session configuration disappeared')
assert p.is_file() and p.stat().st_uid==os.getuid() and p.stat().st_size<=65536
b=p.read_bytes()
if d['action']=='inspect':
 old=b'CHONKSTEP_M3_MESA_PREFIX=/opt/mesa-m3'
 lines=b.splitlines(keepends=True)
 matches=[i for i,line in enumerate(lines) if line.rstrip(b'\\r\\n')==old]
 if len(matches)!=1: print('null');sys.exit(0)
 lines[matches[0]]=lines[matches[0]].replace(old,b'CHONKSTEP_M3_MESA_PREFIX=/usr/lib/siliconforest/mesa')
 print(json.dumps({'before':base64.b64encode(b).decode(),'after':base64.b64encode(b''.join(lines)).decode(),'mode':p.stat().st_mode&0o777}))
else:
 expected=base64.b64decode(d['expected']);replacement=base64.b64decode(d['replacement'])
 if b==replacement: print('null');sys.exit(0)
 assert b==expected,'Session configuration changed; refusing to overwrite user edits'
 fd,name=tempfile.mkstemp(prefix='.siliconforest-session-',dir=p.parent)
 try:
  with os.fdopen(fd,'wb') as f: f.write(replacement);f.flush();os.fsync(f.fileno())
  os.chmod(name,d['mode']);os.replace(name,p)
 finally:
  if os.path.exists(name): os.unlink(name)
 print('null')
'''


def user_file(user, request):
    result = subprocess.check_output(
        ['runuser', '-u', user, '--', '/usr/bin/python3', '-I', '-c', USER_FILE],
        input=json.dumps(request), text=True)
    return json.loads(result)


def plan(data):
    if data['boards'] != ['apple,j516s']:
        return None
    user = os.environ.get('SUDO_USER', '')
    if not user or user == 'root':
        return None
    owner = pwd.getpwnam(user)
    if owner.pw_uid < 1000:
        return None
    change = user_file(user, {'action': 'inspect'})
    config = configparser.ConfigParser(interpolation=None, strict=False)
    files = [*sorted(Path('/usr/lib/sddm/sddm.conf.d').glob('*.conf')),
             *sorted(Path('/etc/sddm.conf.d').glob('*.conf')), Path('/etc/sddm.conf')]
    config.read(files)
    legacy = config.get('Autologin', 'Session', fallback='').removesuffix('.desktop')
    own = config.get('Autologin', 'User', fallback='') == user
    switch = own and legacy in ('chonkstep-native-pro', 'chonkstep-auto-uwsm', 'chonkstep-m3gpu-uwsm')
    if switch and not Path('/usr/share/wayland-sessions/chonkstep-uwsm.desktop').is_file():
        raise ValueError('Native chonkstep session entry is missing')
    return {'user': user, 'uid': owner.pw_uid, 'change': change, 'switch_sddm': switch} if change or switch else None


def apply(migration, restore=False):
    if not migration:
        return
    owner = pwd.getpwnam(migration['user'])
    if owner.pw_uid != migration['uid']:
        raise ValueError('Session configuration owner changed')
    change = migration['change']
    if change:
        user_file(migration['user'], {'action': 'replace', 'mode': change['mode'],
            'expected': change['after' if restore else 'before'],
            'replacement': change['before' if restore else 'after']})
    if migration['switch_sddm'] and not restore:
        from .boot import atomic
        atomic(OVERRIDE, b'# SiliconForest native Mesa session\n[Autologin]\nSession=chonkstep-uwsm.desktop\n')
