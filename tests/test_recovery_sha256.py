"""Exercise the same Go checksum source on the host; no macOS claim."""
import hashlib
import os
from pathlib import Path
import random
import subprocess
import tempfile
import unittest

TOOL=Path(os.environ.get('SF_SHA256_TEST_BINARY',str(Path(__file__).resolve().parents[1]/'build/recovery-tools/sf-sha256-host')))

class ChecksumTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(TOOL.is_file(),'Build scripts/build-recovery-tools.sh first')
        self.tmp=tempfile.TemporaryDirectory(prefix='sf-sha-tests-')
        self.root=Path(self.tmp.name)
    def tearDown(self):
        self.tmp.cleanup()
    def call(self,*args):
        return subprocess.run([str(TOOL),*map(str,args)],capture_output=True,text=True,timeout=5)
    def test_known_answer_self_test(self):
        r=self.call('--self-test');self.assertEqual(r.returncode,0);self.assertEqual(r.stdout,'SHA-256 self-test PASS\n')
    def test_file_vectors_and_block_boundaries(self):
        rng=random.Random(176105)
        for size in [0,1,55,56,63,64,65,127,128,129,4096,32767,32768,32769,1000000,4194304]:
            with self.subTest(size=size):
                raw=rng.randbytes(size);p=self.root/'image with spaces.bin';p.write_bytes(raw);r=self.call(p);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(r.stdout,hashlib.sha256(raw).hexdigest()+'\n');self.assertEqual(p.read_bytes(),raw)
    def test_missing_file(self):
        r=self.call(self.root/'missing');self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,'')
    def test_directory(self):
        r=self.call(self.root);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,'')
    def test_symlink(self):
        p=self.root/'file';p.write_bytes(b'abc');link=self.root/'link';link.symlink_to(p);r=self.call(link);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,'')
    def test_fifo_does_not_block(self):
        p=self.root/'fifo';os.mkfifo(p);r=self.call(p);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,'')
    def test_argument_validation(self):
        for args in [[],['a','b']]:
            r=self.call(*args);self.assertNotEqual(r.returncode,0);self.assertEqual(r.stdout,'')
