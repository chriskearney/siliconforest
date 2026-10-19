# SPDX-License-Identifier: MIT
"""Safety checks for the attended brightness exercise."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'hardware_brightness', Path(__file__).parent / 'hardware/brightness.py')
brightness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(brightness)


class BrightnessSafetyTests(unittest.TestCase):
    def test_screen_never_blanked_at_minimum(self):
        with patch.object(brightness, 'set_level', return_value={}) as setter:
            brightness.exercise(Path('apple-panel-bl'), 500, 1, True)
        self.assertEqual([c.args[1] for c in setter.call_args_list], [26, 1])

    def test_zero_screen_is_refused_without_a_write(self):
        with patch.object(brightness, 'set_level') as setter:
            with self.assertRaises(RuntimeError):
                brightness.exercise(Path('apple-panel-bl'), 500, 0, True)
        setter.assert_not_called()

    def test_failed_adjustment_still_restores_original(self):
        with patch.object(brightness, 'set_level', side_effect=[RuntimeError('write failed'), {}]) as setter:
            with self.assertRaisesRegex(RuntimeError, 'write failed'):
                brightness.exercise(Path('white:kbd_backlight'), 255, 102, False)
        self.assertEqual([c.args[1] for c in setter.call_args_list], [90, 102])

    def test_restore_failure_is_not_reported_as_success(self):
        with patch.object(brightness, 'set_level', side_effect=[{}, RuntimeError('restore failed')]):
            with self.assertRaisesRegex(RuntimeError, 'restore failed'):
                brightness.exercise(Path('white:kbd_backlight'), 255, 102, False)


if __name__ == '__main__':
    unittest.main()
