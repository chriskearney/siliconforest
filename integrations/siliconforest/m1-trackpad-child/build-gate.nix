# Read-only collector using the exact tiny IOKit MIG header/archive.
let
  pd = (import ../rebase/pd.nix).pd;
  pkgs = import pd.inputs.nixpkgs { system = "x86_64-linux"; };
  p = pd.packages.x86_64-linux;
  iokit = import ../m1-dart-survey/build-iokit-mig-header.nix;
  inputs = builtins.fromJSON (builtins.readFile ./gate-build-inputs-digest.json);
  names = [ "gate.c" "gate.h" "main.c" "child_state.h" "trackpad_reference.h" "descriptor_guard.c" "descriptor_guard.h" ];
  source = pkgs.runCommand "darwin-native-registry-gate-source" {} ''
    mkdir -p "$out"
    cp ${./registry-gate-native/gate.c} "$out/gate.c"
    cp ${./registry-gate-native/gate.h} "$out/gate.h"
    cp ${./registry-gate-native/main.c} "$out/main.c"
    cp ${./child_state.h} "$out/child_state.h"
    cp ${./trackpad_reference.h} "$out/trackpad_reference.h"
    cp ${./descriptor_guard.c} "$out/descriptor_guard.c"
    cp ${./descriptor_guard.h} "$out/descriptor_guard.h"
  '';
  checks = pkgs.lib.concatMapStringsSep "\n" (n:
    let sha = inputs.files.${n};
    in assert builtins.match "[0-9a-f]{64}" sha != null;
    "echo '${sha}  ${source}/${n}' | sha256sum -c -") names;
in pkgs.stdenv.mkDerivation {
  name = "darwin-native-input-inventory-arm64";
  dontUnpack = true;
  buildPhase = checks + "\n" + ''
    export DARWIN_SDK_ROOT=${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    mkdir iokit-objects
    (
      cd iokit-objects
      ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-ar x ${iokit}/lib/libIOKit.a
      ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-ar --format=darwin crs ../libIOKit.a *.o
    )
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang \
      -std=c11 -Wall -Wextra -Werror -Wpedantic -O1 -DIOKIT=1 -DKERNEL=0 -UKERNEL \
      -isystem ${p.libsystem-arm64}/usr/include -I${iokit}/include -I${source} \
      ${source}/gate.c ${source}/main.c ${source}/descriptor_guard.c libIOKit.a \
      --ld-path=${p.native-ld}/bin/ld -nostdlib \
      -L${p.libsystem-arm64}/usr/lib -L${p.libsystem-arm64}/usr/lib/system \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${p.libsystem-arm64}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-fixup_chains \
      -lSystem -o darwin-native-input-inventory
  '';
  installPhase = ''
    mkdir -p "$out/usr/bin"
    cp darwin-native-input-inventory "$out/usr/bin/"
  '';
  dontFixup = true;
}
