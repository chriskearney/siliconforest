# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
"""A clean process exit must not hide a failed desktop session."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / 'integrations/siliconforest/qemu-dev/qd_run.py'
spec = importlib.util.spec_from_file_location('qemu_desktop_run', SCRIPT)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class DesktopEvidence(unittest.TestCase):
    def test_failed_session_ends_startup_wait_immediately(self):
        serial = runner.Serial.__new__(runner.Serial)
        serial.text = lambda: b'QDDESK_DESKTOP_RC=1\nQDDESK_END\n'
        process = mock.Mock()
        process.poll.return_value = None
        with mock.patch.object(runner.time, 'sleep', side_effect=AssertionError('wait continued after session ended')):
            self.assertIsNone(serial.wait(b'WMSCALE initial', runner.time.time() + 600,
                                         process, stop=b'QDDESK_END'))

    def test_startup_wait_retains_drawing_before_session_end(self):
        serial = runner.Serial.__new__(runner.Serial)
        serial.text = lambda: b'WMSCALE initial\nQDDESK_END\n'
        self.assertIsNotNone(serial.wait(b'WMSCALE initial', runner.time.time() + 600,
                                         mock.Mock(), stop=b'QDDESK_END'))

    def test_capture_pauses_before_querying_the_framebuffer(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict('os.environ', {'QD_NO_SHOTS': ''}):
            path = Path(directory) / 'desktop.png'
            calls = []
            qmp = runner.Qmp.__new__(runner.Qmp)
            def command(name, **kwargs):
                calls.append(name)
                if name == 'screendump':
                    Path(kwargs['filename']).write_bytes(b'capture fixture')
                return {'return': {}}
            qmp.cmd = command
            self.assertTrue(qmp.shot(path))
            self.assertEqual(calls, ['stop', 'screendump', 'cont'])

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

    def test_failed_application_is_a_failure_without_a_guest_pass_marker(self):
        result = {'status': 'ENDED', 'desktop_up': True}
        runner.record_evidence(result, b'QDDESK_DESKTOP_RC=1\n'
                               b'QDDESK_RESULT cleanup=Incomplete launch_failures=1\nQDDESK_END\n')
        self.assertEqual(result['status'], 'FAILED')


if __name__ == '__main__':
    unittest.main()
