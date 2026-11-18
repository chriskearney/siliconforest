# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Public, pinned SiliconForest base, generated from the upstream source.
# The historical pin predates the rename and is not supported by these recipes.
let asked = builtins.getEnv "SF_PD";
in assert asked == "" || asked == "tip" ||
  throw "SF_PD=pin predates the SiliconForest rename; use a pre-rename checkout";
import ../../../release/base.nix
