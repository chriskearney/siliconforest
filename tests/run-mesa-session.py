#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run inherited user-override and compositor recovery controls without a GPU."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'packaging/mesa/session'
with tempfile.TemporaryDirectory(prefix='sf-session-controls-') as temporary:
    out = Path(temporary)
    for name in ('mesa-m3-user-setup', 'mesa-m3-session-confirm'):
        shutil.copyfile(source / name, out / name)
        (out / name).chmod(0o755)
    subprocess.run(['cc', '-O2', str(source / 'mesa-m3-wlcheck.c'), '-lwayland-client',
                    '-o', str(out / 'wlcheck')], check=True)
    subprocess.run(['sh', str(ROOT / 'tests/mesa-session/test-user-setup.sh'),
                    str(out / 'mesa-m3-user-setup'), str(source / 'user-setup.list')], check=True)
    subprocess.run(['sh', str(ROOT / 'tests/mesa-session/test-confirm.sh'), str(out / 'wlcheck')],
                   check=True, env={**os.environ, 'CONFIRM': str(out / 'mesa-m3-session-confirm')})
