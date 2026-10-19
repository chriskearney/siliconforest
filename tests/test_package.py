# SPDX-License-Identifier: MIT
"""Package metadata must not grant the build user control of installed code."""
import importlib.util
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('sf_package', ROOT / 'scripts/package.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
from installer.release import Refusal


class OwnershipTests(unittest.TestCase):
    def test_payload_normalizes_files_directories_and_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            tree = root / 'payload'
            tree.mkdir()
            (tree / 'program').write_text('code')
            (tree / 'program').chmod(0o755)
            (tree / 'link').symlink_to('program')
            with tarfile.open(root / 'payload.tar', 'w') as archive:
                archive.add(tree, arcname='usr/lib/siliconforest', filter=package.root_owner)
            with tarfile.open(root / 'payload.tar') as archive:
                members = archive.getmembers()
                self.assertEqual(len(members), 3)
                for member in members:
                    self.assertEqual((member.uid, member.gid, member.uname, member.gname),
                                     (0, 0, 'root', 'root'))
                self.assertEqual(archive.getmember('usr/lib/siliconforest/program').mode, 0o755)
                self.assertEqual(archive.getmember('usr/lib/siliconforest/link').linkname, 'program')

    def test_foreign_owner_is_replaced_not_just_named_root(self):
        member = tarfile.TarInfo('program')
        member.uid, member.gid = 12345, 23456
        member.uname, member.gname = 'builder', 'builder'
        member.mode = 0o744
        package.root_owner(member)
        self.assertEqual((member.uid, member.gid), (0, 0))
        self.assertEqual(member.mode, 0o744)

    def test_repairs_are_scoped_and_preserve_modes(self):
        release = '7.2.11-siliconforest-native-gpu-test-layout1'
        self.assertEqual(package.ownership_rules('kernel', release),
                         'z /usr/share/siliconforest - root root -\n'
                         'Z /usr/lib/modules/' + release + ' - root root -\n'
                         'Z /usr/share/licenses/linux-siliconforest - root root -\n')
        self.assertEqual(package.ownership_rules('m1n1'),
                         'z /usr/share/siliconforest - root root -\n'
                         'Z /usr/lib/siliconforest - root root -\n'
                         'Z /usr/share/licenses/m1n1-siliconforest - root root -\n')
        self.assertEqual(package.ownership_rules('mesa'), '')
        with self.assertRaises(Refusal):
            package.ownership_rules('kernel', '../other-kernel')


if __name__ == '__main__':
    unittest.main()
