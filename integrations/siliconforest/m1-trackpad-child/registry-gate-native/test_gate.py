#!/usr/bin/env python3
"""Host-only fake operations and independent decoder checks; no hardware."""
import ctypes
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location("native_gate_decoder", HERE / "decode_records.py")
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)
NONCE = "0123456789abcdef" * 3

def good_record(descriptor):
    r = bytearray(704)
    for off, value in {0: 1, 4: 704, 28: 1, 32: 2, 36: 1, 44: 1, 48: 1, 52: 1,
                       **{x: 1 for x in range(56, 80, 4)}, 528: 110, 532: 4,
                       536: 32, 540: 1, 544: 1, 658: 2, 662: 1, 666: 32, 670: 1,
                       674: 1}.items():
        struct.pack_into("<I", r, off, value)
    for off, value in {80: 0x100000007, 88: 0x200000007, 96: 0x100000007,
                       488: 0x100000007, 496: 0x200000007, 512: 0x100000007}.items():
        struct.pack_into("<Q", r, off, value)
    for off, name in ((104, b"SFM1SPIHID"), (232, b"SFM1SPITrackpad")):
        r[off:off+len(name)] = name
    r[548:658] = descriptor
    return r

def encoded(r, nonce=NONCE):
    result = struct.unpack_from("<I", r, 8)[0]
    summary = dict(event="DL16_GATE", nonce=nonce, result=result,
                   reason=decoder.u32(r, 12), detail=struct.unpack_from("<i", r, 16)[0],
                   query_errors=decoder.u32(r, 20), release_errors=decoder.u32(r, 24),
                   hid_count=decoder.u32(r, 32), physical_input_proven=False,
                   device_opened=False, non_atomic_observation=True)
    lines = [f"DL16_GATE_BEGIN_{nonce} bytes=704 physical_input_proven=false device_opened=false",
             json.dumps(summary, separators=(",", ":"))]
    lines += [f"DL16_GATE_HEX_{nonce} index={i} {r[i*64:(i+1)*64].hex()}" for i in range(11)]
    lines += [f"DL16_GATE_END_{nonce} chunks=11 bytes=704 sha256={hashlib.sha256(r).hexdigest()} result={result}"]
    return ("\n".join(lines) + "\n").encode()

class GateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="darwin-native-gate-")
        cls.out = Path(cls.temp.name)
        cls.flags = ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wpedantic", "-O1", "-I", str(HERE), "-I", str(HERE.parent), "-DSF_TRACKPAD_GUARD_HOST_TEST", "-Wl,--no-as-needed", "-lcrypto", str(HERE.parent / "descriptor_guard.c")]
        subprocess.run(cls.flags + ["-shared", "-fPIC", str(HERE / "gate.c"), "-o", str(cls.out / "gate.so")], check=True)
        cls.lib = ctypes.CDLL(str(cls.out / "gate.so"))
        cls.lib.ng_classify.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        cls.lib.ng_classify.restype = ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_owned_rpc_failure_sweep_sanitized(self):
        binary = self.out / "test-gate"
        subprocess.run(self.flags + ["-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                                    str(HERE / "gate.c"), str(HERE / "test_gate.c"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True, env={**os.environ, "ASAN_OPTIONS": "detect_leaks=1"})

    def test_assertions_required(self):
        p = subprocess.run([f for f in self.flags if f != str(HERE.parent / "descriptor_guard.c")] + ["-DNDEBUG", "-c", str(HERE / "test_gate.c"), "-o", str(self.out / "ndebug.o")], capture_output=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn(b"assertion-based host tests require assertions", p.stderr)

    def test_independent_classifier_differential(self):
        descriptor = bytes(range(110))
        digest = hashlib.sha256(descriptor).hexdigest()
        good = good_record(descriptor)
        rng = random.Random(0xD116)
        for i in range(30000):
            r = good.copy()
            if i:
                for _ in range(rng.randrange(1, 4)):
                    off = rng.randrange(704)
                    r[off] = rng.randrange(256)
            expected = decoder.classify(bytes(r), digest)
            actual = self.lib.ng_classify(ctypes.create_string_buffer(bytes(r)), ctypes.create_string_buffer(hashlib.sha256(descriptor).digest()))
            self.assertEqual(actual, expected, (i, r.hex()))

    def test_mutants_are_assertion_killed(self):
        source = (HERE / "gate.c").read_text()
        mutants = {
            "release-errors": ("if(kr) { ng_put32(r+NG_RELEASE_ERRORS", "if(0) { ng_put32(r+NG_RELEASE_ERRORS"),
            "invalid-iterator": ("if(v!=1)", "if(0)"),
            "descriptor": ("!sf_trackpad_descriptor_matches(r+NG_DESCRIPTOR,110,descriptor_digest)", "descriptor_digest == NULL"),
            "identity-high32": ("return ng_u32(p) | (uint64_t)ng_u32(p+4)<<32;", "return ng_u32(p);"),
            "nonready": ("if(!commit||!route||fault||stop||error||!ng_u32(r+NG_KBD_NODE)||!ng_u32(r+NG_MOUSE_NODE)) return 77;", "if(!ng_u32(r+NG_KBD_NODE)||!ng_u32(r+NG_MOUSE_NODE)) return 77;"),
        }
        for name, (old, new) in mutants.items():
            self.assertEqual(source.count(old), 1, name)
            modified = self.out / f"{name}.c"
            modified.write_text(source.replace(old, new))
            binary = self.out / name
            subprocess.run(self.flags + [str(modified), str(HERE / "test_gate.c"), "-o", str(binary)], check=True)
            p = subprocess.run([str(binary)], capture_output=True, cwd=self.out)
            self.assertNotEqual(p.returncode, 0, name)
            self.assertIn(b"Assertion", p.stderr, (name, p.stderr))

    def test_real_descriptor_framing_and_negatives(self):
        path = ROOT / "runs/m1-desktop-010/trackpad-enum-attempt-002/decoded-trackpad/descriptor.bin"
        if not path.is_file():
            self.skipTest("private acquired descriptor required for actual-digest export tests")
        descriptor = path.read_bytes()
        self.assertEqual(hashlib.sha256(descriptor).hexdigest(), decoder.DESCRIPTOR_SHA256)
        record = good_record(descriptor)
        raw = encoded(record)
        self.assertEqual(decoder.decode(raw, NONCE)["summary"]["result"], 0)
        for off, value, result in ((540, 0, 77), (674, 0, 77), (678, 2, 1), (532, 3, 1), (24, 1, 1)):
            changed = record.copy()
            struct.pack_into("<I", changed, off, value)
            struct.pack_into("<I", changed, 8, result)
            self.assertEqual(decoder.decode(encoded(changed), NONCE)["summary"]["result"], result)
        negatives = [raw + raw, raw[:-50], raw.replace(b"index=1 ", b"index=0 "),
                     raw.replace(b'"result":0', b'"result":true'),
                     raw.replace(b'"result":0', b'"result":0,"result":0'),
                     raw.replace(b"index=0 ", b"warning\nindex=0 "),
                     raw.replace(b"sha256=", b"sha256=0"),
                     raw.replace(b"physical_input_proven=false", b"physical_input_proven=true")]
        for item in negatives:
            with self.assertRaises((ValueError, KeyError, json.JSONDecodeError)):
                decoder.decode(item, NONCE)
        with self.assertRaises(ValueError):
            decoder.decode(raw, "a" * 48)

if __name__ == "__main__":
    unittest.main(verbosity=2)
