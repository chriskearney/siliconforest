# SPDX-License-Identifier: MIT
# Unmodified official Noto data, redistributed under SIL OFL 1.1.
{ pkgs }:
let fetch = import ../../../release/fetch.nix { inherit pkgs; };
in {
  font = fetch "noto-devanagari";
  thai = fetch "noto-thai";
  license = fetch "noto-license";
}
