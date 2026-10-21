# SPDX-License-Identifier: MIT
"""Neo candidate metadata cannot silently become a public installer admission."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('neo_builder', ROOT / 'scripts/build-neo-m1n1.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class CandidateTests(unittest.TestCase):
    def evaluate(self, transform=None, corrupt_hash=False):
        profile = json.loads((ROOT / 'release/neo-candidate.json').read_text())
        lock = json.loads((ROOT / 'sources.lock.json').read_text())
        if transform:
            transform(profile, lock)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'release').mkdir()
            path = root / 'release/neo-candidate.json'
            path.write_text(json.dumps(profile))
            lock['inputs']['release/neo-candidate.json'] = (
                '0' * 64 if corrupt_hash else hashlib.sha256(path.read_bytes()).hexdigest())
            with patch.object(builder, 'ROOT', root), patch.object(builder, 'read_lock', return_value=lock):
                return builder.load_candidate()

    def test_unqualified_source_profile_is_accepted(self):
        profile = self.evaluate()
        self.assertIs(profile['public_installable'], False)
        self.assertIs(profile['hardware_qualified'], False)

    def test_qualification_or_missing_explicit_limit_is_refused(self):
        for field in ('public_installable', 'hardware_qualified'):
            with self.subTest(field=field):
                with self.assertRaisesRegex(ValueError, 'unqualified source-candidate'):
                    self.evaluate(lambda p, l: p.__setitem__(field, True))
                with self.assertRaisesRegex(ValueError, 'unqualified source-candidate'):
                    self.evaluate(lambda p, l: p.pop(field))

    def test_profile_hash_is_checked(self):
        with self.assertRaisesRegex(ValueError, 'differs from source lock'):
            self.evaluate(corrupt_hash=True)

    def test_neo_pin_desynchronization_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'source lock disagree'):
            self.evaluate(lambda p, l: p['sources']['m1n1'].__setitem__('commit', '0' * 40))

    def test_kernel_and_mesa_pairing_desynchronization_is_refused(self):
        for name in ('linux', 'mesa'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'pairing differs'):
                self.evaluate(lambda p, l: p['sources'][name].__setitem__('commit', '0' * 40))

    def test_pairing_must_be_explicit(self):
        with self.assertRaisesRegex(ValueError, 'explicit source lock'):
            self.evaluate(lambda p, l: l['m1n1_profiles'][0].pop('paired_sources'))

    def test_pairing_requires_the_maintained_repository_and_full_commit(self):
        for field, value in (('url', 'https://github.com/unrelated/linux.git'),
                             ('commit', 'short')):
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'invalid repository or commit'):
                self.evaluate(lambda p, l: l['m1n1_profiles'][0]['paired_sources']['linux'].__setitem__(field, value))

    def test_main_stack_can_advance_without_retargeting_neo(self):
        expected = self.evaluate()['sources']['linux']['commit']
        profile = self.evaluate(lambda p, l: l['sources']['linux'].__setitem__('commit', '1' * 40))
        self.assertEqual(profile['sources']['linux']['commit'], expected)


if __name__ == '__main__':
    unittest.main()
