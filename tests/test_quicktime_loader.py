# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The export check for QuickTime Player's loader libraries (finch/QuickTime/loader), on
synthetic images: no Mach-O file and no application bundle is read."""
import importlib.util
import json
import os
import shutil
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

    def test_additions_install_name_is_accepted_and_nothing_else(self):
        ours = Image('/L/A.sf-additions', ['_a'])
        self.assertEqual(check_exports.check({'/L/A': ['_a']}, lambda install: install, lambda path: ours)[0], [])
        other = Image('/L/A.sf-something', ['_a'])
        self.assertEqual(len(check_exports.check({'/L/A': ['_a']}, lambda install: install, lambda path: other)[0]), 1)

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


QT = ROOT / 'integrations/siliconforest/finch/QuickTime'
spec2 = importlib.util.spec_from_file_location('qt_prefix', QT / 'qt_prefix.py')
qt_prefix = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(qt_prefix)


class SymbolTableTests(unittest.TestCase):
    def test_committed_symbol_table(self):
        table = json.loads((QT / 'additions/symbols.json').read_text())['symbols']
        self.assertEqual(len(table), 112)
        self.assertEqual(len({(r['library'], r['symbol']) for r in table}), 112)
        kinds = {}
        for row in table:
            kinds[row['kind']] = kinds.get(row['kind'], 0) + 1
        self.assertEqual(kinds, {'absence': 48, 'constant': 37, 'real': 20, 'model': 7})
        by_library = check_exports.load_imports(QT / 'additions/symbols.json')
        self.assertEqual(len(by_library), 18)
        self.assertEqual(sum(map(len, by_library.values())), 112)

    def test_moved_names_and_what_is_left(self):
        path = QT / 'additions/symbols.json'
        prefix = check_exports.load_imports(path, 'additions')
        frameworks = check_exports.load_imports(path, 'frameworks')
        self.assertEqual(sum(map(len, prefix.values())), 82)
        self.assertEqual(sum(map(len, frameworks.values())), 30)
        # nothing is supplied by both, and nothing is lost
        both = {(k, s) for k, v in prefix.items() for s in v} & {(k, s) for k, v in frameworks.items() for s in v}
        self.assertEqual(both, set())
        # with the moved names in the frameworks, CoreFoundation and CoreAudio need no additions
        self.assertFalse([k for k in prefix if k.endswith(('/CoreFoundation', '/CoreAudio'))])
        # every moved name is guarded out of the additions' sources
        sources = ''.join((QT / 'additions' / f).read_text() for f in ('AppKit.m', 'Foundation.m', 'plain.c', 'QuartzCore.m'))
        self.assertGreaterEqual(sources.count('SF_MOVED'), 8)

    def test_version_link_is_accepted(self):
        appkit = Image('/F/AppKit.framework/Versions/A/AppKit', ['_x'])
        install = '/F/AppKit.framework/Versions/C/AppKit'
        problems, _ = check_exports.check({install: ['_x']}, lambda i: i, lambda p: appkit,
                                          resolved=lambda i: '/F/AppKit.framework/Versions/A/AppKit')
        self.assertEqual(problems, [])

    def test_symbol_table_rules(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 's.json'
            good = {'library': '/L/A', 'symbol': '_a', 'kind': 'real', 'note': 'n'}
            p.write_text(json.dumps({'symbols': [good]}))
            self.assertEqual(check_exports.load_imports(p), {'/L/A': ['_a']})
            for bad in (dict(good, kind='works'), dict(good, note=''), dict(good, library='L/A'), dict(good, symbol='a'), dict(good, extra=1)):
                p.write_text(json.dumps({'symbols': [bad]}))
                with self.assertRaises(ValueError):
                    check_exports.load_imports(p)
            p.write_text(json.dumps({'symbols': [good, good]}))
            with self.assertRaises(ValueError):
                check_exports.load_imports(p)


class PrefixTests(unittest.TestCase):
    """qt_prefix.assemble on a made-up root: plain files stand for libraries."""

    def world(self, d):
        d = Path(d)
        fw = d / 'root/System/Library/Frameworks'
        (fw / 'AppKit.framework/Versions/A').mkdir(parents=True)
        (fw / 'AppKit.framework/Versions/C').mkdir()
        (fw / 'AppKit.framework/Versions/A/AppKit').write_text('system AppKit')
        (fw / 'AppKit.framework/Versions/C/AppKit').symlink_to('../A/AppKit')
        (fw / 'AppKit.framework/Versions/Current').symlink_to('A')
        (fw / 'CoreText.framework/Versions/A').mkdir(parents=True)
        (fw / 'CoreText.framework/Versions/A/CoreText').write_text('system CoreText')
        (fw / 'CoreText.framework/Versions/A/CoreText.pd').write_text('child')
        stage = d / 'stage/System/Library/Frameworks/AVFoundation.framework/Versions/A'
        stage.mkdir(parents=True)
        (stage / 'AVFoundation').write_text('staged AVFoundation')
        (stage / 'AVFoundation.pd').write_text('staged child')
        (d / 'stage/usr/lib/swift').mkdir(parents=True)
        (d / 'stage/usr/lib/swift/libswiftos.dylib').write_text('os')
        add = d / 'add'
        add.mkdir()
        entries = [('AppKit', 'AppKit.framework/Versions/C/AppKit'), ('CoreText', 'CoreText.framework/Versions/A/CoreText'),
                   ('AVFoundation', 'AVFoundation.framework/Versions/A/AVFoundation')]
        for name, _ in entries:
            (add / name).write_text('additions ' + name)
        (add / 'manifest.json').write_text(json.dumps([{'name': n, 'load_path': '/System/Library/Frameworks/' + p} for n, p in entries]))
        return d

    def test_links_the_system_image_and_renames_a_staged_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = self.world(tmp)
            report = qt_prefix.assemble(d / 'prefix', d / 'root', d / 'add', stages=[d / 'stage'])
            self.assertEqual(report['problems'], [])
            fw = d / 'prefix/System/Library/Frameworks'
            self.assertEqual((fw / 'AppKit.framework/Versions/C/AppKit').read_text(), 'additions AppKit')
            self.assertEqual((fw / 'AppKit.framework/Versions/A/AppKit').read_text(), 'additions AppKit')
            under = fw / 'AppKit.framework/Versions/A/AppKit.sf-under'
            self.assertTrue(under.is_symlink())
            self.assertEqual(under.resolve(), (d / 'root/System/Library/Frameworks/AppKit.framework/Versions/A/AppKit').resolve())
            self.assertEqual((fw / 'AppKit.framework/Versions/C/AppKit.sf-under').read_text(), 'system AppKit')
            self.assertEqual((fw / 'AVFoundation.framework/Versions/A/AVFoundation').read_text(), 'additions AVFoundation')
            self.assertEqual((fw / 'AVFoundation.framework/Versions/A/AVFoundation.sf-under').read_text(), 'staged AVFoundation')
            self.assertFalse((fw / 'AVFoundation.framework/Versions/A/AVFoundation.sf-under').is_symlink())
            self.assertEqual((d / 'prefix/usr/lib/swift/libswiftos.dylib').read_text(), 'os')
            self.assertEqual((d / 'root/System/Library/Frameworks/AppKit.framework/Versions/A/AppKit').read_text(), 'system AppKit')
            self.assertIn('/System/Library/PrivateFrameworks:', report['environment']['DYLD_FRAMEWORK_PATH'])

    def test_copy_mode_takes_the_image_and_its_children(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = self.world(tmp)
            qt_prefix.assemble(d / 'prefix', d / 'root', d / 'add', stages=[d / 'stage'], copy_under=True)
            a = d / 'prefix/System/Library/Frameworks/CoreText.framework/Versions/A'
            self.assertFalse((a / 'CoreText.sf-under').is_symlink())
            self.assertEqual((a / 'CoreText.sf-under').read_text(), 'system CoreText')
            self.assertEqual((a / 'CoreText.pd').read_text(), 'child')

    def test_missing_framework_is_a_problem_and_a_prefix_is_never_reused(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = self.world(tmp)
            shutil.rmtree(d / 'root/System/Library/Frameworks/CoreText.framework')
            report = qt_prefix.assemble(d / 'prefix', d / 'root', d / 'add', stages=[d / 'stage'])
            self.assertEqual(len(report['problems']), 1)
            self.assertIn('CoreText', report['problems'][0])
            with self.assertRaises(SystemExit):
                qt_prefix.assemble(d / 'prefix', d / 'root', d / 'add')


class FakeImage:
    def __init__(self, install, reexports=(), own=()):
        self.id = {'name': install}
        self.dylibs = [{'kind': 'reexport', 'name': n} for n in reexports]
        self._own = set(own)

    def exported(self):
        return self._own, {}


class FakeMacho:
    """Stands for hb_macho over a made-up set of files: path -> FakeImage."""
    def __init__(self, images):
        self.images = images

    def load(self, path, prefer=None):
        return self.images[os.path.realpath(path)]


class InstallNameChainTests(unittest.TestCase):
    """The defect found on the M1 on 18 November 2026: dyld folds a library onto a loaded image
    with the same install name, so equal names down a re-export chain break the load."""

    def chain(self, images, start):
        with tempfile.TemporaryDirectory() as d:
            real = {}
            for name in images:
                p = Path(d) / name.strip('/').replace('/', '_')
                p.write_text('x')
                real[name] = str(p)
            fake = FakeMacho({os.path.realpath(real[n]): FakeImage(*images[n]) for n in images})
            find = lambda install: real.get(install)
            return [n for n, _p in qt_prefix.install_name_chain(real[start], find, fake)]

    def test_distinct_names_down_two_levels(self):
        names = self.chain({'ours': ('/F.sf-additions', ['/F.sfcompat-file']),
                            '/F.sfcompat-file': ('/F.sfcompat', ['/F.pd']),
                            '/F.pd': ('/F', [])}, 'ours')
        self.assertEqual(names, ['/F.sf-additions', '/F.sfcompat', '/F'])
        self.assertEqual(len(names), len(set(names)))

    def test_the_old_design_repeats_a_name(self):
        names = self.chain({'ours': ('/F', ['/F.sfcompat-file']),
                            '/F.sfcompat-file': ('/F.sfcompat', ['/F.pd']),
                            '/F.pd': ('/F', [])}, 'ours')
        self.assertEqual(names.count('/F'), 2)

    def test_a_cycle_ends(self):
        names = self.chain({'a': ('/A', ['b']), 'b': ('/B', ['a'])}, 'a')
        self.assertEqual(names, ['/A', '/B'])

    def test_committed_additions_never_carry_a_framework_path(self):
        text = (QT / 'additions.nix').read_text()
        self.assertIn('-Wl,-install_name,${builtins.elemAt l 1}.sf-additions', text)
        self.assertIn('VideoToolbox.sf-additions', text)


if __name__ == '__main__':
    unittest.main()
