# SPDX-License-Identifier: MIT
"""Three-component installer. No release is admitted without exact qualification."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import platform
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
import time

from . import boot
from .release import (PACKAGES, Refusal, asset_name, digest, download, require,
                      validate, verify_packages, verify_signature, verify_detached, verify_database)


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
    require(shutil.disk_usage(esp).free >= 512 * 1024**2, 'Need at least 512 MiB free on the paired ESP')
    overlays = Path('/usr/share/omarchy-platform/dtb-overlays')
    require(not overlays.exists() or not any(overlays.rglob('*.dtbo')),
            'Installed DT overlays need a qualified combined DTB; they cannot be silently dropped')
    dkms = Path('/var/lib/dkms')
    require(not dkms.is_dir() or not any(p.is_dir() for p in dkms.iterdir()),
            'Installed DKMS modules require matching headers; this candidate does not ship headers yet')
    if data:
        require(board in data['boards'], 'Release does not cover this exact board: ' + board)
        require(firmware in data['firmware'], 'Release does not cover OS firmware: ' + firmware)
        command = 'limine-update' if data['boot']['backend'] == 'limine' else 'update-grub'
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


def verified_bundle(directory, fingerprint, install=False):
    data = validate(verify_signature(directory, fingerprint), install=install)
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
    names = ['siliconforest.db', 'siliconforest.db.sig']
    for package in data['packages'].values():
        names.extend([package['file'], package['file'] + '.sig'])
    for name in names:
        download(base + '/' + name, directory / name)
    return data


def cached_previous():
    names = ['mesa', 'mesa-asahi-edge', 'vulkan-asahi', 'linux-asahi', 'linux-aurora', *PACKAGES.values()]
    result = []
    for name in names:
        installed = subprocess.run(['pacman', '-Q', name], text=True, capture_output=True)
        if installed.returncode:
            continue
        package, version = installed.stdout.split()
        candidates = list(Path('/var/cache/pacman/pkg').glob(f'{package}-{version}-aarch64.pkg.tar.*'))
        candidates = [p for p in candidates if not p.name.endswith('.sig')]
        require(len(candidates) == 1, 'Cache the current rollback package before installing: ' + installed.stdout.strip())
        result.append(candidates[0])
    return result


def snapshot(esp, data, previous):
    state = Path('/var/lib/siliconforest/transactions') / (str(time.time_ns()) + '-' + data['id'])
    state.mkdir(parents=True, mode=0o700)
    files = ['/etc/default/update-m1n1', '/etc/m1n1.conf', '/etc/siliconforest/m1n1.conf',
             '/etc/limine-entry-tool.conf', '/etc/pacman.conf', str(boot.ACTIVE)]
    entry_root = esp if data['boot']['backend'] == 'limine' else Path('/boot')
    files += [str(esp / 'm1n1/boot.bin'), str(entry_root / data['boot']['entry']),
              str(entry_root / data['boot']['image'])]
    files += [str(p) for p in (esp / 'EFI/Linux').glob('*.efi')]
    files = list(dict.fromkeys(files))
    record = {'files': {}, 'packages': [], 'status': 'prepared'}
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
    for image in (esp / 'EFI/Linux').glob('*.efi'):
        saved_image = recovery / 'EFI/Linux' / image.name
        saved_image.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(image, saved_image)
    menu = entry_root / data['boot']['entry']
    if menu.is_file():
        shutil.copy2(menu, recovery / 'boot-menu.cfg')
    (recovery / 'README.txt').write_text(
        'Stage 2 backup from before SiliconForest installation.\n'
        'With this paired ESP mounted, copy this boot.bin back to m1n1/boot.bin.\n'
        'Restore the saved EFI/Linux/*.efi files to the same paths on the ESP.\n'
        'Restore boot-menu.cfg to ' + str(menu) + ' (it may be on a separate /boot for GRUB).\n'
        'Then boot the retained previous kernel with its previous DTBs.\n'
        'Package/configuration rollback records on Linux: ' + str(state) + '\n')
    os.sync()
    return state, record


def restore_files(state, record):
    for item in record['files'].values():
        if item:
            require(digest(state / item['saved']) == item['sha256'], 'Rollback copy digest differs')
    for name, item in record['files'].items():
        path = Path(name)
        if item:
            saved = state / item['saved']
            boot.atomic(path, saved.read_bytes(), item.get('mode', 0o644))
        elif path.exists():
            path.unlink()
    os.sync()


def rollback(state):
    require(os.geteuid() == 0, 'Rollback requires root')
    root = Path('/var/lib/siliconforest/transactions').resolve()
    state = state.resolve()
    require(state.parent == root and state.is_dir() and state.stat().st_uid == 0,
            'Require an owned SiliconForest transaction directory')
    record = json.loads((state / 'transaction.json').read_text())
    previous = []
    previous_names = set()
    for package in record['packages']:
        path = state / asset_name(package['file'])
        require(digest(path) == package['sha256'], 'Rollback package hash differs')
        info = subprocess.check_output(['bsdtar', '-xOf', str(path), '.PKGINFO'], text=True)
        name = next(l.split(' = ', 1)[1] for l in info.splitlines() if l.startswith('pkgname = '))
        previous_names.add(name)
        previous.append(str(path))
    require(previous, 'No previous package set was recorded')
    boot.INSTALLING.touch(mode=0o600, exist_ok=False)
    try:
        # New package names can be removed without suppressing dependency checks.
        remove = [n for n in ('m1n1-siliconforest', 'linux-siliconforest') if n not in previous_names and
                  subprocess.run(['pacman', '-Q', n], capture_output=True).returncode == 0]
        with open('/dev/tty') as tty:
            if remove:
                subprocess.run(['pacman', '-R', *remove], check=True, stdin=tty)
            subprocess.run(['pacman', '-U', *previous], check=True, stdin=tty)
        restore_files(state, record)
        record['status'] = 'rolled-back-awaiting-boot-test'
        boot.atomic(state / 'transaction.json', json.dumps(record, indent=2).encode(), 0o600)
    finally:
        boot.INSTALLING.unlink(missing_ok=True)
    print('Previous stack/configuration restored. Reboot when ready; no reboot was performed.')


def apply(directory, fingerprint):
    require(os.geteuid() == 0, 'Install requires root; use the generated release bootstrap')
    with tempfile.TemporaryDirectory(prefix='siliconforest-install-', dir='/var/tmp') as tmp:
        trusted = Path(tmp) / 'bundle'
        shutil.copytree(directory, trusted, symlinks=False)
        data = verified_bundle(trusted, fingerprint, install=True)
        _, _, esp = check_system(data)
        previous = cached_previous()
        state, record = snapshot(esp, data, previous)
        boot.INSTALLING.touch(mode=0o600, exist_ok=False)
        try:
            conf = Path('/etc/default/update-m1n1')
            text = conf.read_text() if conf.exists() else ''
            boot.atomic(conf, boot.managed(text, 'M1N1_UPDATE_DISABLED=1').encode())
            boot.run('pacman-key', '--add', str(trusted / 'release-key.asc'))
            boot.run('pacman-key', '--lsign-key', fingerprint)
            config = Path('/etc/pacman.conf')
            require('[siliconforest]' not in config.read_text().split(boot.BEGIN)[0],
                    'Unmanaged SiliconForest repository already exists')
            block = '[siliconforest]\nSigLevel = Required DatabaseRequired\nServer = ' + data['repository']['url']
            boot.atomic(config, boot.managed(config.read_text(), block).encode())
            for package in data['packages'].values():
                for name in (package['file'], package['file'] + '.sig'):
                    shutil.copyfile(trusted / name, Path('/var/cache/pacman/pkg') / name)
            with open('/dev/tty') as tty:
                subprocess.run(['pacman', '-Syu', *['siliconforest/' + n for n in PACKAGES.values()]],
                               check=True, stdin=tty)
            boot.check_files(data)
            old_config = Path('/etc/m1n1.conf')
            boot.atomic('/etc/siliconforest/m1n1.conf', boot.config_lines(
                old_config.read_text() if old_config.exists() else '', data['boot']['m1n1_config']))
            if data['boot']['backend'] == 'limine':
                limine = Path('/etc/limine-entry-tool.conf')
                text = limine.read_text() if limine.exists() else ''
                boot.atomic(limine, boot.managed(text, 'BOOT_ORDER="linux-siliconforest, *, *fallback, Snapshots"').encode())
            boot.run('mkinitcpio', '-P')
            boot.run('limine-update' if data['boot']['backend'] == 'limine' else 'update-grub')
            boot.atomic(boot.ACTIVE, json.dumps(data, indent=2).encode(), 0o600)
            boot.INSTALLING.unlink()
            boot.boot_update()
            record['status'] = 'installed-awaiting-boot-test'
        except BaseException:
            record['status'] = 'failed-restore-incomplete'
            try:
                restore_files(state, record)
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
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--check', action='store_true', help='read-only host preflight')
    action.add_argument('--dry-run', action='store_true', help='verify a release without installing')
    action.add_argument('--install', action='store_true')
    action.add_argument('--boot-update', action='store_true', help=argparse.SUPPRESS)
    action.add_argument('--guard-transaction', action='store_true', help=argparse.SUPPRESS)
    action.add_argument('--rollback', type=Path, help='restore a recorded previous stack')
    parser.add_argument('--release', help='immutable published release tag')
    parser.add_argument('--catalog', action='store_true', help='select a board/firmware release from a signed catalog')
    parser.add_argument('--bundle', type=Path, help='local signed release directory')
    parser.add_argument('--fingerprint', default='', help='independently published full signing fingerprint')
    args = parser.parse_args()
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
        data = verified_bundle(directory, args.fingerprint, install=args.install)
        board, firmware, esp = check_system(data)
        print(json.dumps({'release': data['id'], 'board': board, 'firmware': firmware,
                          'packages': {k: v['name'] for k, v in data['packages'].items()},
                          'qualification': data['qualification']['status']}, indent=2), flush=True)
        if args.install:
            require(os.geteuid() == 0, 'Run the generated bootstrap to elevate after verification')
            with open('/run/lock/siliconforest-install.lock', 'a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                apply(directory, args.fingerprint)


if __name__ == '__main__':
    try:
        main()
    except (Refusal, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print('SiliconForest: ' + str(error), file=sys.stderr)
        sys.exit(1)
