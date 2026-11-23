#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host tests of the board-aware keyboard guard (J293, J313). Synthetic tables, no hardware.

The frozen guard in ../../m1-keyboard is compiled alongside as the reference for J293.
SF_J293_ADT and SF_J313_ADT may name decoded device trees from Apple's public 13.5 restore
image; those two tests are skipped without them, and such files are never committed.
"""
import ctypes as C
import importlib.util
import os
import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
KB = HERE.parents[1] / 'm1-keyboard'
spec = importlib.util.spec_from_file_location('m1kbd_frozen_test', KB / 'test_adapter.py')
frozen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frozen)

J293 = 0x4a323933
J313 = 0x4a333133
IDENTITY = {('/', 'target-type'), ('/', 'compatible')}


def j313_fixture():
    """The J293 table with J313's identity and the phandles of Apple's J313 tree."""
    remap = {0x70: 0x63, 0x77: 0x6a, 0x79: 0x6c}
    p = frozen.fixture()
    p['/', 'target-type'] = b'J313\0'
    p['/', 'compatible'] = b'J313AP\0MacBookAir10,1\0AppleARM\0'
    for key in [('/arm-io/gpio', 'AAPL,phandle'), ('/arm-io/nub-gpio', 'AAPL,phandle'),
                ('/arm-io/aic', 'AAPL,phandle'), ('/arm-io/spi3', 'interrupt-parent'),
                ('/arm-io/spi3/ipd', 'interrupt-parent'), ('/arm-io/spi3', 'function-spi_cs0'),
                ('/arm-io/spi3/ipd', 'function-enable_cs'), ('/arm-io/spi3/ipd', 'function-spi_en')]:
        v = bytearray(p[key])
        v[:4] = struct.pack('<I', remap[struct.unpack_from('<I', v)[0]])
        p[key] = bytes(v)
    return p


def load_adt(path):
    b = pathlib.Path(path).read_bytes()
    props = {}

    def node(o, parent=None):
        n, c = struct.unpack_from('<II', b, o)
        o += 8
        d = {}
        for _ in range(n):
            name = b[o:o+32].split(b'\0', 1)[0].decode('latin1')
            size = struct.unpack_from('<I', b, o+32)[0] & 0x7fffffff
            o += 36
            d[name] = b[o:o+size]
            o += (size+3) & ~3
        here = '/' if parent is None else parent.rstrip('/') + '/' + d['name'].split(b'\0', 1)[0].decode('latin1')
        props.update({(here, k): v for k, v in d.items()})
        for _ in range(c):
            o = node(o, here)
        return o
    node(0)
    return props


def raw(board):
    return bytes(C.string_at(C.byref(board), C.sizeof(board)))


class Boards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cc = shutil.which('clang') or shutil.which('cc')
        if not cc:
            raise unittest.SkipTest('no C compiler')
        cls.tmp = tempfile.TemporaryDirectory(prefix='m1kbd-boards-')
        out = pathlib.Path(cls.tmp.name)
        flags = [cc, '-std=c11', '-O1', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC']
        subprocess.run(flags + ['-I', str(HERE), '-I', str(KB), '-o', str(out/'new.so'),
                                str(HERE/'m1kbd_board.c'), str(HERE/'m1kbd_pio.c'), str(HERE/'m1kbd_hid.c'),
                                str(KB/'native_protocol/dl_spi_hid.c')], check=True)
        subprocess.run(flags + ['-I', str(KB), '-o', str(out/'frozen.so'), str(KB/'m1kbd_board.c')], check=True)
        cls.new = C.CDLL(str(out/'new.so'))
        cls.old = C.CDLL(str(out/'frozen.so'))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_each_board_is_accepted_with_its_own_tag(self):
        for table, tag in ((frozen.fixture(), J293), (j313_fixture(), J313)):
            rc, board = frozen.validate(self.new, table)
            self.assertEqual((rc, board.qualified), (0, tag))
            self.assertEqual(list(board.base), [0x23510c000, 0x23c100000, 0x23d1f0000, 0x23b700000, 0x23d280000])
            self.assertEqual((board.clock_hz, board.speed_hz), (120000000, 8000000))

    def test_identity_strings_must_name_one_known_board(self):
        for target, compatible in [(b'J293\0', b'J313AP\0MacBookAir10,1\0AppleARM\0'),
                                   (b'J313\0', b'J293AP\0MacBookPro17,1\0AppleARM\0'),
                                   (b'J314\0', b'J314AP\0MacBookPro18,3\0AppleARM\0'),
                                   (b'J313', b'J313AP\0MacBookAir10,1\0AppleARM\0'),
                                   (b'J313\0', b'J313AP\0MacBookAir10,1\0AppleARM'),
                                   (b'J313\0', b'J313AP\0MacBookAir10,2\0AppleARM\0'),
                                   (b'J313\0', b'J313AP\0MacBookAir10,1\0AppleARM\0\0'),
                                   (b'', b'')]:
            with self.subTest(target=target, compatible=compatible):
                p = j313_fixture()
                p['/', 'target-type'] = target
                p['/', 'compatible'] = compatible
                rc, board = frozen.validate(self.new, p)
                self.assertEqual((rc, board.qualified), (-2, 0))

    def test_j293_matches_the_frozen_guard_under_every_change(self):
        base = frozen.fixture()
        cases = [('intact', base)]
        for key, value in base.items():
            cases.append((f'drop {key}', {k: v for k, v in base.items() if k != key}))
            if value:
                cases.append((f'short {key}', {**base, key: value[:-1]}))
                flipped = bytearray(value)
                flipped[0] ^= 1
                cases.append((f'flip {key}', {**base, key: bytes(flipped)}))
            cases.append((f'long {key}', {**base, key: value + b'\0'}))
        for name, table in cases:
            with self.subTest(name):
                a, b = frozen.validate(self.old, table), frozen.validate(self.new, table)
                self.assertEqual(a[0], b[0])
                self.assertEqual(raw(a[1]), raw(b[1]))

    def test_j313_keeps_every_other_check(self):
        base = j313_fixture()
        for key, value in base.items():
            if key in IDENTITY:
                continue
            for name, table in (('drop', {k: v for k, v in base.items() if k != key}),
                                ('short', {**base, key: value[:-1]}),
                                ('long', {**base, key: value + b'\0'})):
                with self.subTest(name, key=key):
                    self.assertEqual(frozen.validate(self.new, table)[0], -2)

    def test_transport_takes_only_accepted_tags(self):
        for tag, want in ((J293, 0), (J313, 0), (0, -2), (0x4a333134, -2)):
            with self.subTest(tag=hex(tag)):
                _, board = frozen.validate(self.new, frozen.fixture())
                board.qualified = tag
                fake = frozen.Fake()
                hw = frozen.HW()
                self.assertEqual(self.new.m1kbd_hw_init(C.byref(hw), C.byref(board), C.byref(fake.io)), want)

    def device_info(self, vendor, product, expected):
        class Identity(C.Structure):
            _fields_ = [('vendor', C.c_uint16), ('product', C.c_uint16), ('version', C.c_uint16),
                        ('max_input', C.c_uint16), ('country', C.c_uint8)]
        payload = struct.pack('<12H', 0, 0, 3, vendor, product, 0x77, 0, 0, 0, 0, 0, 0)
        out = Identity(product=0xbeef)
        rc = self.new.m1kbd_device_info(payload, C.c_size_t(len(payload)), C.c_uint16(expected), C.byref(out))
        return rc, out.product

    def test_product_is_bound_to_the_board(self):
        self.assertEqual(self.device_info(0x05ac, 0x0341, 0x0341), (0, 0x0341))
        self.assertEqual(self.device_info(0x05ac, 0x0281, 0x0281), (0, 0x0281))
        for product, expected in ((0x0281, 0x0341), (0x0341, 0x0281), (0x0341, 0), (0, 0)):
            with self.subTest(product=product, expected=expected):
                self.assertEqual(self.device_info(0x05ac, product, expected), (-5, 0xbeef))
        self.assertEqual(self.device_info(0x05ad, 0x0281, 0x0281), (-4, 0xbeef))

    def test_apple_public_device_trees(self):
        paths = os.environ.get('SF_J293_ADT'), os.environ.get('SF_J313_ADT')
        if not all(paths):
            self.skipTest('SF_J293_ADT and SF_J313_ADT not set')
        for path, tag in zip(paths, (J293, J313)):
            rc, board = frozen.validate(self.new, load_adt(path))
            self.assertEqual((rc, board.qualified), (0, tag))
        self.assertEqual(frozen.validate(self.old, load_adt(paths[1]))[0], -2)


if __name__ == '__main__':
    unittest.main()
