# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
"""The VNC harness must preserve the actual VM runner result."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'release/image/qemu/run-vnc.sh'


@unittest.skipUnless(os.name == 'posix', 'POSIX shell harness')
class VncExitStatus(unittest.TestCase):
    def test_runner_failure_is_not_reported_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = root / 'runner'
            for status in (0, 17):
                runner.write_text('#!/bin/sh\nexit %d\n' % status)
                runner.chmod(0o755)
                result = subprocess.run(
                    ['sh', str(SCRIPT), str(root), '1'],
                    env={**os.environ, 'QD_RUNNER': str(runner)},
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
                )
                self.assertEqual(result.returncode, status, result.stdout.decode())


if __name__ == '__main__':
    unittest.main()
