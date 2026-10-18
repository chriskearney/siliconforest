# SPDX-License-Identifier: MIT
"""Host-only tests. No package install, host configuration write or boot operation."""
import copy
import gzip
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from installer import boot
from installer import __main__ as cli
from installer.release import Refusal, PACKAGES, digest, validate, verify_signature, verify_packages, verify_database

ROOT = Path(__file__).resolve().parents[1]


def example():
    return json.loads((ROOT / 'release/release.example.json').read_text())


def tar(path, contents):
    with tarfile.open(path, 'w') as out:
        for name, data in contents.items():
            data = data.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            out.addfile(info, io.BytesIO(data))


class ReleaseTests(unittest.TestCase):
    def test_no_example_or_target_is_installable(self):
        validate(example())
        with self.assertRaisesRegex(Refusal, 'not hardware-qualified'):
            validate(example(), install=True)
        catalog = json.loads((ROOT / 'release/profiles.json').read_text())
        self.assertTrue(all(p['qualified'] is False for p in catalog['profiles'].values()))
        boards = {b['compatible'] for p in catalog['profiles'].values() for b in p['boards']}
        self.assertTrue(set(catalog['minimum_boards']) <= boards)

    def test_extra_package_is_refused(self):
        d = example()
        d['packages']['touchid'] = copy.deepcopy(d['packages']['mesa'])
        with self.assertRaises(Refusal):
            validate(d)

    def test_unbounded_firmware_or_traversal_is_refused(self):
        for key, value in [('dtb', '../../foreign.dtb'), ('entry', '/etc/passwd'), ('image', 'x/../y')]:
            with self.subTest(key=key):
                d = example()
                d['boot'][key] = value
                with self.assertRaises(Refusal):
                    validate(d)
        d = example()
        d['firmware'] = ['*']
        with self.assertRaises(Refusal):
            validate(d)

    def test_foreign_source_or_repository_is_refused(self):
        d = example()
        d['packages']['mesa']['source']['repository'] = 'aurora-silicon/mesa-aurora'
        with self.assertRaises(Refusal):
            validate(d)
        d = example()
        d['repository']['url'] = 'https://example.com/mesa'
        with self.assertRaises(Refusal):
            validate(d)

    def test_native_profile_cannot_admit_air_or_m1(self):
        for board in ('apple,j613', 'apple,j313'):
            d = example()
            d['boards'] = [board]
            d['kernel_variant'] = 'm3-native'
            with self.assertRaises(Refusal):
                validate(d)

    def test_air_requires_compat_mesa(self):
        d = example()
        d['boards'] = ['apple,j613']
        with self.assertRaisesRegex(Refusal, 'does not support M3 Air'):
            validate(d)
        d['packages']['mesa']['source']['branch'] = 'compat/m3-air-hal200'
        validate(d)

    def test_qualified_bundle_needs_every_board_and_result(self):
        d = example()
        d['qualification'].update(status='passed', report='hardware-report.txt', boards=d['boards'],
                                  desktop=True, hardware_renderer=True, boot_chain=True, rollback=True)
        validate(d, install=True)
        for key in ('desktop', 'hardware_renderer', 'boot_chain', 'rollback'):
            bad = copy.deepcopy(d)
            bad['qualification'][key] = False
            with self.assertRaises(Refusal):
                validate(bad, install=True)
        d['qualification']['boards'] = []
        with self.assertRaises(Refusal):
            validate(d, install=True)

    def test_package_metadata_and_source_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, d = Path(tmp), example()
            for component, name in PACKAGES.items():
                p = d['packages'][component]
                tar(root / p['file'], {'.PKGINFO': f'pkgname = {name}\npkgver = {p["version"]}\narch = aarch64\n',
                    'usr/share/siliconforest/' + component + '.json': json.dumps({'source_commit': p['source']['commit']})})
                p['sha256'] = digest(root / p['file'])
            verify_packages(root, d)
            (root / d['packages']['mesa']['file']).write_bytes(b'tampered')
            with self.assertRaisesRegex(Refusal, 'digest mismatch'):
                verify_packages(root, d)


class BootTests(unittest.TestCase):
    def test_managed_config_is_idempotent_and_keeps_existing_text(self):
        text = 'DTBS=original\n# local option\n'
        new = boot.managed(text, 'M1N1_UPDATE_DISABLED=1')
        self.assertTrue(new.startswith(text))
        self.assertEqual(boot.managed(new, 'M1N1_UPDATE_DISABLED=1'), new)
        for malformed in (boot.BEGIN, boot.END + '\n' + boot.BEGIN):
            with self.assertRaises(Refusal):
                boot.managed(malformed, '')

    def test_m1n1_options_preserve_machine_settings_without_shell_execution(self):
        data = boot.config_lines('# local\nchosen.test=old\ndisplay=retina\n', ['chosen.test=new'])
        self.assertEqual(data, b'display=retina\nchosen.test=new\n')
        with self.assertRaises(Refusal):
            boot.config_lines('source /tmp/foreign\n', [])

    def test_stage2_contains_exact_dtb_and_gzipped_uboot(self):
        with tempfile.TemporaryDirectory() as tmp:
            files, data = {}, example()
            for key, value in [('m1n1_sha256', b'LOADER'), ('dtb_sha256', b'BOARD'), ('uboot_sha256', b'UBOOT')]:
                p = Path(tmp) / key
                p.write_bytes(value)
                files[key] = p
                data['boot'][key] = digest(p)
            image = boot.image(data, files, b'chosen.local=1\n')
            self.assertTrue(image.startswith(b'LOADERBOARD'))
            self.assertTrue(image.endswith(b'chosen.local=1\n'))
            self.assertEqual(gzip.decompress(image[11:-15]), b'UBOOT')
            files['uboot_sha256'].write_bytes(b'CHANGED')
            with self.assertRaisesRegex(Refusal, 'changed before assembly'):
                boot.image(data, files, b'chosen.local=1\n')

    def test_atomic_write_refuses_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            boot.atomic(root / 'boot.bin', b'old')
            boot.atomic(root / 'boot.bin', b'new')
            self.assertEqual((root / 'boot.bin').read_bytes(), b'new')
            (root / 'link').symlink_to(root / 'boot.bin')
            with self.assertRaises(Refusal):
                boot.atomic(root / 'link', b'bad')
            self.assertEqual((root / 'boot.bin').read_bytes(), b'new')

    def test_boot_hook_does_nothing_without_active_profile(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(boot.os, 'geteuid', return_value=0), \
                patch.object(boot, 'INSTALLING', Path(tmp) / 'installing'), \
                patch.object(boot, 'ACTIVE', Path(tmp) / 'active'), patch.object(boot, 'run') as run:
            boot.boot_update()
            run.assert_not_called()

    def test_apply_rejects_unqualified_set_before_any_host_operation(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(cli.os, 'geteuid', return_value=0), \
                patch.object(cli, 'verified_bundle', side_effect=Refusal('not hardware-qualified')), \
                patch.object(cli, 'check_system') as check, patch.object(cli, 'snapshot') as snapshot:
            with self.assertRaises(Refusal):
                cli.apply(Path(tmp), 'A' * 40)
            check.assert_not_called()
            snapshot.assert_not_called()

    def test_hook_checks_all_components_and_boot_entry_before_writing_stage2(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, d = Path(tmp), example()
            d['qualification'].update(status='passed', report='fixture', boards=d['boards'],
                desktop=True, hardware_renderer=True, boot_chain=True, rollback=True)
            active = root / 'active.json'
            active.write_text(json.dumps(d))
            config = root / 'm1n1.conf'
            config.write_bytes(b'chosen.local=1\n')
            esp = root / 'esp'
            (esp / 'm1n1').mkdir(parents=True)
            target = esp / 'm1n1/boot.bin'
            target.write_bytes(b'known-good')
            (esp / d['boot']['image']).parent.mkdir(parents=True)
            (esp / d['boot']['image']).write_bytes(b'UKI fixture')
            (esp / d['boot']['entry']).write_text('linux-siliconforest boot():/' + d['boot']['image'])
            files = {}
            for key in ('m1n1_sha256', 'dtb_sha256', 'uboot_sha256'):
                files[key] = root / key
                files[key].write_bytes(key.encode())
                d['boot'][key] = digest(files[key])
            active.write_text(json.dumps(d))
            def query(args, **kwargs):
                self.assertEqual(args[:2], ['pacman', '-Q'])
                return args[2] + ' ' + d['packages'][next(k for k, v in PACKAGES.items() if v == args[2])]['version']
            with patch.object(boot.os, 'geteuid', return_value=0), patch.object(boot, 'ACTIVE', active), \
                    patch.object(boot, 'INSTALLING', root / 'installing'), patch.object(boot, 'CONFIG', config), \
                    patch.object(boot, 'identity', return_value=('apple,j313', d['firmware'][0])), \
                    patch.object(boot, 'system_esp', return_value=esp), \
                    patch.object(boot.subprocess, 'check_output', side_effect=query), \
                    patch.object(boot, 'check_files', side_effect=Refusal('U-Boot changed')):
                with self.assertRaises(Refusal):
                    boot.boot_update()
                self.assertEqual(target.read_bytes(), b'known-good')
            with patch.object(boot.os, 'geteuid', return_value=0), patch.object(boot, 'ACTIVE', active), \
                    patch.object(boot, 'INSTALLING', root / 'installing'), patch.object(boot, 'CONFIG', config), \
                    patch.object(boot, 'identity', return_value=('apple,j313', d['firmware'][0])), \
                    patch.object(boot, 'system_esp', return_value=esp), \
                    patch.object(boot.subprocess, 'check_output', side_effect=query), \
                    patch.object(boot, 'check_files', return_value=files):
                boot.boot_update()
                self.assertEqual(target.read_bytes(), boot.image(d, files, config.read_bytes()))


class DatabaseTests(unittest.TestCase):
    def test_repository_cannot_add_a_fourth_package_or_swap_an_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, d = Path(tmp), example()
            contents = {}
            for p in d['packages'].values():
                contents[p['name'] + '/desc'] = ('%NAME%\n' + p['name'] + '\n\n%VERSION%\n' + p['version'] +
                    '\n\n%FILENAME%\n' + p['file'] + '\n\n%SHA256SUM%\n' + p['sha256'] + '\n')
            tar(root / 'siliconforest.db', contents)
            verify_database(root, d)
            contents['touchid/desc'] = '%NAME%\ntouchid\n'
            tar(root / 'siliconforest.db', contents)
            with self.assertRaisesRegex(Refusal, 'Extra'):
                verify_database(root, d)
            del contents['touchid/desc']
            contents['linux-siliconforest/desc'] = contents['linux-siliconforest/desc'].replace('0' * 64, '1' * 64)
            tar(root / 'siliconforest.db', contents)
            with self.assertRaisesRegex(Refusal, 'SHA256SUM'):
                verify_database(root, d)


class SignatureTests(unittest.TestCase):
    def test_real_signature_wrong_identity_and_tamper(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / 'gpg'
            home.mkdir(mode=0o700)
            command = ['gpg', '--batch', '--homedir', str(home)]
            subprocess.run(command + ['--pinentry-mode', 'loopback', '--passphrase', '',
                '--quick-generate-key', 'SiliconForest fixture (NOT A RELEASE KEY)', 'ed25519', 'sign', '1d'],
                check=True, capture_output=True)
            listing = subprocess.check_output(command + ['--with-colons', '--list-keys'], text=True)
            fingerprint = next(l.split(':')[9] for l in listing.splitlines() if l.startswith('fpr:'))
            (root / 'release-key.asc').write_bytes(subprocess.check_output(command + ['--armor', '--export', fingerprint]))
            manifest = root / 'release.json'
            manifest.write_text(json.dumps(example()))
            subprocess.run(command + ['--detach-sign', str(manifest)], check=True, capture_output=True)
            self.assertEqual(verify_signature(root, fingerprint)['schema'], 1)
            with self.assertRaises(Refusal):
                verify_signature(root, 'A' * 40)
            manifest.write_text('{"schema":999}')
            with self.assertRaises(subprocess.CalledProcessError):
                verify_signature(root, fingerprint)
            # Exercise the entire signed, three-package download contract.
            data = example()
            descriptions = {}
            for component, name in PACKAGES.items():
                p = data['packages'][component]
                tar(root / p['file'], {'.PKGINFO': f'pkgname = {name}\npkgver = {p["version"]}\narch = aarch64\n',
                    'usr/share/siliconforest/' + component + '.json': json.dumps({'source_commit': p['source']['commit']})})
                p['sha256'] = digest(root / p['file'])
                descriptions[name + '/desc'] = ('%NAME%\n' + name + '\n\n%VERSION%\n' + p['version'] +
                    '\n\n%FILENAME%\n' + p['file'] + '\n\n%SHA256SUM%\n' + p['sha256'] + '\n')
            tar(root / 'siliconforest.db', descriptions)
            data['repository']['sha256'] = digest(root / 'siliconforest.db')
            manifest.write_text(json.dumps(data))
            for f in [manifest, root / 'siliconforest.db', *[root / p['file'] for p in data['packages'].values()]]:
                subprocess.run(command + ['--yes', '--detach-sign', str(f)], check=True, capture_output=True)
            self.assertEqual(cli.verified_bundle(root, fingerprint)['id'], data['id'])
            with self.assertRaisesRegex(Refusal, 'not hardware-qualified'):
                cli.verified_bundle(root, fingerprint, install=True)
            # A signed catalog chooses exactly one board/firmware child.
            catalog = root / 'catalog.json'
            catalog.write_text(json.dumps({'schema': 1, 'id': 'testing-catalog',
                'releases': [{'release': data['id'], 'boards': data['boards'], 'firmware': data['firmware']}]}))
            subprocess.run(command + ['--detach-sign', str(catalog)], check=True, capture_output=True)
            base = 'https://github.com/iconidentify/siliconforest/releases/download/'
            assets = {base + data['id'] + '/' + f.name: f.read_bytes() for f in root.iterdir()
                      if f.is_file() and f.name not in ('catalog.json', 'catalog.json.sig')}
            for name in ('catalog.json', 'catalog.json.sig', 'release-key.asc'):
                assets[base + 'testing-catalog/' + name] = (root / name).read_bytes()
            def fetch(url, target, **kwargs):
                Path(target).write_bytes(assets[url])
            out = root / 'download'
            out.mkdir()
            with patch.object(cli, 'download', side_effect=fetch), \
                    patch.object(boot, 'identity', return_value=(data['boards'][0], data['firmware'][0])):
                selected = cli.fetch_bundle('testing-catalog', out, fingerprint, catalog=True)
            self.assertEqual(selected['id'], data['id'])
            self.assertEqual(cli.verified_bundle(out, fingerprint)['id'], data['id'])


if __name__ == '__main__':
    unittest.main()
