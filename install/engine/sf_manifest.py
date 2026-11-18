# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
"""What a SiliconForest release consists of, checked before anything of it is used.

A release (docs/release/IMAGE.md on the release-image branch) publishes, among others:

  SHA256SUMS        "<sha256>  <file>" for every file of the release
  SHA256SUMS.sig    an SSH signature of SHA256SUMS (namespace siliconforest-release, identity
                    release@siliconforest), checked by install.sh with macOS's own
                    `ssh-keygen -Y verify` against the key pinned in install.sh
  siliconforest-<v>-install.json   what the installer needs to know (this module's schema;
                    example: install/manifest.example.json)
  siliconforest-<v>-boot.tar.xz    the boot files (stage 1, stage 2, the kernel collection, the
                    command-line template, pdsf_pack.py, sf_personalize.py, boot.json, the icon)
  siliconforest-<v>-root.ext4.xz.NN   the root filesystem image, xz-compressed, in parts

install.json is trusted only because its SHA-256 is in the signed SHA256SUMS (install.sh checks
that); every file it names must also be in SHA256SUMS with the same digest (checked here).
xz, not zstd: stock macOS cannot decompress zstd (its tar calls an external `zstd` that is not
there), while liblzma is in macOS and in the engine's Python.
"""
import json
import re

FORMAT = 'siliconforest-install/1'
HEX64 = re.compile(r'^[0-9a-f]{64}$')
UUID = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$')
VERSION = re.compile(r'^[0-9]+(\.[0-9]+){0,3}$')
BOOT_FILES = ('boot.json', 'boot.bin', 'kernel.kc', 'bootargs.template', 'pdsf_pack.py', 'sf_personalize.py',
              'sf-stage1.bin', 'siliconforest.icns')


class ManifestError(Exception):
    pass


def _need(cond, what):
    if not cond:
        raise ManifestError(what)


def parse_sums(text):
    out = {}
    for line in (text.decode() if isinstance(text, bytes) else text).splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        m = re.match(r'^([0-9a-f]{64})  (\S+)$', line)
        _need(m, 'SHA256SUMS: bad line %r' % line)
        _need(m.group(2) not in out, 'SHA256SUMS names %s twice' % m.group(2))
        out[m.group(2)] = m.group(1)
    return out


def _file(entry, where, sums):
    _need(isinstance(entry, dict), where + ': not an object')
    _need(isinstance(entry.get('file'), str) and NAME.match(entry['file']), where + ': file name')
    _need(isinstance(entry.get('bytes'), int) and entry['bytes'] > 0, where + ': bytes')
    _need(isinstance(entry.get('sha256'), str) and HEX64.match(entry['sha256']), where + ': sha256')
    if sums is not None:
        _need(sums.get(entry['file']) == entry['sha256'], '%s: %s is not in SHA256SUMS with this digest' % (where, entry['file']))


def check(data, supported_targets, sums=None):
    """The install descriptor (a dict) if it is well formed, else ManifestError.
    sums: the parsed signed SHA256SUMS (None only in tests of the shape alone)."""
    m = json.loads(data) if isinstance(data, (bytes, str)) else data
    _need(isinstance(m, dict), 'not an object')
    _need(m.get('format') == FORMAT, 'format is not ' + FORMAT)
    _need(isinstance(m.get('release'), str) and NAME.match(m['release']), 'release')
    models = m.get('models')
    _need(isinstance(models, list) and models and all(isinstance(t, str) for t in models), 'models')
    extra = [t for t in models if t not in supported_targets]
    _need(not extra, 'release names boards this installer does not support: ' + ', '.join(extra))
    mac = m.get('macos', {})
    _need(isinstance(mac.get('min'), str) and VERSION.match(mac['min']), 'macos.min')
    _need(isinstance(mac.get('max_major'), int), 'macos.max_major')
    _need(isinstance(m.get('stub_firmware'), list) and m['stub_firmware'] and
          all(isinstance(v, str) and VERSION.match(v) for v in m['stub_firmware']), 'stub_firmware')
    _file(m.get('boot'), 'boot', sums)
    r = m.get('root', {})
    _need(isinstance(r.get('fs_uuid'), str) and UUID.match(r['fs_uuid']), 'root.fs_uuid (lower case)')
    _need(r.get('compression') == 'xz', 'root.compression must be xz')
    for k in ('image_bytes', 'min_bytes', 'default_bytes'):
        _need(isinstance(r.get(k), int) and r[k] > 0, 'root.' + k)
    _need(isinstance(r.get('image_sha256'), str) and HEX64.match(r['image_sha256']), 'root.image_sha256')
    _need(r['image_bytes'] % 4096 == 0, 'root.image_bytes is not a multiple of 4096')
    _need(r['image_bytes'] <= r['min_bytes'] <= r['default_bytes'], 'root: image <= min <= default')
    if 'sizing' in r:
        _need(r['sizing'] == 'fixed', 'root.sizing must be fixed when present')
        _need(r['image_bytes'] == r['min_bytes'] == r['default_bytes'] and r['image_bytes'] % (1 << 20) == 0,
              'fixed root: image, minimum and default sizes must match and be MiB-aligned')
    parts = r.get('parts')
    _need(isinstance(parts, list) and parts, 'root.parts')
    for i, p in enumerate(parts):
        _file(p, 'root.parts[%d]' % i, sums)
    _need(len({p['file'] for p in parts}) == len(parts), 'root.parts names a file twice')
    slot = m.get('firmware_slot')
    _need(isinstance(slot, dict) and isinstance(slot.get('offset'), int) and isinstance(slot.get('length'), int), 'firmware_slot')
    _need(slot['offset'] % 4096 == 0 and slot['length'] >= (1 << 20) and slot['offset'] + slot['length'] <= r['image_bytes'],
          'firmware_slot must be 4096-aligned, at least 1 MiB and inside the root image')
    return m


def downloads(m):
    """[(file, bytes, sha256)] the installer fetches for this release (the engine is separate)."""
    return [(m['boot']['file'], m['boot']['bytes'], m['boot']['sha256'])] + [(p['file'], p['bytes'], p['sha256']) for p in m['root']['parts']]
