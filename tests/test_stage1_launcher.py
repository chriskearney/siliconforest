"""Mocked macOS interfaces only; no target access or privileged operations."""
import hashlib
import shutil
import subprocess
from pathlib import Path
from test_stage1_recovery import RecoveryTests

class LauncherTests(RecoveryTests):
    # Inherit fixture helpers, not the already separately run recovery tests.
    def setUp(self):
        super().setUp()
        source=(Path(__file__).resolve().parents[1]/'start.sh').read_text()
        pinned='3b1c6dbdb4e554f77a7a99c06f57af163b5dc0858e3f7a9b9724287037f341ed'
        assert source.count(pinned)==1 and source.count('/usr/libexec/PlistBuddy')==1
        source=source.replace(pinned,hashlib.sha256((self.capsule/'prepare.sh').read_bytes()).hexdigest()).replace('/usr/libexec/PlistBuddy',str(self.pbuddy))
        self.launcher=self.root/'start.sh';self.launcher.write_text(source)

    def launch(self):
        self.save_state()
        return subprocess.run(['/bin/bash',str(self.launcher)],env=self.env,input='yes\n',text=True,capture_output=True,timeout=35)

    def test_launcher_keeps_stdin_for_owner_confirmation(self):
        r=self.launch();self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((self.root/'kmutil.log').exists())

    def test_launcher_no_efi(self):
        self.state['no_efi']=True;r=self.launch();self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_launcher_no_prepared_capsule(self):
        (self.capsule/'prepare.sh').unlink();r=self.launch();self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_launcher_tampered_helper(self):
        with (self.capsule/'prepare.sh').open('a') as f:f.write('\n# changed\n')
        r=self.launch();self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_launcher_ambiguous_capsules(self):
        other=self.root/'EFI 2/siliconforest/recovery-stage1';other.parent.mkdir(parents=True);shutil.copytree(self.capsule,other);self.state['two_capsules']=True;r=self.launch();self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_launcher_wrong_recovery_stops_in_helper(self):
        self.state['not_paired']=True;r=self.launch();self.assertNotEqual(r.returncode,0);self.assertIn('Wrong Recovery',r.stderr);self.assert_no_boot_write()

    def test_launcher_malformed_target_stops_in_helper(self):
        self.state['duplicate_group']=True;r=self.launch();self.assertNotEqual(r.returncode,0);self.assertIn('exactly one matching',r.stderr);self.assert_no_boot_write()

# Avoid rerunning inherited test methods under a second class; their fixture and
# assertions are shared deliberately, the seven launcher cases are separate.
for _name in tuple(vars(RecoveryTests)):
    if _name.startswith('test_') and _name not in vars(LauncherTests):
        setattr(LauncherTests,_name,None)
del RecoveryTests
