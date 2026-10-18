# SPDX-License-Identifier: MIT
"""Three-component installer. No release is admitted without exact qualification."""
import argparse
import fcntl
import gzip
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zlib

from . import boot, graphics
from .release import (PACKAGES, Refusal, asset_name, digest, download, require,
                      validate, verify_packages, verify_signature, verify_detached, verify_database)


def recovery_uki(esp, data):
    if data['boot']['backend'] != 'limine':
        return None
    lines = (esp / data['boot']['entry']).read_text().splitlines()
    result = set()
    for index, line in enumerate(lines):
        if line.strip() != 'comment: Kernel version: ' + platform.release():
            continue
        for value in lines[index + 1:]:
            if value.strip().startswith(('/', 'comment: Kernel version:')):
                break
            match = re.fullmatch(r'\s*path:\s*boot\(\):/(EFI/Linux/[^/#\s]+\.efi)(?:#[0-9a-fA-F]+)?\s*', value)
            if match:
                result.add(esp / match[1])
    require(len(result) == 1, 'Identify one retained UKI for the currently running kernel before installing')
    image = result.pop()
    require(image.is_file() and not image.is_symlink(), 'Retained recovery UKI is missing or a symlink')
    return image


def recovery_image_sizes(esp, data=None):
    sizes = {}
    images = sorted((esp / 'EFI/Linux').glob('*.efi')) if data is None else [recovery_uki(esp, data)]
    for path in images:
        if path is None:
            continue
        require(path.is_file() and not path.is_symlink(), 'Recovery UKI must be a regular file')
        compressor = zlib.compressobj(6, zlib.DEFLATED, 31)
        size = 0
        with path.open('rb') as stream:
            while chunk := stream.read(1024 * 1024):
                size += len(compressor.compress(chunk))
        sizes[path.name] = size + len(compressor.flush())
    return sizes


def esp_space_required(esp, data):
    # UKIs are backed up compressed on the ESP; uncompressed originals also
    # live in the root-owned transaction. Keep space for a full new image,
    # the atomic stage-2 replacement and filesystem overhead simultaneously.
    old_loader = (esp / 'm1n1/boot.bin').stat().st_size
    new_image = data['boot']['max_image_bytes']
    final = sum(recovery_image_sizes(esp, data).values()) + new_image + data['boot']['max_stage2_bytes']
    # The qualified backend builds only our UKI in a temporary directory on
    # root. It does not regenerate every installed kernel or reinstall Limine.
    return old_loader + final + 8 * 1024**2


def check_system(data=None):
    require(platform.machine() == 'aarch64', 'Requires an existing aarch64 Apple Silicon Omarchy install')
    owner = pwd.getpwnam(os.environ['SUDO_USER']) if os.environ.get('SUDO_USER') else pwd.getpwuid(os.getuid())
    require(Path('/usr/share/omarchy').is_dir() or shutil.which('omarchy-version') or
            (Path(owner.pw_dir) / '.local/share/omarchy').is_dir(), 'Omarchy installation was not detected')
    board, firmware = boot.identity()
    esp = boot.system_esp()
    require(not Path('/var/lib/pacman/db.lck').exists(), 'pacman is busy')
    for command in ('pacman', 'pacman-key', 'gpg', 'bsdtar', 'mkinitcpio'):
        require(shutil.which(command), 'Missing system prerequisite: ' + command)
    require(shutil.disk_usage('/').free >= 4 * 1024**3, 'Need at least 4 GiB free on root')
    overlays = Path('/usr/share/omarchy-platform/dtb-overlays')
    require(not overlays.exists() or not any(overlays.rglob('*.dtbo')),
            'Installed DT overlays need a qualified combined DTB; they cannot be silently dropped')
    dkms = Path('/var/lib/dkms')
    require(not dkms.is_dir() or not any(p.is_dir() for p in dkms.iterdir()),
            'Installed DKMS modules require matching headers; this candidate does not ship headers yet')
    if data:
        boot.check_stage1(data)
        required = esp_space_required(esp, data)
        require(shutil.disk_usage(esp).free >= required,
                'Paired ESP needs ' + str((required + 1024**2 - 1) // 1024**2) +
                ' MiB free for compressed recovery copies and the qualified image limits')
        require(board in data['boards'], 'Release does not cover this exact board: ' + board)
        require(firmware in data['firmware'], 'Release does not cover OS firmware: ' + firmware)
        command = 'limine-mkinitcpio' if data['boot']['backend'] == 'limine' else 'update-grub'
        require(shutil.which(command), 'Missing qualified boot backend: ' + command)
        require(digest(data['boot']['uboot_path']) == data['boot']['uboot_sha256'],
                'Existing U-Boot differs from the qualified release')
    return board, firmware, esp


def signature(directory, name, fingerprint):
    with tempfile.TemporaryDirectory(prefix='siliconforest-signature-') as tmp:
        out = Path(tmp)
        for src, dst in [('release-key.asc', 'release-key.asc'), (name, 'release.json'),
                         (name + '.sig', 'release.json.sig')]:
            shutil.copyfile(directory / src, out / dst)
        verify_detached(out, fingerprint)


def verified_bundle(directory, fingerprint, install=False, testing=False):
    data = validate(verify_signature(directory, fingerprint), install=install, testing=testing)
    verify_packages(directory, data)
    database = directory / 'siliconforest.db'
    require(digest(database) == data['repository']['sha256'], 'Repository database digest differs')
    signature(directory, 'siliconforest.db', fingerprint)
    verify_database(directory, data)
    for item in data['packages'].values():
        signature(directory, item['file'], fingerprint)
    return data


def fetch_bundle(tag, directory, fingerprint, catalog=False):
    asset_name(tag)
    base = 'https://github.com/iconidentify/siliconforest/releases/download/' + tag
    if catalog:
        for remote, local in [('release-key.asc', 'release-key.asc'),
                              ('catalog.json', 'release.json'), ('catalog.json.sig', 'release.json.sig')]:
            download(base + '/' + remote, directory / local, limit=4 * 1024**2)
        index = verify_signature(directory, fingerprint)
        require(index.get('schema') == 1, 'Unsupported release catalog')
        board, firmware = boot.identity()
        matches = [r for r in index['releases'] if board in r['boards'] and firmware in r['firmware']]
        require(len(matches) == 1, 'No unique qualified release for this board and firmware')
        for name in ('release-key.asc', 'release.json', 'release.json.sig'):
            (directory / name).unlink()
        return fetch_bundle(matches[0]['release'], directory, fingerprint)
    for name in ('release-key.asc', 'release.json', 'release.json.sig'):
        download(base + '/' + name, directory / name, limit=4 * 1024**2)
    data = validate(verify_signature(directory, fingerprint))
    require(data['id'] == tag, 'Downloaded manifest names another release')
    for name in ('siliconforest.db', 'siliconforest.db.sig'):
        download(base + '/' + name, directory / name)
    for package in data['packages'].values():
        artifact = package.get('artifact')
        component_base = ('https://github.com/' + artifact['repository'] + '/releases/download/' +
                          artifact['tag']) if artifact else base
        for name in (package['file'], package['file'] + '.sig'):
            download(component_base + '/' + name, directory / name)
    return data


def cached_previous():
    names = ['mesa', 'mesa-asahi-edge', 'vulkan-asahi', 'mesa-m3', 'mesa-m3-native-pro',
             'mesa-m3-pro-vulkan', 'linux-asahi', 'linux-aurora', *PACKAGES.values()]
    result = []
    seen = set()
    for name in names:
        installed = subprocess.run(['pacman', '-Q', name], text=True, capture_output=True)
        if installed.returncode:
            continue
        package, version = installed.stdout.split()
        if (package, version) in seen:
            continue
        seen.add((package, version))
        candidates = set()
        for spelling in {version, version.split(':', 1)[-1]}:
            for path in Path('/var/cache/pacman/pkg').glob(f'{package}-{spelling}-aarch64.pkg.tar.*'):
                if path.name.endswith('.sig') or not path.is_file() or path.is_symlink():
                    continue
                text = subprocess.check_output(['bsdtar', '-xOf', str(path), '.PKGINFO'], text=True)
                fields = dict(line.split(' = ', 1) for line in text.splitlines()
                              if line.startswith(('pkgname = ', 'pkgver = ', 'arch = ')))
                if fields == {'pkgname': package, 'pkgver': version, 'arch': 'aarch64'}:
                    candidates.add(path)
        require(len(candidates) == 1, 'Cache the current rollback package before installing: ' + installed.stdout.strip())
        result.append(candidates.pop())
    return result


def install_runtime_dependencies(directory, data):
    requirements = set()
    for item in data['packages'].values():
        info = subprocess.check_output(['bsdtar', '-xOf', str(directory / item['file']), '.PKGINFO'], text=True)
        requirements.update(l.split(' = ', 1)[1] for l in info.splitlines() if l.startswith('depend = '))
    checked = subprocess.run(['pacman', '-T', *sorted(requirements)], text=True, capture_output=True)
    require(checked.returncode in (0, 127), 'Runtime dependency check failed')
    missing = checked.stdout.splitlines()
    if not missing:
        return []
    # Resolve against existing distribution indexes, without synchronizing or
    # upgrading the OS. Refuse any plan that changes an installed package.
    planned = subprocess.check_output(['pacman', '-Sp', '--needed', '--print-format', '%n', *missing], text=True).splitlines()
    require(planned, 'Missing runtime dependencies did not resolve')
    for name in planned:
        require(bool(re.fullmatch(r'[a-zA-Z0-9@._+-]+', name)), 'Unexpected dependency resolver output')
        require(subprocess.run(['pacman', '-Q', name], capture_output=True).returncode != 0,
                'Update the Omarchy base first; this runtime dependency would upgrade an installed package: ' + name)
    with open('/dev/tty') as tty:
        subprocess.run(['pacman', '-S', '--needed', '--asdeps', *missing], check=True, stdin=tty)
    return planned


def snapshot(esp, data, previous):
    from . import session
    state = Path('/var/lib/siliconforest/transactions') / (str(time.time_ns()) + '-' + data['id'])
    state.mkdir(parents=True, mode=0o700)
    files = [str(session.OVERRIDE), '/var/lib/pacman/sync/siliconforest.db', '/var/lib/pacman/sync/siliconforest.db.sig',
             '/etc/default/update-m1n1', '/etc/m1n1.conf', '/etc/siliconforest/m1n1.conf',
             '/etc/limine-entry-tool.conf', '/etc/default/limine', '/etc/pacman.conf', str(boot.ACTIVE), str(graphics.MANIFEST)]
    entry_root = esp if data['boot']['backend'] == 'limine' else Path('/boot')
    files += [str(esp / 'm1n1/boot.bin'), str(entry_root / data['boot']['entry']),
              str(entry_root / data['boot']['image'])]
    files += [str(p) for p in (esp / 'EFI/Linux').glob('*.efi')]
    files = list(dict.fromkeys(files))
    selected = recovery_uki(esp, data)
    record = {'files': {}, 'packages': [], 'status': 'prepared',
              'recovery_image': str(selected) if selected else None,
              'boot_files': [str(esp / 'm1n1/boot.bin'), str(entry_root / data['boot']['entry']),
                             str(entry_root / data['boot']['image']),
                             *[str(p) for p in (esp / 'EFI/Linux').glob('*.efi')]]}
    for index, name in enumerate(files):
        path = Path(name)
        require(not path.is_symlink(), 'Refuse a symlink configuration: ' + name)
        if path.exists():
            require(path.is_file(), 'Expected a regular configuration file: ' + name)
            saved = state / str(index)
            shutil.copy2(path, saved)
            record['files'][name] = {'saved': saved.name, 'sha256': digest(saved),
                                    'mode': stat.S_IMODE(path.stat().st_mode)}
        else:
            record['files'][name] = None
    for path in previous:
        shutil.copy2(path, state / path.name)
        record['packages'].append({'file': path.name, 'sha256': digest(state / path.name)})
    record['installed_before'] = subprocess.check_output(['pacman', '-Q'], text=True)
    boot.atomic(state / 'transaction.json', json.dumps(record, indent=2).encode(), 0o600)
    recovery = esp / 'siliconforest-recovery' / state.name
    recovery.mkdir(parents=True)
    shutil.copy2(esp / 'm1n1/boot.bin', recovery / 'boot.bin')
    menu = entry_root / data['boot']['entry']
    if menu.is_file():
        shutil.copy2(menu, recovery / 'boot-menu.cfg')
    (recovery / 'README.txt').write_text(
        'Stage 2 backup from before SiliconForest installation.\n'
        'With this paired ESP mounted, copy this boot.bin back to m1n1/boot.bin.\n'
        'Decompress each saved EFI/Linux/NAME.efi.gz to EFI/Linux/NAME.efi on the ESP.\n'
        'For example on macOS: gzip -dc NAME.efi.gz > /Volumes/ESP/EFI/Linux/NAME.efi\n'
        'Restore boot-menu.cfg to ' + str(menu) + ' (it may be on a separate /boot for GRUB).\n'
        'Then boot the retained previous kernel with its previous DTBs.\n'
        'Package/configuration rollback records on Linux: ' + str(state) + '\n')
    os.sync()
    return state, record


def complete_esp_recovery(esp, state, record):
    recovery = esp / 'siliconforest-recovery' / state.name
    for name, item in record['files'].items():
        path = Path(name)
        if item and name == record.get('recovery_image'):
            source = state / item['saved']
            require(digest(source) == item['sha256'], 'Recovery UKI snapshot digest differs')
            saved_image = recovery / 'EFI/Linux' / (path.name + '.gz')
            saved_image.parent.mkdir(parents=True, exist_ok=True)
            with source.open('rb') as stream, gzip.GzipFile(filename=str(saved_image), mode='wb',
                                                          compresslevel=6, mtime=0) as output:
                shutil.copyfileobj(stream, output)
    os.sync()


def restore_files(state, record, names=None):
    for item in record['files'].values():
        if item:
            require(digest(state / item['saved']) == item['sha256'], 'Rollback copy digest differs')
    for name, item in record['files'].items():
        if names is not None and name not in names:
            continue
        path = Path(name)
        if item:
            saved = state / item['saved']
            boot.atomic(path, saved.read_bytes(), item.get('mode', 0o644))
        elif path.exists():
            path.unlink()
    os.sync()


def rollback(state):
    from . import session
    require(os.geteuid() == 0, 'Rollback requires root')
    root = Path('/var/lib/siliconforest/transactions').resolve()
    state = state.resolve()
    require(state.parent == root and state.is_dir() and state.stat().st_uid == 0,
            'Require an owned SiliconForest transaction directory')
    record = json.loads((state / 'transaction.json').read_text())
    previous = []
    previous_names = set()
    for package in record['packages']:
        require(bool(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+:-]*', package['file'])),
                'Unsafe rollback package filename')
        path = state / package['file']
        require(digest(path) == package['sha256'], 'Rollback package hash differs')
        info = subprocess.check_output(['bsdtar', '-xOf', str(path), '.PKGINFO'], text=True)
        name = next(l.split(' = ', 1)[1] for l in info.splitlines() if l.startswith('pkgname = '))
        if name in previous_names:
            require(str(path) in previous, 'Ambiguous duplicate rollback package identity')
            continue
        previous_names.add(name)
        previous.append(str(path))
    require(previous, 'No previous package set was recorded')
    boot.INSTALLING.touch(mode=0o600, exist_ok=False)
    try:
        restore_files(state, record, names=record.get('boot_files', []))
        # New package names can be removed without suppressing dependency checks.
        remove = [n for n in ('m1n1-siliconforest', 'linux-siliconforest') if n not in previous_names and
                  subprocess.run(['pacman', '-Q', n], capture_output=True).returncode == 0]
        with open('/dev/tty') as tty:
            if remove:
                subprocess.run(['pacman', '-R', *remove], check=True, stdin=tty)
            subprocess.run(['pacman', '-U', *previous], check=True, stdin=tty)
        restore_files(state, record)
        session.apply(record.get('user_session'), restore=True)
        record['status'] = 'rolled-back-awaiting-boot-test'
        boot.atomic(state / 'transaction.json', json.dumps(record, indent=2).encode(), 0o600)
    finally:
        boot.INSTALLING.unlink(missing_ok=True)
    print('Previous stack/configuration restored. Reboot when ready; no reboot was performed.')


def apply(directory, fingerprint, testing=False):
    from . import session
    require(os.geteuid() == 0, 'Install requires root; use the generated release bootstrap')
    with tempfile.TemporaryDirectory(prefix='siliconforest-install-', dir='/var/tmp') as tmp:
        trusted = Path(tmp) / 'bundle'
        shutil.copytree(directory, trusted, symlinks=False)
        data = verified_bundle(trusted, fingerprint, install=True, testing=testing)
        _, _, esp = check_system(data)
        previous = cached_previous()
        migration = session.plan(data)
        state, record = snapshot(esp, data, previous)
        record['user_session'] = migration
        boot.atomic(state / 'transaction.json', json.dumps(record, indent=2).encode(), 0o600)
        boot.INSTALLING.touch(mode=0o600, exist_ok=False)
        try:
            record['added_runtime_dependencies'] = install_runtime_dependencies(trusted, data)
            conf = Path('/etc/default/update-m1n1')
            text = conf.read_text() if conf.exists() else ''
            boot.atomic(conf, boot.managed(text, 'M1N1_UPDATE_DISABLED=1').encode())
            boot.run('pacman-key', '--add', str(trusted / 'release-key.asc'))
            boot.run('pacman-key', '--lsign-key', fingerprint)
            config = Path('/etc/pacman.conf')
            require('[siliconforest]' not in config.read_text().split(boot.BEGIN)[0],
                    'Unmanaged SiliconForest repository already exists')
            if all(p.get('artifact') for p in data['packages'].values()):
                # Components have separate release hosts. Their matched set is
                # updated by this verifier, not independently through pacman -S.
                block = '# Matched component releases: update with the SiliconForest installer.'
            else:
                block = '[siliconforest]\nSigLevel = Required DatabaseRequired\nServer = ' + data['repository']['url']
            boot.atomic(config, boot.managed(config.read_text(), block).encode())
            for name in ('siliconforest.db', 'siliconforest.db.sig'):
                boot.atomic(Path('/var/lib/pacman/sync') / name, (trusted / name).read_bytes())
            for package in data['packages'].values():
                for name in (package['file'], package['file'] + '.sig'):
                    shutil.copyfile(trusted / name, Path('/var/cache/pacman/pkg') / name)
            if data['boot']['backend'] == 'limine':
                limine = Path('/etc/default/limine')
                text = limine.read_text() if limine.exists() else ''
                boot.atomic(limine, boot.managed(text, 'BOOT_ORDER="linux-siliconforest, *, *fallback, Snapshots"').encode())
            with open('/dev/tty') as tty:
                subprocess.run(['pacman', '-U', *[str(trusted / data['packages'][k]['file']) for k in PACKAGES]],
                               check=True, stdin=tty)
            boot.check_files(data)
            old_config = Path('/etc/m1n1.conf')
            boot.atomic('/etc/siliconforest/m1n1.conf', boot.config_lines(
                old_config.read_text() if old_config.exists() else '', data['boot']['m1n1_config']))
            if data['boot']['backend'] == 'limine':
                try:
                    boot.check_boot_image(data, esp)
                except (OSError, Refusal):
                    boot.run('limine-mkinitcpio', 'linux-siliconforest')
            else:
                boot.run('mkinitcpio', '-p', 'linux-siliconforest')
                boot.run('update-grub')
            complete_esp_recovery(esp, state, record)
            boot.atomic(boot.ACTIVE, json.dumps(data, indent=2).encode(), 0o600)
            boot.atomic(graphics.MANIFEST, json.dumps(data, indent=2).encode(), 0o644)
            session.apply(migration)
            boot.INSTALLING.unlink()
            boot.boot_update()
            record['status'] = 'installed-awaiting-boot-test'
        except BaseException:
            record['status'] = 'failed-restore-incomplete'
            try:
                restore_files(state, record)
                session.apply(migration, restore=True)
                record['status'] = 'failed-config-and-stage2-restored'
                print('Configuration and stage 2 restored. Packages may have changed; recovery records: ' + str(state), file=sys.stderr)
            except BaseException:
                print('Automatic boot-file restoration failed; use the paired ESP recovery copy. Records: ' + str(state), file=sys.stderr)
                raise
            raise
        finally:
            boot.INSTALLING.unlink(missing_ok=True)
            boot.atomic(state / 'transaction.json', json.dumps(record, indent=2).encode(), 0o600)
        print('Installed. Reboot when ready; exact boot success is not yet recorded. Recovery: ' + str(state))


def main():
    if os.geteuid() == 0:
        os.environ['PATH'] = '/usr/sbin:/usr/bin:/sbin:/bin'
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--check', action='store_true', help='read-only host preflight')
    action.add_argument('--dry-run', action='store_true', help='verify a release without installing')
    action.add_argument('--install', action='store_true')
    action.add_argument('--boot-update', action='store_true', help=argparse.SUPPRESS)
    action.add_argument('--guard-transaction', action='store_true', help=argparse.SUPPRESS)
    action.add_argument('--graphics-admit', action='store_true', help=argparse.SUPPRESS)
    action.add_argument('--rollback', type=Path, help='restore a recorded previous stack')
    parser.add_argument('--release', help='immutable published release tag')
    parser.add_argument('--catalog', action='store_true', help='select a board/firmware release from a signed catalog')
    parser.add_argument('--bundle', type=Path, help='local signed release directory')
    parser.add_argument('--fingerprint', default='', help='independently published full signing fingerprint')
    parser.add_argument('--test-candidate', action='store_true',
                        help='explicit attended installation of a signed, single-machine test candidate')
    args = parser.parse_args()
    if args.graphics_admit:
        graphics.admit()
        return
    require(not args.install or args.bundle or args.release, 'Installation requires an exact release or signed bundle')
    if args.boot_update:
        boot.boot_update()
        return
    if args.guard_transaction:
        require(boot.INSTALLING.exists() or not boot.ACTIVE.exists(),
                'Use the matched installer to upgrade or roll back an active stack component')
        return
    if args.rollback:
        with open('/run/lock/siliconforest-install.lock', 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            rollback(args.rollback)
        return
    if args.check or not (args.bundle or args.release):
        board, firmware, esp = check_system()
        print(json.dumps({'board': board, 'os_firmware': firmware, 'paired_esp': str(esp),
                          'status': 'host preflight only; no release qualification implied'}, indent=2))
        return
    with tempfile.TemporaryDirectory(prefix='siliconforest-download-') as tmp:
        directory = args.bundle.resolve() if args.bundle else Path(tmp)
        if not args.bundle:
            fetch_bundle(args.release, directory, args.fingerprint, args.catalog)
        data = verified_bundle(directory, args.fingerprint, install=args.install, testing=args.test_candidate)
        if os.geteuid() == 0:
            board, firmware, esp = check_system(data)
        else:
            # The paired ESP may legitimately be mounted root-only. Verify
            # signatures and exact selection here; apply repeats full target
            # preflight as root before taking a snapshot or changing packages.
            board, firmware = boot.identity()
            require(board in data['boards'] and firmware in data['firmware'], 'Release does not cover this board/firmware')
            print('Bundle verified; complete ESP/dependency preflight runs after elevation.', flush=True)
        print(json.dumps({'release': data['id'], 'board': board, 'firmware': firmware,
                          'packages': {k: v['name'] for k, v in data['packages'].items()},
                          'qualification': data['qualification']['status']}, indent=2), flush=True)
        if args.install:
            require(os.geteuid() == 0, 'Run the generated bootstrap to elevate after verification')
            with open('/run/lock/siliconforest-install.lock', 'a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                apply(directory, args.fingerprint, testing=args.test_candidate)


if __name__ == '__main__':
    try:
        main()
    except (Refusal, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print('SiliconForest: ' + str(error), file=sys.stderr)
        sys.exit(1)
