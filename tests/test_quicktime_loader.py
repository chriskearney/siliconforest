# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The export check for QuickTime Player's loader libraries (finch/QuickTime/loader), on
synthetic images: no Mach-O file and no application bundle is read."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / 'integrations/siliconforest/finch/QuickTime/loader'
spec = importlib.util.spec_from_file_location('qt_check_exports', LOADER / 'check_exports.py')
check_exports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_exports)


class Image:
    def __init__(self, name, own=(), reexports=(), individually=None, arm64=True):
        self.id = {'name': name}
        self.dylibs = [{'kind': 'reexport', 'name': n} for n in reexports] + [{'kind': 'load', 'name': '/usr/lib/libSystem.B.dylib'}]
        self._own, self._individually, self.arm64 = set(own), dict(individually or {}), arm64

    def exported(self):
        return self._own, self._individually


def world(*images):
    table = {i.id['name']: i for i in images}
    return (lambda install: install if install in table else None), (lambda path: table[path])


class LoaderCheckTests(unittest.TestCase):
    def test_all_present(self):
        find, load = world(Image('/L/A', ['_a', '_b']))
        problems, counts = check_exports.check({'/L/A': ['_a', '_b']}, find, load)
        self.assertEqual(problems, [])
        self.assertEqual(counts, {'/L/A': (2, 2)})

    def test_missing_symbol_and_missing_library(self):
        find, load = world(Image('/L/A', ['_a']))
        problems, counts = check_exports.check({'/L/A': ['_a', '_b'], '/L/B': ['_c']}, find, load)
        self.assertEqual(problems, ['/L/A: does not export _b', '/L/B: not in the root'])
        self.assertEqual(counts, {'/L/A': (2, 1), '/L/B': (1, 0)})

    def test_umbrella_reexport_is_followed_and_cycles_end(self):
        find, load = world(Image('/L/U', [], reexports=['/L/M']), Image('/L/M', ['_m'], reexports=['/L/U']))
        problems, _ = check_exports.check({'/L/U': ['_m']}, find, load)
        self.assertEqual(problems, [])

    def test_an_ordinary_dependency_is_not_an_export(self):
        find, load = world(Image('/L/A', []), Image('/usr/lib/libSystem.B.dylib', ['_malloc']))
        problems, _ = check_exports.check({'/L/A': ['_malloc']}, find, load)
        self.assertEqual(problems, ['/L/A: does not export _malloc'])

    def test_individually_reexported_symbol_counts(self):
        find, load = world(Image('/L/A', [], individually={'_x': (1, '_x')}))
        self.assertEqual(check_exports.check({'/L/A': ['_x']}, find, load)[0], [])

    def test_wrong_install_name_and_architecture(self):
        other = Image('/L/Other', ['_a'], arm64=False)
        problems, _ = check_exports.check({'/L/A': ['_a']}, lambda install: install, lambda path: other)
        self.assertEqual(problems, ['/L/A: the file there has install name /L/Other', '/L/A: not an arm64 image'])

    def test_import_list_rules(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'i.json'
            p.write_text(json.dumps({'comment': 'c', '/L/A': ['_a', '_b']}))
            self.assertEqual(check_exports.load_imports(p), {'/L/A': ['_a', '_b']})
            for bad in ({'/L/A': ['_b', '_a']}, {'/L/A': ['_a', '_a']}, {'L/A': ['_a']}, {'/L/A': ['a']}, {'/L/A': '_a'}):
                p.write_text(json.dumps(bad))
                with self.assertRaises(ValueError):
                    check_exports.load_imports(p)

    def test_committed_import_list(self):
        imports = check_exports.load_imports(LOADER / 'imports.json')
        self.assertEqual({k.rsplit('/', 1)[1]: len(v) for k, v in imports.items()},
                         {'SwiftUI': 34, 'DeveloperToolsSupport': 2, 'libswiftos.dylib': 2, 'QuickLook': 3, 'QuickLookUI': 1, 'Quartz': 0})
        self.assertFalse([s for v in imports.values() for s in v if 'FORCE_LOAD' in s])


if __name__ == '__main__':
    unittest.main()
