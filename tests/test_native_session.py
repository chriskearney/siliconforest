# SPDX-License-Identifier: MIT
"""Recovery-login behavior without touching a desktop or installed files."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeSessionTests(unittest.TestCase):
    def run_guard(self, *, after=1, marker=True, environment=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            verifier = root / 'verify.py'
            verifier.write_text('import os,pathlib,sys\n'
                                'p=pathlib.Path(os.environ["SF_COUNT"])\n'
                                'n=int(p.read_text())+1 if p.exists() else 1\n'
                                'p.write_text(str(n))\n'
                                'sys.exit(0 if n>=int(os.environ["SF_AFTER"]) else 1)\n')
            flag = root / 'marker'
            if marker:
                flag.touch()
            script = (ROOT / 'installer/native-gpu-session.sh').read_text()
            script = script.replace('/usr/share/siliconforest/native-gpu-session', str(flag))
            script = script.replace('/usr/lib/siliconforest/installer.pyz', str(verifier))
            script = 'sleep() { :; }; logger() { :; };\n' + script
            script += '\nprintf "%s|%s" "${LIBGL_ALWAYS_SOFTWARE-unset}" "${SILICONFOREST_NATIVE_FALLBACK-unset}"\n'
            env = {'PATH': '/usr/bin:/bin', 'SF_COUNT': str(root / 'count'),
                   'SF_AFTER': str(after), **(environment or {})}
            result = subprocess.check_output(['sh', '-c', script], env=env, text=True)
            count = int((root / 'count').read_text()) if (root / 'count').exists() else 0
            return result, count

    def test_recovery_pair_failure_uses_software_with_bounded_wait(self):
        self.assertEqual(self.run_guard(after=9), ('1|software', 5))

    def test_native_pair_waits_for_gpu_and_clears_only_own_fallback(self):
        self.assertEqual(self.run_guard(after=3, environment={
            'LIBGL_ALWAYS_SOFTWARE': '1', 'SILICONFOREST_NATIVE_FALLBACK': 'software'}),
            ('unset|unset', 3))

    def test_user_software_choice_is_preserved(self):
        self.assertEqual(self.run_guard(environment={'LIBGL_ALWAYS_SOFTWARE': '1'}), ('1|unset', 1))

    def test_other_profiles_are_untouched(self):
        self.assertEqual(self.run_guard(marker=False), ('unset|unset', 0))


if __name__ == '__main__':
    unittest.main()
