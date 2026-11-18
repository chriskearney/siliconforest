# SPDX-License-Identifier: MIT
# Copyright (c) 2026 SiliconForest contributors
# Retain the original fetcher/strip policy; move its pins to the common lock.
{ pkgs }:
name:
let
  lock = builtins.fromJSON (builtins.readFile ../sources.lock);
  spec = lock.auxiliarySources.${name};
  args = builtins.removeAttrs spec [ "fetcher" "revision" ];
in if spec.fetcher == "fetchurl" then pkgs.fetchurl args
   else if spec.fetcher == "fetchzip" then pkgs.fetchzip args
   else throw "Unknown public source fetcher: ${spec.fetcher}"
