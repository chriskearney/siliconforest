# SPDX-License-Identifier: MIT
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from installer.session import USER_FILE


class SessionMigrationTests(unittest.TestCase):
    def test_restore_and_refuse_changed_or_symlink_user_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = home / '.config/chonkstep/m3gpu-session.env'
            path.parent.mkdir(parents=True)
            original = (b'# keep my settings\nCHONKSTEP_M3_CLIENTS=gpu\n'
                        b'CHONKSTEP_M3_MESA_PREFIX=/opt/mesa-m3\n')
            path.write_bytes(original)
            path.chmod(0o640)

            def run(request):
                return subprocess.run(['/usr/bin/python3', '-I', '-c', USER_FILE],
                    input=json.dumps(request), text=True, capture_output=True,
                    env={**os.environ, 'HOME': str(home)})

            inspected = run({'action': 'inspect'})
            self.assertEqual(inspected.returncode, 0, inspected.stderr)
            change = json.loads(inspected.stdout)
            self.assertEqual(base64.b64decode(change['before']), original)
            request = {'action': 'replace', 'expected': change['before'],
                       'replacement': change['after'], 'mode': change['mode']}
            self.assertEqual(run(request).returncode, 0)
            self.assertEqual(path.read_bytes(), original.replace(b'/opt/mesa-m3', b'/usr/lib/siliconforest/mesa'))
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            restore = {**request, 'expected': change['after'], 'replacement': change['before']}
            self.assertEqual(run(restore).returncode, 0)
            self.assertEqual(path.read_bytes(), original)
            path.write_bytes(original + b'# later user edit\n')
            self.assertNotEqual(run(request).returncode, 0)
            self.assertTrue(path.read_bytes().endswith(b'# later user edit\n'))
            target = home / 'other-file'
            target.write_bytes(original)
            path.unlink()
            path.symlink_to(target)
            self.assertNotEqual(run(request).returncode, 0)
            self.assertEqual(target.read_bytes(), original)
