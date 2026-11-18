# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The SiliconForest installer (install.sh, install/engine) without a Mac and without a disk.

Planning is tested against recorded diskutil outputs: install/tests/fixtures/m1-* are SYNTHETIC
(made by install/tests/make_fixtures.py from the FakeMac model), real-m5-scrubbed is a scrubbed
recording from a real Mac that the installer must refuse. The whole install, uninstall and
update are driven end to end through the gate against FakeMac, with SimulatedAsahi issuing the
commands the Asahi installer issues. Nothing here touches a real device.
"""
import contextlib
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'install' / 'engine'), str(ROOT / 'install' / 'tests')]
import fakemac  # noqa: E402
import make_fixtures  # noqa: E402
import sf_disk  # noqa: E402
import sf_engine  # noqa: E402
import sf_fwslot  # noqa: E402
import sf_gate  # noqa: E402
import sf_kernelcfg  # noqa: E402
import sf_manifest  # noqa: E402
import sf_plan  # noqa: E402

FIX = ROOT / 'install' / 'tests' / 'fixtures'
MODELS = sf_plan.load_models((ROOT / 'install' / 'models.tsv').read_text())
GB = 1_000_000_000


def facts(name):
    return sf_plan.gather(make_fixtures.Replay(FIX / name))


def codes(findings):
    return {x.code for x in findings}


class Models(unittest.TestCase):
    def test_table_has_exactly_the_one_supported_board(self):
        self.assertEqual([t for t, m in MODELS.items() if m.status == 'supported'], ['J293'])
        m = MODELS['J293']
        self.assertEqual((m.hw_model, m.device_class, m.chip, m.stub_firmware), ('MacBookPro17,1', 'j293ap', 'T8103', ['13.5']))


class Fixtures(unittest.TestCase):
    def test_synthetic_fixtures_are_current(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(make_fixtures.main(['--check']), 0, out.getvalue())

    def test_fakemac_speaks_like_the_real_recording(self):
        """Every key and type sf_disk reads exists, with the same type, in the real (scrubbed) output."""
        import plistlib
        real = {n: plistlib.loads((FIX / 'real-m5-scrubbed' / n).read_bytes()) for n in ('list.plist', 'apfs.plist', 'info-disk0s2.plist', 'info-disk0.plist', 'info-root.plist', 'limits-disk3.plist')}
        fake = {n: plistlib.loads((FIX / 'm1-stock' / m).read_bytes()) for n, m in (('list.plist', 'list.plist'), ('apfs.plist', 'apfs.plist'), ('info-disk0s2.plist', 'info-disk0s2.plist'),
                                                                                     ('info-disk0.plist', 'info-disk0.plist'), ('info-root.plist', 'info-root.plist'), ('limits-disk3.plist', 'limits-disk0s2.plist'))}
        checks = [('list.plist', lambda d: d['AllDisksAndPartitions'][0], ('DeviceIdentifier', 'Content', 'Partitions', 'Size')),
                  ('list.plist', lambda d: d['AllDisksAndPartitions'][0]['Partitions'][0], ('DeviceIdentifier', 'Content', 'Size')),
                  ('apfs.plist', lambda d: d['Containers'][0], ('ContainerReference', 'DesignatedPhysicalStore', 'CapacityCeiling', 'CapacityFree', 'Volumes')),
                  ('apfs.plist', lambda d: d['Containers'][0]['Volumes'][0], ('DeviceIdentifier', 'Name', 'Roles', 'FileVault', 'Locked')),
                  ('info-disk0s2.plist', lambda d: d, ('PartitionMapPartitionOffset', 'Size', 'Content', 'DiskUUID', 'APFSContainerReference', 'DeviceBlockSize')),
                  ('info-disk0.plist', lambda d: d, ('Internal', 'DeviceBlockSize', 'Size', 'Content')),
                  ('info-root.plist', lambda d: d, ('APFSContainerReference',)),
                  ('limits-disk3.plist', lambda d: d, ('MinimumSizePreferred', 'CurrentSize'))]
        for name, pick, keys in checks:
            for k in keys:
                self.assertIn(k, pick(real[name]), (name, k))
                self.assertIs(type(pick(fake[name])[k]), type(pick(real[name])[k]), (name, k))

    def test_real_recording_parses(self):
        f = facts('real-m5-scrubbed')
        self.assertIsNone(f.layout_error or None)
        mac = f.layout.macos_part()
        self.assertEqual((mac.dev, mac.container.ref), ('disk0s2', 'disk3'))
        self.assertEqual(f.layout.gaps(), [])
        self.assertIsNone(f.layout.find_ours())
        self.assertEqual(len(f.layout.real_parts()), 3)


class Checks(unittest.TestCase):
    def test_wrong_model_is_refused(self):
        f = facts('real-m5-scrubbed')
        with self.assertRaises(sf_plan.Refusal) as e:
            sf_plan.plan_install(f, MODELS)
        self.assertIn('model', codes(e.exception.findings))
        self.assertIn('J704', e.exception.findings[0].text)

    def test_macos_range(self):
        for version, code in (('13.4', 'macos-old'), ('12.7.6', 'macos-old'), ('27.0', 'macos-new')):
            f = sf_plan.gather(fakemac.FakeMac(macos=version))
            self.assertIn(code, codes(sf_plan.refusals(sf_plan.check(f, MODELS))), version)
        for version in ('13.5', '14.7', '26.5.2'):
            f = sf_plan.gather(fakemac.FakeMac(macos=version))
            self.assertEqual(sf_plan.refusals(sf_plan.check(f, MODELS)), [], version)

    def test_people_and_power(self):
        self.assertIn('console', codes(sf_plan.check(sf_plan.gather(fakemac.FakeMac(console='root')), MODELS)))
        self.assertIn('admin', codes(sf_plan.refusals(sf_plan.check(sf_plan.gather(fakemac.FakeMac(admin=False)), MODELS))))
        self.assertIn('rosetta', codes(sf_plan.refusals(sf_plan.check(sf_plan.gather(fakemac.FakeMac(translated=True)), MODELS))))
        warn = [x for x in sf_plan.check(sf_plan.gather(fakemac.FakeMac(on_ac=False)), MODELS) if x.code == 'battery']
        self.assertEqual([x.level for x in warn], ['warn'])

    def test_filevault(self):
        on = sf_plan.check(facts('m1-filevault-on'), MODELS)
        self.assertIn('filevault', codes(on))
        self.assertEqual(sf_plan.refusals(on), [])
        busy = sf_plan.gather(fakemac.FakeMac(filevault='Encryption in progress: Percent completed = 41'))
        self.assertIn('filevault-busy', codes(sf_plan.refusals(sf_plan.check(busy, MODELS))))

    def test_release_narrows_the_models(self):
        with tempfile.TemporaryDirectory() as tmp:
            m, _, _ = fakemac.make_release(tmp)
            m['models'] = ['J293']
            self.assertEqual(sf_plan.refusals(sf_plan.check(facts('m1-stock'), MODELS, m)), [])
            m2 = dict(m, macos=dict(min='14.0', max_major=26))
            self.assertIn('macos-old', codes(sf_plan.check(sf_plan.gather(fakemac.FakeMac(macos='13.6')), MODELS, m2)))


class Plans(unittest.TestCase):
    def test_stock_shrinks_macos_and_keeps_its_free_space(self):
        f = facts('m1-stock')
        p = sf_plan.plan_install(f, MODELS)
        r = p['resize']
        mac = f.layout.macos_part()
        self.assertEqual(r['store'], 'disk0s2')
        self.assertEqual(r['from_bytes'] - r['to_bytes'], r['shrink_bytes'])
        self.assertEqual(r['shrink_bytes'] % (1 << 20), 0)
        self.assertGreaterEqual(p['macos_free_after'], sf_plan.MIN_FREE_MACOS)
        self.assertEqual(p['total_bytes'], sf_plan.STUB_BYTES + sf_plan.BOOT_BYTES + p['root_bytes'])
        self.assertEqual(p['gap_offset'], mac.offset + r['to_bytes'])
        self.assertTrue(p['provisional_sizes'])
        self.assertTrue(any('Shrink the macOS container' in l for l in p['changes']))

    def test_size_request(self):
        f = facts('m1-stock')
        p = sf_plan.plan_install(f, MODELS, total=100 * GB)
        self.assertLessEqual(p['total_bytes'], 100 * GB)
        self.assertGreater(p['total_bytes'], 99 * GB)
        with self.assertRaises(sf_plan.Refusal) as e:
            sf_plan.plan_install(f, MODELS, total=10 * GB)
        self.assertEqual(codes(e.exception.findings), {'size'})
        with self.assertRaises(sf_plan.Refusal) as e:
            sf_plan.plan_install(f, MODELS, total=400 * GB)
        self.assertEqual(codes(e.exception.findings), {'space'})

    def test_too_little_space_says_how_much_is_possible(self):
        with self.assertRaises(sf_plan.Refusal) as e:
            sf_plan.plan_install(facts('m1-too-little-space'), MODELS)
        self.assertIn('At most', e.exception.findings[-1].text)

    def test_snapshot_overhead_warns(self):
        f = sf_plan.gather(fakemac.FakeMac(snapshots=6, snapshot_overhead=60 * GB))
        p = sf_plan.plan_install(f, MODELS)
        self.assertIn('overhead', {x['code'] for x in p['findings']})
        self.assertGreaterEqual(p['resize']['to_bytes'], p['resize']['min_bytes'])

    def test_asahi_with_free_space_is_left_alone(self):
        f = facts('m1-asahi')
        p = sf_plan.plan_install(f, MODELS)
        self.assertIsNone(p['resize'])
        self.assertEqual(p['after'], 'disk0s6')
        others = [x for x in p['findings'] if x['code'] == 'others']
        self.assertTrue(others and 'Asahi Linux' in others[0]['text'])

    def test_asahi_without_free_space_shrinks_macos_in_front_of_it(self):
        p = sf_plan.plan_install(facts('m1-asahi-no-free-space'), MODELS)
        self.assertEqual((p['resize']['store'], p['after']), ('disk0s2', 'disk0s2'))

    def test_already_installed_and_partial(self):
        with self.assertRaises(sf_plan.Refusal) as e:
            sf_plan.plan_install(facts('m1-siliconforest'), MODELS)
        self.assertIn('installed', codes(e.exception.findings))
        with self.assertRaises(sf_plan.Refusal) as e:
            sf_plan.plan_install(facts('m1-partial-siliconforest'), MODELS)
        self.assertIn('partial', codes(e.exception.findings))

    def test_uninstall_plans(self):
        p = sf_plan.plan_uninstall(facts('m1-siliconforest'), MODELS)
        self.assertEqual([r['action'] for r in p['remove']], ['deleteContainer', 'eraseVolume', 'eraseVolume'])
        self.assertEqual(p['grow'], dict(store='disk0s2', container='disk3'))
        p = sf_plan.plan_uninstall(facts('m1-partial-siliconforest'), MODELS)
        self.assertEqual([r['dev'] for r in p['remove']], ['disk0s4'])
        with self.assertRaises(sf_plan.Refusal):
            sf_plan.plan_uninstall(facts('m1-stock'), MODELS)
        with self.assertRaises(sf_plan.Refusal):
            sf_plan.plan_uninstall(facts('m1-asahi'), MODELS)          # Asahi Linux is not ours

    def test_digest_ignores_free_space_but_not_partitions(self):
        a = sf_plan.gather(fakemac.FakeMac()).layout.digest()
        self.assertEqual(a, sf_plan.gather(fakemac.FakeMac(macos_used=200 * GB)).layout.digest())
        self.assertNotEqual(a, sf_plan.gather(fakemac.FakeMac(macos_bytes=400 * GB)).layout.digest())


class KernelConfig(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.m, _, self.kbin = fakemac.make_release(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_fills_the_three_tokens_and_keeps_the_kernel(self):
        guid = fakemac.fake_uuid('root')
        out = sf_kernelcfg.personalize(self.kbin, guid.lower(), 123456, 7890, self.m['os']['kernel_record_sha256'])
        args = sf_kernelcfg.bootargs(out)
        self.assertIn('sfnvme_part=%s sfnvme_part_lba=123456 sfnvme_part_blocks=7890' % guid, args)
        self.assertNotIn('@SF_', args)
        self.assertEqual(sf_kernelcfg.kernel_digest(out), self.m['os']['kernel_record_sha256'])
        sys.path.insert(0, str(ROOT / 'integrations' / 'siliconforest' / 'm1-native-boot' / 'b1'))
        import pdsf_pack
        found, end = pdsf_pack.parse(out)
        self.assertEqual(end, len(out))
        self.assertTrue(all(item[4] for item in found))

    def test_refusals(self):
        g = fakemac.fake_uuid('root')
        bad = [
            (self.kbin.replace(b'@SF_ROOT_LBA@', b'4096'), g, 1, 1, None),           # a token missing (CRC also breaks: refused either way)
            (self.kbin, 'not-a-guid', 1, 1, None),
            (self.kbin, g, 0, 1, None),
            (self.kbin, g, 1, 1, '0' * 64),                                            # another kernel
            (self.kbin[:-8], g, 1, 1, None),                                           # cut off
        ]
        for data, guid, first, blocks, digest in bad:
            with self.assertRaises(sf_kernelcfg.ConfigError):
                sf_kernelcfg.personalize(data, guid, first, blocks, digest)

    def test_token_twice_and_too_long(self):
        sys.path.insert(0, str(ROOT / 'integrations' / 'siliconforest' / 'm1-native-boot' / 'b1'))
        import pdsf_pack
        twice = pdsf_pack.records(pdsf_pack.config_text('sfnvme_part=@SF_ROOT_PARTUUID@ @SF_ROOT_PARTUUID@ sfnvme_part_lba=@SF_ROOT_LBA@ sfnvme_part_blocks=@SF_ROOT_BLOCKS@'), b'k')
        with self.assertRaises(sf_kernelcfg.ConfigError):
            sf_kernelcfg.personalize(twice, fakemac.fake_uuid('x'), 1, 1)
        long = pdsf_pack.records(pdsf_pack.config_text('x' * 505 + ' sfnvme_part=@SF_ROOT_PARTUUID@ sfnvme_part_lba=@SF_ROOT_LBA@ sfnvme_part_blocks=@SF_ROOT_BLOCKS@'), b'k')
        with self.assertRaises(sf_kernelcfg.ConfigError):
            sf_kernelcfg.personalize(long, fakemac.fake_uuid('x'), 123456789, 123456789)


class FirmwareSlot(unittest.TestCase):
    def test_payload_and_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            fw = os.path.join(tmp, 'firmware.tar')
            fakemac.firmware_tar(fw)
            data, names = sf_fwslot.payload(fw)
            self.assertTrue(all(n.startswith('brcm/') for n in names))
            self.assertEqual(len(names), 4)                  # three files and the hard link; not isp/
            dev = os.path.join(tmp, 'dev')
            with open(dev, 'wb') as fd:
                fd.truncate(8 << 20)
            with self.assertRaises(sf_fwslot.SlotError):     # no slot header: nothing written
                sf_fwslot.write(dev, 4 << 20, 2 << 20, data)
            self.assertEqual(pathlib.Path(dev).read_bytes().count(b'\0'), 8 << 20)
            with open(dev, 'r+b') as fd:
                fd.seek(4 << 20)
                fd.write(sf_fwslot.EMPTY)
            sf_fwslot.write(dev, 4 << 20, 2 << 20, data)
            raw = pathlib.Path(dev).read_bytes()
            head = raw[4 << 20:(4 << 20) + 4096].rstrip(b'\0').decode()
            self.assertTrue(head.startswith('SFFWSLOT1\nlength=%d\nsha256=' % len(data)))
            t = tarfile.open(fileobj=io.BytesIO(raw[(4 << 20) + 4096:(4 << 20) + 4096 + len(data)]))
            self.assertEqual(sorted(t.getnames()), names)
            with self.assertRaises(sf_fwslot.SlotError):     # too big for the slot
                sf_fwslot.write(dev, 4 << 20, 8192, data)


class Manifest(unittest.TestCase):
    def test_example_and_mutations(self):
        ex = json.loads((ROOT / 'install' / 'manifest.example.json').read_text())
        sf_manifest.check(ex, ['J293'])
        with tempfile.TemporaryDirectory() as tmp:
            m, _, _ = fakemac.make_release(tmp)
        sf_manifest.check(m, ['J293'])
        muts = [
            lambda d: d.update(format='other/1'),
            lambda d: d.update(models=['J704']),
            lambda d: d.update(base_url='http://example.invalid/'),
            lambda d: d['files'][0].update(sha256='ABC'),
            lambda d: d['files'].pop(),
            lambda d: d['os'].update(root_image_bytes=4097),
            lambda d: d['os'].update(boot_partition_bytes=1 << 29),
            lambda d: d['os']['firmware_slot'].update(offset=d['os']['root_image_bytes']),
            lambda d: d['engine'].update(name='something-else'),
            lambda d: d['files'][1].update(file='../escape.zip'),
        ]
        for i, mut in enumerate(muts):
            d = json.loads(json.dumps(m))
            mut(d)
            with self.assertRaises(sf_manifest.ManifestError, msg='mutation %d' % i):
                sf_manifest.check(d, ['J293'])


class Gate(unittest.TestCase):
    def setUp(self):
        self.mac = fakemac.FakeMac(name='gate')
        self.plan = sf_plan.plan_install(sf_plan.gather(self.mac), MODELS)
        self.gate = sf_gate.Gate(self.plan, lambda: sf_plan.gather(self.mac).layout, execute=self.mac, log=lambda *a: None)

    def refused(self, argv):
        with self.assertRaises(sf_gate.Refused):
            self.gate.run(argv)

    def test_only_what_the_plan_names(self):
        r = self.plan['resize']
        self.refused(['diskutil', 'apfs', 'resizeContainer', 'disk0s2', str(r['to_bytes'] - (1 << 20))])
        self.refused(['diskutil', 'apfs', 'resizeContainer', 'disk0s3', str(r['to_bytes'])])
        self.refused(['diskutil', 'addPartition', 'disk0s1', 'apfs', 'X', '1000000'])
        self.refused(['diskutil', 'eraseVolume', 'free', 'free', 'disk0s2'])
        self.refused(['diskutil', 'apfs', 'deleteContainer', 'disk3'])
        self.refused(['diskutil', 'apfs', 'addVolume', 'disk3', 'apfs', 'X', '-role', 'S'])
        self.refused(['newfs_msdos', '-F', '32', '/dev/rdisk0s2'])
        self.refused(['bless', '--setBoot', '--device', '/dev/disk3s1'])
        self.refused(['dd', 'if=/dev/zero', 'of=/dev/rdisk0'])
        self.refused(['gpt', 'add', '-i', '9', 'disk0'])
        self.refused(['kmutil', 'configure-boot', '-c', 'x'])
        self.refused(['bputil', '-g'])
        with self.assertRaises(sf_gate.Refused):
            self.gate.open('/dev/rdisk0s2', 'r+b')
        # read-only commands pass
        self.assertEqual(self.gate.run(['diskutil', 'list', '-plist'])[0], 0)
        self.assertEqual(self.gate.run(['bless', '--getBoot'])[0], 0)
        self.assertFalse([c for c in self.mac.events if c[0] == 'diskutil' and c[1] not in ('list', 'apfs', 'info')])

    def test_resize_once_then_partition_inside_the_gap(self):
        r = self.plan['resize']
        self.gate.run(['diskutil', 'apfs', 'resizeContainer', 'disk0s2', str(r['to_bytes'])])
        self.refused(['diskutil', 'apfs', 'resizeContainer', 'disk0s2', str(r['to_bytes'])])
        self.gate.run(['diskutil', 'addPartition', 'disk0s2', 'apfs', 'SiliconForest', str(sf_plan.STUB_BYTES)])
        self.assertEqual(self.gate.created, {'disk0s4': 'apfs'})
        self.refused(['diskutil', 'addPartition', 'disk0s4', '%Linux%', '%noformat%', str(self.plan['total_bytes'])])

    def test_stops_when_another_partition_moves(self):
        mac = self.mac
        real = mac.diskutil

        def evil(a):
            rc, out = real(a)
            if a[0] == 'addPartition':
                mac.part('disk0s3')['offset'] += 4096        # the recovery container "moves"
            return rc, out
        mac.diskutil = evil
        self.gate.run(['diskutil', 'apfs', 'resizeContainer', 'disk0s2', str(self.plan['resize']['to_bytes'])])
        with self.assertRaises(sf_gate.Refused) as e:
            self.gate.run(['diskutil', 'addPartition', 'disk0s2', 'apfs', 'SiliconForest', str(sf_plan.STUB_BYTES)])
        self.assertIn('STOP', str(e.exception))


class EndToEnd(unittest.TestCase):
    """install -> update -> uninstall on FakeMac, all through the gate, with a synthetic release."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.m, self.mp, self.kbin = fakemac.make_release(self.tmp)
        os.makedirs(os.path.join(self.tmp, 'os'))
        pkg = sf_manifest.role(self.m, 'os-package')['file']
        shutil.copy(os.path.join(self.tmp, pkg), os.path.join(self.tmp, 'os', pkg))
        self.mac = fakemac.FakeMac(name='e2e')
        self.reader = lambda: sf_plan.gather(self.mac).layout
        self.journal = os.path.join(self.tmp, 'journal.jsonl')

    def tearDown(self):
        shutil.rmtree(self.tmp)
        shutil.rmtree(self.mac.tmp)

    def install(self):
        before = {p.uuid: (p.offset, p.size) for p in self.reader().real_parts()}
        plan = sf_plan.plan_install(sf_plan.gather(self.mac), MODELS, self.m)
        gate = sf_gate.Gate(plan, self.reader, journal=self.journal, execute=self.mac, log=lambda *a: None)
        res = fakemac.SimulatedAsahi(self.mac, gate).install(plan, self.m, self.tmp, None, sf_engine.finish)
        return before, plan, gate, res

    def test_install_update_uninstall(self):
        before, plan, gate, res = self.install()
        lay = self.reader()
        ours = lay.find_ours()
        self.assertTrue(ours.complete, ours and ours.problems)
        self.assertEqual((ours.stub.dev, ours.boot.dev, ours.root.dev), (res['stub'], res['efi'], res['root']))
        # every partition that was there is where it was; only macOS shrank, to exactly the planned size
        for uuid, (off, size) in before.items():
            now = next(p for p in lay.real_parts() if p.uuid == uuid)
            self.assertEqual(now.offset, off)
            self.assertEqual(now.size, plan['resize']['to_bytes'] if now.dev == 'disk0s2' else size)
        # this Mac's root partition is in sf/kernel.bin
        k = open(os.path.join(res['mount'], 'sf', 'kernel.bin'), 'rb').read()
        args = sf_kernelcfg.bootargs(k)
        self.assertIn('sfnvme_part=%s sfnvme_part_lba=%d sfnvme_part_blocks=%d' % (ours.root.uuid, ours.root.offset // 4096, ours.root.size // 4096), args)
        # the firmware is in the root's slot; the root image itself is otherwise as shipped
        dev = open(self.mac.device_file(res['root']), 'rb').read(8 << 20)
        slot = self.m['os']['firmware_slot']['offset']
        self.assertTrue(dev[slot:slot + 20].startswith(b'SFFWSLOT1\nlength='))
        self.assertEqual(dev[:slot], bytes(slot))
        # bless went to our new system volume; the machine was asked to shut down
        self.assertTrue(self.mac.default_boot.startswith('/dev/disk4s'))
        self.assertIn(['POWER', '-h'], self.mac.events)
        # the journal has a start and a done for every change
        lines = [json.loads(l) for l in open(self.journal)]
        starts = [l for l in lines if l.get('state') == 'start' and l['step'] not in ('open', 'write')]
        self.assertEqual(len(starts), len([l for l in lines if l.get('state') == 'done' and l['step'] not in ('open', 'write')]))
        self.assertEqual(len(starts), 12)
        changing = [c for c in gate.calls if gate.classify(c) is not None]
        self.assertEqual([' '.join(c[:3]) for c in changing][:3], ['diskutil apfs resizeContainer', 'diskutil addPartition disk0s2', 'diskutil apfs changeVolumeRole'])
        self.assertFalse([c for c in changing if 'disk0s1' in c or 'disk0s3' in c or 'disk3s' in ' '.join(c)])
        # SimulatedAsahi asks for what the real Asahi v0.9.2 code asked for on the same model
        # (recorded by install/tests/test_with_asahi.py from the Asahi installer's own code)
        real = (ROOT / 'install' / 'tests' / 'fixtures' / 'asahi-v0.9.2-commands.txt').read_text().splitlines()
        self.assertEqual([' '.join(c) for c in changing][:len(real)], real)

        # update: new boot files, old ones kept, root identifiers rewritten the same way
        uplan = sf_plan.plan_update(sf_plan.gather(self.mac), MODELS, self.m)
        ugate = sf_gate.Gate(uplan, self.reader, execute=self.mac, log=lambda *a: None)
        with open(os.path.join(res['mount'], 'sf', 'boot.bin'), 'wb') as fd:
            fd.write(b'an older stage 2')
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            sf_engine.execute_update(uplan, ugate, self.m, self.tmp, run=self.info_with_mount(res))
        self.assertEqual(open(os.path.join(res['mount'], 'sf', 'boot.bin.old'), 'rb').read(), b'an older stage 2')
        self.assertIn('already this release', out.getvalue())               # kernel.bin was already current
        self.assertFalse([c for c in ugate.calls if ugate.classify(c) is not None])

        # uninstall: refused while SiliconForest is the startup disk
        with self.assertRaises(sf_plan.Refusal):
            sf_plan.plan_uninstall(sf_plan.gather(self.mac), MODELS)
        self.mac.default_boot = '/dev/disk3s1'
        uplan = sf_plan.plan_uninstall(sf_plan.gather(self.mac), MODELS)
        ugate = sf_gate.Gate(uplan, self.reader, execute=self.mac, log=lambda *a: None)
        with contextlib.redirect_stdout(io.StringIO()):
            sf_engine.execute_uninstall(uplan, ugate, self.reader)
        after = {p.uuid: (p.offset, p.size) for p in self.reader().real_parts()}
        self.assertEqual(after, before)                      # the table is what it was, macOS its old size

    def info_with_mount(self, res):
        def run(argv):
            if argv[:3] == ['diskutil', 'info', '-plist'] and argv[3] == res['efi']:
                import plistlib
                d = plistlib.loads(self.mac(argv)[1])
                d['MountPoint'] = res['mount']
                return 0, plistlib.dumps(d)
            return self.mac(argv)
        return run

    def test_uninstall_when_deleting_the_container_leaves_its_partition(self):
        self.install()
        self.mac.default_boot = '/dev/disk3s1'
        self.mac.delete_leaves_partition = True
        plan = sf_plan.plan_uninstall(sf_plan.gather(self.mac), MODELS)
        gate = sf_gate.Gate(plan, self.reader, execute=self.mac, log=lambda *a: None)
        with contextlib.redirect_stdout(io.StringIO()):
            sf_engine.execute_uninstall(plan, gate, self.reader)
        self.assertIsNone(self.reader().find_ours())
        self.assertEqual(len(self.reader().real_parts()), 3)

    def test_engine_main_check_dry_run_and_no_release(self):
        old = sf_engine.real_run
        sf_engine.real_run = self.mac
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(sf_engine.main(['check']), 0)
                self.assertEqual(sf_engine.main(['install', '--dry-run']), 0)
                self.assertEqual(sf_engine.main(['install']), 4)
                self.assertEqual(sf_engine.main(['uninstall', '--dry-run']), 3)
            text = out.getvalue()
            self.assertIn('Dry run: nothing was changed.', text)
            self.assertIn('There is no SiliconForest release yet', text)
            old_confirm = sf_engine.confirm
            sf_engine.confirm = lambda word, tty=None: False
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(sf_engine.main(['install', '--manifest', self.mp, '--artifacts', self.tmp]), 1)
            finally:
                sf_engine.confirm = old_confirm
            self.assertFalse([e for e in self.mac.events if e[0] in ('diskutil', 'newfs_msdos', 'bless') and
                              sf_gate.Gate.classify(None, e) is not None])
        finally:
            sf_engine.real_run = old


class Shell(unittest.TestCase):
    def test_install_sh_is_assembled_and_refuses_elsewhere(self):
        r = subprocess.run([sys.executable, str(ROOT / 'install' / 'tools' / 'assemble.py'), '--check'], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout)
        r = subprocess.run(['sh', str(ROOT / 'install.sh')], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn('runs on macOS', r.stderr)
        r = subprocess.run(['sh', '-n', str(ROOT / 'install.sh')])
        self.assertEqual(r.returncode, 0)

    def test_install_sh_on_a_pretend_mac(self):
        """install.sh's own checks with macOS's commands replaced by small scripts (uname, sysctl, ...)."""
        with tempfile.TemporaryDirectory() as tmp:
            bin_ = os.path.join(tmp, 'bin')
            os.makedirs(bin_)
            fake = {'uname': 'echo Darwin', 'sw_vers': 'echo 15.6.1', 'id': '[ "$1" = -u ] && echo 501 || /usr/bin/id "$@"',
                    'sysctl': 'case "$*" in *arm64*) echo 1;; *translated*) echo "${SF_T:-0}";; *targettype*) echo J293;; *) echo MacBookPro17,1;; esac',
                    'curl': 'exit 22'}
            for name, body in fake.items():
                p = os.path.join(bin_, name)
                with open(p, 'w') as fd:
                    fd.write('#!/bin/sh\n' + body + '\n')
                os.chmod(p, 0o755)
            script = (ROOT / 'install.sh').read_text().replace('/System/Library/CoreServices/SystemVersion.plist', '/dev/null') \
                .replace('export PATH="/usr/bin:/bin:/usr/sbin:/sbin"', 'export PATH="%s:$PATH"' % bin_)
            path = os.path.join(tmp, 'install.sh')
            with open(path, 'w') as fd:
                fd.write(script)
            env = dict(os.environ, PATH=bin_ + ':' + os.environ['PATH'], HOME=tmp, SF_PYTHON=sys.executable, SF_T='1')
            r = subprocess.run(['sh', path, '--check'], capture_output=True, text=True, env=env)
            self.assertEqual(r.returncode, 1)
            self.assertIn('Rosetta', r.stderr)
            env['SF_T'] = '0'
            r = subprocess.run(['sh', path, '--dry-run'], capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)
            # past the shell checks; the engine then reads the (absent) disk and refuses
            self.assertIn('No SiliconForest release has been published yet.', r.stdout)
            self.assertIn('Nothing was changed.', r.stdout)
            self.assertTrue(os.listdir(os.path.join(tmp, 'Library', 'Logs', 'SiliconForest')))


if __name__ == '__main__':
    unittest.main()
