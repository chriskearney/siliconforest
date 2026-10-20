"""Mocked macOS interfaces only; no target access or privileged operations."""
import hashlib
import shutil
import subprocess
from pathlib import Path
from test_stage1_recovery import RecoveryTests, SOURCE, HOST_TOOL, NATIVE_TOOL_SHA

class LauncherTests(RecoveryTests):
    # Inherit fixture helpers, not the already separately run recovery tests.
    def setUp(self):
        super().setUp()
        source=(Path(__file__).resolve().parents[1]/'start.sh').read_text()
        host_sha=hashlib.sha256(HOST_TOOL.read_bytes()).hexdigest()
        template=SOURCE.replace(NATIVE_TOOL_SHA,host_sha).replace('/usr/libexec/PlistBuddy',str(self.pbuddy))
        template_file=self.root/'template.sh';template_file.write_text(template)
        self.env['MOCK_TOOL']=str(HOST_TOOL);self.env['MOCK_TEMPLATE']=str(template_file)
        metadata=hashlib.sha256((self.capsule/'target.conf').read_bytes()).hexdigest()
        repaired=template.replace('@TARGET_CONF_SHA@',metadata)
        old=b'#!/bin/bash\necho old-helper-must-not-run >&2\nexit 99\n'
        (self.capsule/'prepare.sh').write_bytes(old)
        expected={'old':hashlib.sha256(old).hexdigest(),'new':hashlib.sha256(repaired.encode()).hexdigest(),'metadata':metadata,'template':hashlib.sha256(template.encode()).hexdigest(),'tool':host_sha}
        import re
        for name,value in expected.items():
            source,n=re.subn(r'^expected_'+name+r'=[0-9a-f]{64}$','expected_'+name+'='+value,source,flags=re.M)
            assert n==1
        source=source.replace('/usr/libexec/PlistBuddy',str(self.pbuddy))
        self.launcher=self.root/'start.sh';self.launcher.write_text(source)

    def launch(self):
        self.save_state()
        return subprocess.run(['/bin/bash',str(self.launcher)],env=self.env,input='yes\n',text=True,capture_output=True,timeout=35)

    def test_launcher_keeps_stdin_for_owner_confirmation(self):
        r=self.launch();self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((self.root/'kmutil.log').exists());self.assertEqual((self.capsule/'prepare-before-sha-fix.sh').read_bytes(),b'#!/bin/bash\necho old-helper-must-not-run >&2\nexit 99\n')

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

    def test_launcher_bad_downloaded_crypto_refused(self):
        bad=self.root/'bad-tool';bad.write_text('#!/bin/sh\nexit 1\n');self.env['MOCK_TOOL']=str(bad);r=self.launch();self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_launcher_corrupted_template_refused(self):
        bad=self.root/'bad-template';bad.write_text('bad');self.env['MOCK_TEMPLATE']=str(bad);r=self.launch();self.assertNotEqual(r.returncode,0);self.assert_no_boot_write()

    def test_launcher_requires_no_host_crypto_commands(self):
        with Path(self.env['BASH_ENV']).open('a') as f:f.write('\nshasum() { return 127; }\nopenssl() { return 127; }\nsha256() { return 127; }\nsha256sum() { return 127; }\n')
        r=self.launch();self.assertEqual(r.returncode,0,r.stderr);self.assertTrue((self.root/'kmutil.log').exists())

# Avoid rerunning inherited test methods under a second class; their fixture and
# assertions are shared deliberately, the seven launcher cases are separate.
for _name in tuple(vars(RecoveryTests)):
    if _name.startswith('test_') and _name not in vars(LauncherTests):
        setattr(LauncherTests,_name,None)
del RecoveryTests
