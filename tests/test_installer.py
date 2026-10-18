# SPDX-License-Identifier: MIT
"""Host-only tests. No package install, host configuration write or boot operation."""
import copy
import builtins
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import struct
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from installer import boot, graphics, uki
from installer import __main__ as cli
from installer.release import Refusal, PACKAGES, digest, validate, verify_signature, verify_packages, verify_database

ROOT = Path(__file__).resolve().parents[1]


def fixture_uki(kernel):
    """A non-executable standard PE fixture with Linux and initrd sections."""
    out = bytearray(1024)
    out[:2] = b'MZ'
    struct.pack_into('<I', out, 60, 64)
    out[64:68] = b'PE\0\0'
    struct.pack_into('<HH', out, 68, 0xAA64, 2)
    struct.pack_into('<H', out, 84, 112)
    struct.pack_into('<H', out, 88, 0x20B)
    for index, (name, payload, offset) in enumerate([(b'.linux', kernel, 512), (b'.initrd', b'FIXTURE INITRD', 896)]):
        header = 200 + index * 40
        out[header:header + len(name)] = name
        struct.pack_into('<I', out, header + 8, len(payload))
        struct.pack_into('<II', out, header + 16, len(payload), offset)
        out[offset:offset + len(payload)] = payload
    return bytes(out)


def example():
    return json.loads((ROOT / 'release/release.example.json').read_text())


def tar(path, contents):
    with tarfile.open(path, 'w') as out:
        for name, data in contents.items():
            data = data.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            out.addfile(info, io.BytesIO(data))


def payload(data, component):
    p = data['packages'][component]
    files = {'.PKGINFO': f'pkgname = {p["name"]}\npkgver = {p["version"]}\narch = aarch64\n',
             'usr/share/siliconforest/' + component + '.json': json.dumps({'source_commit': p['source']['commit']})}
    modules = 'usr/lib/modules/' + data['kernel_release'] + '/'
    critical = {'kernel': {modules + 'vmlinuz': 'kernel_image_sha256', modules + 'config': 'config_sha256',
                           modules + 'dtbs/' + data['boot']['dtb']: 'dtb_sha256'},
                'mesa': {}, 'm1n1': {'usr/lib/siliconforest/m1n1.bin': 'm1n1_sha256'}}[component]
    for name, key in critical.items():
        files[name] = 'TEST FIXTURE ONLY: ' + key
        data['boot'][key] = hashlib.sha256(files[name].encode()).hexdigest()
    required = {'kernel': [modules + 'pkgbase'],
                'mesa': ['usr/lib/libEGL_mesa.so.0', 'usr/lib/libgbm.so.1', 'usr/lib/dri/asahi_dri.so'],
                'm1n1': ['usr/lib/siliconforest/installer.pyz', 'usr/share/libalpm/hooks/99-siliconforest-stage2.hook',
                         'usr/share/libalpm/hooks/00-siliconforest-transaction.hook']}[component]
    files.update({name: 'TEST FIXTURE ONLY' for name in required})
    return files


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

    def test_attended_candidate_is_explicit_and_never_claims_passed(self):
        d = example()
        d['qualification'].update(status='attended-testing', report='attended-plan.json')
        with self.assertRaisesRegex(Refusal, 'not hardware-qualified'):
            validate(d, install=True)
        validate(d, install=True, testing=True)
        self.assertFalse(d['qualification']['desktop'])
        d['boards'].append('apple,j293')
        with self.assertRaisesRegex(Refusal, 'one exact board/firmware pair'):
            validate(d, install=True, testing=True)

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
        d['qualification'].update(status='passed', report='hardware-report.txt', boards=d['boards'], firmware=d['firmware'],
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
                tar(root / p['file'], payload(d, component))
                p['sha256'] = digest(root / p['file'])
            verify_packages(root, d)
            (root / d['packages']['mesa']['file']).write_bytes(b'tampered')
            with self.assertRaisesRegex(Refusal, 'digest mismatch'):
                verify_packages(root, d)


class BootTests(unittest.TestCase):
    def test_runtime_dependencies_cannot_upgrade_the_installed_base(self):
        d = example()
        for upgrades_base in (False, True):
            with self.subTest(upgrades_base=upgrades_base):
                installed = []
                def output(args, **kwargs):
                    if args[0] == 'bsdtar':
                        return 'depend = llvm22-libs>=22\n'
                    self.assertEqual(args[:5], ['pacman', '-Sp', '--needed', '--print-format', '%n'])
                    return 'llvm22-libs\nglibc\n' if upgrades_base else 'llvm22-libs\n'
                def command(args, **kwargs):
                    if args[:2] == ['pacman', '-T']:
                        return subprocess.CompletedProcess(args, 127, stdout='llvm22-libs>=22\n')
                    if args[:2] == ['pacman', '-Q']:
                        return subprocess.CompletedProcess(args, 0 if args[-1] == 'glibc' else 1)
                    installed.append(args)
                    return subprocess.CompletedProcess(args, 0)
                with patch.object(cli.subprocess, 'check_output', side_effect=output), \
                     patch.object(cli.subprocess, 'run', side_effect=command), \
                     patch('builtins.open', return_value=io.StringIO()):
                    if upgrades_base:
                        with self.assertRaisesRegex(Refusal, 'Update the Omarchy base first'):
                            cli.install_runtime_dependencies(Path('/fixture'), d)
                        self.assertEqual(installed, [])
                    else:
                        self.assertEqual(cli.install_runtime_dependencies(Path('/fixture'), d), ['llvm22-libs'])
                        self.assertEqual(installed, [['pacman', '-S', '--needed', '--asdeps', 'llvm22-libs>=22']])

    def test_rollback_cache_accepts_real_epoch_metadata_with_either_filename(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp)
            package = cache / 'mesa-26.2.4-1-aarch64.pkg.tar.zst'
            tar(package, {'.PKGINFO': 'pkgname = mesa\npkgver = 1:26.2.4-1\narch = aarch64\n'})
            real_run = subprocess.run
            def query(args, **kwargs):
                if args[0] == 'pacman':
                    answer = ('mesa 1:26.2.4-1\n' if args[-1] == 'mesa' else
                              'linux-aurora 1-1\n' if args[-1] in ('linux-asahi', 'linux-aurora') else '')
                    return subprocess.CompletedProcess(args, 0 if answer else 1, stdout=answer)
                return real_run(args, **kwargs)
            def path(value):
                return cache if str(value) == '/var/cache/pacman/pkg' else Path(value)
            with patch.object(cli, 'Path', side_effect=path), patch.object(cli.subprocess, 'run', side_effect=query):
                kernel = cache / 'linux-aurora-1-1-aarch64.pkg.tar.zst'
                tar(kernel, {'.PKGINFO': 'pkgname = linux-aurora\npkgver = 1-1\narch = aarch64\n'})
                self.assertEqual(cli.cached_previous(), [package, kernel])
                renamed = cache / 'mesa-1:26.2.4-1-aarch64.pkg.tar.zst'
                package.rename(renamed)
                self.assertEqual(cli.cached_previous(), [renamed, kernel])

    def test_m3_stage1_handoff_must_match_exactly(self):
        with tempfile.TemporaryDirectory() as tmp:
            chosen, d = Path(tmp), example()
            d['boards'] = ['apple,j516s']
            d['boot'].update(stage1_versions=['stage1-exact'], iboot_versions=['iboot-exact'])
            (chosen / 'asahi,m1n1-stage1-version').write_bytes(b'stage1-exact\0')
            (chosen / 'asahi,iboot2-version').write_bytes(b'iboot-exact\0')
            def path(value):
                return chosen if str(value) == '/proc/device-tree/chosen' else Path(value)
            with patch.object(boot, 'Path', side_effect=path):
                boot.check_stage1(d)
                (chosen / 'asahi,iboot2-version').write_bytes(b'other-iboot\0')
                with self.assertRaisesRegex(Refusal, 'qualified M3 handoff'):
                    boot.check_stage1(d)
                (chosen / 'asahi,iboot2-version').write_bytes(b'iboot-exact\0')
                (chosen / 'asahi,m1n1-oslog-overlap').touch()
                with self.assertRaisesRegex(Refusal, 'log-buffer overlap'):
                    boot.check_stage1(d)

    def test_uki_contains_the_exact_kernel_and_bounded_sections(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'image.efi'
            p.write_bytes(fixture_uki(b'KERNEL FIXTURE'))
            expected = hashlib.sha256(b'KERNEL FIXTURE').hexdigest()
            uki.check(p, expected)
            with self.assertRaisesRegex(Refusal, 'pinned kernel'):
                uki.check(p, '0' * 64)
            wrong = bytearray(p.read_bytes())
            struct.pack_into('<I', wrong, 220, 2**31)
            p.write_bytes(wrong)
            with self.assertRaisesRegex(Refusal, 'payload section'):
                uki.check(p, expected)

    def test_recovery_uki_identifies_the_running_kernel_from_its_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            esp, d = Path(tmp), example()
            image = esp / 'EFI/Linux/previous.efi'
            image.parent.mkdir(parents=True)
            image.write_bytes(b'previous fixture')
            (esp / 'limine.conf').write_text('  //previous\n  comment: Kernel version: fixture-release\n'
                '  protocol: efi\n  path: boot():/EFI/Linux/previous.efi#abcd\n  //other\n')
            with patch.object(cli.platform, 'release', return_value='fixture-release'):
                self.assertEqual(cli.recovery_uki(esp, d), image)
            with patch.object(cli.platform, 'release', return_value='different-kernel'):
                with self.assertRaisesRegex(Refusal, 'currently running kernel'):
                    cli.recovery_uki(esp, d)

    def test_graphics_admission_requires_the_running_kernel_and_all_sources(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, d = Path(tmp), example()
            d['qualification'].update(status='passed', report='fixture', boards=d['boards'], firmware=d['firmware'],
                                     desktop=True, hardware_renderer=True, boot_chain=True, rollback=True)
            d['packages']['mesa']['source']['additional_sources'] = [{'role': 'vulkan',
                'repository': 'iconidentify/siliconforest-mesa', 'commit': 'a' * 40}]
            manifest = root / 'graphics.json'
            manifest.write_text(json.dumps(d))
            receipts = root / 'usr/share/siliconforest'
            receipts.mkdir(parents=True)
            for component, p in d['packages'].items():
                (receipts / (component + '.json')).write_text(json.dumps({
                    'source_commit': p['source']['commit'],
                    'additional_sources': p['source'].get('additional_sources', [])}))
            def path(value):
                return receipts if str(value) == '/usr/share/siliconforest' else Path(value)
            def query(args, **kwargs):
                p = next(p for p in d['packages'].values() if p['name'] == args[-1])
                return p['name'] + ' ' + p['version']
            with patch.object(graphics, 'MANIFEST', manifest), patch.object(graphics, 'Path', side_effect=path), \
                    patch.object(boot, 'dt_string', return_value=d['boot']['stage2_version']), \
                    patch.object(graphics.platform, 'release', return_value=d['kernel_release']), \
                    patch.object(boot, 'identity', return_value=(d['boards'][0], d['firmware'][0])), \
                    patch.object(graphics.subprocess, 'check_output', side_effect=query), \
                    patch.object(boot, 'check_files') as checked:
                self.assertEqual(graphics.admit(), d)
                checked.assert_called_once_with(d)
                with patch.object(boot, 'dt_string', return_value='previous-stage2'):
                    with self.assertRaisesRegex(Refusal, 'Running stage 2 differs'):
                        graphics.admit()
                with patch.object(graphics.platform, 'release', return_value='previous-stock-kernel'):
                    with self.assertRaisesRegex(Refusal, 'qualified SiliconForest kernel'):
                        graphics.admit()
                (receipts / 'mesa.json').write_text(json.dumps({'source_commit': d['packages']['mesa']['source']['commit']}))
                with self.assertRaisesRegex(Refusal, 'additional graphics sources differ'):
                    graphics.admit()

    def test_esp_budget_accounts_for_compressed_recovery_and_both_new_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            esp, data = Path(tmp), example()
            (esp / 'm1n1').mkdir()
            (esp / 'm1n1/boot.bin').write_bytes(b'OLD-STAGE2')
            (esp / 'EFI/Linux').mkdir(parents=True)
            raw = b'previous kernel image' * 100000
            (esp / 'EFI/Linux/stock.efi').write_bytes(raw)
            sizes = cli.recovery_image_sizes(esp)
            self.assertLess(sizes['stock.efi'], len(raw) // 10)
            with patch.object(cli, 'recovery_uki', return_value=esp / 'EFI/Linux/stock.efi'):
                self.assertEqual(cli.esp_space_required(esp, data), 10 + 8 * 1024**2 +
                    sizes['stock.efi'] + data['boot']['max_image_bytes'] + data['boot']['max_stage2_bytes'])
            for value in (0, 'unlimited', 1024**3):
                data['boot']['max_image_bytes'] = value
                with self.assertRaisesRegex(Refusal, 'bounded qualified boot-file size'):
                    validate(data)

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
            for configuration in (b'', b'\n'):
                with self.subTest(configuration=configuration):
                    image = boot.image(data, files, configuration)
                    payload = image[11:-len(configuration)] if configuration else image[11:]
                    self.assertEqual(gzip.decompress(payload), b'UBOOT')
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

    def test_active_stack_cannot_be_upgraded_outside_coordinated_transaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            active, installing = root / 'active', root / 'installing'
            active.touch()
            with patch.object(boot, 'ACTIVE', active), patch.object(boot, 'INSTALLING', installing), \
                    patch('sys.argv', ['siliconforest', '--guard-transaction']):
                with self.assertRaisesRegex(Refusal, 'matched installer'):
                    cli.main()
                installing.touch()
                cli.main()

    def test_restore_checks_all_backup_hashes_before_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first, second = root / 'first', root / 'second'
            first.write_bytes(b'current-first')
            second.write_bytes(b'current-second')
            (root / 'saved-first').write_bytes(b'old-first')
            (root / 'saved-second').write_bytes(b'CORRUPTED')
            record = {'files': {str(first): {'saved': 'saved-first', 'sha256': digest(root / 'saved-first')},
                                str(second): {'saved': 'saved-second', 'sha256': '0' * 64}}}
            with self.assertRaisesRegex(Refusal, 'Rollback copy digest'):
                cli.restore_files(root, record)
            self.assertEqual(first.read_bytes(), b'current-first')
            self.assertEqual(second.read_bytes(), b'current-second')

    def test_hook_checks_all_components_and_boot_entry_before_writing_stage2(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, d = Path(tmp), example()
            d['qualification'].update(status='passed', report='fixture', boards=d['boards'], firmware=d['firmware'],
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
            (esp / d['boot']['image']).write_bytes(fixture_uki(b'kernel fixture'))
            d['boot']['kernel_image_sha256'] = hashlib.sha256(b'kernel fixture').hexdigest()
            (esp / d['boot']['entry']).write_text('linux-siliconforest boot():/' + d['boot']['image'] +
                                                '\ncomment: Kernel version: ' + d['kernel_release'])
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
                d['boot']['max_image_bytes'] = 1024**2
                active.write_text(json.dumps(d))
                (esp / d['boot']['image']).write_bytes(b'x' * (1024**2 + 1))
                with self.assertRaisesRegex(Refusal, 'boot image exceeds'):
                    boot.boot_update()
                self.assertEqual(target.read_bytes(), b'known-good')
                (esp / d['boot']['image']).write_bytes(fixture_uki(b'kernel fixture'))
                boot.boot_update()
                self.assertEqual(target.read_bytes(), boot.image(d, files, config.read_bytes()))


class DatabaseTests(unittest.TestCase):
    def test_repository_cannot_add_a_fourth_package_or_swap_an_artifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, d = Path(tmp), example()
            contents = {}
            for p in d['packages'].values():
                contents[p['name'] + '/desc'] = ('%NAME%\n' + p['name'] + '\n\n%VERSION%\n' + p['version'] +
                    '\n\n%FILENAME%\n' + p['file'] + '\n\n%SHA256SUM%\n' + p['sha256'] + '\n\n%ARCH%\naarch64\n')
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
    def test_elevation_verifier_rechecks_bytes_before_executing(self):
        import importlib.util
        import sys
        sys.path.insert(0, str(ROOT / 'scripts'))
        spec = importlib.util.spec_from_file_location('sf_release_script', ROOT / 'scripts/release.py')
        tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tool)
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp) / 'fixture.pyz'
            payload.write_text('print("ONLY A TEST FIXTURE")\n')
            command = [sys.executable, '-I', '-c', tool.ROOT_VERIFIER, str(payload), digest(payload),
                       'testing-fixture', 'A' * 40, '']
            result = subprocess.run(command, check=True, text=True, capture_output=True)
            self.assertIn('ONLY A TEST FIXTURE', result.stdout)
            payload.write_text('raise SystemExit("UNVERIFIED CODE RAN")\n')
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('hash changed before elevation', result.stderr)
            self.assertNotIn('UNVERIFIED CODE RAN', result.stderr)

    def exercise_install(self, bundle, data, fingerprint, fail=False, rollback=False):
        """Run the coordinator with real signatures/files and sandboxed OS commands."""
        with tempfile.TemporaryDirectory(prefix='siliconforest-fake-host-') as tmp:
            host = Path(tmp)
            def mapped(value='.'):
                value = Path(value)
                if value.is_absolute() and value.parts[1] in ('etc', 'usr', 'var', 'run'):
                    return host / str(value).lstrip('/')
                return value
            esp = host / 'esp'
            (esp / 'm1n1').mkdir(parents=True)
            (esp / 'm1n1/boot.bin').write_bytes(b'OLD-STAGE2')
            (esp / 'EFI/Linux').mkdir(parents=True)
            (esp / 'EFI/Linux/stock.efi').write_bytes(b'OLD-UKI')
            (esp / data['boot']['entry']).write_text('stock kernel entry\n')
            old_config = 'DTBS=stock\n'
            for name, text in [('/etc/default/update-m1n1', old_config), ('/etc/m1n1.conf', 'display=test\n'),
                               ('/etc/pacman.conf', '[options]\nSigLevel = Required\n[core]\nServer = fixture\n')]:
                f = mapped(name)
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_text(text)
            uboot = mapped(data['boot']['uboot_path'])
            uboot.parent.mkdir(parents=True, exist_ok=True)
            uboot.write_bytes(b'qualified-u-boot fixture')
            active = mapped('/var/lib/siliconforest/active.json')
            installing = mapped('/run/siliconforest-installing')
            installing.parent.mkdir(parents=True, exist_ok=True)
            previous = host / 'mesa-1:1-1-aarch64.pkg.tar.zst'
            tar(previous, {'.PKGINFO': 'pkgname = mesa\npkgver = 1:1-1\narch = aarch64\n'})
            commands = []
            phase = {'rollback': False}
            real_run, real_open = subprocess.run, builtins.open
            def command(args, **kwargs):
                commands.append(args)
                if args[0] == 'pacman':
                    if args[1] == '-T':
                        return subprocess.CompletedProcess(args, 0, stdout='')
                    if args[1] == '-Q':
                        text = 'mesa 1\n' if len(args) == 2 else args[2] + ' ' + next(
                            p['version'] for p in data['packages'].values() if p['name'] == args[2]) + '\n'
                        return subprocess.CompletedProcess(args, 0, stdout=text)
                    if phase['rollback']:
                        self.assertEqual((esp / 'm1n1/boot.bin').read_bytes(), b'OLD-STAGE2')
                        self.assertEqual((esp / data['boot']['entry']).read_text(), 'stock kernel entry\n')
                        if args[1] == '-R':
                            self.assertEqual(set(args[2:]), {'linux-siliconforest', 'm1n1-siliconforest'})
                        else:
                            self.assertEqual(args, ['pacman', '-U', str(phase['state'] / previous.name)])
                        return subprocess.CompletedProcess(args, 0)
                    self.assertEqual(args[:2], ['pacman', '-U'])
                    self.assertEqual([Path(p).name for p in args[2:]],
                                     [data['packages'][k]['file'] for k in PACKAGES])
                    # Simulate the package transaction in this temporary filesystem.
                    for p in data['packages'].values():
                        with tarfile.open(bundle / p['file']) as archive:
                            for member in archive.getmembers():
                                if member.name.startswith('usr/'):
                                    archive.extract(member, host, filter='data')
                    return subprocess.CompletedProcess(args, 0)
                if args[0] == 'pacman-key':
                    return subprocess.CompletedProcess(args, 0)
                if args[0] == 'mkinitcpio':
                    if fail:
                        raise subprocess.CalledProcessError(1, args)
                    (esp / data['boot']['image']).write_bytes(b'NEW-UKI-FIXTURE')
                    return subprocess.CompletedProcess(args, 0)
                if args[0] == 'limine-mkinitcpio':
                    if fail:
                        raise subprocess.CalledProcessError(1, args)
                    kernel = mapped('/usr/lib/modules/' + data['kernel_release'] + '/vmlinuz').read_bytes()
                    (esp / data['boot']['image']).write_bytes(fixture_uki(kernel))
                    (esp / data['boot']['entry']).write_text('linux-siliconforest boot():/' + data['boot']['image'] +
                        '\ncomment: Kernel version: ' + data['kernel_release'])
                    return subprocess.CompletedProcess(args, 0)
                self.assertIn(args[0], ('gpg', 'bsdtar'))
                return real_run(args, **kwargs)
            def opened(name, *args, **kwargs):
                return io.StringIO() if name == '/dev/tty' else real_open(name, *args, **kwargs)
            cache = mapped('/var/cache/pacman/pkg')
            cache.mkdir(parents=True)
            with patch.object(cli, 'Path', side_effect=mapped), patch.object(boot, 'Path', side_effect=mapped), \
                    patch.object(cli.os, 'geteuid', return_value=0), patch.object(cli.os, 'sync'), \
                    patch.object(cli, 'check_system', return_value=('apple,j313', data['firmware'][0], esp)), \
                    patch.object(cli, 'cached_previous', return_value=[previous]), \
                    patch.object(cli, 'recovery_uki', return_value=esp / 'EFI/Linux/stock.efi'), \
                    patch.object(boot, 'ACTIVE', active), patch.object(boot, 'INSTALLING', installing), \
                    patch.object(boot, 'CONFIG', mapped('/etc/siliconforest/m1n1.conf')), \
                    patch.object(boot, 'identity', return_value=('apple,j313', data['firmware'][0])), \
                    patch.object(boot, 'system_esp', return_value=esp), \
                    patch.object(subprocess, 'run', side_effect=command), patch('builtins.open', side_effect=opened):
                if fail:
                    with self.assertRaises(subprocess.CalledProcessError):
                        cli.apply(bundle, fingerprint)
                else:
                    cli.apply(bundle, fingerprint)
                    if rollback:
                        state = next(mapped('/var/lib/siliconforest/transactions').iterdir())
                        # Older records may repeat the same archive after
                        # querying both a package and its provided alias.
                        record_path = state / 'transaction.json'
                        old_record = json.loads(record_path.read_text())
                        old_record['packages'].append(old_record['packages'][0])
                        record_path.write_text(json.dumps(old_record))
                        phase.update(rollback=True, state=state)
                        # The sandbox runs as an ordinary user. Model only the
                        # transaction-directory ownership; all bytes and paths
                        # still come from this temporary fake filesystem.
                        class OwnedState(type(state)):
                            def stat(self, **kwargs):
                                result = super().stat(**kwargs)
                                if str(self) == str(state):
                                    values = list(result)
                                    values[4] = 0
                                    return os.stat_result(values)
                                return result
                        cli.rollback(OwnedState(state))
            self.assertFalse(installing.exists())
            records = list(mapped('/var/lib/siliconforest/transactions').glob('*/transaction.json'))
            self.assertEqual(len(records), 1)
            record = json.loads(records[0].read_text())
            recovery = list((esp / 'siliconforest-recovery').iterdir())[0]
            self.assertEqual((recovery / 'boot.bin').read_bytes(), b'OLD-STAGE2')
            if fail:
                self.assertFalse((recovery / 'EFI/Linux/stock.efi.gz').exists())
                self.assertEqual(record['status'], 'failed-config-and-stage2-restored')
                self.assertEqual((esp / 'm1n1/boot.bin').read_bytes(), b'OLD-STAGE2')
                self.assertEqual(mapped('/etc/default/update-m1n1').read_text(), old_config)
                self.assertFalse(active.exists())
            elif rollback:
                self.assertEqual(record['status'], 'rolled-back-awaiting-boot-test')
                self.assertEqual((esp / 'm1n1/boot.bin').read_bytes(), b'OLD-STAGE2')
                self.assertEqual((esp / 'EFI/Linux/stock.efi').read_bytes(), b'OLD-UKI')
                self.assertFalse((esp / data['boot']['image']).exists())
                self.assertFalse(active.exists())
            else:
                self.assertEqual(gzip.decompress((recovery / 'EFI/Linux/stock.efi.gz').read_bytes()), b'OLD-UKI')
                self.assertEqual(record['status'], 'installed-awaiting-boot-test')
                self.assertNotEqual((esp / 'm1n1/boot.bin').read_bytes(), b'OLD-STAGE2')
                self.assertEqual(json.loads(active.read_text())['id'], data['id'])

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
                tar(root / p['file'], payload(data, component))
                p['sha256'] = digest(root / p['file'])
                descriptions[name + '/desc'] = ('%NAME%\n' + name + '\n\n%VERSION%\n' + p['version'] +
                    '\n\n%FILENAME%\n' + p['file'] + '\n\n%SHA256SUM%\n' + p['sha256'] + '\n\n%ARCH%\naarch64\n')
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
            # 'passed' here is a fixture solely to reach sandboxed OS operations.
            # No installer release or hardware evidence is produced by this test.
            data['qualification'].update(status='passed', report='TEST FIXTURE ONLY', boards=data['boards'], firmware=data['firmware'],
                desktop=True, hardware_renderer=True, boot_chain=True, rollback=True)
            data['boot']['uboot_sha256'] = hashlib.sha256(b'qualified-u-boot fixture').hexdigest()
            manifest.write_text(json.dumps(data))
            subprocess.run(command + ['--yes', '--detach-sign', str(manifest)], check=True, capture_output=True)
            self.exercise_install(root, data, fingerprint)
            self.exercise_install(root, data, fingerprint, fail=True)
            self.exercise_install(root, data, fingerprint, rollback=True)


if __name__ == '__main__':
    unittest.main()
