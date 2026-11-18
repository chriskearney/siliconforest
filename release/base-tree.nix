# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Evaluate upstream's flake with its own pinned dependency graph, after the
# deterministic source rename. No local Git checkout or registry is consulted.
{ sourceName ? "upstream-base", corecryptoName ? "corecrypto", forkRev ? null }:
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
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  renameTools = builtins.path {
    path = ../tools;
    name = "siliconforest-rename-tools";
    filter = path: type: (type == "directory" && path == toString ../tools) ||
      builtins.elem (builtins.baseNameOf path) [ "sf_rename.py" "sf_rename_data.json" ];
  };
  renamed = pkgs.runCommand "siliconforest-${sourceName}-source" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    cp -R ${sources.${sourceName}} "$out"
    chmod -R u+w "$out"
    rm -f "$out/.gitmodules"
    mkdir -p "$out/external/corecrypto"
    cp -R ${sources.${corecryptoName}}/. "$out/external/corecrypto/"
    chmod -R u+w "$out/external/corecrypto"
    python3 ${renameTools}/sf_rename.py tree "$out"
  '';
  inputs = rootInputs // {
    corecrypto-src = renamed + "/external/corecrypto";
  } // pkgs.lib.optionalAttrs (sourceName != "upstream-cocoa") {
    sf-sb-key = renamed + "/nix/secureboot/no-key";
  };
  pd = (import (renamed + "/flake.nix")).outputs (inputs // { self = pd; })
    // { outPath = renamed; inherit inputs; };
in {
  inherit pd pkgs sources renamed renameTools;
  rev = if forkRev != null then forkRev
    else if sourceName == "upstream-cocoa" then lock.cocoaRename.expectedForkCommit
    else lock.baseRename.expectedForkCommit;
  which = "tip";
  tip = true;
  pick = { pin, tip }: tip;
}
