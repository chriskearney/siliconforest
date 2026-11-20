# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cross = import ../../Network/toolchain.nix;
  foundationURL = import ../foundation-url.nix;
  runtime = import ../../../terminal-app/build-swift-runtime.nix;
  cxx = e.p.libcxxDylib-arm64;
  cxxabi = e.p.libcxxabiDylib-arm64;
  source = e.pkgs.fetchFromGitHub {
    owner = "OpenCombine";
    repo = "OpenCombine";
    rev = "8576f0d579b27020beccbccc3ea6844f3ddfc2c2";
    hash = "sha256-tw/WVY3TG8Jp+AO2rCA20x0u3lrg1wl7IaPkJXdfMzE=";
  };
in e.pkgs.runCommand "siliconforest-preview-combine-arm64" { nativeBuildInputs = [ e.pkgs.python3 ]; } ''
  sdk=${foundationURL}/compiler-sdk
  export DARWIN_SDK_ROOT="$sdk"
  fwpath="$out/System/Library/Frameworks"
  framework="$fwpath/Combine.framework"
  module="$framework/Versions/A/Modules/Combine.swiftmodule"
  mkdir -p "$module" "$out/bin" "$out/include" "$out/share/licenses/OpenCombine" "$out/share/licenses/Finch" helpers
  cp -r ${source}/Sources/OpenCombine src
  chmod -R u+w src
  python3 ${e.finch}/userland/Combine/adapt.py src
  cp ${e.finch}/userland/Combine/Finch/*.swift src/
  chmod u+w src/FanIn.swift
  sed -i '/^import Darwin$/a internal import SFCombineLocks' src/FanIn.swift
  printf '%s\n' '#include <os/lock.h>' > helpers/CombineLocks.h
  cp ${source}/Sources/COpenCombineHelpers/include/COpenCombineHelpers.h helpers/
  cat > helpers/module.modulemap <<'MAP'
  module COpenCombineHelpers {
    header "COpenCombineHelpers.h"
    export *
  }
  module SFCombineLocks [system] {
    header "CombineLocks.h"
    export *
  }
  MAP
  ${e.p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang++ \
    -O2 -fvisibility=hidden -isysroot "$sdk" -DXNU_PLATFORM_MacOSX=1 \
    -std=c++17 -nostdinc++ -I${cxx}/usr/include/c++/v1 -Ihelpers \
    -c ${source}/Sources/COpenCombineHelpers/COpenCombineHelpers.cpp -o Helpers.o
  swift_common=(
    -target arm64-apple-macosx26.5 -sdk "$sdk" -resource-dir ${cross}/resource
    -I${runtime.dev}/usr/lib/swift -I"$PWD/helpers"
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__
    -parse-as-library -swift-version 5 -O -wmo -enable-library-evolution -module-cache-path "$TMPDIR/modules"
    -Xfrontend -disable-implicit-string-processing-module-import
  )
  linker=(
    --ld-path=${e.ld} -nostdlib -isysroot "$sdk"
    -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${runtime}/usr/lib/swift
    -L${cxx}/usr/lib -L${cxxabi}/usr/lib
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  mapfile -t sources < <(find src -name '*.swift' | LC_ALL=C sort)
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" -module-name Combine \
    -emit-module -emit-module-path "$module/arm64-apple-macos.swiftmodule" \
    -emit-module-interface-path "$module/arm64-apple-macos.swiftinterface" \
    -emit-object -o Combine.o "''${sources[@]}"
  ${e.cc} -dynamiclib Combine.o Helpers.o "''${linker[@]}" -lc++ -lc++abi -lswiftCore -lswift_Concurrency -lobjc -lSystem \
    -Wl,-install_name,/System/Library/Frameworks/Combine.framework/Versions/A/Combine \
    -Wl,-compatibility_version,1 -Wl,-current_version,3023 -o "$framework/Versions/A/Combine"
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/Combine "$framework/Combine"
  ln -s Versions/Current/Modules "$framework/Modules"
  cp helpers/* "$out/include/"
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" -F"$fwpath" \
    -module-name CombineProbe -emit-object -o Probe.o ${./probe.swift}
  ${e.cc} Probe.o "''${linker[@]}" -F"$fwpath" -framework Combine -lswiftCore -lswift_Concurrency -lobjc -lSystem \
    -o "$out/bin/combine-probe"
  cp ${source}/LICENSE "$out/share/licenses/OpenCombine/"
  cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE "$out/share/licenses/Finch/"
''
