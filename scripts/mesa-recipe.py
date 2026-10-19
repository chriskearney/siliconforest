#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare a pinned Mesa recipe for the disposable maclab ARM64 builder."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from installer.release import TOKEN, require

# Public LLVM/SPIR-V inputs retained by the existing build infrastructure.
# Hashes identify the source bytes, including the LLVM 22.1.8 libclc subset.
INPUTS = {
    'llvm-project-22.1.8-libclc.tar.zst': '3d41db41e1e566c1db697ca7acd521d8d8d457de8af84cbaf4ad6ac14ae0af23',
    'SPIRV-LLVM-Translator-0e67244.tar.gz': 'b43abf03cfe1614b562a7c84d829a9f29d0443e23ac75a622ce622744c5a7ada',
    'SPIRV-Headers-575b651.tar.gz': '775ee89eb77d067df3f5736e2b4bb2f5f3e39ead915f11f3d366139dcb42209d',
    'SPIRV-Tools-vulkan-sdk-1.4.357.0.tar.gz': 'd31e7109b6ef3559067e53e520870eafed7c9534d00db9728814b6df03fa4a5e',
    'SPIRV-Headers-vulkan-sdk-1.4.357.0.tar.gz': '4d703067a7e06331ccb37bdfed3f9b7879cc61969a2689ae95c95db34a47ff07',
}


def git(source, *args):
    return subprocess.check_output(['git', '-C', str(source), *args], text=True).strip()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def archive(source, commit, prefix, output):
    with output.open('xb') as stream:
        process = subprocess.Popen(['git', '-C', str(source), 'archive', '--format=tar',
                                    '--prefix=' + prefix + '/', commit], stdout=subprocess.PIPE)
        try:
            subprocess.run(['zstd', '-q', '-T4', '-3'], stdin=process.stdout, stdout=stream, check=True)
        finally:
            process.stdout.close()
        require(process.wait() == 0, 'Source export failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--source', type=Path, required=True, help='public Mesa object store containing the exact pins')
    parser.add_argument('--toolchain-inputs', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    a = parser.parse_args()
    require(TOKEN.fullmatch(a.version) and '-' not in a.version, 'Invalid package version')
    require(not git(ROOT, 'status', '--porcelain'), 'Commit control changes before preparing a source receipt')
    profile = json.loads((ROOT / 'release/profiles.json').read_text())['profiles'][a.profile]
    primary = profile['mesa']['commit']
    llvm_owner = profile['mesa'].get('runtime_llvm_owner')
    require(llvm_owner in (None, 'llvm-libs', 'llvm22-libs'), 'Unsupported target LLVM runtime owner')
    extras = profile['mesa'].get('additional_sources', [])
    for name, expected in INPUTS.items():
        require(digest(a.toolchain_inputs / name) == expected, 'Compiler input digest differs: ' + name)
    require(not a.output.exists(), 'Use a fresh recipe directory')
    a.output.mkdir(parents=True)
    files = []
    for commit, prefix in [(primary, 'mesa'), *[(e['commit'], 'mesa-' + e['role']) for e in extras]]:
        require(git(a.source, 'cat-file', '-t', commit) == 'commit', 'Missing exact public source commit')
        name = prefix + '-' + commit + '.tar.zst'
        archive(a.source, commit, prefix, a.output / name)
        files.append(name)
    for name in INPUTS:
        shutil.copy2(a.toolchain_inputs / name, a.output / name)
        files.append(name)
    receipt = {'component': 'mesa', 'source_commit': primary, 'additional_sources': extras,
               'profile': a.profile, 'control_commit': git(ROOT, 'rev-parse', 'HEAD')}
    if llvm_owner:
        receipt['runtime_llvm_owner'] = llvm_owner
    (a.output / 'mesa-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    shutil.copy2(ROOT / 'packaging/mesa/needs-derive.py', a.output / 'needs-derive.py')
    shutil.copy2(ROOT / 'packaging/mesa/build-registered-tests.py', a.output / 'build-registered-tests.py')
    with tarfile.open(a.output / 'session.tar', 'w') as stream:
        stream.add(ROOT / 'packaging/mesa/session', arcname='session',
                   filter=lambda info: None if '__pycache__' in info.name or info.name.endswith('.pyc') else info)
    files += ['mesa-receipt.json', 'needs-derive.py', 'build-registered-tests.py', 'session.tar']
    arrays = ('source=(' + ' '.join(repr(n) for n in files) + ')\nsha256sums=(' +
              ' '.join(repr(digest(a.output / n)) for n in files) + ')')
    version = git(a.source, 'show', primary + ':VERSION').split('-')[0]
    template = (ROOT / 'packaging/mesa/PKGBUILD.in').read_text()
    for key, value in {'VERSION': a.version, 'PROFILE': a.profile, 'MESA_VERSION': version,
                       'SOURCE_ARRAYS': arrays,
                       'LLVM_RUNTIME_ARGS': '--llvm-runtime-owner ' + llvm_owner if llvm_owner else ''}.items():
        template = template.replace('__' + key + '__', value)
    (a.output / 'PKGBUILD').write_text(template)
    subprocess.run(['bash', '-n', a.output / 'PKGBUILD'], check=True)
    print('Prepared uninstalled ARM64 recipe:', a.output)
    print('Run: lab package', a.output, '--no-wait')


if __name__ == '__main__':
    main()
