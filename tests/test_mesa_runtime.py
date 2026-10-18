# SPDX-License-Identifier: MIT
"""An existing LLVM 22 base must satisfy the Air recipe without file conflicts."""
import contextlib
import io
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class RuntimeTests(unittest.TestCase):
    def derive(self, *options):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lib = root / 'usr/lib'
            lib.mkdir(parents=True)
            (lib / 'libgallium.so').write_bytes(b'\x7fELFfixture')
            table, needs = root / 'runtime.tsv', root / 'runtime.needs'

            def run(args, **kwargs):
                if args[:2] == ('readelf', '-d'):
                    text = '(NEEDED) Shared library: [libLLVM.so.22.1]\n'
                elif args[:2] == ('readelf', '-V'):
                    text = ''
                elif args == ('pacman', '-Qqo', '/usr/lib/libLLVM.so.22.1'):
                    text = 'llvm22-libs\n'
                else:
                    raise AssertionError(args)
                return subprocess.CompletedProcess(args, 0, stdout=text)

            exists = __import__('os').path.exists
            with patch.object(sys, 'argv', ['needs-derive.py', str(root), str(lib), str(table), str(needs), *options]), \
                 patch('subprocess.run', side_effect=run), \
                 patch('os.path.exists', side_effect=lambda p: str(p) == '/usr/lib/libLLVM.so.22.1' or exists(p)), \
                 contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(ROOT / 'packaging/mesa/needs-derive.py'), run_name='__main__')
            return needs.read_text().split(), table.read_text()

    def test_legacy_base_uses_existing_llvm22_with_next_major_excluded(self):
        needs, table = self.derive('--llvm-runtime-owner', 'llvm-libs')
        self.assertEqual(set(needs), {'llvm-libs>=22', 'llvm-libs<23'})
        self.assertIn('build owner llvm22-libs', table)
        self.assertIn('libLLVM.so.22.1\tllvm-libs\t22', table)

    def test_unselected_profiles_keep_the_build_runtime_owner(self):
        needs, _ = self.derive()
        self.assertEqual(needs, ['llvm22-libs>=22'])

    def test_unknown_provider_is_refused(self):
        with self.assertRaisesRegex(SystemExit, 'unsupported target LLVM runtime owner'):
            self.derive('--llvm-runtime-owner', 'unreviewed-provider')
