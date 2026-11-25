# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The installer's shippable payload (docs/installer/PAYLOAD.md): root preparation, growth, boot
receipt, firmware slot, release signing and verification. Host only, ordinary files only.
Tests needing e2fsprogs, xz, perl or ssh-keygen skip when the tool is missing."""
import hashlib
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
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
P = ROOT / 'installer/payload'
for sub in ('image', 'release', 'firmware'):
    sys.path.insert(0, str(P / sub))

import receipt  # noqa: E402
import remote_zip  # noqa: E402
import sfrelease  # noqa: E402
from extract_firmware import slot_payload  # noqa: E402
from wifi import WiFiFWCollection  # noqa: E402


def have(*tools):
    extra = os.environ.get('PATH', '') + os.pathsep + '/sbin' + os.pathsep + '/usr/sbin'
    return all(shutil.which(t, path=extra) for t in tools)


E2FS = have('debugfs', 'mke2fs', 'resize2fs', 'e2fsck', 'dumpe2fs')
if E2FS:
    os.environ['PATH'] = os.environ.get('PATH', '') + os.pathsep + '/sbin' + os.pathsep + '/usr/sbin'


@unittest.skipUnless(E2FS, 'e2fsprogs not installed')
class RootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import synthetic_base
        import prepare_root
        cls.tmp = tempfile.TemporaryDirectory(prefix='sf-payload-')
        t = pathlib.Path(cls.tmp.name)
        synthetic_base.build(t / 'base', 64)
        cls.base = t / 'base'
        cls.root = t / 'root'
        cls.info = prepare_root.prepare(cls.base, cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def debugfs_cat(self, path):
        return subprocess.run(['debugfs', '-R', f'cat {path}', str(self.root / 'siliconforest-root.ext4')],
                              capture_output=True, check=True).stdout

    def test_slots_are_contiguous_and_at_the_recorded_offsets(self):
        img = (self.root / 'siliconforest-root.ext4').read_bytes()
        fw, rc = self.info['firmware_slot'], self.info['receipt_slot']
        self.assertEqual(img[fw['offset']:fw['offset'] + fw['bytes']], b'SFFWSLOT1\n' + bytes(fw['bytes'] - 10))
        self.assertEqual(img[rc['offset']:rc['offset'] + rc['bytes']], bytes(rc['bytes']))
        self.assertEqual(fw['offset'] % 4096, 0)
        self.assertEqual(rc['offset'] % 4096, 0)

    def test_firstboot_job_runs_the_installer_wrapper(self):
        job = self.debugfs_cat('/System/Library/LaunchDaemons/org.siliconforest.firstboot.plist').decode()
        self.assertIn('<string>/usr/libexec/sf-installer-firstboot</string>', job)
        self.assertNotIn('<string>/usr/libexec/sf-firstboot</string>', job)
        self.assertEqual(self.debugfs_cat('/usr/libexec/sf-boot-receipt'), (P / 'image/sf-boot-receipt').read_bytes())

    def test_manifest_lists_what_was_written(self):
        rows = {r.split('\t')[0]: r.split('\t') for r in (self.root / 'root.manifest.tsv').read_text().splitlines()[1:]}
        for path in ('/private/var/db/sf-firmware-slot', '/private/var/db/sf-boot-receipt', '/usr/libexec/sf-installer-firstboot'):
            self.assertIn(path, rows)
        self.assertEqual(rows['/private/var/db/sf-boot-receipt'][2], '0600')

    def test_base_is_not_modified(self):
        self.assertEqual(self.info['base_sha256'], hashlib.sha256((self.base / 'siliconforest-root.ext4').read_bytes()).hexdigest())

    def test_grow_keeps_slots_and_fills_the_partition(self):
        import grow_check
        r = grow_check.grow(self.root, 3 << 30)
        self.assertTrue(r['slots_unchanged'])
        self.assertEqual(r['blocks'], (3 << 30) // 4096)

    def test_grow_refuses_beyond_reserved_gdt(self):
        import grow_check
        with self.assertRaises(Exception):
            grow_check.grow(self.root, self.info['grow']['max_bytes'] + (1 << 30))


@unittest.skipUnless(have('perl'), 'perl not installed')
class ReceiptTests(unittest.TestCase):
    def run_writer(self, path, stage):
        return subprocess.run(['perl', str(P / 'image/sf-boot-receipt'), stage], env={**os.environ, 'SF_RECEIPT_PATH': str(path)},
                              capture_output=True, text=True).returncode

    def test_stages_append_once_and_classify(self):
        with tempfile.TemporaryDirectory() as d:
            dev = pathlib.Path(d) / 'dev'
            dev.write_bytes(bytes(1 << 20))
            off, size, iid = 8192, 64 << 10, 'ab' * 16
            slot = lambda: dev.read_bytes()[off:off + size]  # noqa: E731
            self.assertEqual(receipt.classify(slot(), iid), 'invalid')
            receipt.write_header(dev, off, size, iid)
            with self.assertRaises(ValueError):
                receipt.write_header(dev, off, size, iid)       # never over an existing header
            self.assertEqual(receipt.classify(slot(), iid), 'empty')
            # sf-boot-receipt works on the slot file inside the root; emulate it with the same bytes
            f = pathlib.Path(d) / 'slot'
            f.write_bytes(slot())
            for stage in ('root-mounted', 'launchd-up', 'root-mounted'):
                self.assertEqual(self.run_writer(f, stage), 0)
            self.assertEqual(f.read_bytes().count(b'root-mounted '), 1)
            self.assertEqual(receipt.classify(f.read_bytes(), iid), 'partial:launchd-up')
            self.assertEqual(self.run_writer(f, 'desktop-ready'), 0)
            self.assertEqual(receipt.classify(f.read_bytes(), iid), 'installed')
            self.assertEqual(receipt.classify(f.read_bytes(), 'cd' * 16), 'foreign')
            self.assertEqual(len(f.read_bytes()), size)

    def test_writer_does_nothing_without_a_header(self):
        with tempfile.TemporaryDirectory() as d:
            f = pathlib.Path(d) / 'slot'
            f.write_bytes(bytes(64 << 10))
            self.assertEqual(self.run_writer(f, 'launchd-up'), 3)
            self.assertEqual(f.read_bytes(), bytes(64 << 10))
            f.write_bytes(bytes(100))
            self.assertEqual(self.run_writer(f, 'launchd-up'), 2)
            self.assertNotEqual(self.run_writer(f, 'Bad Stage'), 0)


class FirmwareTests(unittest.TestCase):
    def tree(self, d):
        base = pathlib.Path(d) / 'wifi' / 'C-4378__s-B1'
        base.mkdir(parents=True)
        # Apple's layout: firmware named <platform>_M-<module>_V-<vendor>__m-<rev>, NVRAM named P-<...>.txt
        (base / 'shikoku_M-RASP_V-u__m-7.5.trx').write_bytes(b'fw-shikoku')
        (base / 'honshu_M-RASP_V-u__m-7.5.trx').write_bytes(b'fw-honshu')
        (base / 'shikoku_M-RASP_V-u__m-7.5.clmb').write_bytes(b'clm')
        (base / 'honshu_M-RASP_V-u__m-7.5.clmb').write_bytes(b'clm')
        (base / 'P-shikoku-X0_M-RASP_V-u__m-7.5.txt').write_bytes(b' a=1\nb =2\n')
        (base / 'perf').mkdir()
        (base / 'perf' / 'shikoku_M-RASP_V-u__m-7.5.trx').write_bytes(b'perf')
        return pathlib.Path(d) / 'wifi'

    def test_wifi_names(self):
        with tempfile.TemporaryDirectory() as d:
            names = dict((n, f.data) for n, f in WiFiFWCollection(str(self.tree(d))).files())
        self.assertIn('brcm/brcmfmac4378b1-pcie.apple,shikoku.bin', names)
        self.assertEqual(names['brcm/brcmfmac4378b1-pcie.apple,shikoku.bin'], b'fw-shikoku')
        self.assertNotIn(b'perf', names.values())
        txt = [v for k, v in names.items() if k.endswith('.txt')]
        self.assertEqual(txt, [b'a=1\nb=2\n'])

    @unittest.skipUnless(have('perl'), 'perl not installed')
    def test_slot_payload_round_trips_through_the_image_unpacker(self):
        files = sorted([('brcm/brcmfmac4378b1-pcie.apple,shikoku.bin', b'A' * 5000), ('brcm/brcmfmac4378b1-pcie.apple,shikoku.clm_blob', b'B'),
                        ('brcm/brcmfmac4378b1-pcie.apple,shikoku-X.clm_blob', b'B')])
        slot = slot_payload(files)
        with tempfile.TemporaryDirectory() as d:
            s = pathlib.Path(d) / 'slot'
            s.write_bytes(slot + bytes((32 << 20) - len(slot)))
            dest = pathlib.Path(d) / 'fw'
            (dest / 'brcm').mkdir(parents=True)
            (dest / 'apple').mkdir()
            r = subprocess.run(['perl', str(P / 'image/sf-unpack-firmware'), str(s), str(dest)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            for n, data in files:
                self.assertEqual((dest / n).read_bytes(), data)
            empty = pathlib.Path(d) / 'empty'
            empty.write_bytes(b'SFFWSLOT1\n' + bytes((32 << 20) - 10))
            r = subprocess.run(['perl', str(P / 'image/sf-unpack-firmware'), str(empty), str(dest)], capture_output=True)
            self.assertEqual(r.returncode, 3)

    def test_zip_reader_zip64_and_crc(self):
        with tempfile.TemporaryDirectory() as d:
            zp = pathlib.Path(d) / 'x.ipsw'
            with zipfile.ZipFile(zp, 'w') as z:
                z.writestr('BuildManifest.plist', b'<plist/>', compress_type=zipfile.ZIP_DEFLATED)
                with z.open('090-1.dmg', 'w', force_zip64=True) as f:
                    f.write(os.urandom(300000))
            rz = remote_zip.RemoteZip(remote_zip.LocalSource(str(zp)))
            with zipfile.ZipFile(zp) as z:
                self.assertEqual(rz.read('090-1.dmg'), z.read('090-1.dmg'))
                self.assertEqual(rz.read('BuildManifest.plist'), b'<plist/>')
            raw = bytearray(zp.read_bytes())
            i = raw.find(b'<plist/>')
            if i > 0:   # stored only if not compressed; corrupt the dmg body instead
                pass
            j = bytes(raw).find(b'090-1.dmg') + 9 + 20 + 40
            raw[j] ^= 0xFF
            zp.write_bytes(bytes(raw))
            rz = remote_zip.RemoteZip(remote_zip.LocalSource(str(zp)))
            with self.assertRaises(remote_zip.ZipError):
                rz.read('090-1.dmg')


class Stage1Tests(unittest.TestCase):
    """The release's sf-stage1.bin (installer/payload/boot/build_stage1.sh; PAYLOAD.md section 12)."""
    PIN = '121fcbf35d4501814b58ca5347926a4173b6a512'

    def image(self, tag=None, stopped=True, size=600_000):
        tag = tag if tag is not None else self.PIN + '-siliconforest-stage1-v1'
        body = b'\x1f' * 4096 + b'##m1n1_ver##' + tag.encode() + b'\0' + (b'SF_STOPPED\0' if stopped else b'')
        return body + b'\0' * (size - len(body))

    def test_our_stage_1_is_accepted(self):
        self.assertEqual(sfrelease.check_stage1(self.image(), self.PIN, 4325376), self.PIN + '-siliconforest-stage1-v1')

    def test_anything_else_is_refused(self):
        bad = {
            'empty': b'',
            'too large for the footprint': self.image(size=4325377),
            "Asahi's stage 1": self.image(tag='v1.5.2'),
            'another m1n1 revision': self.image(tag='5e3a756398bf0000000000000000000000000000-siliconforest-stage1-v1'),
            'a stage 2 tag': self.image(tag=self.PIN + '-siliconforest-boot-v2'),
            'the proxy-fallback variant': self.image(stopped=False),
            'a placeholder': b'SF-REHEARSAL placeholder sf-stage1.bin\n',
        }
        for why, data in bad.items():
            with self.subTest(why), self.assertRaises(sfrelease.ReleaseError):
                sfrelease.check_stage1(data, self.PIN, 4325376)

    def test_profiles_agree_with_the_g2_window(self):
        rev, footprint = sfrelease.profile_stage1(ROOT / 'installer/profiles')
        self.assertEqual((rev, footprint), (self.PIN, 4325376))
        pins = json.loads((ROOT / 'integrations/siliconforest/m1-j313-g2/g2-pins.json').read_text())
        self.assertTrue(pins['window_tag'].startswith(rev))
        self.assertEqual(pins['window_raw']['bytes'], footprint)

    def test_the_release_build_is_the_installed_machines_stage_1_recipe(self):
        # build_stage1.sh must build what install/build.sh's "sf-stage1" built (the stage 1 in the stub of the
        # installed machine): same make variables, tag, patch set and expected SHA-256. A drift fails here.
        rel = (P / 'boot/build_stage1.sh').read_text()
        kit = (ROOT / 'integrations/siliconforest/m1-native-boot/install/build.sh').read_text()
        for v in ('USE_CLANG=1', 'RELEASE=1', 'SF_INSTALLED=1', 'BUILTIN_LOGO=siliconforest', 'CHAINLOADING=1'):
            self.assertIn(v, rel)
            self.assertIn(v, kit)
        self.assertIn('m1n1 sf-stage1 "$PIN-siliconforest-stage1-v1" 0 CHAINLOADING=1', kit)
        self.assertIn('TAG="$PIN-siliconforest-stage1-v1"', rel)
        installed = '44c1ef0bda96224f5fe8c6228cc12ec1966b7781f38844cea960b21b47654318'
        self.assertIn('STAGE1_INSTALLED=' + installed, rel)
        self.assertIn('STAGE1_INSTALLED=' + installed, kit)
        # stage 1 takes the top-level patches only; the stage 2 ones are never applied to it
        self.assertIn('"$PATCHES"/*.patch', rel)
        self.assertIn('PATCHES=$ROOT/integrations/siliconforest/m1-native-boot/install/patches\n', rel)


@unittest.skipUnless(E2FS and have('xz', 'ssh-keygen', 'perl'), 'needs e2fsprogs, xz, ssh-keygen')
class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import synthetic_base
        import prepare_root
        cls.tmp = tempfile.TemporaryDirectory(prefix='sf-release-')
        t = pathlib.Path(cls.tmp.name)
        synthetic_base.build(t / 'base', 48)
        prepare_root.prepare(t / 'base', t / 'root')
        boot = t / 'boot'
        boot.mkdir()
        for n in ('sf-stage1.bin', 'boot.bin', 'bootargs.template'):
            (boot / n).write_bytes(b'SF-REHEARSAL ' + n.encode() + b'\n')
        import rehearsal_kc_builder
        kc = rehearsal_kc_builder.synthetic(t / 'kc-inputs')
        keys = t / 'keys'
        subprocess.run(['sh', str(P / 'release/make_test_key.sh'), str(keys)], check=True, capture_output=True)
        names = t / 'names.tsv'
        names.write_text('# version: 13.5\n# build: 22G74\nJ313\tbrcm/brcmfmac4378b1-pcie.apple,shikoku.bin\t3\t' + 'a' * 64 + '\n')
        cls.t, cls.keys = t, keys
        cls.args = ['--root-dir', str(t / 'root'), '--boot-dir', str(boot), '--firmware-names', str(names),
                    '--profiles', str(ROOT / 'installer/profiles'), '--version', '0.0.1-rehearsal', '--sequence', '1',
                    '--key', str(keys / 'TEST-ONLY-release-key'), '--xz-level', '1',
                    '--kc-inputs', str(kc), '--kc-builder', str(P / 'release/rehearsal_kc_builder.py'),
                    '--kc-builder-signing', 'rehearsal-stand-in']
        import make_release
        cls.make_release = make_release
        assert make_release.main(cls.args + ['--out', str(t / 'rel'), '--rehearsal']) == 0

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def verify(self, d, **kw):
        import verify_release
        return verify_release.verify(d, self.keys / 'allowed_signers', **kw)

    def copy(self):
        d = pathlib.Path(tempfile.mkdtemp(dir=self.t))
        shutil.rmtree(d)
        shutil.copytree(self.t / 'rel', d)
        return d

    def test_good_rehearsal_verifies_deeply(self):
        r = self.verify(self.t / 'rel', allow_rehearsal=True)
        self.assertTrue(r['ok'] and r['rehearsal'] and r['root_checked'])
        inst = json.loads((self.t / 'rel/install.json').read_text())
        self.assertEqual(inst['firmware']['boards']['J313'][0]['name'], 'brcm/brcmfmac4378b1-pcie.apple,shikoku.bin')
        self.assertTrue(inst['signing_key']['test_only'])

    def test_rehearsal_refused_without_flag(self):
        with self.assertRaises(sfrelease.ReleaseError):
            self.verify(self.t / 'rel')

    def test_tampered_artifact_refused(self):
        d = self.copy()
        with (d / 'boot.bin').open('ab') as f:
            f.write(b'x')
        with self.assertRaises(sfrelease.ReleaseError):
            self.verify(d, allow_rehearsal=True)

    def test_unlisted_file_refused(self):
        d = self.copy()
        (d / 'extra.bin').write_bytes(b'x')
        with self.assertRaises(sfrelease.ReleaseError):
            self.verify(d, allow_rehearsal=True)

    def test_resigned_by_another_key_refused(self):
        d = self.copy()
        other = self.t / 'other'
        subprocess.run(['sh', str(P / 'release/make_test_key.sh'), str(other)], check=True, capture_output=True)
        (d / 'SHA256SUMS.sig').unlink()
        subprocess.run(['ssh-keygen', '-q', '-Y', 'sign', '-n', sfrelease.NAMESPACE, '-f', str(other / 'TEST-ONLY-release-key'),
                        str(d / 'SHA256SUMS')], check=True, capture_output=True)
        with self.assertRaises(sfrelease.ReleaseError):
            self.verify(d, allow_rehearsal=True)

    def test_install_json_cannot_be_swapped(self):
        d = self.copy()
        inst = json.loads((d / 'install.json').read_text())
        inst['receipt_slot']['offset'] += 4096
        (d / 'install.json').write_text(json.dumps(inst))
        with self.assertRaises(sfrelease.ReleaseError):
            self.verify(d, allow_rehearsal=True)

    def test_test_key_cannot_sign_a_real_release(self):
        self.assertEqual(self.make_release.main(self.args + ['--out', str(self.t / 'real')]), 1)

    def test_real_release_needs_a_known_key(self):
        k = self.t / 'nottest'
        k.mkdir()
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'someone', '-f', str(k / 'key')], check=True)
        args = [a if a != str(self.keys / 'TEST-ONLY-release-key') else str(k / 'key') for a in self.args]
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'real2')]), 1)
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'real3'), '--rehearsal']), 1)

    def test_a_tagged_stage_1_is_checked_even_in_a_rehearsal(self):
        boot = self.t / 'boot-wrong-stage1'
        shutil.copytree(self.t / 'boot', boot)
        (boot / 'sf-stage1.bin').write_bytes(Stage1Tests().image(tag='0' * 40 + '-siliconforest-stage1-v1'))
        args = [a if a != str(self.t / 'boot') else str(boot) for a in self.args]
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'wrong-s1'), '--rehearsal']), 1)
        (boot / 'sf-stage1.bin').write_bytes(Stage1Tests().image())
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'right-s1'), '--rehearsal']), 0)

    # SAP and A/B boot on SFBOOT (docs/sap/IMAGE.md): the trust anchor, slot B's stage 2, the record

    def boot_variant(self, name, stage1=None, boot_b=False, template=None):
        boot = self.t / name
        shutil.copytree(self.t / 'boot', boot)
        if stage1 is not None:
            (boot / 'sf-stage1.bin').write_bytes(stage1)
        if boot_b:
            (boot / 'boot-b.bin').write_bytes(b'SF-REHEARSAL boot-b.bin\n')
        if template is not None:
            (boot / 'bootargs.template').write_text(template)
        return [a if a != str(self.t / 'boot') else str(boot) for a in self.args]

    def test_trust_anchor_ships_and_fits_the_boot_arguments(self):
        inst = json.loads((self.t / 'rel/install.json').read_text())
        tok = (self.t / 'rel/sf-trust.txt').read_text().strip()
        self.assertRegex(tok, r'^sf_trust=1:[A-Za-z0-9+/]{43}$')
        pub = (self.keys / 'TEST-ONLY-release-key.pub').read_text().split()[1]
        import base64
        self.assertEqual(base64.b64decode(pub)[-32:], base64.b64decode(tok.split(':')[1] + '='))
        self.assertEqual(inst['boot']['trust'], 'sf-trust.txt')
        self.assertTrue(inst['boot']['trust_in_bootargs'])
        self.assertIn(tok, (self.t / 'rel/bootargs.template').read_text())
        self.assertFalse(inst['boot']['slots'])
        self.assertNotIn('bootstate', inst['boot'])

    def test_trust_stays_out_of_boot_arguments_that_would_overflow(self):
        # J313's real arguments are ~587 characters personalised: no room for the 54 of sf_trust
        long = '# comment\n' + ' '.join(['x' * 60] * 8) + ' root=@SF_FSUUID@ part=@SF_PARTUUID@\n'
        args = self.boot_variant('boot-long', template=long)
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'long'), '--rehearsal']), 0)
        inst = json.loads((self.t / 'long/install.json').read_text())
        self.assertFalse(inst['boot']['trust_in_bootargs'])
        self.assertEqual((self.t / 'long/bootargs.template').read_text(), long)
        self.assertLess(inst['boot']['bootargs_personalised_max'], 608)
        self.assertTrue(self.verify(self.t / 'long', allow_rehearsal=True)['ok'])

    def test_stage1_v2_and_slot_b_carry_the_ab_record(self):
        v2 = Stage1Tests().image(tag=Stage1Tests.PIN + '-siliconforest-stage1-v2')
        args = self.boot_variant('boot-v2', stage1=v2, boot_b=True)
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'v2'), '--rehearsal']), 0)
        inst = json.loads((self.t / 'v2/install.json').read_text())
        self.assertTrue(inst['boot']['slots'])
        self.assertEqual((inst['boot']['stage2_b'], inst['boot']['bootstate']), ('boot-b.bin', 'bootstate.bin'))
        self.assertEqual(inst['boot']['stage1_tag'], Stage1Tests.PIN + '-siliconforest-stage1-v2')
        self.assertEqual((self.t / 'v2/bootstate.bin').stat().st_size, 8192)
        roles = {a['name']: a['role'] for a in inst['artifacts']}
        self.assertEqual((roles['boot-b.bin'], roles['bootstate.bin'], roles['sf-trust.txt']), ('boot-stage2-b', 'boot-state', 'boot-trust'))
        self.assertTrue(self.verify(self.t / 'v2', allow_rehearsal=True)['ok'])

    def test_stage1_v1_never_gets_the_ab_record(self):
        args = self.boot_variant('boot-v1b', stage1=Stage1Tests().image(), boot_b=True)
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'v1b'), '--rehearsal']), 0)
        inst = json.loads((self.t / 'v1b/install.json').read_text())
        self.assertFalse(inst['boot']['slots'])
        self.assertEqual(inst['boot']['stage2_b'], 'boot-b.bin')
        self.assertFalse((self.t / 'v1b/bootstate.bin').exists())
        # --slots yes with stage 1 v1 is refused outside a rehearsal; without boot-b.bin always
        self.assertEqual(self.make_release.main(self.args + ['--out', str(self.t / 'nob'), '--rehearsal', '--slots', 'yes']), 1)

    # The kernel collection as separate files (PAYLOAD.md section 13; release/kc_release.py)

    def kc(self, d=None):
        return json.loads(((d or self.t / 'rel') / 'install.json').read_text())['kernel_collection']

    def kc_files(self, d=None):
        d = d or self.t / 'rel'
        inst = json.loads((d / 'install.json').read_text())
        return {a['name']: (d / a['name'], a['sha256']) for a in inst['artifacts']}

    def test_kc_release_carries_inputs_not_the_collection(self):
        import kc_release
        inst = json.loads((self.t / 'rel/install.json').read_text())
        roles = {a['name']: a['role'] for a in inst['artifacts']}
        self.assertNotIn('kernel', inst['boot'])
        self.assertEqual(roles['kc-builder'], 'kc-tool')
        self.assertEqual(roles['kc.kernel'], 'kc-kernel')
        self.assertEqual(sum(r == 'kc-bundle-file' for r in roles.values()), 8)   # 3 kexts (2+2+3 files) + 1 codeless
        self.assertIn('kc.kexts.SFRehearsalC.kext.Contents.NOTICE', roles)
        kc = inst['kernel_collection']
        self.assertEqual(kc['link_args'][-2:], ['-o', '@OUTPUT@'])
        self.assertNotIn(kc['collection_sha256'], {a['sha256'] for a in inst['artifacts']})
        self.assertFalse(any(n.endswith(('.kc', 'collection')) for n in roles))
        kc_release.check_section(kc, {a['name']: a for a in inst['artifacts']})

    def test_kc_assembles_to_the_expected_hash(self):
        import kc_release
        out = kc_release.assemble(self.kc(), self.kc_files(), self.t / 'asm-good')
        self.assertEqual(sfrelease.sha256_file(out)[0], self.kc()['collection_sha256'])
        self.assertFalse((self.t / 'asm-good/inputs').exists())

    def test_kc_tampered_input_refused_before_linking(self):
        import kc_release
        d = self.copy()
        with (d / 'kc.kexts.SFRehearsalB.kext.Contents.MacOS.SFRehearsalB').open('ab') as f:
            f.write(b'x')
        with self.assertRaises(sfrelease.ReleaseError):
            self.verify(d, allow_rehearsal=True)
        with self.assertRaisesRegex(sfrelease.ReleaseError, 'signed hash'):
            kc_release.assemble(self.kc(), self.kc_files(self.t / 'rel') | {
                'kc.kexts.SFRehearsalB.kext.Contents.MacOS.SFRehearsalB':
                (d / 'kc.kexts.SFRehearsalB.kext.Contents.MacOS.SFRehearsalB', self.kc_files()['kc.kexts.SFRehearsalB.kext.Contents.MacOS.SFRehearsalB'][1])},
                self.t / 'asm-tamper')
        self.assertFalse((self.t / 'asm-tamper/collection').exists())

    def test_kc_wrong_expected_hash_leaves_no_collection(self):
        import kc_release
        kc = self.kc()
        kc['collection_sha256'] = '0' * 64
        with self.assertRaisesRegex(sfrelease.ReleaseError, 'not the release'):
            kc_release.assemble(kc, self.kc_files(), self.t / 'asm-wrong')
        self.assertFalse((self.t / 'asm-wrong/collection').exists())

    def test_kc_changed_options_change_the_collection(self):
        import kc_release
        kc = self.kc()
        i = kc['link_args'].index('-kc-base')
        kc['link_args'][i + 1] = 'fffffe0007000000'
        kc['kc_base'] = 'fffffe0007000000'
        with self.assertRaises(sfrelease.ReleaseError):
            kc_release.assemble(kc, self.kc_files(), self.t / 'asm-opts')

    def test_kc_section_rules(self):
        import kc_release
        inst = json.loads((self.t / 'rel/install.json').read_text())
        listed = {a['name']: a for a in inst['artifacts']}
        for mutate, why in [
            (lambda k: k['link_args'].insert(0, '-classic'), 'option'),
            (lambda k: k['link_args'].extend(['-aux-o', 'x']), 'option'),
            (lambda k: k['bundles'].reverse(), 'in order'),
            (lambda k: k['bundles'][0]['files'][0].update(artifact='kc.kernel'), 'bad file entry'),
            (lambda k: k['bundles'][0]['files'][0].update(path='../x'), 'bad file entry'),
            (lambda k: k['bundles'][0]['files'].pop(), 'not used'),
            (lambda k: k['tool'].update(signing='none'), 'signing'),
            (lambda k: k.pop('collection_sha256'), 'expected'),
            (lambda k: k['link_args'].__setitem__(k['link_args'].index('-kernel') + 1, '/etc/passwd'), 'kernel'),
            (lambda k: k['link_args'].__setitem__(k['link_args'].index('-kext') + 1, 'kexts/../../x.kext'), 'bundle'),
        ]:
            kc = json.loads(json.dumps(inst['kernel_collection']))
            mutate(kc)
            with self.assertRaisesRegex(sfrelease.ReleaseError, why):
                kc_release.check_section(kc, listed)

    def test_kc_expect_mismatch_refused(self):
        self.assertEqual(self.make_release.main(self.args + ['--out', str(self.t / 'kcexp'), '--rehearsal', '--kc-expect', '0' * 64]), 1)

    def test_kc_real_release_needs_developer_id_tool(self):
        args = [a if a != 'rehearsal-stand-in' else 'ad-hoc' for a in self.args]
        self.assertEqual(self.make_release.main(args + ['--out', str(self.t / 'adhoc')]), 1)

    def test_kc_failing_tool_refused(self):
        import kc_release
        files = self.kc_files()
        bad = self.t / 'false-kc-builder'
        bad.write_text('#!/bin/sh\nexit 3\n')
        files['kc-builder'] = (bad, sfrelease.sha256_file(bad)[0])
        with self.assertRaisesRegex(sfrelease.ReleaseError, 'failed'):
            kc_release.assemble(self.kc(), files, self.t / 'asm-fail')


if __name__ == '__main__':
    unittest.main()
