"""The real picker bootstrap on mocked native interfaces; no target access."""
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
from test_apple_picker import PickerTests,ROOT,HOST_TOOL

class PickerLauncherTests(PickerTests):
    def setUp(self):
        super().setUp()
        self.env['MOCK_TOOL']=str(HOST_TOOL)
        source=(ROOT/'picker.sh').read_text()
        pins={'tool':hashlib.sha256(HOST_TOOL.read_bytes()).hexdigest(),'conf':hashlib.sha256((self.capsule/'target.conf').read_bytes()).hexdigest(),'helper':hashlib.sha256((self.capsule/'update.sh').read_bytes()).hexdigest()}
        for name,value in pins.items():
            source,n=re.subn(r'^expected_'+name+'=[0-9a-f]{64}$','expected_'+name+'='+value,source,flags=re.M);assert n==1
        source=source.replace('/usr/libexec/PlistBuddy',str(self.pbuddy))
        self.launcher=self.root/'picker.sh';self.launcher.write_text(source)
    def launch(self,args=(),answer='yes\n'):
        self.save_state()
        return subprocess.run(['/bin/bash',str(self.launcher),*args],env=self.env,input=answer,text=True,capture_output=True,timeout=35)
    def test_launcher_apply_with_terminal_confirmation(self):
        r=self.launch();self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.current_root().name,'SiliconForest Linux');self.assert_no_boot_write()
    def test_launcher_inspection_does_not_mutate(self):
        r=self.launch(['--inspect']);self.assertEqual(r.returncode,0,r.stderr);self.original_intact()
    def test_launcher_tampered_helper_refused(self):
        with (self.capsule/'update.sh').open('a') as f:f.write('\n# changed\n')
        r=self.launch();self.assertNotEqual(r.returncode,0);self.original_intact()
    def test_launcher_tampered_metadata_refused(self):
        with (self.capsule/'target.conf').open('a') as f:f.write('board=other\n')
        r=self.launch();self.assertNotEqual(r.returncode,0);self.original_intact()
    def test_launcher_tampered_icon_refused(self):
        (self.capsule/'siliconforest-volume.icns').write_bytes(b'bad')
        r=self.launch();self.assertNotEqual(r.returncode,0);self.original_intact()
    def test_launcher_tampered_staged_hasher_refused(self):
        (self.capsule/'sf-sha256').write_bytes(b'bad')
        r=self.launch();self.assertNotEqual(r.returncode,0);self.original_intact()
    def test_launcher_no_capsule_refused(self):
        (self.capsule/'update.sh').unlink();r=self.launch();self.assertNotEqual(r.returncode,0);self.original_intact()
    def test_launcher_ambiguous_capsules_refused(self):
        other=self.root/'EFI 2/siliconforest/apple-picker';other.parent.mkdir(parents=True);shutil.copytree(self.capsule,other);self.state['two_capsules']=True
        r=self.launch();self.assertNotEqual(r.returncode,0);self.original_intact()

for name in vars(PickerTests):
    if name.startswith('test_') and name not in vars(PickerLauncherTests):setattr(PickerLauncherTests,name,None)
del PickerTests
