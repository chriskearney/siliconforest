#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Attended read-only boot, compositor and GPU readback checks on a target Mac.

Run as root after boot, with independently built ARM64 probes. Screenshots stay
in the supplied local output directory; the JSON contains only selected evidence.
This program installs nothing, changes no configuration and never reboots.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--user', required=True)
p.add_argument('--probes', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--manifest', type=Path, help='root-owned installed SiliconForest manifest')
a = p.parse_args()
assert os.geteuid() == 0, 'Run with root read access to compositor mappings'
assert platform.machine() == 'aarch64'
owner = pwd.getpwnam(a.user)
a.output.mkdir(mode=0o700, parents=True, exist_ok=False)


def run(command, **kwargs):
    return subprocess.check_output(command, text=True, timeout=45, **kwargs).strip()


def sha(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


chosen = Path('/proc/device-tree/chosen')
compatible = Path('/proc/device-tree/compatible').read_bytes().rstrip(b'\0').decode().split('\0')
board = next(c for c in compatible if c.startswith('apple,j'))
firmware = (chosen / 'asahi,os-fw-version').read_bytes().rstrip(b'\0').decode()
report = {'schema': 1, 'board': board, 'os_firmware': firmware,
          'kernel_release': platform.release(), 'status': 'in-progress', 'checks': {}}
report['system_state'] = run(['systemctl', 'is-system-running'])
assert report['system_state'] == 'running', report['system_state']
report['checks']['boot_health'] = True

candidates = []
for proc in Path('/proc').iterdir():
    if not proc.name.isdecimal():
        continue
    try:
        if proc.stat().st_uid != owner.pw_uid:
            continue
        executable = (proc / 'exe').resolve(strict=True)
        if executable.name in ('Hyprland', 'Hyprland.full', 'chonkstep-wayland'):
            candidates.append(proc)
    except (FileNotFoundError, PermissionError):
        pass
assert len(candidates) == 1, 'Expected one active compositor'
proc = candidates[0]
# Keep only the environment required for the same GUI/graphics path. Never
# serialize the complete process environment or unrelated user variables.
allowed = {'XDG_RUNTIME_DIR', 'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE',
           'DBUS_SESSION_BUS_ADDRESS', 'LD_LIBRARY_PATH', 'LIBGL_DRIVERS_PATH',
           'GBM_BACKENDS_PATH', 'DRIRC_CONFIGDIR', '__EGL_VENDOR_LIBRARY_FILENAMES',
           'MESA_LOADER_DRIVER_OVERRIDE', 'GALLIUM_DRIVER', 'LIBGL_ALWAYS_SOFTWARE',
           'GBM_ALWAYS_SOFTWARE'}
env = {'PATH': '/usr/bin:/bin', 'HOME': owner.pw_dir, 'USER': a.user}
for entry in (proc / 'environ').read_bytes().split(b'\0'):
    if b'=' not in entry:
        continue
    k, v = entry.decode().split('=', 1)
    if k in allowed or k.startswith(('HK_', 'AGX_', 'ASAHI_', 'VK_')):
        env[k] = v
prefix = ['runuser', '-u', a.user, '--']
# Wayland compositors publish socket names after exec; /proc/environ can still
# hold the initial environment. Use the GUI manager's exported socket names.
manager_env = {**env, 'XDG_RUNTIME_DIR': '/run/user/' + str(owner.pw_uid),
               'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/' + str(owner.pw_uid) + '/bus'}
for line in run(prefix + ['systemctl', '--user', 'show-environment'], env=manager_env).splitlines():
    key, sep, value = line.partition('=')
    if sep and key in {'WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS'}:
        env[key] = value
monitors = json.loads(run(prefix + ['hyprctl', '-j', 'monitors'], env=env))
assert monitors and all(m['width'] > 0 and m['height'] > 0 for m in monitors)
report['displays'] = [{k: m[k] for k in ('name', 'width', 'height', 'refreshRate') if k in m} for m in monitors]
report['checks']['compositor_and_displays'] = True

# Capture as the GUI user into a private temporary file, then copy into the
# root-owned evidence directory. Never include this desktop image in a release.
shot = run(prefix + ['mktemp', '--suffix=.png'], env=env)
try:
    run(prefix + ['grim', shot], env=env)
    raw = Path(shot).read_bytes()
    assert raw.startswith(b'\x89PNG\r\n\x1a\n') and len(raw) > 100
    (a.output / 'desktop-private.png').write_bytes(raw)
    report['desktop_capture_sha256'] = hashlib.sha256(raw).hexdigest()
finally:
    Path(shot).unlink(missing_ok=True)

if a.manifest:
    assert a.manifest.stat().st_uid == 0 and not a.manifest.is_symlink()
    data = json.loads(a.manifest.read_text())
    assert data['boards'] == [board] and data['firmware'] == [firmware]
    assert platform.release() == data['kernel_release']
    verifier = '''import sys,json,hashlib
sys.path.insert(0, '/usr/lib/siliconforest/installer.pyz')
from installer import boot,graphics
from installer.release import require
data=graphics.admit()
esp=boot.system_esp()
boot.check_boot_image(data,esp)
expected=boot.image(data,boot.check_files(data),boot.CONFIG.read_bytes())
require((esp/'m1n1/boot.bin').read_bytes()==expected,'Installed stage 2 differs; evidence collection never rewrites it')
'''
    run(['/usr/bin/python3', '-I', '-c', verifier])
    report['stage2_version'] = (chosen / 'asahi,m1n1-stage2-version').read_bytes().rstrip(b'\0').decode()
    assert report['stage2_version'] == data['boot']['stage2_version']
    report['checks']['matched_boot_chain'] = True
    report['packages'] = {}
    for item in data['packages'].values():
        actual = run(['pacman', '-Q', item['name']]).split()
        assert actual == [item['name'], item['version']]
        report['packages'][item['name']] = item['version']
    maps = (proc / 'maps').read_text().splitlines()
    libraries = {line.split()[-1] for line in maps if '/libgallium-' in line or '/libvulkan_asahi.so' in line}
    assert libraries and all(line.startswith('/usr/lib/') for line in libraries), libraries
    assert not any('(deleted)' in line for line in maps if '/libgallium-' in line or '/libvulkan_asahi.so' in line)
    for library in libraries:
        assert run(['pacman', '-Qqo', library]) == 'mesa-siliconforest'
    report['compositor_graphics_libraries'] = {lib: sha(lib) for lib in sorted(libraries)}
    if (data['packages']['mesa']['source']['branch'].startswith('compat/') or
            data['kernel_variant'] == 'native-gpu'):
        run(['/usr/bin/python3', '-I', '/usr/lib/siliconforest/installer.pyz', '--graphics-admit'])
        report['checks']['graphics_admission'] = True

expected = 'Apple M1' if board == 'apple,j313' else 'Apple M3 Pro' if board == 'apple,j516s' else None
assert expected, 'Add and review the exact renderer expectation for this board'
env['RENDER_CHECK_RENDERER'] = expected
for api, binary in [('OpenGL', 'gl-render-check-aarch64'), ('Vulkan', 'vk-render-check-aarch64')]:
    text = run(prefix + ['timeout', '30', str(a.probes / binary), '3'], env=env)
    assert expected in text and 'PASS:' in text and '0 with wrong pixels' in text, text
    report[api] = text
    report['checks'][api + '_hardware_readback'] = True
report['status'] = 'passed-current-boot-checks'
report['completed_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
(a.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
