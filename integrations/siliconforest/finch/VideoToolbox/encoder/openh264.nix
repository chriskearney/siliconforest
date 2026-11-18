# SPDX-License-Identifier: MIT
# Source-built software fallback, same upstream release Finch uses; no Mac builds.
let
 e=import ../../environment.nix;
 inherit(e) pkgs p sdk libsystem;
 tc=p.arm64-cross-toolchain;
 cxx=p.libcxxDylib-arm64;
in pkgs.stdenv.mkDerivation {
 pname="siliconforest-openh264-arm64";version="2.6.0";
 src=(import ../../../../../release/fetch.nix { pkgs = pkgs; }) "openh264";
 nativeBuildInputs=[pkgs.gnumake pkgs.perl];
 dontConfigure=true;
 buildPhase=''
  export DARWIN_SDK_ROOT=${sdk}
  BASE="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -DNDEBUG -fPIC -fvisibility=hidden -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -I${libsystem}/usr/include"
  make -j$NIX_BUILD_CORES OS=darwin ARCH=arm64 USE_ASM=No \
   CC=${tc}/bin/arm64-apple-darwin20.4-clang CXX=${tc}/bin/arm64-apple-darwin20.4-clang++ \
   AR=${tc}/bin/arm64-apple-darwin20.4-ar \
   CFLAGS="$BASE -MMD -MP -DGENERATED_VERSION_HEADER" \
   CXXFLAGS="$BASE -nostdinc++ -I${cxx}/usr/include/c++/v1 -std=c++17 -DGENERATED_VERSION_HEADER" libopenh264.a
 '';
 installPhase=''
  mkdir -p $out/lib $out/include/wels $out/share/licenses/openh264
  cp libopenh264.a $out/lib/
  cp codec/api/wels/*.h $out/include/wels/
  cp LICENSE $out/share/licenses/openh264/
  if test -f PATENTS; then cp PATENTS $out/share/licenses/openh264/; fi
 '';
 dontFixup=true;dontStrip=true;
}
