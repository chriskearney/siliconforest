"""Host-only checks of the real stage-2 composer and signed package inputs."""
import gzip
import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

from installer import boot, bootlogo
from installer.release import Refusal, validate, verify_packages
from test_installer import example, payload


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


class Stage2LogoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.data = example()
        self.retina = b'\x12\x34\x56\xff' * (256 * 256)
        self.standard = b'\x98\x76\x54\xff' * (128 * 128)
        self.logo = bootlogo.compose(self.retina, self.standard)
        self.configuration = b'display=main\n'
        self.data['boot']['m1n1_config'] = ['display=main']
        self.inputs = {'m1n1_sha256': b'LOADER WITH PADDING', 'dtb_sha256': b'DTB',
                       'uboot_sha256': b'U-BOOT'}
        self.files = {}
        for key, raw in self.inputs.items():
            self.files[key] = self.root / key
            self.files[key].write_bytes(raw)
            self.data['boot'][key] = sha(raw)

    def tearDown(self):
        self.tmp.cleanup()

    def enable(self, logo=None):
        raw = self.logo if logo is None else logo
        self.files['stage2_logo_sha256'] = self.root / 'logo'
        self.files['stage2_logo_sha256'].write_bytes(raw)
        self.data['boot']['stage2_logo_sha256'] = sha(raw)

    def image(self):
        return boot.image(self.data, self.files, self.configuration)

    def test_legacy_release_remains_byte_identical(self):
        self.assertEqual(self.image(), self.inputs['m1n1_sha256'] + self.inputs['dtb_sha256'] +
                         gzip.compress(self.inputs['uboot_sha256'], mtime=0) + self.configuration)

    def test_logo_is_first_payload_and_other_components_unchanged(self):
        old = self.image()
        self.enable()
        result = self.image()
        offset = len(self.inputs['m1n1_sha256'])
        self.assertEqual(result[:offset], old[:offset])
        self.assertEqual(result[offset:offset + len(self.logo)], self.logo)
        self.assertEqual(result[offset + len(self.logo):], old[offset:])
        self.assertEqual(self.logo[len(bootlogo.MAGIC):len(bootlogo.MAGIC) + 4 * 256**2], self.retina)
        self.assertEqual(self.logo[-4 * 128**2:], self.standard)

    def test_changed_logo_is_refused(self):
        self.enable()
        self.files['stage2_logo_sha256'].write_bytes(self.logo[:-1] + b'\x00')
        with self.assertRaisesRegex(Refusal, 'Boot input changed'):
            self.image()

    def test_signed_malformed_payloads_are_still_refused(self):
        for raw in (b'', self.logo[:-1], self.logo + b'x', b'x' + self.logo[1:], self.logo[:-1] + b'\x00'):
            with self.subTest(size=len(raw)):
                self.enable(raw)
                with self.assertRaises(Refusal):
                    self.image()

    def test_wrong_image_dimensions_refused(self):
        for retina, standard in ((self.standard, self.retina), (self.retina[:-4], self.standard)):
            with self.assertRaises(Refusal):
                bootlogo.compose(retina, standard)

    def test_signed_manifest_rejects_invalid_digest(self):
        for value in ('', '0' * 63, '../logo', None):
            self.data['boot']['stage2_logo_sha256'] = value
            with self.assertRaisesRegex(Refusal, 'artwork digest'):
                validate(self.data)

    def package_fixture(self, raw):
        self.enable()
        for component, spec in self.data['packages'].items():
            contents = payload(self.data, component)
            if component == 'm1n1' and raw is not None:
                contents['usr/share/siliconforest/stage2-logo.bin'] = raw
            target = self.root / spec['file']
            with tarfile.open(target, 'w') as archive:
                for name, value in contents.items():
                    blob = value.encode() if isinstance(value, str) else value
                    info = tarfile.TarInfo(name); info.size = len(blob)
                    archive.addfile(info, io.BytesIO(blob))
            spec['sha256'] = sha(target.read_bytes())

    def test_package_artwork_digest_is_checked_independently_of_package_hash(self):
        self.package_fixture(self.logo)
        verify_packages(self.root, self.data)
        self.package_fixture(self.logo[:-1] + b'\x00')
        with self.assertRaisesRegex(Refusal, 'Archived boot component differs'):
            verify_packages(self.root, self.data)

    def test_missing_packaged_artwork_is_refused(self):
        self.package_fixture(None)
        with self.assertRaisesRegex(Refusal, 'Missing required payload'):
            verify_packages(self.root, self.data)
