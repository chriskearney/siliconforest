# SPDX-License-Identifier: MIT
# The SiliconForest tree every recipe of the Cocoa stream builds from: upstream PureDarwin e7aa00a6 (the
# revision this stream is pinned to) plus one generated commit, the mechanical rename (branch
# siliconforest/e7aa00a6 of sources/puredarwin-baseline, made by tools/sf_rename.py fork).
let inherit (import ../../../release/cocoa-base.nix) pd; in pd.packages.${pd.buildSystem}
