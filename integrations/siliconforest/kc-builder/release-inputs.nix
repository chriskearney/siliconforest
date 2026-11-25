# SPDX-License-Identifier: MIT
# A collection recipe's link, as the release ships it: the collection linked by ./build-tools.nix from
# separate input files (./capture-kc-builder.sh), and those files.
#
#   nix-build release-inputs.nix                                    the J313 installed-system collection
#   nix-build release-inputs.nix --arg collection 'import ../rebase/build-kc.nix { }'   (from this directory:
#                                     nix resolves the path in --arg against the working directory)
#
# $out/kernel          the collection (byte-identical to the recipe's own; never published, README.md)
# $out/inputs/kernel   the kernel; inputs/kexts/<Name>.kext, inputs/codeless/<Name>.kext the bundles
# $out/inputs/link-args.txt   the kc-builder options, one per line, the output as @OUTPUT@
{ collection ? import ../m1-storage/build-kc-native-rw-halt.nix { } }:
let
  inherit (import ../rebase/pd.nix) pkgs;
  tools = import ./build-tools.nix;
  capture = pkgs.writeShellScriptBin "kc-builder"
    (builtins.replaceStrings [ "@real@" ] [ "${tools}" ] (builtins.readFile ./capture-kc-builder.sh));
in
(collection.override { kcTools = capture; }).overrideAttrs (old: {
  pname = "${old.pname}-release-inputs";
  installPhase = old.installPhase + ''
    cp -R release-inputs $out/inputs
  '';
})
