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
    data = validate(json.loads(MANIFEST.read_text()), install=True)
    board, firmware = boot.identity()
    require(board in data['boards'] and firmware in data['firmware'],
            'Running board/firmware is outside the qualified graphics set')
    require(platform.release() == data['kernel_release'], 'Boot the qualified SiliconForest kernel first')
    for component, name in PACKAGES.items():
        actual = subprocess.check_output(['pacman', '-Q', name], text=True).split()
        require(actual == [name, data['packages'][component]['version']], 'Mixed graphics package versions')
        receipt = json.loads((Path('/usr/share/siliconforest') / (component + '.json')).read_text())
        source = data['packages'][component]['source']
        require(receipt['source_commit'] == source['commit'], 'Installed graphics source differs')
        require(receipt.get('additional_sources', []) == source.get('additional_sources', []),
                'Installed additional graphics sources differ')
    boot.check_files(data)
    return data
