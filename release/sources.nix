# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Every external source here is public and content pinned in one manifest.
let
  lock = builtins.fromJSON (builtins.readFile ../sources.lock);
  fetch = spec:
    if spec.type == "file" then builtins.fetchurl { inherit (spec) url sha256; }
    else builtins.fetchTree (if spec.type == "github" then builtins.removeAttrs spec [ "url" ] else spec);
in builtins.mapAttrs (_: fetch) lock.sources
