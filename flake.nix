{
  # SPDX-License-Identifier: MIT
  # Copyright (c) 2026 SiliconForest contributors
  description = "SiliconForest public source build";
  outputs = { self }:
    let
      base = import ./release/base.nix;
      release = import ./release/packages.nix { inherit base; };
    in {
      packages.x86_64-linux = release.packages;
      apps.x86_64-linux.qemu = {
        type = "app";
        program = "${release.packages.qemu-runner}/bin/siliconforest-qemu";
      };
      apps.x86_64-linux.qemu-vnc = {
        type = "app";
        program = "${release.packages.qemu-runner}/bin/siliconforest-qemu-vnc";
      };
      apps.x86_64-linux.qemu-records = {
        type = "app";
        program = "${release.packages.qemu-runner}/bin/siliconforest-qemu-records";
      };
      checks.x86_64-linux.source-manifest = self.packages.x86_64-linux.source-manifest;
    };
}
