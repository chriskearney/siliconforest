#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
"""Host hash-guard tests. Optional acquired input is read only at test time.

Set SF_TRACKPAD_REFERENCE_HEADER to an untracked acquired reference header to
test the actual identity and every single-byte mutation. No bytes are printed.
"""
import ctypes
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


class DescriptorGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        library = Path(cls.temp.name) / "guard.so"
        subprocess.run([
            "cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wpedantic",
            "-DSF_TRACKPAD_GUARD_HOST_TEST", "-shared", "-fPIC",
            str(HERE / "descriptor_guard.c"), "-lcrypto", "-o", str(library),
        ], check=True)
        cls.guard = ctypes.CDLL(str(library)).sf_trackpad_descriptor_matches
        cls.guard.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p]
        cls.guard.restype = ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def matches(self, data, expected, length=None):
        return self.guard(ctypes.create_string_buffer(data), len(data) if length is None else length,
                          ctypes.create_string_buffer(expected))

    def check_mutations(self, data, digest):
        self.assertEqual(self.matches(data, digest), 1)
        for i in range(len(data)):
            changed = bytearray(data)
            changed[i] ^= 1
            self.assertEqual(self.matches(bytes(changed), digest), 0, i)

    def test_synthetic_digest_and_each_byte(self):
        data = bytes(range(110))
        self.check_mutations(data, hashlib.sha256(data).digest())

    def test_wrong_lengths_digest_and_null(self):
        data = bytes(range(110))
        digest = hashlib.sha256(data).digest()
        for length in (0, 1, 109, 111, 4096):
            self.assertEqual(self.matches(data, digest, length), 0)
        self.assertEqual(self.matches(data, bytes(32)), 0)
        self.assertEqual(self.guard(None, 110, ctypes.create_string_buffer(digest)), 0)
        self.assertEqual(self.guard(ctypes.create_string_buffer(data), 110, None), 0)

    @unittest.skipUnless(os.environ.get("SF_TRACKPAD_REFERENCE_HEADER"), "acquired reference not supplied")
    def test_acquired_identity_and_each_byte(self):
        text = Path(os.environ["SF_TRACKPAD_REFERENCE_HEADER"]).read_text()
        body = re.search(r"dl_m1_tp_descriptor_reference\[[^]]+\]\s*=\s*\{([^}]+)\}", text)
        self.assertIsNotNone(body)
        data = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{2})", body.group(1)))
        expected = bytes(int(x, 16) for x in re.findall(
            r"0x([0-9a-fA-F]{2})", (HERE / "trackpad_reference.h").read_text()))
        self.assertEqual(len(data), 110)
        self.assertEqual(len(expected), 32)
        self.assertEqual(hashlib.sha256(data).digest(), expected)
        self.check_mutations(data, expected)


if __name__ == "__main__":
    unittest.main()
