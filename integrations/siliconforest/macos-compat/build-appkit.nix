# SPDX-License-Identifier: MIT
# AppKit and Cocoa for the disk root: the part of the Cocoa stream's arm64 system root
# (../cocoa/build-desktop-root.nix: upstream PureDarwin's AppKit stack at the pin with the
# lab's patches, docs/roadmap/issues/SF-U-cocoa.md) that dyld loads for a program linking
# AppKit or Cocoa: the framework bundles on that path, whole, and the libraries under them.
# No second AppKit: these are that stream's binaries, selected by ../homebrew/sf_gapscan.py's
# walk of the load commands (tools/sf_closure_copy.py). Not taken: applications, launchd jobs,
# fonts and configuration (the desktop side stays the Cocoa stream's step), and the base
# frameworks a root has already (CoreFoundation, Foundation, CoreServices, IOKit: whoever
# lays this tree onto a root keeps the root's file wherever a path exists).
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-appkit.nix
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = pd.buildPkgs;
  root = import ../cocoa/build-desktop-root.nix;
  F = "/System/Library/Frameworks";
in pkgs.runCommand "siliconforest-appkit-closure-arm64" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -o pipefail
  L=lab/integrations/siliconforest; mkdir -p $L/macos-compat/tools $L/homebrew
  cp ${./tools/sf_closure_copy.py} $L/macos-compat/tools/sf_closure_copy.py
  cp ${../homebrew/sf_gapscan.py} $L/homebrew/sf_gapscan.py
  cp ${../homebrew/hb_macho.py} $L/homebrew/hb_macho.py
  mkdir -p $out
  python3 -B $L/macos-compat/tools/sf_closure_copy.py --root ${root} --out $out \
    ${F}/AppKit.framework/Versions/C/AppKit ${F}/Cocoa.framework/Versions/A/Cocoa | tee $out/.closure.txt
  mkdir -p $out/nix-support && mv $out/.closure.txt $out/nix-support/closure.txt
  # libraries named by @rpath are found by leaf name: the Cocoa root has /usr/lib links to those in /lib
  for l in $out/lib/*.dylib; do
    n=$(basename "$l"); [ ! -L ${root}/usr/lib/$n ] || [ -e $out/usr/lib/$n ] || cp -P ${root}/usr/lib/$n $out/usr/lib/$n
  done
  # the base system's own stay the root's
  rm -rf $out${F}/CoreFoundation.framework $out${F}/Foundation.framework $out${F}/CoreServices.framework $out${F}/IOKit.framework
  rm -f $out/usr/lib/libc++.1.dylib $out/usr/lib/libc++abi.dylib $out/usr/lib/libIOKitCF.dylib
  chmod -R u+w $out
''
