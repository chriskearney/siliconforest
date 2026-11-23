# SFM1SPIHID with the trackpad in multitouch mode. The same module layout as
# ../../m1-trackpad-input-trace/build-input-trace.nix, which builds the bundle in the current
# collections: the keyboard, transport, enumeration, child-policy and trace sources are taken
# unchanged from their directories; SFM1SPIHID.{cpp,h}, SFM1SPIHIDChild.inc, SFM1SPITrackpad.{cpp,h}
# and CMakeLists.txt come from this directory (modified copies), plus the new decoder.
# m1kbd_{board,pio,hid}.* are board-aware copies (J293, J313; m1kbd_boards.h): the originals in
# ../../m1-keyboard stay as they are, because the frozen recipes pin their hashes.
let
 pd = (import ../../rebase/pd.nix).pd;
 pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
 lab = pkgs.runCommand "siliconforest-m1-spi-hid-multitouch-module-source" {} ''
  mkdir -p "$out/native_protocol"
  cp ${./CMakeLists.txt} "$out/CMakeLists.txt"
  cp ${../../m1-keyboard/Info.plist} "$out/Info.plist"
  cp ${../../m1-keyboard/SFM1KeyboardHW.cpp} "$out/SFM1KeyboardHW.cpp"
  cp ${../../m1-keyboard/SFM1KeyboardHW.h} "$out/SFM1KeyboardHW.h"
  cp ${./SFM1SPIHID.cpp} "$out/SFM1SPIHID.cpp"
  cp ${./SFM1SPIHID.h} "$out/SFM1SPIHID.h"
  cp ${./m1kbd_boards.h} "$out/m1kbd_boards.h"
  cp ${./m1kbd_board.c} "$out/m1kbd_board.c"
  cp ${../../m1-keyboard/m1kbd_hw.h} "$out/m1kbd_hw.h"
  cp ${./m1kbd_pio.c} "$out/m1kbd_pio.c"
  cp ${./m1kbd_hid.c} "$out/m1kbd_hid.c"
  cp ${./m1kbd_hid.h} "$out/m1kbd_hid.h"
  cp ${../../m1-keyboard/native_protocol/dl_spi_hid.c} "$out/native_protocol/dl_spi_hid.c"
  cp ${../../m1-keyboard/native_protocol/dl_spi_hid.h} "$out/native_protocol/dl_spi_hid.h"
  cp ${../../m1-trackpad-enum/observation_layout.h} "$out/observation_layout.h"
  cp ${../../m1-trackpad-enum/core/m1tp_enum.c} "$out/m1tp_enum.c"
  cp ${../../m1-trackpad-enum/core/m1tp_enum.h} "$out/m1tp_enum.h"
  cp ${./SFM1SPIHIDChild.inc} "$out/SFM1SPIHIDChild.inc"
  cp ${./SFM1SPIHIDMultitouch.inc} "$out/SFM1SPIHIDMultitouch.inc"
  cp ${./SFM1SPITrackpad.cpp} "$out/SFM1SPITrackpad.cpp"
  cp ${./SFM1SPITrackpad.h} "$out/SFM1SPITrackpad.h"
  cp ${../adapter/m1tp_child_policy.c} "$out/m1tp_child_policy.c"
  cp ${../adapter/m1tp_child_policy.h} "$out/m1tp_child_policy.h"
  cp ${../child_state.h} "$out/child_state.h"
  cp ${../../m1-trackpad-input-trace/core/m1tp_trace.c} "$out/m1tp_trace.c"
  cp ${../../m1-trackpad-input-trace/core/m1tp_trace.h} "$out/m1tp_trace.h"
  cp ${./m1tp_mt.c} "$out/m1tp_mt.c"
  cp ${./m1tp_mt.h} "$out/m1tp_mt.h"
  cp ${./sf_tp_gesture_ring.h} "$out/sf_tp_gesture_ring.h"
  cp ${./m1tp_mt_selftest.c} "$out/m1tp_mt_selftest.c"
  cp ${./NOTICE} "$out/NOTICE"
  cp ${/home/chrisk/src/darwin-lab/runs/m1-desktop-010/trackpad-child-reference-001/trackpad_reference.h} "$out/trackpad_reference.h"
 '';
in pd.packages.x86_64-linux.kexts-arm64.overrideAttrs (old: {
 pname = "siliconforest-m1-spi-hid-multitouch";
 src = pkgs.runCommand "siliconforest-m1-spi-hid-multitouch-source" {} ''
  cp -R ${old.src} "$out"
  chmod -R u+w "$out"
  test ! -e "$out/src/Kernel/Extensions/SFM1SPIHID"
  cp -R ${lab} "$out/src/Kernel/Extensions/SFM1SPIHID"
  printf '\nadd_subdirectory(SFM1SPIHID)\n' >> "$out/src/Kernel/Extensions/CMakeLists.txt"
 '';
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
  cp ${./NOTICE} "$out/System/Library/Extensions/SFM1SPIHID.kext/Contents/NOTICE"
  runHook postInstall
 '';
})
