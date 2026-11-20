{
  # SPDX-License-Identifier: MIT
  # Copyright (c) 2026 SiliconForest contributors
  description = "SiliconForest public source build";
  outputs = { self }:
    let
      packagesFor = base: (import ./release/packages.nix { inherit base; }).packages;
      x86 = packagesFor (import ./release/base.nix);
      arm = packagesFor (import ./release/base-tree.nix { system = "aarch64-linux"; });
      qemuApp = packages: {
        type = "app";
        program = "${packages.qemu-runner}/bin/siliconforest-qemu";
      };
    in {
      packages.x86_64-linux = x86;
      packages.aarch64-linux = {
        inherit (arm) base-source qemu-base qemu-image qemu-proof-image qemu-runner source-manifest;
      };
      apps.x86_64-linux.qemu = qemuApp x86;
      apps.x86_64-linux.qemu-vnc = {
        type = "app";
        program = "${x86.qemu-runner}/bin/siliconforest-qemu-vnc";
      };
      apps.x86_64-linux.qemu-records = {
        type = "app";
        program = "${x86.qemu-runner}/bin/siliconforest-qemu-records";
      };
      apps.aarch64-linux.qemu = qemuApp arm;
      checks.x86_64-linux.source-manifest = self.packages.x86_64-linux.source-manifest;
    };
}
