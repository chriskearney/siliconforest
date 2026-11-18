# SPDX-License-Identifier: MIT
# Whole provider, with a private ICC checksum and separately qualified installs.
let
  e = import ../environment.nix;
  inherit (e) pkgs p finch libsystem sdk cc ld;
  skcms = (import ../../../../release/fetch.nix { pkgs = pkgs; }) "skcms";
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-finch-ColorSync-arm64";
  src = finch;
  patches = [ ./patches/0001-sf-runtime-layout.patch ./patches/0002-private-profile-md5.patch ];
  nativeBuildInputs = [ pkgs.python3 ];
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    mkdir backend objects
    cp -r ${skcms}/. backend/
    cp -r ${./include} headers
    chmod -R u+w headers
    cp ${../../m1-avd/user/sf_md5.h} headers/sf_md5.h
    cp ${./SFProfileMD5.h} headers/SFProfileMD5.h
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fblocks -D_DARWIN_C_SOURCE -I$PWD/headers -I$PWD/backend -I${libsystem}/usr/include -I${p.coreFoundation-arm64}/include"
    for s in userland/ColorSync/ColorSync*.c; do
      ${cc} $CF -DSF_COLORSYNC_PREPROCESS -E -P "$s" -o objects/$(basename "$s" .c).i
    done
    python3 ${./declarations.py} ${../tools/c_functions.py} userland/ColorSync headers/ColorSync/Functions.h objects/*.i
    for s in userland/ColorSync/ColorSync*.c; do
      ${cc} $CF -c "$s" -o objects/$(basename "$s" .c).o
    done
    for s in backend/skcms.cc backend/src/skcms_TransformBaseline.cc; do
      ${cc} $CF -std=c++17 -fno-exceptions -fno-rtti -fvisibility=hidden -DSKCMS_DISABLE_HSW -DSKCMS_DISABLE_SKX -c "$s" -o objects/$(basename "$s" .cc).o
    done
    ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-nm -g -U objects/*.o | awk '{print $NF}' | sed -n '/^_ColorSync/p; /^_CGDisplay/p; /^_kColorSync/p' | sort -u > exports
    ${cc} -dynamiclib objects/*.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system -L${p.coreFoundation-arm64}/usr/lib \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-exported_symbols_list,exports \
      -install_name /System/Library/Frameworks/ColorSync.framework/Versions/A/ColorSync -current_version 3813.3.3 -compatibility_version 1 \
      ${p.compiler-rt-arm64}/lib/libcompiler_rt.a -lCoreFoundation -lSystem -o ColorSync
  '';
  installPhase = ''
    fw=$out/System/Library/Frameworks/ColorSync.framework
    mkdir -p $fw/Versions/A/Resources/Licenses
    cp ColorSync $fw/Versions/A/
    cp -r headers/ColorSync $fw/Versions/A/Headers
    ln -s A $fw/Versions/Current
    ln -s Versions/Current/ColorSync $fw/ColorSync
    ln -s Versions/Current/Headers $fw/Headers
    cp ${finch}/LICENSE* $fw/Versions/A/Resources/Licenses/
    cp backend/LICENSE $fw/Versions/A/Resources/Licenses/skcms-LICENSE
  '';
  dontFixup = true;
  dontStrip = true;
}
