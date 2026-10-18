#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Package built, pinned sources without installing into the builder host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipapp

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from installer.release import PACKAGES, TOKEN, require


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def installer_archive(output):
    with tempfile.TemporaryDirectory(prefix='siliconforest-zipapp-') as tmp:
        app = Path(tmp)
        shutil.copytree(ROOT / 'installer', app / 'installer',
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        (app / '__main__.py').write_text(
            "import runpy\nrunpy.run_module('installer', run_name='__main__')\n")
        zipapp.create_archive(app, output, interpreter='/usr/bin/env python3')


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def stage(component, source, build, tree, profile):
    if component == 'kernel':
        with (build / 'arch/arm64/boot/Image').open('rb') as stream:
            require(stream.read(64)[56:60] == b'ARMd', 'Require an ARM64 kernel Image')
        release = (build / 'kernelrelease').read_text().strip()
        require(TOKEN.fullmatch(release) and '-siliconforest-' in release, 'Wrong kernel ABI name')
        config = (build / '.config').read_text()
        native = '\nCONFIG_SILICONFOREST_M3=y\n' in '\n' + config
        require(native == (profile['kernel_variant'] == 'm3-native'), 'Wrong kernel profile')
        modules = tree / 'usr/lib/modules' / release
        run('make', '-C', source, 'O=' + str(build), 'ARCH=arm64', 'LLVM=1',
            'INSTALL_MOD_PATH=' + str(tree / 'usr'), 'INSTALL_MOD_STRIP=1', 'modules_install')
        copy(build / 'arch/arm64/boot/Image', modules / 'vmlinuz')
        copy(build / '.config', modules / 'config')
        (modules / 'pkgbase').write_text(PACKAGES['kernel'] + '\n')
        for board in profile['boards']:
            dtb = build / 'arch/arm64/boot/dts' / board['dtb']
            compatible = subprocess.check_output(['fdtget', '-t', 's', str(dtb), '/', 'compatible'], text=True).split()
            require(board['compatible'] in compatible, 'Board DTB identity differs from catalog')
            copy(dtb, modules / 'dtbs' / board['dtb'])
        for name in ('build', 'source'):
            (modules / name).unlink(missing_ok=True)
        copy(source / 'COPYING', tree / 'usr/share/licenses/linux-siliconforest/COPYING')
    elif component == 'mesa':
        info = build / 'meson-info'
        require(Path(json.loads((info / 'meson-info.json').read_text())['directories']['source']).resolve() == source,
                'Mesa build directory belongs to another source tree')
        options = {v['name']: v['value'] for v in json.loads((info / 'intro-buildoptions.json').read_text())}
        machine = json.loads((info / 'intro-machines.json').read_text())['host']
        require(machine['cpu_family'] == 'aarch64', 'Do not package host/shim Mesa as aarch64')
        require(options['prefix'] == '/usr' and options['libdir'] == 'lib' and
                options['glvnd'] == 'enabled', 'Require a production /usr GLVND build')
        run('meson', 'install', '-C', build, '--no-rebuild', env={**os.environ, 'DESTDIR': str(tree)})
        copy(source / 'docs/license.rst', tree / 'usr/share/licenses/mesa-siliconforest/LICENSE')
    else:
        flags = (build / 'build_cfg.h').read_text()
        require('#define RELEASE\n' in flags, 'Require a release stage 2 build')
        require(not any('#define ' + v in flags for v in ('CHAINLOADING', 'J613_ESP_STAGE1', 'ESP_STAGE2',
                                                        'J700_CDC_PROXY', 'T8140_KIS_PROXY')),
                'Refuse stage 1/proxy bootloader flags')
        copy(build / 'm1n1.bin', tree / 'usr/lib/siliconforest/m1n1.bin')
        installer_archive(tree / 'usr/lib/siliconforest/installer.pyz')
        command = tree / 'usr/bin/siliconforest-boot-update'
        command.parent.mkdir(parents=True, exist_ok=True)
        command.write_text('#!/bin/sh\nexec python3 /usr/lib/siliconforest/installer.pyz --boot-update\n')
        command.chmod(0o755)
        hook = tree / 'usr/share/libalpm/hooks/99-siliconforest-stage2.hook'
        hook.parent.mkdir(parents=True, exist_ok=True)
        hook.write_text('[Trigger]\nType = Path\nOperation = Install\nOperation = Upgrade\n'
                        'Target = usr/lib/modules/*\nTarget = usr/lib/asahi-boot/*\n'
                        'Target = usr/lib/siliconforest/*\n\n[Action]\n'
                        'Description = Verifying the matched SiliconForest stage 2...\n'
                        'When = PostTransaction\nExec = /usr/bin/siliconforest-boot-update\n')
        guard = hook.with_name('00-siliconforest-transaction.hook')
        guard.write_text('[Trigger]\nType = Package\nOperation = Install\nOperation = Upgrade\nOperation = Remove\n'
                         'Target = linux-siliconforest\nTarget = mesa-siliconforest\nTarget = m1n1-siliconforest\n'
                         '\n[Action]\nDescription = Checking SiliconForest rollback state...\n'
                         'When = PreTransaction\nAbortOnFail\n'
                         'Exec = /usr/bin/python3 /usr/lib/siliconforest/installer.pyz --guard-transaction\n')
        for f in [*source.glob('LICENSE*'), *list((source / '3rdparty_licenses').glob('*'))]:
            if f.is_file():
                copy(f, tree / 'usr/share/licenses/m1n1-siliconforest' / f.name)
        copy(ROOT / 'LICENSE', tree / 'usr/share/licenses/m1n1-siliconforest/LICENSE.SiliconForest-tools')
    # Every packaged ELF must be native ARM64, including any installed utilities.
    for f in tree.rglob('*'):
        if f.is_file() and not f.is_symlink():
            with f.open('rb') as stream:
                header = stream.read(20)
            if header.startswith(b'\x7fELF'):
                require(len(header) == 20 and header[4:6] == bytes([2, 1]) and int.from_bytes(header[18:20], 'little') == 183,
                        'Non-aarch64 ELF in payload: ' + str(f))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('component', choices=PACKAGES)
    p.add_argument('--profile', required=True)
    p.add_argument('--source', required=True, type=Path)
    p.add_argument('--build', required=True, type=Path)
    p.add_argument('--version', required=True, help='shared bundle pkgver, excluding pkgrel')
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    require(TOKEN.fullmatch(a.version) and '-' not in a.version, 'Invalid Arch pkgver')
    profile = json.loads((ROOT / 'release/profiles.json').read_text())['profiles'][a.profile]
    lock = json.loads((ROOT / 'sources.lock.json').read_text())
    component = a.component
    source = a.source.resolve()
    expected = (profile['mesa']['commit'] if component == 'mesa' else profile['m1n1']
                if component == 'm1n1' else lock['sources']['linux']['commit'])
    head = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    require(head == expected, 'Source differs from profile pin')
    require(not subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True),
            'Source contains uncommitted changes')
    build = a.build.resolve()
    a.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='siliconforest-package-') as tmp:
        work = Path(tmp)
        tree = work / 'payload'
        tree.mkdir()
        stage(component, source, build, tree, profile)
        receipt = {'component': component, 'source_commit': expected, 'profile': a.profile,
                   'control_commit': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()}
        path = tree / 'usr/share/siliconforest' / (component + '.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(receipt, indent=2) + '\n')
        tar = work / 'payload.tar'
        with tarfile.open(tar, 'w') as archive:
            for child in sorted(tree.iterdir()):
                archive.add(child, arcname=child.name)
        sha = hashlib.sha256(tar.read_bytes()).hexdigest()
        depends = {'kernel': ['kmod', 'mkinitcpio'],
                   'mesa': ['expat', 'gcc-libs', 'libdisplay-info', 'libdrm', 'libelf', 'libglvnd', 'libunwind',
                            'libx11', 'libxcb', 'libxext', 'libxfixes', 'libxshmfence',
                            'libxrandr', 'libxxf86vm', 'xcb-util-keysyms', 'systemd-libs',
                            'vulkan-icd-loader', 'wayland', 'zlib', 'zstd', 'llvm22-libs'],
                   'm1n1': ['python']}[component]
        def array(values):
            return '(' + ' '.join("'" + v + "'" for v in values) + ')'
        extra = ''
        if component == 'mesa':
            version = (source / 'VERSION').read_text().strip().split('-')[0]
            provides = ['mesa=1:' + version, 'opengl-driver', 'libgbm.so']
            if any((tree / 'usr/share/vulkan/icd.d').glob('*asahi*.json')):
                provides += ['vulkan-asahi=1:' + version, 'vulkan-driver']
            extra = 'provides=' + array(provides) + '\n'
            extra += 'conflicts=' + array(['mesa', 'mesa-asahi-edge', 'vulkan-asahi']) + '\n'
        (work / 'PKGBUILD').write_text(
            'pkgname=' + PACKAGES[component] + '\npkgver=' + a.version + '\npkgrel=1\n'
            "pkgdesc='SiliconForest matched " + component + "'\narch=('aarch64')\n"
            "url='https://github.com/iconidentify/siliconforest'\nlicense=('LicenseRef-Upstream')\n"
            'depends=' + array(depends) + '\n' + extra + "options=('!strip' '!debug')\n"
            "source=('payload.tar')\nsha256sums=('" + sha + "')\nnoextract=('payload.tar')\n"
            'package() { bsdtar -xf "$srcdir/payload.tar" -C "$pkgdir"; }\n')
        run('makepkg', '--nodeps', cwd=work,
            env={**os.environ, 'PKGDEST': str(a.output.resolve()), 'CARCH': 'aarch64'})
        candidates = list(a.output.glob(PACKAGES[component] + '-' + a.version + '-1-aarch64.pkg.tar.*'))
        candidates = [p for p in candidates if not p.name.endswith('.sig')]
        require(len(candidates) == 1, 'Missing unambiguous aarch64 package output')
        info = subprocess.check_output(['bsdtar', '-xOf', str(candidates[0]), '.PKGINFO'], text=True)
        require('\narch = aarch64\n' in '\n' + info, 'makepkg output architecture differs')
        print('Created uninstalled candidate package; signing and qualification are separate.')


if __name__ == '__main__':
    main()
