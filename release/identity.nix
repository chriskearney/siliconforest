# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# The identity of one SiliconForest release, shared by the image recipe (the root filesystem's
# UUID) and the boot stages (the root stage 2 may boot, PDSF_ROOT_UUID). The UUID is derived
# from the version alone: two builds of one release agree, two releases differ, and no machine
# identifier is involved. Every machine installed from a release carries the same root UUID;
# the kernel arguments tie it to the target's own partition (sfnvme_part, filled in at install).
{ version ? "0.1.0" }:
let
  h = builtins.hashString "sha256" "siliconforest-root-filesystem-${version}";
  s = builtins.substring;
in {
  inherit version;
  # RFC 9562 layout: version nibble 8 (custom), variant 10xx
  rootUUID = "${s 0 8 h}-${s 8 4 h}-8${s 13 3 h}-a${s 17 3 h}-${s 20 12 h}";
}
