# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The A/B try-once boot (m1-native-boot/install/abboot/README.md): the record and decision unit
tests in C, then whole update cycles driven through the real sf-bootslot tool and a host emulation
of stage 1 v2's decision over ordinary directories standing in for SFBOOT. Host only: no device,
no disk, nothing booted. Also checks that stage 1 v1 and its build are untouched by v2."""
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / 'integrations/siliconforest/m1-native-boot/install'
AB = INSTALL / 'abboot'
STATE = 'sf/bootstate.bin'

REASON_TEXT_NOT_CONFIRMED = 'the updated system started once but never reported a clean start'
TRYING, NOT_CONFIRMED, STATE_CORRUPT, TRIAL_DAMAGED, SLOT_DAMAGED, UNVERIFIED = 1, 2, 3, 4, 5, 6


def compiler():
    cc = os.environ.get('CC') or shutil.which('cc') or shutil.which('clang') or shutil.which('gcc')
    if not cc:
        raise AssertionError('no C compiler (set CC)')
    return cc


class Built:
    tmp = None

    @classmethod
    def get(cls):
        if cls.tmp is None:
            cls.tmp = tempfile.TemporaryDirectory(prefix='sf-ab-')
            out = pathlib.Path(cls.tmp.name)
            flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-Wpedantic', '-O1', '-g',
                     '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', str(AB)]
            for name, main in (('test_sf_ab', 'test_sf_ab.c'), ('sf-bootslot', 'sf-bootslot.c'),
                               ('sf-ab-stage1', 'sf_ab_sim.c')):
                subprocess.run([compiler(), *flags, str(AB / 'sf_ab.c'), str(AB / main), '-o',
                                str(out / name)], check=True, capture_output=True, text=True)
            # stage 1's glue, sf_ab_stage1.c unchanged, against host stand-ins for m1n1 (hostmock/),
            # laid out as in m1n1: src/ with the sources and headers, build/build_cfg.h
            glue = out / 'glue'
            (glue / 'src').mkdir(parents=True)
            (glue / 'build').mkdir()
            for f in ('sf_ab.h', 'sf_ab.c', 'sf_ab_stage1.c', 'test_sf_ab_stage1.c'):
                shutil.copy(AB / f, glue / 'src' / f)
            for f in (AB / 'hostmock').glob('*.h'):
                shutil.copy(f, glue / ('build' if f.name == 'build_cfg.h' else 'src') / f.name)
            subprocess.run([compiler(), *flags[:-2], *(str(glue / 'src' / f) for f in
                            ('sf_ab.c', 'sf_ab_stage1.c', 'test_sf_ab_stage1.c')),
                            '-o', str(out / 'test_sf_ab_stage1')], check=True, capture_output=True,
                           text=True)
            cls.bin = out
        return cls.bin


def parse_kv(text):
    out = {}
    for line in text.splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            out.setdefault(k, v)
    return out


class Boot:
    """An SFBOOT directory as the installer writes it (slot A only), plus the two programs."""

    def __init__(self, test):
        self.test = test
        self.bin = Built.get()
        self._tmp = tempfile.TemporaryDirectory(prefix='sfboot-')
        test.addCleanup(self._tmp.cleanup)
        self.dir = pathlib.Path(self._tmp.name)
        self.write('sf/boot.bin', b'stage2 A ' * 1000)
        self.write('sf/kernel.bin', b'kernel A')

    def write(self, rel, data):
        p = self.dir / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)

    def flip(self, rel, offset):
        p = self.dir / rel
        b = bytearray(p.read_bytes())
        b[offset] ^= 0x40
        p.write_bytes(bytes(b))

    def tool(self, *args, running='a', expect=0):
        r = subprocess.run([str(self.bin / 'sf-bootslot'), '--boot', str(self.dir), '--running',
                            running, *args], capture_output=True, text=True)
        self.test.assertEqual(r.returncode, expect, (args, r.stdout, r.stderr))
        return parse_kv(r.stdout)

    def stage1(self, writes=False, expect=0):
        r = subprocess.run([str(self.bin / 'sf-ab-stage1'), str(self.dir),
                            *(['--stage1-writes'] if writes else [])], capture_output=True, text=True)
        self.test.assertEqual(r.returncode, expect, (r.stdout, r.stderr))
        # stage 1 logs TRYING but only puts the other reasons on screen (sf_ab_stage1.c)
        notices = [int(m) for m in re.findall(r'^notice=(\d+)', r.stdout, re.M) if int(m) != TRYING]
        booted = re.search(r'^booted=(\w+)', r.stdout, re.M).group(1)
        return booted, notices, parse_kv(r.stdout)

    def stage_b(self, data=b'stage2 B ' * 1200):
        """What SAP does: begin-stage, write slot B's files, arm."""
        self.tool('begin-stage', 'b')
        self.write('sf/b/boot.bin', data)
        self.write('sf/b/kernel.bin', b'kernel B sf_slot=b')
        return self.tool('--generation', '2', 'arm', 'b')


class Unit(unittest.TestCase):
    def test_c_unit_tests(self):
        r = subprocess.run([str(Built.get() / 'test_sf_ab')], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r'ok: 0 of \d+ checks failed')
        self.assertGreaterEqual(int(re.search(r'^1\.\.(\d+)', r.stdout, re.M).group(1)), 60)

    def test_stage1_glue(self):
        r = subprocess.run([str(Built.get() / 'test_sf_ab_stage1')], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r'ok: 0 of \d+ checks failed')

    def test_core_is_freestanding(self):
        """sf_ab.c goes into m1n1 unchanged, so it may need nothing beyond what m1n1 has."""
        with tempfile.TemporaryDirectory() as t:
            obj = pathlib.Path(t) / 'sf_ab.o'
            subprocess.run([compiler(), '-std=c11', '-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-Wall',
                            '-Wextra', '-Werror', '-O2', '-c', str(AB / 'sf_ab.c'), '-o', str(obj)],
                           check=True, capture_output=True, text=True)
            nm = shutil.which('nm')
            self.assertIsNotNone(nm, 'nm is needed')
            undef = subprocess.run([nm, '-u', str(obj)], check=True, capture_output=True,
                                   text=True).stdout.split()
            undef = {u.lstrip('_') for u in undef if u not in ('U', 'w')}
            self.assertLessEqual(undef, {'memcpy', 'memset'}, undef)
        src = (AB / 'sf_ab.c').read_text()
        self.assertEqual(sorted(set(re.findall(r'#include <([^>]+)>', src))), [])
        hdr = (AB / 'sf_ab.h').read_text()
        self.assertLessEqual(set(re.findall(r'#include <([^>]+)>', hdr)),
                             {'stdint.h', 'stddef.h', 'stdbool.h'})


class Cycles(unittest.TestCase):
    def test_fresh_install_without_a_record_is_v1(self):
        b = Boot(self)
        booted, notices, out = b.stage1()
        self.assertEqual((booted, notices), ('a', []))
        self.assertEqual(out['plan'], 'a?,b?')
        b.tool('early')
        b.tool('mark-good')
        b.tool('begin-stage', 'b', expect=1)   # SAP must init first
        self.assertFalse((b.dir / STATE).exists())

    def test_init_then_normal_starts(self):
        b = Boot(self)
        st = b.tool('init')
        self.assertEqual((st['default'], st['trial_state']), ('a', 'none'))
        self.assertEqual((b.dir / STATE).stat().st_size, 8192)
        b.tool('init', expect=1)
        for _ in range(3):
            self.assertEqual(b.stage1()[:2], ('a', []))
            b.tool('early')
            b.tool('mark-good')
        self.assertEqual(b.tool('status')['seq'], '1')      # nothing was rewritten

    def test_update_confirmed(self):
        b = Boot(self)
        b.tool('init')
        st = b.stage_b()
        self.assertEqual((st['trial'], st['trial_state']), ('b', 'armed'))
        self.assertEqual(b.stage1()[:2], ('b', []))          # TRYING is logged, not shown
        self.assertEqual(b.tool('early', running='b')['trial_state'], 'tried')
        st = b.tool('mark-good', running='b')
        self.assertEqual((st['default'], st['trial'], st['trial_state']), ('b', '-', 'none'))
        booted, notices, out = b.stage1()
        self.assertEqual((booted, notices, out['plan']), ('b', [], 'b,a,b?'))
        # the next update goes into A, now the inactive slot
        b.tool('begin-stage', 'a', running='b')
        b.write('sf/boot.bin', b'stage2 A2 ' * 900)
        b.tool('arm', 'a', running='b')
        self.assertEqual(b.stage1()[:2], ('a', []))
        b.tool('early')
        self.assertEqual(b.tool('mark-good')['default'], 'a')

    def test_update_never_confirmed_falls_back(self):
        b = Boot(self)
        b.tool('init')
        b.stage_b()
        self.assertEqual(b.stage1()[0], 'b')
        b.tool('early', running='b')
        # B hangs or panics before mark-good; the next start
        self.assertEqual(b.stage1()[:2], ('a', [NOT_CONFIRMED]))
        st = b.tool('early', running='a')
        self.assertEqual(st['trial_state'], 'failed')
        self.assertEqual(st['reason'], REASON_TEXT_NOT_CONFIRMED)
        self.assertEqual(b.stage1()[:2], ('a', []))           # shown once, then quiet
        b.tool('mark-good', running='b', expect=1)
        b.tool('begin-stage', 'b')                           # SAP may try again
        self.assertEqual(b.tool('status')['trial_state'], 'none')

    def test_damaged_or_missing_trial(self):
        for damage in ('flip', 'truncate', 'delete'):
            with self.subTest(damage=damage):
                b = Boot(self)
                b.tool('init')
                b.stage_b()
                p = b.dir / 'sf/b/boot.bin'
                if damage == 'flip':
                    b.flip('sf/b/boot.bin', 100)
                elif damage == 'truncate':
                    p.write_bytes(p.read_bytes()[:-1])
                else:
                    p.unlink()
                self.assertEqual(b.stage1()[:2], ('a', [TRIAL_DAMAGED]))
                st = b.tool('early')
                self.assertEqual(st['trial_state'], 'failed')

    def test_torn_record_write_keeps_the_previous_state(self):
        b = Boot(self)
        b.tool('init')
        b.stage_b()
        status = b.tool('status')
        seq = int(status['seq'])
        # the arm write landed in copy (seq % 2); tear it
        data = bytearray((b.dir / STATE).read_bytes())
        newest = next(o for o in (0, 4096) if int.from_bytes(data[o + 12:o + 16], 'little') == seq)
        data[newest + 30] ^= 1
        (b.dir / STATE).write_bytes(bytes(data))
        st = b.tool('status')
        self.assertEqual((int(st['seq']), st['trial_state']), (seq - 1, 'none'))
        self.assertEqual(b.stage1()[:2], ('a', []))

    def test_both_copies_corrupt(self):
        b = Boot(self)
        b.tool('init')
        b.flip(STATE, 3)
        b.flip(STATE, 4096 + 3)
        self.assertEqual(b.stage1()[:2], ('a', [STATE_CORRUPT]))
        b.tool('early', expect=2)                           # the tool refuses to guess
        (b.dir / 'sf/boot.bin').unlink()
        b.write('sf/b/boot.bin', b'stage2 B')
        self.assertEqual(b.stage1()[:2], ('b', [STATE_CORRUPT, SLOT_DAMAGED]))

    def test_default_damaged_other_slot_good(self):
        b = Boot(self)
        b.tool('init')
        b.stage_b()
        b.stage1()
        b.tool('early', running='b')
        b.tool('mark-good', running='b')                    # default B, A still good
        b.flip('sf/b/boot.bin', 7)
        booted, notices, _ = b.stage1()
        self.assertEqual((booted, notices), ('a', [SLOT_DAMAGED]))

    def test_everything_damaged_last_resort(self):
        b = Boot(self)
        b.tool('init')
        b.write('sf/boot.bin', b'replaced outside the protocol')
        booted, notices, out = b.stage1()
        self.assertEqual((booted, notices, out['plan']), ('a', [UNVERIFIED], 'a,a?'))
        (b.dir / 'sf/boot.bin').unlink()
        self.assertEqual(b.stage1(expect=1)[0], 'none')

    def test_refusals_write_nothing(self):
        b = Boot(self)
        b.tool('init')
        before = (b.dir / STATE).read_bytes()
        b.tool('begin-stage', 'a', expect=1)                 # the running/default slot
        b.tool('arm', 'b', expect=2)                         # nothing staged in B
        b.tool('mark-good', running='b', expect=1)
        self.assertEqual((b.dir / STATE).read_bytes(), before)
        b.stage_b()
        armed = (b.dir / STATE).read_bytes()
        b.tool('begin-stage', 'b', expect=1)                 # while armed
        b.tool('arm', 'b', expect=1)
        self.assertEqual((b.dir / STATE).read_bytes(), armed)

    def test_the_v2_gap_and_a_writing_stage1(self):
        """v2 cannot write: a trial that dies before 'early' runs is started again (README, gap).
        A stage 1 that stores the plan's writeback (v3) closes it."""
        b = Boot(self)
        b.tool('init')
        b.stage_b()
        self.assertEqual(b.stage1()[0], 'b')
        self.assertEqual(b.stage1()[:2], ('b', []))          # the gap, as documented
        c = Boot(self)
        c.tool('init')
        c.stage_b()
        booted, _, out = c.stage1(writes=True)
        self.assertEqual((booted, out.get('stage1_wrote')), ('b', 'tried'))
        self.assertEqual(c.stage1(writes=True)[:2], ('a', [NOT_CONFIRMED]))


class Packaging(unittest.TestCase):
    def test_v1_is_untouched(self):
        top = sorted(p.name for p in (INSTALL / 'patches').glob('*.patch'))
        self.assertEqual(top, ['0001-m1n1-installed-SiliconForest-stops-instead-of-proxy-or-restart.patch'])
        v1 = (ROOT / 'installer/payload/boot/build_stage1.sh').read_text()
        self.assertIn('-siliconforest-stage1-v1', v1)
        self.assertNotIn('stage1-v2', v1)
        self.assertNotIn('SF_AB_BOOT', v1)

    def test_v2_patch_and_build(self):
        patches = sorted((INSTALL / 'patches/stage1-v2').glob('*.patch'))
        self.assertEqual([p.name[:5] for p in patches], ['0002-'])
        text = patches[0].read_text()
        files = sorted(set(re.findall(r'^\+\+\+ b/(\S+)', text, re.M)))
        self.assertEqual(files, ['Makefile', 'src/chainload.c', 'src/chainload.h', 'src/payload.c'])
        for needle in ('SF_AB_BOOT', 'sf_ab_stage1_chainload', 'chainload_load_slot'):
            self.assertIn(needle, text)
        sh = (AB / 'build_stage1_v2.sh').read_text()
        self.assertIn('-siliconforest-stage1-v2', sh)
        self.assertIn('SF_AB_BOOT=1', sh)
        self.assertRegex(sh, r'STAGE1_V2_SHA256=[0-9a-f]{64}')
        self.assertNotIn('44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318',
                         re.search(r'STAGE1_V2_SHA256=(\w+)', sh).group(1))
        readme = (AB / 'README.md').read_text()
        self.assertIn(re.search(r'STAGE1_V2_SHA256=(\w+)', sh).group(1), readme)


if __name__ == '__main__':
    unittest.main()
