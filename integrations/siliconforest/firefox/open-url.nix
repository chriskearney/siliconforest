# SPDX-License-Identifier: MIT
# Private candidate for the Terminal owner's open(1), not an installed replacement.
let
  a = import ../cocoa/arm64.nix;
  inherit (a) pkgs pd;
  system = pd.libsystem-arm64;
  tc = pd.arm64-cross-toolchain;
  sdk = "${pd.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  triple = "arm64-apple-darwin20.4";
in pkgs.stdenv.mkDerivation {
  pname = "siliconforest-firefox-open-url-candidate-arm64";
  version = "1";
  src = pkgs.runCommand "siliconforest-firefox-open-source" {} ''
    mkdir -p $out/integrations/siliconforest/terminal-app/system
    cp ${../terminal-app/system/open.c} $out/integrations/siliconforest/terminal-app/system/open.c
  '';
  # The tracked open.c already contains HTTP(S) LaunchServices handling and
  # later fixes. The historical proposal must not be applied again.
  dontConfigure = true;
  buildPhase = ''
    ${tc}/bin/${triple}-clang -O2 -g -isysroot ${sdk} \
      -I${system}/usr/include -I${pd.coreFoundation-arm64}/include \
      -c integrations/siliconforest/terminal-app/system/open.c -o open.o
    ${tc}/bin/${triple}-clang -isysroot ${sdk} -nostdlib \
      -fuse-ld=${pd.native-ld}/bin/ld -L${system}/usr/lib \
      -L${pd.coreFoundation-arm64}/usr/lib -F${pd.coreServices-arm64}/System/Library/Frameworks \
      -framework CoreServices -lCoreFoundation -lSystem \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${system}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 open.o -o open-url
  '';
  installPhase = ''mkdir -p $out/bin; cp open-url $out/bin/'';
  dontFixup = true;
  dontStrip = true;
}
