# SPDX-License-Identifier: MIT
"""Read-only admission of the running downstream graphics/boot contract."""
import json
import platform
from pathlib import Path
import subprocess

from . import boot
from .release import PACKAGES, require, validate

MANIFEST = Path('/etc/siliconforest/graphics.json')


def admit():
    data = json.loads(MANIFEST.read_text())
    validate(data, install=True, testing=data['qualification'].get('status') == 'attended-testing')
    board, firmware = boot.identity()
    require(board in data['boards'] and firmware in data['firmware'],
            'Running board/firmware is outside the qualified graphics set')
    require(platform.release() == data['kernel_release'], 'Boot the qualified SiliconForest kernel first')
    boot.check_stage1(data)
    require(boot.dt_string('/proc/device-tree/chosen/asahi,m1n1-stage2-version') ==
            data['boot']['stage2_version'], 'Running stage 2 differs from the matched graphics set')
    for component, name in PACKAGES.items():
        actual = subprocess.check_output(['pacman', '-Q', name], text=True).split()
        require(actual == [name, data['packages'][component]['version']], 'Mixed graphics package versions')
        receipt = json.loads((Path('/usr/share/siliconforest') / (component + '.json')).read_text())
        source = data['packages'][component]['source']
        require(receipt['source_commit'] == source['commit'], 'Installed graphics source differs')
        require(receipt.get('additional_sources', []) == source.get('additional_sources', []),
                'Installed additional graphics sources differ')
    boot.check_files(data)
    if data['kernel_variant'] == 'native-gpu':
        nodes = list(Path('/sys/class/drm').glob('renderD*'))
        require(len(nodes) == 1 and
                (nodes[0] / 'device/driver').resolve().name == 'asahi-g15',
                'Native G15 render device is not ready')
        compatibles = (nodes[0] / 'device/of_node/compatible').read_bytes().split(b'\0')
        require(b'apple,agx-t6030' in compatibles, 'Native render device is not T6030')
    return data
