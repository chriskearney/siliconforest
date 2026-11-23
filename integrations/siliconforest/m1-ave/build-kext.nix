# SPDX-License-Identifier: MIT
# SDK compile only. CODEX-TB must integrate on its current kernel collection.
let
 source=import ../rebase/pd.nix;
 inherit(source) pd pkgs;
in pd.packages.x86_64-linux.kexts-arm64.overrideAttrs(old: {
 pname="siliconforest-apple-ave-boot";
 src=pkgs.runCommand "siliconforest-apple-ave-diagnostic-tree" {} ''
  cp -R ${old.src} $out
  chmod -R u+w $out
  dest=$out/src/Kernel/Extensions/SFAppleAVE
  mkdir -p $dest
  cp -R ${./kernel} $dest/kernel
  cp -R ${./include} $dest/include
  printf '\nadd_subdirectory(SFAppleAVE/kernel)\n' >> $out/src/Kernel/Extensions/CMakeLists.txt
 '';
 buildPhase=''
  runHook preBuild
  ninja -C build-nix SFAppleAVE.kext
  runHook postBuild
 '';
 installPhase=''
  mkdir -p $out/System/Library/Extensions
  cp -R build-nix/src/Kernel/Extensions/SFAppleAVE/kernel/SFAppleAVE.kext $out/System/Library/Extensions/
 '';
})
