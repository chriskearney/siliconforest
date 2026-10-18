# SPDX-License-Identifier: MIT
"""Validate a complete, signed board-specific release, never a moving source tip."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
from urllib.parse import urlparse
from urllib.request import urlopen

PACKAGES = {'kernel': 'linux-siliconforest', 'mesa': 'mesa-siliconforest',
            'm1n1': 'm1n1-siliconforest'}
M3_BOARDS = {'apple,j514s', 'apple,j516s', 'apple,j514c', 'apple,j516c', 'apple,j613', 'apple,j615'}
SHA = re.compile(r'[0-9a-f]{64}')
COMMIT = re.compile(r'[0-9a-f]{40}')
TOKEN = re.compile(r'[A-Za-z0-9][A-Za-z0-9._+-]*')
REPOS = {name: 'iconidentify/siliconforest-' + ('linux' if name == 'kernel' else name)
         for name in PACKAGES}


class Refusal(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Refusal(message)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def relative(path):
    p = PurePosixPath(path)
    require(bool(path) and not p.is_absolute() and '..' not in p.parts and
            str(p) == path and '\\' not in path and '\n' not in path,
            'Unsafe release path: ' + path)
    return path


def asset_name(name):
    require(bool(TOKEN.fullmatch(name)), 'Unsafe asset name')
    return name


def download(url, target, limit=2 * 1024**3):
    parsed = urlparse(url)
    require(parsed.scheme == 'https' and parsed.hostname == 'github.com' and
            parsed.path.startswith('/iconidentify/'), 'Require a SiliconForest HTTPS asset URL')
    with urlopen(url, timeout=60) as source, Path(target).open('xb') as out:
        size = 0
        while chunk := source.read(1024 * 1024):
            size += len(chunk)
            require(size <= limit, 'Download exceeds size limit')
            out.write(chunk)


def verify_detached(directory, fingerprint):
    require(bool(re.fullmatch(r'[A-F0-9]{40}|[A-F0-9]{64}', fingerprint)),
            'A full independently published signing fingerprint is required')
    directory = Path(directory)
    with tempfile.TemporaryDirectory(prefix='siliconforest-gpg-') as tmp:
        command = ['gpg', '--batch', '--no-options', '--homedir', tmp]
        subprocess.run(command + ['--import', str(directory / 'release-key.asc')],
                       check=True, capture_output=True)
        result = subprocess.run(command + ['--status-fd=1', '--verify',
            str(directory / 'release.json.sig'), str(directory / 'release.json')],
            check=True, capture_output=True, text=True)
        valid = [line.split()[2:] for line in result.stdout.splitlines()
                 if line.startswith('[GNUPG:] VALIDSIG ')]
        require(len(valid) == 1 and fingerprint in (valid[0][0], valid[0][-1]),
                'Manifest signer does not match the pinned identity')


def verify_signature(directory, fingerprint):
    verify_detached(directory, fingerprint)
    return json.loads((Path(directory) / 'release.json').read_text())


def validate(data, *, install=False, testing=False):
    require(data.get('schema') == 1, 'Unsupported release schema')
    asset_name(data['id'])
    repository = data['repository']
    require(repository['name'] == 'siliconforest', 'Unexpected package channel')
    require(repository['url'] == 'https://github.com/iconidentify/siliconforest/releases/download/' + data['id'],
            'Repository must be the exact owned release')
    require(bool(SHA.fullmatch(repository['sha256'])), 'Missing repository digest')
    require(data['architecture'] == 'aarch64', 'Release must target aarch64')
    require(set(data['packages']) == set(PACKAGES), 'Require exactly kernel, Mesa and m1n1 packages')
    require(data['kernel_variant'] in ('normal', 'm3-native', 'native-gpu'), 'Unknown kernel variant')
    require(bool(TOKEN.fullmatch(data['kernel_release'])) and
            '-siliconforest-' in data['kernel_release'], 'Kernel needs a unique SiliconForest ABI name')
    for component, expected in PACKAGES.items():
        package = data['packages'][component]
        artifact = package.get('artifact')
        if artifact is not None:
            require(isinstance(artifact, dict) and set(artifact) == {'repository', 'tag'} and
                    artifact['repository'] == REPOS[component],
                    'Package artifacts must come from their exact public component repository')
            asset_name(artifact['tag'])
        if install and not testing:
            require(artifact is not None, 'Public releases require pinned component artifacts')
        require(package['name'] == expected, 'Unexpected package in minimal release')
        asset_name(package['file'])
        asset_name(package['version'])
        require(bool(SHA.fullmatch(package['sha256'])), 'Invalid package digest')
        require(package['source']['repository'] == REPOS[component], 'Require owned source repository')
        require(bool(COMMIT.fullmatch(package['source']['commit'])), 'Require exact source commit')
        extras = package['source'].get('additional_sources', [])
        require(isinstance(extras, list), 'Additional sources must be explicit')
        require(not extras or component == 'mesa', 'Only the combined Mesa package has additional sources')
        require(len({e['role'] for e in extras}) == len(extras), 'Duplicate additional source roles')
        for extra in extras:
            require(extra['role'] == 'vulkan' and extra['repository'] == REPOS['mesa'] and
                    bool(COMMIT.fullmatch(extra['commit'])), 'Unexpected additional Mesa source')
    require(data['boards'] and len(set(data['boards'])) == len(data['boards']), 'Require distinct boards')
    for board in data['boards']:
        require(bool(re.fullmatch(r'apple,j[0-9]+[a-z]?', board)), 'Require exact board compatible')
    require(data['firmware'] and all(isinstance(f, str) and f and '*' not in f for f in data['firmware']),
            'Require exact firmware identities')
    boot = data['boot']
    require(bool(TOKEN.fullmatch(boot.get('stage2_version', ''))), 'Require an exact stage 2 build identity')
    relative(boot['dtb'])
    require(boot['dtb'].endswith('.dtb'), 'Require a DTB')
    require(boot['backend'] in ('limine', 'grub'), 'Unknown boot backend')
    for key, maximum in [('max_image_bytes', 256 * 1024**2), ('max_stage2_bytes', 32 * 1024**2)]:
        require(type(boot.get(key)) is int and 1024**2 <= boot[key] <= maximum,
                'Require a bounded qualified boot-file size: ' + key)
    relative(boot['entry'])
    relative(boot['image'])
    require(isinstance(boot['m1n1_config'], list), 'Require explicit handoff configuration')
    for line in boot['m1n1_config']:
        require(bool(re.fullmatch(r'(chosen\.[A-Za-z0-9,._-]+|display|mitigations)=[^\n\r\x00]+', line)),
                'Invalid m1n1 option')
    require(bool(SHA.fullmatch(boot['uboot_sha256'])), 'Require exact existing U-Boot identity')
    require(boot['uboot_path'].startswith('/usr/'), 'U-Boot must be a packaged system file')
    require('..' not in PurePosixPath(boot['uboot_path']).parts, 'Invalid U-Boot path')
    for name in ('kernel_image_sha256', 'dtb_sha256', 'm1n1_sha256', 'config_sha256'):
        require(bool(SHA.fullmatch(boot[name])), 'Missing boot-chain digest: ' + name)
    if data['kernel_variant'] == 'm3-native':
        require(all(b in ('apple,j514s', 'apple,j516c') for b in data['boards']),
                'The native display DTBs only cover J514S/J516C')
        require('/m3-g15/' in '/' + boot['dtb'], 'Native profile requires the alternative DTB')
    if data['kernel_variant'] == 'native-gpu':
        require(data['boards'] == ['apple,j516s'] and boot['dtb'] == 'apple/t6030-j516s.dtb',
                'Native GPU with maintained display currently targets J516S only')
        require(data['packages']['mesa']['source']['branch'] in
                ('siliconforest/next', 'mesa/native-update-20261018'),
                'Native GPU requires the integrated native Mesa source')
        require(not data['packages']['mesa']['source'].get('additional_sources'),
                'Native GPU must not include a compatibility Vulkan driver')
    if any(b in ('apple,j613', 'apple,j615') for b in data['boards']):
        require(data['kernel_variant'] == 'normal', 'Air requires the normal kernel path')
        require(data['packages']['mesa']['source']['branch'].startswith('compat/'),
                'Main native Mesa does not support M3 Air')
    if set(data['boards']) & M3_BOARDS:
        for key in ('stage1_versions', 'iboot_versions'):
            values = boot.get(key)
            require(isinstance(values, list) and values and
                    all(isinstance(v, str) and v and '*' not in v for v in values),
                    'M3 requires exact qualified loader handoffs: ' + key)
    qualification = data['qualification']
    if install and testing:
        require(qualification.get('status') == 'attended-testing', 'Require an explicit attended test candidate')
        require(len(data['boards']) == len(data['firmware']) == 1,
                'Attended testing is limited to one exact board/firmware pair')
        require(bool(qualification.get('report')), 'Require an attended test plan/report location')
    elif install:
        require(qualification.get('status') == 'passed', 'This exact bundle is not hardware-qualified')
        require(bool(qualification.get('report')), 'Require a hardware qualification report')
        require(set(qualification.get('boards', [])) == set(data['boards']),
                'Qualification must cover every admitted board')
        require(set(qualification.get('firmware', [])) == set(data['firmware']),
                'Qualification must cover every admitted firmware identity')
        for check in ('desktop', 'hardware_renderer', 'boot_chain', 'rollback'):
            require(qualification.get(check) is True, 'Missing hardware result: ' + check)
    return data


def verify_packages(directory, data):
    directory = Path(directory)
    for package in data['packages'].values():
        path = directory / package['file']
        require(path.is_file() and not path.is_symlink(), 'Missing package: ' + path.name)
        require(digest(path) == package['sha256'], 'Package digest mismatch: ' + path.name)
        text = subprocess.check_output(['bsdtar', '-xOf', str(path), '.PKGINFO'], text=True)
        fields = {}
        for line in text.splitlines():
            if ' = ' in line:
                key, value = line.split(' = ', 1)
                fields.setdefault(key, []).append(value)
        for field, expected in [('pkgname', package['name']), ('pkgver', package['version']), ('arch', 'aarch64')]:
            require(fields.get(field) == [expected], 'Package metadata mismatch: ' + field)
        receipt = json.loads(subprocess.check_output(['bsdtar', '-xOf', str(path),
            'usr/share/siliconforest/' + next(k for k, v in PACKAGES.items() if v == package['name']) + '.json'], text=True))
        require(receipt['source_commit'] == package['source']['commit'], 'Package source receipt differs')
        require(receipt.get('additional_sources', []) == package['source'].get('additional_sources', []),
                'Additional package source receipts differ')
        members = set(subprocess.check_output(['bsdtar', '-tf', str(path)], text=True).splitlines())
        for member in members:
            relative(member.rstrip('/'))
        component = next(k for k, v in PACKAGES.items() if v == package['name'])
        modules = 'usr/lib/modules/' + data['kernel_release'] + '/'
        critical = {'kernel': {modules + 'vmlinuz': 'kernel_image_sha256',
                               modules + 'config': 'config_sha256',
                               modules + 'dtbs/' + data['boot']['dtb']: 'dtb_sha256'},
                    'mesa': {}, 'm1n1': {'usr/lib/siliconforest/m1n1.bin': 'm1n1_sha256'}}[component]
        for member, key in critical.items():
            require(member in members, 'Missing required payload: ' + member)
            raw = subprocess.check_output(['bsdtar', '-xOf', str(path), member])
            require(hashlib.sha256(raw).hexdigest() == data['boot'][key],
                    'Archived boot component differs: ' + member)
        dri = 'zink_dri.so' if package['source'].get('branch') == 'compat/m3-legacy' else 'asahi_dri.so'
        required = {'kernel': {modules + 'pkgbase'},
                    'mesa': {'usr/lib/libEGL_mesa.so.0', 'usr/lib/libgbm.so.1', 'usr/lib/dri/' + dri},
                    'm1n1': {'usr/lib/siliconforest/installer.pyz',
                             'usr/share/libalpm/hooks/99-siliconforest-stage2.hook',
                             'usr/share/libalpm/hooks/00-siliconforest-transaction.hook'}}[component]
        require(required <= members, 'Incomplete ' + component + ' package payload')
        if component == 'm1n1' and set(data['boards']) & M3_BOARDS:
            layout = json.loads(subprocess.check_output(['bsdtar', '-xOf', str(path),
                'usr/share/siliconforest/m1n1-layout.json'], text=True))
            require(layout['version'] == data['boot']['stage2_version'] and
                    layout['sha256'] == data['boot']['m1n1_sha256'] and
                    0 < layout['file_end'] <= 0x120000 and
                    layout['payload_offset'] >= layout['file_end'],
                    'M3 loader file part exceeds the reviewed stage-1 log-buffer boundary')


def verify_database(directory, data):
    database = Path(directory) / 'siliconforest.db'
    members = subprocess.check_output(['bsdtar', '-tf', str(database)], text=True).splitlines()
    expected = {p['name']: p for p in data['packages'].values()}
    seen = set()
    for member in members:
        relative(member.rstrip('/'))
        if not member.endswith('/desc'):
            continue
        text = subprocess.check_output(['bsdtar', '-xOf', str(database), member], text=True)
        fields = {}
        for block in text.strip().split('\n\n'):
            lines = block.splitlines()
            if lines:
                fields[lines[0].strip('%')] = lines[1:]
        name = fields.get('NAME', [''])[0]
        require(name in expected and name not in seen, 'Extra or duplicate package in repository')
        seen.add(name)
        p = expected[name]
        for field, value in [('VERSION', p['version']), ('FILENAME', p['file']), ('SHA256SUM', p['sha256']),
                             ('ARCH', 'aarch64')]:
            require(fields.get(field) == [value], 'Repository package differs: ' + field)
    require(seen == set(expected), 'Signed repository is missing a required component')
