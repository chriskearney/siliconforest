# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""The release manifest: what a SiliconForest release consists of, checked before it is used.

The manifest is a JSON file published with each release next to a detached signature
(ECDSA P-256 over SHA-256 of the exact bytes, DER; verified by install.sh with macOS's own
`openssl dgst -sha256 -verify` before this module ever sees the file). This module checks
its shape; it trusts nothing it has not checked. Schema: install/manifest.example.json.
"""
import json
import re

FORMAT = 'siliconforest-release/1'
HEX64 = re.compile(r'^[0-9a-f]{64}$')
UUID = re.compile(r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')
NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$')
VERSION = re.compile(r'^[0-9]+(\.[0-9]+){0,3}$')
ROLES = ('stage1', 'os-package')


class ManifestError(Exception):
    pass


def _need(cond, what):
    if not cond:
        raise ManifestError(what)


def _file(entry, where):
    _need(isinstance(entry, dict), where + ': not an object')
    _need(isinstance(entry.get('file'), str) and NAME.match(entry['file']), where + ': file name')
    _need(isinstance(entry.get('bytes'), int) and entry['bytes'] > 0, where + ': bytes')
    _need(isinstance(entry.get('sha256'), str) and HEX64.match(entry['sha256']), where + ': sha256')
    parts = entry.get('parts')
    if parts is not None:
        _need(isinstance(parts, list) and parts, where + ': parts')
        for i, p in enumerate(parts):
            _file(p, '%s part %d' % (where, i))
        _need(sum(p['bytes'] for p in parts) == entry['bytes'], where + ': parts do not add up to bytes')


def check(data, supported_targets):
    """Return the manifest (a dict) if it is well formed, else raise ManifestError."""
    m = json.loads(data) if isinstance(data, (bytes, str)) else data
    _need(isinstance(m, dict), 'not an object')
    _need(m.get('format') == FORMAT, 'format is not ' + FORMAT)
    _need(isinstance(m.get('release'), str) and NAME.match(m['release']), 'release')
    base = m.get('base_url')
    _need(isinstance(base, str) and base.startswith('https://') and base.endswith('/'), 'base_url must be https and end in /')
    models = m.get('models')
    _need(isinstance(models, list) and models and all(isinstance(t, str) for t in models), 'models')
    extra = [t for t in models if t not in supported_targets]
    _need(not extra, 'release names boards this installer does not support: ' + ', '.join(extra))
    mac = m.get('macos', {})
    _need(isinstance(mac.get('min'), str) and VERSION.match(mac['min']), 'macos.min')
    _need(isinstance(mac.get('max_major'), int), 'macos.max_major')
    _need(isinstance(m.get('stub_firmware'), list) and m['stub_firmware'] and
          all(isinstance(v, str) and VERSION.match(v) for v in m['stub_firmware']), 'stub_firmware')
    eng = m.get('engine', {})
    _file(eng, 'engine')
    _need(eng.get('name') == 'asahi-installer', 'engine.name')
    _need(isinstance(eng.get('urls'), list) and eng['urls'] and all(isinstance(u, str) and u.startswith('https://')
                                                                     for u in eng['urls']), 'engine.urls')
    files = m.get('files')
    _need(isinstance(files, list), 'files')
    roles = {}
    for i, f in enumerate(files):
        _file(f, 'files[%d]' % i)
        _need(f.get('role') in ROLES, 'files[%d].role' % i)
        _need(f['role'] not in roles, 'two files with role ' + f['role'])
        roles[f['role']] = f
    _need(set(roles) == set(ROLES), 'files must have exactly the roles ' + ', '.join(ROLES))
    os_ = m.get('os', {})
    _need(isinstance(os_.get('root_fs_uuid'), str) and UUID.match(os_['root_fs_uuid']), 'os.root_fs_uuid')
    for k in ('root_image_bytes', 'root_min_bytes', 'root_default_bytes', 'boot_partition_bytes'):
        _need(isinstance(os_.get(k), int) and os_[k] > 0, 'os.' + k)
    _need(os_['root_image_bytes'] % 4096 == 0, 'os.root_image_bytes is not a multiple of 4096 (the Asahi installer refuses it)')
    _need(os_['root_image_bytes'] <= os_['root_min_bytes'] <= os_['root_default_bytes'], 'os: image <= min <= default')
    _need(os_['boot_partition_bytes'] == 524288000, 'os.boot_partition_bytes must be 500 MiB (the size the installed boot chain was proven with)')
    _need(os_.get('kernel_file') == 'esp/sf/kernel.bin', 'os.kernel_file')
    _need(isinstance(os_.get('kernel_record_sha256'), str) and HEX64.match(os_['kernel_record_sha256']), 'os.kernel_record_sha256')
    slot = os_.get('firmware_slot')
    _need(isinstance(slot, dict) and isinstance(slot.get('offset'), int) and isinstance(slot.get('length'), int), 'os.firmware_slot')
    _need(slot['offset'] % 4096 == 0 and slot['length'] >= (1 << 20) and slot['offset'] + slot['length'] <= os_['root_image_bytes'],
          'os.firmware_slot must be 4096-aligned, at least 1 MiB and inside the root image')
    return m


def role(m, name):
    return next(f for f in m['files'] if f['role'] == name)
