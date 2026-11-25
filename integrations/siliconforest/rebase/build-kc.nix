# SPDX-License-Identifier: MIT
# The default desktop collection on the rebase target (SF_PD=tip, ./pd.nix), in one recipe.
#
# On the pin this collection is m1-boot-speed/build-kc.nix: fifteen recipes, each rewriting the
# build phase of the one before. Those are not changed. This recipe names the same members
# (pin collection /nix/store/z66w83kk…-siliconforest-kc-arm64-0.1, read from its derivation) and
# takes each one from the same leaf recipe the pin uses, now evaluated at the tip:
#
#   kernel                 ./kernel.nix
#   boot kexts             upstream's arm64 set at the tip as m1-smp/build-corecrypto.nix builds it
#                          (the whole set from the corecrypto source with the DRBG state size
#                          patch; the pin takes only corecrypto.kext from that build and the
#                          rest from the unpatched set, which is the same source), with three
#                          of them replaced by our builds:
#     SFArmPlatformExpert    m1-smp/build-platform.nix
#     IOGOPFramebuffer       m1-display/console-return/build-framebuffer.nix
#     IOHIDFamily            m1-native-input/build-hid-rev002.nix
#   left out               SFSerialHID (as on the pin: the SPI keyboard replaces it) and the six
#                          members upstream added to its list after the pin (Tegra, the USB
#                          gadget family, SFFBSDem): hardware this machine does not have
#   gone upstream          SFSun50iMMC (the launcher's member gate still asks for it: the boot
#                          tools apply ./launcher-tip-members.patch)
#   added                  SFM1SPIHID (m1-touchbar/build-spihid.nix), SFApcieT8103Bridge,
#                          IO80211Family, SFBwfm, SFGpuDT, SFDRMDri, SFAgx, SFDcp, SFCpuPower,
#                          SFAppleSound, SFAppleTouchBar, SFAppleAVD (inert without sfavd=1)
# Every member's debug map is stripped (`strip -S`), as on the pin, where the collection does
# not fit otherwise. The build ends with the launcher's overlap check (kc_overlap.py).
#
#   nix-build build-kc.nix --no-out-link
#   --arg extra '[ "<bundle path>" ]'    further bundles;  --arg omit '[ "Name" ]'  fewer boot kexts
{ kernelConfig ? "development", extra ? [ ], omit ? [ ], kernel ? import ./kernel.nix { inherit kernelConfig; }
# the platform expert build (m1-native-boot passes its own, with the held-cores patch)
, platform ? import ../m1-smp/build-platform.nix
# the SFCpuPower build (m1-native-boot/reboot passes its own, with restart and power-off)
, cpupower ? import ../m1-cpufreq/build-kext.nix
# further kexts by recipe: [ { name = "SFAppleNVMe"; from = <derivation>; } ]
, more ? [ ]
# the PCIe bridge and the Wi-Fi pair (IO80211Family, SFBwfm): siliconforest-patches/build-kc.nix passes
# the builds made from the exported tree patches instead of the lab directories
, bridge ? import ../m1-apcie-host/build-kext.nix
, wifi ? import ../m1-bwfm/build-kexts.nix { } }:
let
  source = import ./pd.nix;
  inherit (source) pd pkgs;
  p = pd.packages.x86_64-linux;
  strip = "${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-strip";
  ext = "System/Library/Extensions";
  set = import ../m1-smp/build-corecrypto.nix;
  ours = {
    SFArmPlatformExpert = platform;
    IOGOPFramebuffer = import ../m1-display/console-return/build-framebuffer.nix;
    IOHIDFamily = import ../m1-native-input/build-hid-rev002.nix;
  };
  # upstream's boot kexts with ours in place of three of them, debug maps stripped
  kexts = pkgs.runCommand "siliconforest-boot-kexts" { } ''
    dest=$out/${ext}
    mkdir -p $dest
    cp -RL ${set}/${ext}/. $dest/
    chmod -R u+w $out
    ${pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList (name: drv: ''
      test -f ${drv}/${ext}/${name}.kext/Contents/MacOS/${name}
      rm -rf $dest/${name}.kext
      cp -RL ${drv}/${ext}/${name}.kext $dest/${name}.kext
    '') ours)}
    chmod -R u+w $out
    for b in $dest/*.kext/Contents/MacOS/*; do ${strip} -S "$b"; done
  '';
  slim = name: drv: pkgs.runCommand "${name}-no-debug-map" { } ''
    mkdir -p $out
    cp -RL ${drv}/${ext}/${name}.kext $out/${name}.kext
    chmod -R u+w $out
    ${strip} -S $out/${name}.kext/Contents/MacOS/${name}
  '';
  dcp = import ../m1-dcp/build-kext.nix;
  agx = import ../m1-rust-kext/build-agx-kext.nix;
  added = map (m: "${slim m.name m.from}/${m.name}.kext") ([
    { name = "SFM1SPIHID"; from = import ../m1-touchbar/build-spihid.nix; }
    { name = "SFApcieT8103Bridge"; from = bridge; }
    { name = "IO80211Family"; from = wifi; }
    { name = "SFBwfm"; from = wifi; }
    { name = "SFGpuDT"; from = import ../m1-gpu-dt/build-kext.nix; }
    { name = "SFDRMDri"; from = dcp; }
    { name = "SFAgx"; from = agx; }
    { name = "SFDcp"; from = dcp; }
    { name = "SFCpuPower"; from = cpupower; }
    { name = "SFAppleSound"; from = import ../m1-sound/build-kext.nix; }
    { name = "SFAppleTouchBar"; from = import ../m1-touchbar/build-kext.nix; }
    # the video decoder: does nothing without sfavd=1 in the boot-args
    { name = "SFAppleAVD"; from = import ../m1-avd/build-kext.nix; }
  ] ++ more);
  afterPin = [ "SFTegraSDMMC" "SFGadgetFamily" "SFTegraUSB" "SFTegraXUSB" "SFTegraDisplay" "SFFBSDem" ];
  collection = pkgs.callPackage (pd.outPath + "/nix/pkgs/toolchain/kc-arm64.nix") {
    # kc-tools-fixed.nix plus the host-independent symbol order (../kc-builder/README.md): the same bytes
    # on glibc, and the same bytes again when the installer links this collection on macOS
    kcTools = import ../kc-builder/build-tools.nix;
    inherit kernel kexts;
    kernelSource = kernel.src;
    kcBase = "fffffe0006000000";
    extraKexts = added ++ extra;
    omitKexts = [ "SFSerialHID" ] ++ afterPin ++ omit;
  };
in
assert source.tip || throw "rebase/build-kc.nix is the tip's collection: run it with SF_PD=tip (the pin's is m1-boot-speed/build-kc.nix)";
collection.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.python3 ];
  buildPhase = ''
    set -o pipefail
    {
    '' + old.buildPhase + ''
    } 2>&1 | tee kc-build.log
    python3 ${../m1-rust-kext/tools/kc_overlap.py} kernel
  '';
  passthru = (old.passthru or { }) // { inherit kexts kernel; };
})
