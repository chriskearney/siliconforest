# SPDX-License-Identifier: MIT
"""J313 gate G0: per-board keyboard, display, sound and Touch Bar checks. Host only."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SF = ROOT / 'integrations/siliconforest'
SANITIZE = ['-fsanitize=address,undefined', '-fno-sanitize-recover=all', '-g']


def compiler():
    return shutil.which('clang') or shutil.which('cc')


class NativeTests(unittest.TestCase):
    def build_and_run(self, sources, includes=()):
        cc = compiler()
        if not cc:
            self.skipTest('no C compiler')
        with tempfile.TemporaryDirectory(prefix='j313-gates-') as d:
            exe = pathlib.Path(d) / 'test'
            cmd = [cc, '-std=c11', '-O1', '-Wall', '-Wextra', '-Wpedantic', '-Werror', *SANITIZE]
            cmd += [f'-I{i}' for i in includes] + ['-o', str(exe)] + [str(s) for s in sources]
            subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=60)
            subprocess.run([str(exe)], check=True, capture_output=True, text=True, timeout=30)

    def test_display_tree_is_per_board(self):
        dt = SF / 'm1-gpu-dt'
        self.build_and_run([dt/'src/dispdt.c', dt/'test/dispdt_board_test.c'], [dt/'src'])

    def test_sound_and_touch_bar_board_gate(self):
        self.build_and_run([SF/'m1-sound/board-gate-test/test_board_gate.c'])

    def test_keyboard_guard(self):
        script = SF / 'm1-trackpad-child/multitouch/test_m1kbd_boards.py'
        run = subprocess.run([sys.executable, str(script)], capture_output=True, text=True, timeout=120)
        self.assertEqual(run.returncode, 0, run.stderr[-2000:])


class SourceOrder(unittest.TestCase):
    def body(self, path, name):
        text = path.read_text()
        start = text.index(f'\n{name}::start(IOService *provider)')
        return text[start:text.index('\n}\n', start)]

    def test_drivers_check_the_board_before_any_hardware_or_thread(self):
        for path, name, arg in ((SF/'m1-sound/kernel/SFAppleSound.cpp', 'SFAppleSound', '"sfsound"'),
                                (SF/'m1-touchbar/kernel/SFAppleTouchBar.cpp', 'SFAppleTouchBar', '"sftouchbar"')):
            with self.subTest(name):
                body = self.body(path, name)
                gate = body.index('if (!sf_on_j293())')
                self.assertLess(gate, body.index(arg))
                self.assertLess(gate, body.index('IOLockAlloc'))
                self.assertLess(gate, body.index('kernel_thread_start'))
                self.assertIn('gLevel == 0', body)

    def test_frozen_keyboard_sources_are_unchanged(self):
        pins = json.loads((SF/'m1-trackpad-child/sdk-build-inputs-001.json').read_text())['files']
        import hashlib
        for name in ('m1kbd_board.c', 'm1kbd_pio.c', 'm1kbd_hid.c', 'm1kbd_hid.h', 'm1kbd_hw.h'):
            row = pins[name]
            self.assertEqual(hashlib.sha256((ROOT/row['source']).read_bytes()).hexdigest(), row['sha256'], name)


class Profiles(unittest.TestCase):
    def arguments(self, board):
        return json.loads((ROOT/f'installer/profiles/{board}.json').read_text())['kernel']['arguments']

    def test_j313_is_j293_with_sound_and_touch_bar_off(self):
        j293, j313 = self.arguments('J293'), self.arguments('J313')
        self.assertEqual(j313, j293 + ['sfsound=0', 'sftouchbar=0'])
        self.assertFalse([a for a in j293 if a.startswith(('sfsound=', 'sftouchbar='))])


if __name__ == '__main__':
    unittest.main()
