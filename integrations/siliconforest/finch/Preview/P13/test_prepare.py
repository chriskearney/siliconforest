#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host transport boundary tests; fixture bytes are not an application or runtime proof."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from prepare import digest, inventory

TOOL = Path(__file__).with_name('prepare.py')


class PacketBoundaries(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sf-p13-prepare-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.external = self.root / 'external'
        self.external.mkdir()
        (self.external / 'bystander').write_text('preserve me')
        original = self.root / 'original'
        (original / 'Contents/MacOS').mkdir(parents=True)
        (original / 'Contents/MacOS/Preview').write_text('transport fixture only')
        base = self.root / 'base'
        import shutil
        shutil.copytree(original, base / 'Applications/Preview.app')
        (base / 'core').symlink_to(self.external)
        (base / 'SHA256SUMS.json').write_text(json.dumps(inventory(base)))
        provider = self.root / 'provider'
        provider.write_text('owned provider fixture')
        self.spec = {'remote_root': '/private/var/db/sfpreview-app/p13-transport-fixture',
                     'app_execution_allowed': False, 'base_packet': str(base),
                     'base_manifest_sha256': digest(base / 'SHA256SUMS.json'),
                     'original_app': str(original),
                     'app_regular_files': inventory(original)['regular_files'],
                     'blocking_conditions': ['Fixture only; no execution'],
                     'entries': [{'kind': 'file', 'source': str(provider),
                                  'sha256': digest(provider), 'destination': 'core/provider'}]}

    def run_prepare(self, name, spec=None):
        source = self.root / (name + '.json')
        source.write_text(json.dumps(spec or self.spec))
        return subprocess.run([sys.executable, str(TOOL), '--spec', str(source),
                               '--scratch', str(self.root), '--output', str(self.root / name)],
                              capture_output=True, text=True)

    def test_inherited_alias_is_detached_and_archives_reproduce(self):
        self.assertEqual(self.run_prepare('one').returncode, 0)
        self.assertEqual(self.run_prepare('two').returncode, 0)
        self.assertEqual(digest(self.root / 'one/p13.tar.gz'), digest(self.root / 'two/p13.tar.gz'))
        self.assertEqual((self.external / 'bystander').read_text(), 'preserve me')
        self.assertFalse((self.external / 'provider').exists())
        self.assertTrue((self.root / 'base/core').is_symlink())
        self.assertFalse((self.root / 'one/packet/core').is_symlink())
        self.assertEqual((self.root / 'one/packet/core/provider').read_text(), 'owned provider fixture')

    def test_changed_digest_and_escape_fail_before_destination_exists(self):
        bad = json.loads(json.dumps(self.spec))
        bad['entries'][0]['sha256'] = '0' * 64
        self.assertNotEqual(self.run_prepare('wrong-digest', bad).returncode, 0)
        self.assertFalse((self.root / 'wrong-digest').exists())
        bad['entries'][0]['sha256'] = self.spec['entries'][0]['sha256']
        bad['entries'][0]['destination'] = '../external/provider'
        self.assertNotEqual(self.run_prepare('escape', bad).returncode, 0)
        self.assertFalse((self.root / 'escape').exists())
        self.assertFalse((self.external / 'provider').exists())

    def test_existing_output_and_execution_authority_are_rejected(self):
        self.assertEqual(self.run_prepare('one').returncode, 0)
        before = digest(self.root / 'one/p13.tar.gz')
        self.assertNotEqual(self.run_prepare('one').returncode, 0)
        self.assertEqual(digest(self.root / 'one/p13.tar.gz'), before)
        bad = dict(self.spec, app_execution_allowed=True)
        self.assertNotEqual(self.run_prepare('launch-authority', bad).returncode, 0)
        self.assertFalse((self.root / 'launch-authority').exists())


if __name__ == '__main__':
    unittest.main()
