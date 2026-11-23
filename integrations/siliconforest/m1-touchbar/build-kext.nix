# SPDX-License-Identifier: MIT
# Builds SFAppleTouchBar.kext (GPL-2.0: the J293 Touch Bar as a key strip) in the pinned SiliconForest
# tree. Sources: ./kernel and ./spihid/sf_touchbar_kbd.h (shared with the keyboard's driver).
#   nix-build --extra-experimental-features nix-command --extra-experimental-features flakes build-kext.nix
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
  copied = pkgs.runCommand "siliconforest-touchbar-source" {} ''
    mkdir -p "$out"
    cp ${./kernel}/* "$out/"
    cp ${./spihid/sf_touchbar_kbd.h} "$out/sf_touchbar_kbd.h"
    cp ${../m1-sound/kernel/sf_board_gate.h} "$out/sf_board_gate.h"
  '';
in pd.packages.x86_64-linux.kexts-arm64.overrideAttrs (old: {
  pname = "siliconforest-touchbar";
  src = pkgs.runCommand "siliconforest-touchbar-tree" {} ''
    cp -R ${old.src} "$out"
    chmod -R u+w "$out"
    test ! -e "$out/src/Kernel/Extensions/SFAppleTouchBar"
    cp -R ${copied} "$out/src/Kernel/Extensions/SFAppleTouchBar"
    printf '\nadd_subdirectory(SFAppleTouchBar)\n' >> "$out/src/Kernel/Extensions/CMakeLists.txt"
  '';
  buildPhase = ''
    runHook preBuild
    ninja -C build-nix SFAppleTouchBar.kext
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    bundle=build-nix/src/Kernel/Extensions/SFAppleTouchBar/SFAppleTouchBar.kext
    test -f "$bundle/Contents/MacOS/SFAppleTouchBar"
    mkdir -p "$out/System/Library/Extensions"
    cp -R "$bundle" "$out/System/Library/Extensions/"
    runHook postInstall
  '';
})
