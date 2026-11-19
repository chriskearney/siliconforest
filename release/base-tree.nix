# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Evaluate upstream's flake with its own pinned dependency graph, after the
# deterministic source rename. No local Git checkout or registry is consulted.
{ sourceName ? "upstream-base", corecryptoName ? "corecrypto", forkRev ? null, system ? "x86_64-linux" }:
let
  lock = builtins.fromJSON (builtins.readFile ../sources.lock);
  sources = import ./sources.nix;
  nodes = if sourceName == "upstream-cocoa" then lock.upstreamPinFlakeNodes else lock.upstreamFlakeNodes;
  load = name:
    let
      node = nodes.${name};
      tree = sources.${name};
      inputs = builtins.mapAttrs (_: target: load target) (node.inputs or { });
      result = tree // ((import (tree.outPath + "/flake.nix")).outputs
        (inputs // { self = result; })) // { inherit inputs; };
    in if (node.flake or true) then result else tree;
  rootInputs = builtins.mapAttrs (_: load)
    (pkgs.lib.filterAttrs (_: target: nodes.${target}.locked.type != "path") nodes.${lock.upstreamFlakeRoot}.inputs);
  nixpkgs = load nodes.${lock.upstreamFlakeRoot}.inputs.nixpkgs;
  pkgs = import nixpkgs { inherit system; };
  renameTools = builtins.path {
    path = ../tools;
    name = "siliconforest-rename-tools";
    filter = path: type: (type == "directory" && path == toString ../tools) ||
      builtins.elem (builtins.baseNameOf path) [ "sf_rename.py" "sf_rename_data.json" ];
  };
  renamed = pkgs.runCommand "siliconforest-${sourceName}-source" {
    nativeBuildInputs = [ pkgs.python3 ];
    # Verify the complete generated tree and keep its store identity independent
    # of implementation-only changes to the rename tool or build environment.
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = (if sourceName == "upstream-cocoa" then lock.cocoaRename else lock.baseRename).narHash;
  } ''
    cp -R ${sources.${sourceName}} "$out"
    chmod -R u+w "$out"
    rm -f "$out/.gitmodules"
    mkdir -p "$out/external/corecrypto"
    cp -R ${sources.${corecryptoName}}/. "$out/external/corecrypto/"
    chmod -R u+w "$out/external/corecrypto"
    python3 ${renameTools}/sf_rename.py tree "$out"
  '';
  # Preserve the locked generated tree above. This build-only overlay makes
  # every invocation of upstream's real Mach-O linker zero N_OSO timestamps,
  # including links that name native-ld directly rather than a compiler shim.
  buildSource = pkgs.runCommand "siliconforest-${sourceName}-source" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp -R ${renamed} "$out"
    chmod -R u+w "$out"
    python3 - "$out/nix/pkgs/toolchain/native-ld.nix" <<'PY'
    from pathlib import Path
    import sys
    path = Path(sys.argv[1])
    source = path.read_text()
    needle = 'ulimit -s unlimited 2>/dev/null || true\n'
    assert source.count(needle) == 1, 'native-ld wrapper layout changed'
    path.write_text(source.replace(needle, 'export ZERO_AR_DATE=1\n' + needle))
    PY
  '';
  cocoaAarch64 = sourceName == "upstream-cocoa" && system == "aarch64-linux";
  prepared = if system == "aarch64-linux" && sourceName == "upstream-base" then
    pkgs.applyPatches {
      name = "siliconforest-aarch64-linux-build-source";
      src = buildSource;
      patches = [ ./patches/aarch64-linux-xnu-headers.patch ];
      patchFlags = [ "-p1" "--fuzz=0" ];
    }
  else if cocoaAarch64 then pkgs.applyPatches {
    name = "siliconforest-cocoa-aarch64-linux-source";
    src = buildSource;
    patches = [
      ./patches/cocoa-aarch64-linux-swift.patch
      ./patches/cocoa-aarch64-linux-mig-sdk.patch
      ./patches/cocoa-aarch64-linux-cctools.patch
    ];
    patchFlags = [ "-p1" "--fuzz=0" ];
  }
  else buildSource;
  inputs = rootInputs // {
    # An aarch64 Linux host needs corecrypto f577aafe, which the base tree pins: corecrypto-pin plus its aarch64 Linux host case.
    corecrypto-src = (if cocoaAarch64 then (import ./base-tree.nix { inherit system; }).renamed else renamed) + "/external/corecrypto";
  } // pkgs.lib.optionalAttrs (sourceName != "upstream-cocoa") {
    sf-sb-key = renamed + "/nix/secureboot/no-key";
  } // pkgs.lib.optionalAttrs cocoaAarch64 {
    sf-swift-host-source = sources."swift-6.3.3-ubuntu24.04-aarch64";
  };
  pd = (import (prepared + "/flake.nix")).outputs (inputs // { self = pd; })
    // { outPath = prepared; inherit inputs; buildSystem = system; buildPkgs = pkgs; };
in {
  inherit pd pkgs sources renamed renameTools buildSource;
  rev = if forkRev != null then forkRev
    else if sourceName == "upstream-cocoa" then lock.cocoaRename.expectedForkCommit
    else lock.baseRename.expectedForkCommit;
  which = "tip";
  tip = true;
  pick = { pin, tip }: tip;
}
