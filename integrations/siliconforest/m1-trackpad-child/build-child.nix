# Isolated T1 enumeration-only experimental bundle, no checkout mutation.
let
 pd = (import ../rebase/pd.nix).pd;
 pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
 inputs = builtins.fromJSON (builtins.readFile ./sdk-build-inputs-digest.json);
 names = [ "CMakeLists.txt" "Info.plist" "SFM1KeyboardHW.cpp" "SFM1KeyboardHW.h" "SFM1SPIHID.cpp" "SFM1SPIHID.h" "m1kbd_board.c" "m1kbd_hw.h" "m1kbd_pio.c" "m1kbd_hid.c" "m1kbd_hid.h" "native_protocol/dl_spi_hid.c" "native_protocol/dl_spi_hid.h" "observation_layout.h" "m1tp_enum.c" "m1tp_enum.h" "SFM1SPIHIDChild.inc" "SFM1SPITrackpad.cpp" "SFM1SPITrackpad.h" "m1tp_child_policy.c" "m1tp_child_policy.h" "child_state.h" "trackpad_reference.h" "descriptor_guard.c" "descriptor_guard.h" ];
 lab = pkgs.runCommand "siliconforest-m1-passive-trackpad-child-module-source" {} ''
  mkdir -p "$out/native_protocol"
  cp ${./adapter/CMakeLists.txt} "$out/CMakeLists.txt"
  cp ${../m1-keyboard/Info.plist} "$out/Info.plist"
  cp ${../m1-keyboard/SFM1KeyboardHW.cpp} "$out/SFM1KeyboardHW.cpp"
  cp ${../m1-keyboard/SFM1KeyboardHW.h} "$out/SFM1KeyboardHW.h"
  cp ${./adapter/SFM1SPIHID.cpp} "$out/SFM1SPIHID.cpp"
  cp ${./adapter/SFM1SPIHID.h} "$out/SFM1SPIHID.h"
  cp ${../m1-keyboard/m1kbd_board.c} "$out/m1kbd_board.c"
  cp ${../m1-keyboard/m1kbd_hw.h} "$out/m1kbd_hw.h"
  cp ${../m1-keyboard/m1kbd_pio.c} "$out/m1kbd_pio.c"
  cp ${../m1-keyboard/m1kbd_hid.c} "$out/m1kbd_hid.c"
  cp ${../m1-keyboard/m1kbd_hid.h} "$out/m1kbd_hid.h"
  cp ${../m1-keyboard/native_protocol/dl_spi_hid.c} "$out/native_protocol/dl_spi_hid.c"
  cp ${../m1-keyboard/native_protocol/dl_spi_hid.h} "$out/native_protocol/dl_spi_hid.h"
  cp ${../m1-trackpad-enum/observation_layout.h} "$out/observation_layout.h"
  cp ${../m1-trackpad-enum/core/m1tp_enum.c} "$out/m1tp_enum.c"
  cp ${../m1-trackpad-enum/core/m1tp_enum.h} "$out/m1tp_enum.h"
  cp ${./adapter/SFM1SPIHIDChild.inc} "$out/SFM1SPIHIDChild.inc"
  cp ${./adapter/SFM1SPITrackpad.cpp} "$out/SFM1SPITrackpad.cpp"
  cp ${./adapter/SFM1SPITrackpad.h} "$out/SFM1SPITrackpad.h"
  cp ${./adapter/m1tp_child_policy.c} "$out/m1tp_child_policy.c"
  cp ${./adapter/m1tp_child_policy.h} "$out/m1tp_child_policy.h"
  cp ${./child_state.h} "$out/child_state.h"
  cp ${./trackpad_reference.h} "$out/trackpad_reference.h"
  cp ${./descriptor_guard.c} "$out/descriptor_guard.c"
  cp ${./descriptor_guard.h} "$out/descriptor_guard.h"
 '';
 checks = pkgs.lib.concatMapStringsSep "\n" (name:
  let sha = inputs.files.${name}.sha256;
  in assert builtins.match "[0-9a-f]{64}" sha != null;
   "echo '${sha}  src/Kernel/Extensions/SFM1SPIHID/${name}' | sha256sum -c -"
 ) names;
in pd.packages.x86_64-linux.kexts-arm64.overrideAttrs (old: {
 pname = "siliconforest-m1-passive-trackpad-child";
 src = pkgs.runCommand "siliconforest-m1-passive-trackpad-child-source" {} ''
  cp -R ${old.src} "$out"
  chmod -R u+w "$out"
  test ! -e "$out/src/Kernel/Extensions/SFM1SPIHID"
  cp -R ${lab} "$out/src/Kernel/Extensions/SFM1SPIHID"
  printf '\nadd_subdirectory(SFM1SPIHID)\n' >> "$out/src/Kernel/Extensions/CMakeLists.txt"
 '';
 postPatch = (old.postPatch or "") + "\n" + checks;
 buildPhase = ''
  runHook preBuild
  ninja -C build-nix SFM1SPIHID.kext
  runHook postBuild
 '';
 installPhase = ''
  runHook preInstall
  bundle=build-nix/src/Kernel/Extensions/SFM1SPIHID/SFM1SPIHID.kext
  test -f "$bundle/Contents/MacOS/SFM1SPIHID"
  mkdir -p "$out/System/Library/Extensions"
  cp -R "$bundle" "$out/System/Library/Extensions/"
  runHook postInstall
 '';
})
