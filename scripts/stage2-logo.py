#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compose m1n1's data-only logo payload from a verified artwork export."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from installer.bootlogo import compose
from installer.release import digest, require

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--artwork', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
require(not a.output.exists(), 'Output already exists')
manifest = json.loads((a.artwork / 'manifest.json').read_text())
require(manifest.get('schema') == 1, 'Unknown artwork manifest')
images = []
inputs = {}
for size in (256, 128):
    name = 'm1n1/bootlogo_' + str(size) + '.bin'
    path = a.artwork / name
    require(path.is_file() and not path.is_symlink(), 'Missing artwork: ' + name)
    raw = path.read_bytes()
    inputs[name] = hashlib.sha256(raw).hexdigest()
    require(inputs[name] == manifest['files'][name], 'Artwork digest differs: ' + name)
    images.append(raw)
payload = compose(*images)
with a.output.open('xb') as stream:
    stream.write(payload)
print(json.dumps({'artwork_id': manifest['id'], 'artwork_manifest_sha256': digest(a.artwork / 'manifest.json'),
                  'inputs': inputs, 'stage2_logo_sha256': hashlib.sha256(payload).hexdigest(),
                  'bytes': len(payload)}, sort_keys=True))
