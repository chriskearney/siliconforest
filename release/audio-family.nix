# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# The Finch family reexports the selected-device output provider under its
# private loader-relative name, as the installed family does. CoreAudio and
# AudioUnit from the provider's output are deliberately not copied here.
{ pkgs, family, provider }:
pkgs.runCommand "siliconforest-audiotoolbox-release-family" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  cp -R ${family}/. "$out"
  chmod -R u+w "$out"
  python3 - ${provider}/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox \
      "$out/System/Library/Frameworks/AudioToolbox.framework/Versions/A/AudioToolbox.output-sf" <<'PY'
  import json
  from pathlib import Path
  import runpy
  import sys
  api = runpy.run_path('${../integrations/siliconforest/homebrew/hb_macho.py}')
  before = Path(sys.argv[1]).read_bytes()
  image = api['MachO'](before)
  interface = Path('${../integrations/siliconforest/finch/AudioToolbox/codec/retained-provider.tbd}')
  expected = {json.loads(line.strip()[2:]) for line in interface.read_text().splitlines()
              if line.strip().startswith('- "')}
  assert expected and expected <= set(image.exported()[0]), 'retained audio interface is incomplete'
  old = image.id['name']
  name = '@loader_path/AudioToolbox.output-sf'
  after, changed = api['rewrite_names'](before, lambda value: name if value == old else value)
  assert changed, 'retained audio install name was not rewritten'
  after = api['resign'](after)[0]
  assert not api['verify'](after), 'retained audio signature verification failed'
  assert api['MachO'](after).id['name'] == name
  output = Path(sys.argv[2])
  output.write_bytes(after)
  output.chmod(0o755)
  PY
''
