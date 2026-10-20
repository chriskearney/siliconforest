"""Disposable filesystem + mocked macOS interfaces; never contacts a Mac.

Production branches and command arguments are exercised. Only the absolute
PlistBuddy executable path and target metadata digest are fixture substitutions.
This is not macOS/Recovery/hardware qualification.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

BASE = Path(__file__).resolve().parent
SOURCE = (BASE.parent / 'scripts/stage1-recovery-prepare.sh').read_text()
VG = '11111111-1111-4111-8111-111111111111'
EFI = '22222222-2222-4222-8222-222222222222'
OLD = 'a' * 96
NEW = 'b' * 96
NSIH = 'c' * 96
SYSTEM_UUID = '33333333-3333-4333-8333-333333333333'


def sha(b):
    return hashlib.sha256(b).hexdigest()


DRIVER = r'''#!/usr/bin/python3
import sys,pathlib,os,json,plistlib,hashlib
r=pathlib.Path(os.environ['MOCK_ROOT']);s=json.loads((r/'state.json').read_text());a=sys.argv[2:];kind=sys.argv[1]
if kind=='plist':
 try:
  assert a[0]=='-c' and a[1].startswith('Print :');v=plistlib.loads(pathlib.Path(a[2]).read_bytes())
  for k in a[1][7:].split(':'):v=v[int(k)] if isinstance(v,list) else v[k]
  assert isinstance(v,(str,int));print(v)
 except (AssertionError,KeyError,IndexError,ValueError):sys.exit(1)
elif kind=='diskutil':
 if a[0]=='mount':
  assert a[1] in ['disk0s3','disk1s3','disk4s1','disk4s2',s['system_uuid']];sys.exit(0)
 if a[:2]==['info','-plist']:
  name=a[2]
  d={'DiskUUID':s['efi'],'Content':s.get('content','EFI'),'MountPoint':str(r/('EFI 2' if name=='disk1s3' else 'EFI'))} if name in (s['requested_efi'],'disk0s3','disk1s3') else {'MountPoint':str(r/(s.get('system_mount','Omarchy Pro') if name in ('disk4s1',s['system_uuid']) else 'Preboot'))}
 elif a==['list','-plist']:
  disks=[{'DeviceIdentifier':'disk0','Partitions':[] if s.get('no_efi') else [{'Content':'EFI','DeviceIdentifier':'disk0s3'}]}]
  if s.get('two_capsules'):disks.append({'DeviceIdentifier':'disk1','Partitions':[{'Content':'EFI','DeviceIdentifier':'disk1s3'}]})
  d={'AllDisksAndPartitions':disks}
 elif a==['apfs','list','-plist']:
  vols=[{'DeviceIdentifier':'disk4s1','Roles':['System'],'APFSVolumeUUID':s['system_uuid']},{'DeviceIdentifier':'disk4s2','Roles':['Preboot']}]
  if s.get('duplicate_preboot'):vols.append({'DeviceIdentifier':'disk4s2','Roles':['Preboot']})
  d={'Containers':[{'ContainerReference':'disk4','Volumes':vols}]}
 elif a==['apfs','listVolumeGroups','disk4','-plist']:
  groups=[{'APFSVolumeGroupUUID':s['vg'],'Volumes':[{'DeviceIdentifier':'disk4s1','Role':'System'}]}]
  if s.get('duplicate_group'):groups*=2
  d={'Containers':[{'ContainerReference':'disk4','VolumeGroups':groups}]}
 else:raise AssertionError(a)
 sys.stdout.buffer.write(plistlib.dumps(d))
elif kind=='bputil':
 assert a==['-d','-v',s['requested_vg']]
 if s.get('not_paired'):print('Recovery: Not paired')
 else:print('Recovery: Paired')
 if not s.get('not_1tr'):print('Booted in one true recoveryOS')
 print('(coih): '+s['coih']);print('(nsih): '+s['nsih'])
elif kind=='kmutil':
 assert a[:2]==['configure-boot','-c']
 assert a[3:]==['--raw','--entry-point','2048','--lowest-virtual-address','0','-v',str(r/s.get('system_mount','Omarchy Pro'))],a
 with (r/'kmutil.log').open('a') as f:f.write(json.dumps(a)+'\n')
 if s.get('kmutil_failure'):sys.exit(1)
 data=pathlib.Path(a[2]).read_bytes();s['coih']=s['old'] if data==(r/'old.raw').read_bytes() else s['new']
 installed=r/'Preboot'/s['requested_vg']/'boot'/s['nsih']/'System/Library/Caches/com.apple.kernelcaches'/('kernelcache.custom.'+s['coih']);installed.parent.mkdir(parents=True,exist_ok=True);installed.write_bytes(b'wrapper'+data+b'wrapper')
 (r/'state.json').write_text(json.dumps(s))
 if s.get('touch_stage2'):(r/'EFI/m1n1/boot.bin').write_bytes(b'changed')
else:raise AssertionError(kind)
'''


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sf-stage1-tests-')
        self.root = Path(self.tmp.name)
        self.capsule = self.root / 'EFI/siliconforest/recovery-stage1'
        self.capsule.mkdir(parents=True)
        for name in ('m1n1/boot.bin', 'm1n1/boot.bin.old', 'EFI/Linux/sf.efi', 'EFI/Linux/recovery.efi', 'limine.conf'):
            p = self.root / 'EFI' / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(name.encode())
        self.vars = ('chosen.asahi,efi-system-partition=' + EFI + '\nchainload=' + EFI + ';m1n1/boot.bin\n').encode()
        self.old = b'RAW-OLD\0##m1n1_ver##v1.6.1-dirty\0' + bytes(524288) + b'STACKBOT' + self.vars + bytes(4)
        self.new = b'RAW-NEW\0##m1n1_ver##neutral\0' + bytes(524288) + b'STACKBOT' + self.vars + bytes(4)
        (self.root / 'old.raw').write_bytes(self.old)
        self.raw_path = self.root / 'Omarchy Pro/Finish Installation.app/Contents/Resources/boot.bin'
        self.raw_path.parent.mkdir(parents=True)
        self.raw_path.write_bytes(self.old)
        self.installed = self.root / 'Preboot' / VG / 'boot' / NSIH / 'System/Library/Caches/com.apple.kernelcaches' / ('kernelcache.custom.' + OLD)
        self.installed.parent.mkdir(parents=True)
        self.installed.write_bytes(b'wrapper' + self.old + b'wrapper')
        (self.capsule / 'm1n1-neutral-stage1.bin').write_bytes(self.new[:-len(self.vars)-4])
        (self.capsule / 'm1n1-stage1.bin').write_bytes(self.new)
        conf = {'board':'j516s', 'vgid':VG, 'esp_uuid':EFI, 'raw_sha':sha(self.new[:-len(self.vars)-4]), 'image_sha':sha(self.new), 'stage2_sha':sha(b'm1n1/boot.bin'), 'old_version':'v1.6.1-dirty'}
        data = ''.join(k+'='+v+'\n' for k,v in conf.items()).encode()
        (self.capsule / 'target.conf').write_bytes(data)
        driver = self.root / 'driver.py'
        driver.write_text(DRIVER)
        self.pbuddy = self.root / 'PlistBuddy'
        self.pbuddy.write_text('#!/bin/bash\nexec /usr/bin/python3 '+str(driver)+' plist "$@"\n')
        self.pbuddy.chmod(0o700)
        assert SOURCE.count('/usr/libexec/PlistBuddy') == 1
        source = SOURCE.replace('/usr/libexec/PlistBuddy', str(self.pbuddy)).replace('@TARGET_CONF_SHA@', sha(data))
        (self.capsule / 'prepare.sh').write_text(source)
        self.driver = driver
        self.env = dict(os.environ, MOCK_ROOT=str(self.root))
        mock = self.root / 'mock-env.sh'
        mock.write_text('''uname() { case "$1" in -s) echo Darwin;; -m) echo arm64;; *) return1;; esac; }
id() { echo0; }
stat() { /usr/bin/stat --printf='%s\\n' "$3"; }
sync() { :; }
'''.replace('return1','return 1').replace('echo0','echo 0') + '\n' +
                        '\n'.join(k+'() { /usr/bin/python3 '+str(driver)+' '+k+' "$@"; }' for k in ('diskutil','bputil','kmutil')) + '\n')
        self.env['BASH_ENV'] = str(mock)
        self.state = {'requested_vg':VG,'requested_efi':EFI,'vg':VG,'efi':EFI,'nsih':NSIH,'coih':OLD,'old':OLD,'new':NEW,'system_uuid':SYSTEM_UUID}
        self.save_state()
        self.boot_before = {p.relative_to(self.root).as_posix():p.read_bytes() for p in (self.root/'EFI').rglob('*') if p.is_file() and not p.is_relative_to(self.capsule)}

    def tearDown(self):
        self.tmp.cleanup()

    def save_state(self):
        (self.root / 'state.json').write_text(json.dumps(self.state))

    def run_tool(self, mode='--inspect', answer='yes\n'):
        self.save_state()
        return subprocess.run(['/bin/bash',str(self.capsule/'prepare.sh'),mode], env=self.env, input=answer, text=True, capture_output=True, timeout=35)

    def assert_no_boot_write(self):
        self.assertFalse((self.root/'kmutil.log').exists())
        for name, data in self.boot_before.items():
            self.assertEqual((self.root/name).read_bytes(),data)

    def test_inspect(self):
        r=self.run_tool();self.assertEqual(r.returncode,0,r.stderr);self.assert_no_boot_write();self.assertFalse(list(self.capsule.glob('backup-*')))

    def test_wrong_pair(self):
        self.state['not_paired']=True;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_not_1tr(self):
        self.state['not_1tr']=True;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_wrong_efi(self):
        self.state['efi']=VG;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_wrong_group(self):
        self.state['vg']=EFI;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_duplicate_group(self):
        self.state['duplicate_group']=True;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_duplicate_preboot(self):
        self.state['duplicate_preboot']=True;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_metadata_tamper(self):
        with (self.capsule/'target.conf').open('a') as f:f.write('vgid='+EFI+'\n')
        r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_binary_tamper(self):
        (self.capsule/'m1n1-stage1.bin').write_bytes(b'bad');r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_stage2_changed(self):
        (self.root/'EFI/m1n1/boot.bin').write_bytes(b'new');r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assertFalse((self.root/'kmutil.log').exists())

    def test_wrong_installed_image(self):
        self.installed.write_bytes(b'unknown active loader');r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_truncated_old(self):
        short=b'##m1n1_ver##v1.6.1-dirty\0STACKBOT'+self.vars+bytes(4);self.raw_path.write_bytes(short);self.installed.write_bytes(b'wrapper'+short);r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assertIn('unexpectedly small',r.stderr);self.assert_no_boot_write()

    def test_unknown_stage1_variable(self):
        bad=self.old[:-4]+b'bad-extra=1\n'+bytes(4);self.raw_path.write_bytes(bad);self.installed.write_bytes(b'wrapper'+bad);r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_decline(self):
        r=self.run_tool('--install','no\n');self.assertEqual(r.returncode,0,r.stderr);self.assert_no_boot_write();backup=list(self.capsule.glob('backup-*'));self.assertEqual(len(backup),1);self.assertEqual((backup[0]/'original-stage1.bin').read_bytes(),self.old);self.assertEqual((backup[0]/'status').read_text(),'cancelled\n')

    def test_partial_backup_copy_never_calls_kmutil(self):
        env=Path(self.env['BASH_ENV'])
        with env.open('a') as f:f.write('\ncp() { printf partial > "${@: -1}"; return 1; }\n')
        r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_wrong_old_version(self):
        bad=self.old.replace(b'v1.6.1-dirty',b'v1.0.0-other');self.raw_path.write_bytes(bad);self.installed.write_bytes(b'wrapper'+bad);r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assertIn('identity differs',r.stderr);self.assert_no_boot_write()

    def test_wrong_old_esp_variable(self):
        bad=self.old.replace(('chainload='+EFI).encode(),('chainload='+VG).encode());self.raw_path.write_bytes(bad);self.installed.write_bytes(b'wrapper'+bad);r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assertIn('Unexpected stage-1 variable',r.stderr);self.assert_no_boot_write()

    def test_tampered_rollback_image_refused(self):
        r=self.run_tool('--install');self.assertEqual(r.returncode,0,r.stderr);backup=list(self.capsule.glob('backup-*'))[0];(backup/'original-stage1.bin').write_bytes(b'bad');r=subprocess.run(['/bin/bash',str(backup/'restore.sh')],env=self.env,text=True,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertEqual(len((self.root/'kmutil.log').read_text().splitlines()),1)

    def test_rollback_resolves_uuid_after_mountpoint_changes(self):
        r=self.run_tool('--install');self.assertEqual(r.returncode,0,r.stderr);backup=list(self.capsule.glob('backup-*'))[0];moved=self.root/'Moved EFI'/backup.name;moved.parent.mkdir();backup.rename(moved)
        state=json.loads((self.root/'state.json').read_text());state['system_mount']='Omarchy Pro 1';(self.root/'state.json').write_text(json.dumps(state));(self.root/'Omarchy Pro').rename(self.root/'Omarchy Pro 1')
        r=subprocess.run(['/bin/bash',str(moved/'restore.sh')],env=self.env,text=True,capture_output=True);self.assertEqual(r.returncode,0,r.stderr);a=json.loads((self.root/'kmutil.log').read_text().splitlines()[-1]);self.assertEqual(a[2],str(moved/'original-stage1.bin'));self.assertEqual(a[-1],str(self.root/'Omarchy Pro 1'))

    def test_broken_shasum_uses_openssl(self):
        with Path(self.env['BASH_ENV']).open('a') as f:f.write('\nshasum() { return 1; }\n')
        r=self.run_tool();self.assertEqual(r.returncode,0,r.stderr);self.assert_no_boot_write()

    def test_install_and_native_rollback(self):
        r=self.run_tool('--install');self.assertEqual(r.returncode,0,r.stderr);backup=list(self.capsule.glob('backup-*'));self.assertEqual(len(backup),1);self.assertEqual((backup[0]/'original-stage1.bin').read_bytes(),self.old);self.assertEqual((backup[0]/'status').read_text(),'installed-awaiting-linux-boot-test\n')
        for name,data in self.boot_before.items():self.assertEqual((self.root/name).read_bytes(),data)
        args=json.loads((self.root/'kmutil.log').read_text());self.assertEqual(args[2],str(backup[0]/'neutral-stage1.bin'));self.assertEqual(args[-1],str(self.root/'Omarchy Pro'))
        r=subprocess.run(['/bin/bash',str(backup[0]/'restore.sh')],env=self.env,text=True,capture_output=True);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(json.loads((self.root/'state.json').read_text())['coih'],OLD)

    def test_kmutil_failure_keeps_backups(self):
        self.state['kmutil_failure']=True;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);backup=list(self.capsule.glob('backup-*'))[0];self.assertEqual((backup/'status').read_text(),'apply-unverified\n');self.assertEqual((backup/'original-stage1.bin').read_bytes(),self.old)

    def test_unexpected_linux_boot_write_refused(self):
        self.state['touch_stage2']=True;r=self.run_tool('--install');self.assertNotEqual(r.returncode,0);self.assertIn('Linux boot files changed unexpectedly',r.stderr)

    def test_already_installed_no_second_write(self):
        self.installed.write_bytes(b'wrapper'+self.new);r=self.run_tool('--install');self.assertEqual(r.returncode,0,r.stderr);self.assert_no_boot_write();self.assertFalse(list(self.capsule.glob('backup-*')))

    def test_wrong_host_refused_without_mac_tools(self):
        env=dict(os.environ);env.pop('BASH_ENV',None);r=subprocess.run(['/bin/bash',str(self.capsule/'prepare.sh'),'--install'],env=env,text=True,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertIn('Apple Silicon in Recovery',r.stderr);self.assert_no_boot_write()


if __name__ == '__main__':
    unittest.main(verbosity=2)
