"""Metadata-only Recovery tests on disposable files and mocked Apple tools."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import unittest
from test_stage1_recovery import RecoveryTests, DRIVER, HOST_TOOL, NATIVE_TOOL_SHA, VG, EFI, SYSTEM_UUID

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'scripts/apple-picker-update.sh').read_text()
ICON=(ROOT/'branding/apple-picker/siliconforest-volume.icns').read_bytes()

class PickerTests(RecoveryTests):
    def setUp(self):
        super().setUp()
        self.capsule=self.root/'EFI/siliconforest/apple-picker';self.capsule.mkdir()
        self.old_icon=b'opaque original volume icon bytes'
        icon=self.root/'Omarchy Pro/.VolumeIcon.icns';icon.write_bytes(self.old_icon);icon.chmod(0o640)
        self.system_inode=icon.parent.stat().st_ino
        for name,raw in [('siliconforest-volume.icns',ICON),('sf-sha256',HOST_TOOL.read_bytes())]:
            (self.capsule/name).write_bytes(raw)
        conf={'board':'j516s','vgid':VG,'esp_uuid':EFI,'system_uuid':SYSTEM_UUID,'stage2_sha':hashlib.sha256(b'm1n1/boot.bin').hexdigest()}
        raw=''.join(k+'='+v+'\n' for k,v in conf.items()).encode();(self.capsule/'target.conf').write_bytes(raw)
        src=SOURCE.replace(NATIVE_TOOL_SHA,hashlib.sha256(HOST_TOOL.read_bytes()).hexdigest()).replace('/usr/libexec/PlistBuddy',str(self.pbuddy)).replace('@TARGET_CONF_SHA@',hashlib.sha256(raw).hexdigest())
        (self.capsule/'update.sh').write_text(src)
        driver=DRIVER.replace("if a[0]=='mount':",'''if a[0]=='renameVolume':
  assert a[1]=='disk4s1' and len(a)==3
  with (r/'rename.log').open('a') as f:f.write(json.dumps(a)+'\\n')
  if s.get('rename_failure') and a[2]=='SiliconForest Linux':sys.exit(1)
  old=s.get('system_mount','Omarchy Pro');new=a[2]
  if old!=new:(r/old).rename(r/new)
  s['system_mount']=new;s['volume_name']=new;(r/'state.json').write_text(json.dumps(s))
  if s.get('touch_boot') and a[2]=='SiliconForest Linux':(r/'EFI/m1n1/boot.bin').write_bytes(b'external change')
  if s.get('rename_partial_failure') and a[2]=='SiliconForest Linux':sys.exit(1)
  sys.exit(0)
 if a[0]=='mount':''')
        old="{'MountPoint':str(r/(s.get('system_mount','Omarchy Pro') if name in ('disk4s1',s['system_uuid']) else 'Preboot'))}"
        new="{'DeviceIdentifier':'disk4s1','VolumeName':s.get('volume_name','Omarchy Pro'),'MountPoint':str(r/(s.get('system_mount','Omarchy Pro') if name in ('disk4s1',s['system_uuid']) else 'Preboot'))}"
        assert driver.count(old)==1;driver=driver.replace(old,new);self.driver.write_text(driver)
        with Path(self.env['BASH_ENV']).open('a') as f:
            f.write('''\nstat() { case "$2" in %Lp) /usr/bin/stat --printf='%a\\n' "$3";; *) /usr/bin/stat --printf='%s\\n' "$3";; esac; }
kmutil() { echo FORBIDDEN-KMUTIL >&2; return 99; }
openssl() { return 127; }
shasum() { return 127; }
sha256() { return 127; }
sha256sum() { return 127; }
cmp() { return 127; }
''')
        self.boot_before={p.relative_to(self.root).as_posix():p.read_bytes() for p in (self.root/'EFI').rglob('*') if p.is_file() and not p.is_relative_to(self.capsule)}

    def invoke(self,mode='--inspect',answer='yes\n'):
        self.save_state()
        return subprocess.run(['/bin/bash',str(self.capsule/'update.sh'),mode],env=self.env,input=answer,text=True,capture_output=True,timeout=35)

    def current_root(self):
        return self.root/json.loads((self.root/'state.json').read_text()).get('system_mount','Omarchy Pro')

    def original_intact(self):
        self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),self.old_icon)
        self.assertEqual(self.current_root().name,'Omarchy Pro')
        self.assertEqual((self.current_root()/'.VolumeIcon.icns').stat().st_mode&0o777,0o640)
        self.assert_no_boot_write()

    def test_inspection_has_no_changes(self):
        r=self.invoke();self.assertEqual(r.returncode,0,r.stderr);self.original_intact();self.assertFalse(list(self.capsule.glob('backup-*')))

    def test_decline_retains_verified_backup(self):
        r=self.invoke('--apply','no\n');self.assertEqual(r.returncode,0,r.stderr);self.original_intact()
        b=next(self.capsule.glob('backup-*'));self.assertEqual((b/'status').read_text(),'cancelled\n');self.assertEqual((b/'original.icns').read_bytes(),self.old_icon)

    def test_apply_then_restore_through_uuid_after_mount_name_changes(self):
        r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.current_root().name,'SiliconForest Linux');self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),ICON)
        self.assertEqual(self.current_root().stat().st_ino,self.system_inode)
        self.assertEqual((self.current_root()/'Finish Installation.app/Contents/Resources/boot.bin').read_bytes(),self.old)
        self.assert_no_boot_write()
        b=next(self.capsule.glob('backup-*'));self.assertEqual((b/'status').read_text(),'applied-awaiting-visual-check\n')
        r=subprocess.run(['/bin/bash',str(b/'restore.sh')],env=self.env,text=True,capture_output=True)
        self.assertEqual(r.returncode,0,r.stderr);self.original_intact();self.assertEqual((b/'status').read_text(),'restored\n')

    def test_failed_rename_restores_original_icon(self):
        self.state['rename_failure']=True;r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()
        self.assertEqual((next(self.capsule.glob('backup-*'))/'status').read_text(),'failed-restored\n')

    def test_partial_rename_failure_resolves_new_mount_name_and_restores(self):
        self.state['rename_partial_failure']=True;r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_wrong_pair_refused(self):
        self.state['not_paired']=True;r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_wrong_system_uuid_refused(self):
        self.state['system_uuid']='44444444-4444-4444-8444-444444444444';r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_ambiguous_volume_group_refused(self):
        self.state['duplicate_group']=True;r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_changed_loader_refused(self):
        (self.root/'EFI/m1n1/boot.bin').write_bytes(b'newer loader');r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.assertFalse(list(self.capsule.glob('backup-*')))

    def test_tampered_artwork_refused(self):
        (self.capsule/'siliconforest-volume.icns').write_bytes(b'bad');r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_missing_existing_icon_refused_without_changing_flags(self):
        (self.current_root()/'.VolumeIcon.icns').unlink();r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.assertFalse(list(self.capsule.glob('backup-*')));self.assert_no_boot_write()

    def test_preexisting_lock_refused(self):
        (self.capsule/'.picker-lock').mkdir();r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact();self.assertTrue((self.capsule/'.picker-lock').is_dir())

    def test_partial_backup_never_changes_metadata(self):
        with Path(self.env['BASH_ENV']).open('a') as f:f.write('\ncp() { case "${@: -1}" in */original.icns) printf partial > "${@: -1}"; return 1;; *) /usr/bin/cp "$@";; esac; }\n')
        r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_short_successful_backup_is_detected_before_mutation(self):
        with Path(self.env['BASH_ENV']).open('a') as f:f.write('\ncp() { case "${@: -1}" in */original.icns) printf partial > "${@: -1}"; return 0;; *) /usr/bin/cp "$@";; esac; }\n')
        r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()

    def test_unwritable_icon_slot_leaves_original_state_and_backups(self):
        with Path(self.env['BASH_ENV']).open('a') as f:f.write('\nmktemp() { case "${@: -1}" in */.siliconforest-icon.*) return 1;; *) /usr/bin/mktemp "$@";; esac; }\n')
        r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.original_intact()
        self.assertEqual((next(self.capsule.glob('backup-*'))/'status').read_text(),'failed-restored\n')

    def test_missing_tools_are_reported_together_before_backup(self):
        with Path(self.env['BASH_ENV']).open('a') as f:f.write('\ncommand() { if [ "$1" = -v ]; then case "$2" in mkdir|mv) return 1;; esac; fi; builtin command "$@"; }\n')
        r=self.invoke('--apply');self.assertNotEqual(r.returncode,0);self.assertIn('mkdir',r.stderr);self.assertIn('mv',r.stderr);self.original_intact();self.assertFalse(list(self.capsule.glob('backup-*')))

    def test_detects_unrelated_boot_change_without_overwriting_it(self):
        self.state['touch_boot']=True;r=self.invoke('--apply');self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.current_root().name,'Omarchy Pro');self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),self.old_icon)
        self.assertEqual((self.root/'EFI/m1n1/boot.bin').read_bytes(),b'external change')

    def test_restorer_refuses_changed_backup(self):
        r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr);b=next(self.capsule.glob('backup-*'));(b/'original.icns').write_bytes(b'bad')
        r=subprocess.run(['/bin/bash',str(b/'restore.sh')],env=self.env,text=True,capture_output=True)
        self.assertNotEqual(r.returncode,0);self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),ICON)

    def test_restorer_respects_picker_lock(self):
        r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr);b=next(self.capsule.glob('backup-*'));(self.capsule/'.picker-lock').mkdir()
        r=subprocess.run(['/bin/bash',str(b/'restore.sh')],env=self.env,text=True,capture_output=True)
        self.assertNotEqual(r.returncode,0);self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),ICON)
        self.assertTrue((self.capsule/'.picker-lock').is_dir())

    def test_restorer_refuses_independent_icon_changes(self):
        r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr);b=next(self.capsule.glob('backup-*'));(self.current_root()/'.VolumeIcon.icns').write_bytes(b'owner changed it')
        r=subprocess.run(['/bin/bash',str(b/'restore.sh')],env=self.env,text=True,capture_output=True)
        self.assertNotEqual(r.returncode,0);self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),b'owner changed it')

    def test_restorer_preserves_a_later_kernel_update(self):
        r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr);b=next(self.capsule.glob('backup-*'));(self.root/'EFI/m1n1/boot.bin').write_bytes(b'newer boot chain')
        r=subprocess.run(['/bin/bash',str(b/'restore.sh')],env=self.env,text=True,capture_output=True)
        self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((self.root/'EFI/m1n1/boot.bin').read_bytes(),b'newer boot chain')
        self.assertEqual(self.current_root().name,'Omarchy Pro');self.assertEqual((self.current_root()/'.VolumeIcon.icns').read_bytes(),self.old_icon)

    def test_already_branded_is_idempotent(self):
        r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr)
        self.state=json.loads((self.root/'state.json').read_text());r=self.invoke('--apply');self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(len(list(self.capsule.glob('backup-*'))),1)

for name in vars(RecoveryTests):
    if name.startswith('test_') and name not in vars(PickerTests):setattr(PickerTests,name,None)
del RecoveryTests
