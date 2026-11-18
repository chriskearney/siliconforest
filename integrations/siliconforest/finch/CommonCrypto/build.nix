# SPDX-License-Identifier: MIT
# Finch's CommonCrypto bridge against the same published source it uses.
let
  e = import ../environment.nix;
  inherit (e) pkgs p finch libsystem sdk cc ld;
  crypto = import ../corecrypto/build.nix;
  source = (import ../../../../release/fetch.nix { pkgs = pkgs; }) "apple-commoncrypto-oss";
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-finch-commoncrypto-arm64";
  src = source;
  patches = [ ./patches/0001-private-global-storage.patch ./patches/0002-dyld-sdk-version.patch ];
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    mkdir -p headers/CommonCrypto headers/CommonNumerics objects
    cp include/*.h include/Private/*.h headers/CommonCrypto/
    cp include/Private/Common{Numerics,BaseXX,CRC}.h headers/CommonNumerics/
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -fno-stack-protector -D_DARWIN_C_SOURCE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -Wno-deprecated-declarations -I${finch}/userland/corecrypto/compat -I$PWD/headers -Ilib -Ilibcn -I${libsystem}/usr/include"
    for s in lib/*.c libcn/*.c; do
      ${cc} $CF -c "$s" -o objects/$(basename "$s" .c).o
    done
    ${cc} -dynamiclib objects/*.o \
      --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system -L${crypto}/usr/lib/system \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-exported_symbols_list,exports.exp-in \
      -install_name /usr/lib/system/libcommonCrypto.dylib -compatibility_version 1 -current_version 65535 \
      -lcorecrypto -lSystem -o libcommonCrypto.dylib
  '';
  installPhase = ''
    mkdir -p $out/usr/lib/system $out/usr/share/licenses/finch-commoncrypto
    cp libcommonCrypto.dylib $out/usr/lib/system/
    cp -a headers $out/include
    cp ${e.pd.outPath}/src/Libraries/Security/apple/APPLE_LICENSE $out/usr/share/licenses/finch-commoncrypto/APPLE_LICENSE
    cp ${finch}/LICENSE* $out/usr/share/licenses/finch-commoncrypto/
  '';
  dontFixup = true;
  dontStrip = true;
}
