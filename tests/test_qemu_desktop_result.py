# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
"""A clean process exit must not hide a failed desktop session."""
import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'integrations/siliconforest/qemu-dev/qd_run.py'
spec = importlib.util.spec_from_file_location('qemu_desktop_run', SCRIPT)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class DesktopEvidence(unittest.TestCase):
    def test_observed_deadline_failure_overrides_guest_pass_marker(self):
        result = {'status': 'PASS', 'desktop_up': True}
        runner.record_evidence(result, b'WMAUTO done result=INCOMPLETE stopped_in_phase=arm\n'
                               b'QDDESK_RESULT launch_failures=1\nQDDESK_PASS\n')
        self.assertEqual(result['status'], 'FAILED')
        self.assertEqual(len(result['failed']), 2)

    def test_pass_requires_drawing_and_no_failure_evidence(self):
        log = b'WMAUTO done result=PASS\nQDDESK_RESULT launch_failures=0\nQDDESK_PASS\n'
        for drawing, expected in [(True, 'PASS'), (False, 'FAILED')]:
            result = {'status': 'PASS', 'desktop_up': drawing}
            runner.record_evidence(result, log)
            self.assertEqual(result['status'], expected)
            self.assertEqual(result['failed'], [])


if __name__ == '__main__':
    unittest.main()
