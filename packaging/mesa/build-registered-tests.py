#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build every registered Asahi test, including executables behind wrappers."""
import json
import os
from pathlib import Path
import subprocess
import sys

build = Path(sys.argv[1]).resolve()
info = build / 'meson-info'
tests = [t for t in json.loads((info / 'intro-tests.json').read_text())
         if any(s == 'asahi' or s.endswith(':asahi') for s in t['suite'])]
if not tests:
    raise SystemExit('No registered Asahi tests')
dependencies = {d for t in tests for d in t.get('depends', [])}
outputs = set()
for test in tests:
    executable = Path(test['cmd'][0])
    if executable.is_relative_to(build):
        outputs.add(str(executable.relative_to(build)))
seen = set()
for target in json.loads((info / 'intro-targets.json').read_text()):
    if target['id'] in dependencies:
        seen.add(target['id'])
        outputs.update(str(Path(p).relative_to(build)) for p in target['filename'])
if dependencies - seen:
    raise SystemExit('Unresolved registered test dependencies: ' + repr(dependencies - seen))
if not outputs:
    raise SystemExit('No Asahi test executables resolved')
subprocess.run(['ninja', '-C', str(build), '-j', os.environ.get('JOBS', '4'),
                *sorted(outputs)], check=True)
