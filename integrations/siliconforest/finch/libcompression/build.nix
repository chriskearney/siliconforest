# SPDX-License-Identifier: MIT
# Finch's whole codec wrapper and its exact pinned open codec sources.
let
  e = import ../environment.nix;
  inherit (e) pkgs p finch libsystem sdk cc ld;
  lzfse = (import ../../../../release/fetch.nix { pkgs = pkgs; }) "lzfse";
  lz4 = (import ../../../../release/fetch.nix { pkgs = pkgs; }) "lz4";
  brotli = (import ../../../../release/fetch.nix { pkgs = pkgs; }) "brotli";
  xz = p.xz-arm64;
  zlib = p.zlib-arm64;
in pkgs.stdenv.mkDerivation {
  name = "siliconforest-finch-libcompression-arm64";
  src = finch;
  dontConfigure = true;
  buildPhase = ''
    export DARWIN_SDK_ROOT=${sdk}
    tar -xf ${lzfse}
    tar -xf ${lz4}
    tar -xf ${brotli}
    tar -xf ${xz.src}
    mkdir objects
    CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O2 -fvisibility=hidden -D_DARWIN_C_SOURCE -I${libsystem}/usr/include -I${e.pd.outPath}/src/Libraries/libcompression -I${zlib}/include -I${xz}/include -isystem lzfse-lzfse-1.0/src -Ilz4-1.10.0/lib -Ibrotli-1.1.0/c/include"
    for s in lzfse-lzfse-1.0/src/*.c lz4-1.10.0/lib/lz4.c brotli-1.1.0/c/common/*.c brotli-1.1.0/c/dec/*.c brotli-1.1.0/c/enc/*.c; do
      case "$s" in */lzfse_main.c) continue;; esac
      ${cc} $CF -c "$s" -o objects/$(echo "$s" | tr / _).o
    done
    ${cc} $CF -fvisibility=default -Wall -Wextra -Werror -c userland/libcompression/compression.c -o objects/compression.o
    ${cc} -dynamiclib objects/*.o --ld-path=${ld} -nostdlib -isysroot ${sdk} \
      -L${libsystem}/usr/lib -L${libsystem}/usr/lib/system \
      -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${libsystem}/usr/lib/system/libdyld.dylib \
      -Wl,-platform_version,macos,26.5,26.5 -Wl,-exported_symbols_list,userland/libcompression/exports.txt \
      -install_name /usr/lib/libcompression.dylib -compatibility_version 1 -current_version 1 \
      ${xz}/lib/liblzma.a ${zlib}/lib/libz.a -lSystem -o libcompression.dylib
  '';
  installPhase = ''
    mkdir -p $out/usr/lib $out/usr/include $out/usr/share/licenses/finch-libcompression/{finch,lzfse,lz4,brotli}
    cp libcompression.dylib $out/usr/lib/
    cp ${e.pd.outPath}/src/Libraries/libcompression/compression.h $out/usr/include/
    cp ${finch}/LICENSE* $out/usr/share/licenses/finch-libcompression/finch/
    cp lzfse-lzfse-1.0/LICENSE $out/usr/share/licenses/finch-libcompression/lzfse/
    cp lz4-1.10.0/lib/LICENSE $out/usr/share/licenses/finch-libcompression/lz4/
    cp brotli-1.1.0/LICENSE $out/usr/share/licenses/finch-libcompression/brotli/
    mkdir -p $out/usr/share/licenses/finch-libcompression/{xz,zlib}
    cp xz-${xz.version}/COPYING* $out/usr/share/licenses/finch-libcompression/xz/
    cp ${zlib}/include/zlib.h $out/usr/share/licenses/finch-libcompression/zlib/
  '';
  dontFixup = true;
  dontStrip = true;
}
