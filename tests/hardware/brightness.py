#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Inventory Mac brightness controls; optionally exercise and restore them.

Run as the logged-in desktop user (for logind's active-seat permission), not
from an SSH login. --exercise briefly changes each control, then restores its
original level even if a check fails. It never blanks a display. Successful
readback is driver evidence, not proof of visible panel or keyboard luminance.
"""
import argparse
from datetime import datetime, timezone
import json
import platform
from pathlib import Path
import subprocess
import time


def level(device, name):
    return int((device / name).read_text())


def set_level(device, value):
    subprocess.run(['brightnessctl', '--device=' + device.name, 'set', str(value)],
                   check=True, capture_output=True, text=True, timeout=10)
    deadline = time.monotonic() + 3
    while True:
        requested = level(device, 'brightness')
        actual = (level(device, 'actual_brightness')
                  if (device / 'actual_brightness').exists() else None)
        if requested == value and actual in (None, value):
            return {'requested': requested, 'actual': actual}
        if time.monotonic() >= deadline:
            raise RuntimeError(f'{device.name}: expected {value}, '
                               f'requested={requested}, actual={actual}')
        time.sleep(0.05)


def exercise(device, maximum, original, display):
    if display and original == 0:
        raise RuntimeError('Display reports zero brightness; refusing an automatic test')
    step = max(1, maximum // 20)
    minimum = 1 if display else 0
    alternate = original - step if original - step >= minimum else min(maximum, original + step)
    if alternate == original:
        raise RuntimeError('No distinct safe test level')
    result = {}
    try:
        result['changed'] = set_level(device, alternate)
    finally:
        # Restoration errors must fail the test, too.
        result['restored'] = set_level(device, original)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exercise', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    compatible = Path('/proc/device-tree/compatible').read_bytes().rstrip(b'\0').decode().split('\0')
    report = {'schema': 1, 'kernel': platform.release(),
              'board': next(c for c in compatible if c.startswith('apple,j')),
              'os_firmware': Path('/proc/device-tree/chosen/asahi,os-fw-version').read_bytes().rstrip(b'\0').decode(),
              'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
              'exercised': args.exercise, 'controls': [],
              'visible_luminance_verified': False}
    devices = [(p, False) for p in sorted(Path('/sys/class/leds').glob('*kbd_backlight*'))]
    panel = Path('/sys/class/backlight/apple-panel-bl')
    if panel.exists():
        devices.append((panel, True))
    failed = False
    for device, display in devices:
        item = {'device': device.name, 'kind': 'display' if display else 'keyboard'}
        report['controls'].append(item)
        try:
            maximum, original = level(device, 'max_brightness'), level(device, 'brightness')
            if not 0 <= original <= maximum or maximum <= 0:
                raise RuntimeError('Invalid brightness range')
            item.update(maximum=maximum, original=original)
            if args.exercise:
                item.update(exercise(device, maximum, original, display))
            item['status'] = 'passed' if args.exercise else 'present'
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            item.update(status='failed', error=str(error))
            if isinstance(error, subprocess.CalledProcessError):
                item['stderr'] = (error.stderr or '').strip()
            failed = True
    report['missing'] = [kind for kind in ('display', 'keyboard')
                         if not any(c['kind'] == kind for c in report['controls'])]
    report['status'] = 'failed' if failed or report['missing'] else ('passed' if args.exercise else 'present')
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))
    return 0 if report['status'] in ('passed', 'present') else 1


if __name__ == '__main__':
    raise SystemExit(main())
