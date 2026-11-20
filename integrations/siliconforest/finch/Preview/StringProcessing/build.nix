# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cross = import ../../Network/toolchain.nix;
  foundationURL = import ../foundation-url.nix;
  runtime = import ../../../terminal-app/build-swift-runtime.nix;
  source = e.pkgs.fetchFromGitHub {
    owner = "swiftlang";
    repo = "swift-experimental-string-processing";
    rev = "efe8986824694c53fd5e94a4c634f20b3682baeb";
    hash = "sha256-ENnaw/1UN9PnVLTZujtpfGs5d1e3Z+5Z6EjiwM/8alU=";
  };
in e.pkgs.runCommand "siliconforest-preview-string-processing-arm64" {} ''
  sdk=${foundationURL}/compiler-sdk
  export DARWIN_SDK_ROOT="$sdk"
  out_swift="$out/usr/lib/swift"
  mkdir -p "$out_swift" "$out/bin" "$out/share/licenses/SwiftStringProcessing"
  swift_common=(
    -target arm64-apple-macosx26.5 -sdk "$sdk" -resource-dir ${cross}/resource
    -I${runtime.dev}/usr/lib/swift -I"$out_swift"
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__
    -parse-as-library -swift-version 5 -O -wmo -enable-library-evolution -module-cache-path "$TMPDIR/modules"
    -Xfrontend -disable-implicit-concurrency-module-import -Xfrontend -disable-implicit-string-processing-module-import
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 5.7:macOS 13'
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 5.9:macOS 14'
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 6.0:macOS 15'
  )
  linker=(
    --ld-path=${e.ld} -nostdlib -isysroot "$sdk"
    -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${runtime}/usr/lib/swift -L"$out_swift"
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  build_module() {
    local name=$1
    shift
    local module_dir="$out_swift/$name.swiftmodule"
    mkdir -p "$module_dir"
    mapfile -t files < <(find ${source}/Sources/"$name" -type f -name '*.swift' | LC_ALL=C sort)
    ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" \
      -module-name "$name" -module-link-name "swift$name" -emit-module \
      -emit-module-path "$module_dir/arm64-apple-macos.swiftmodule" \
      -emit-module-interface-path "$module_dir/arm64-apple-macos.swiftinterface" \
      -emit-object -o "$name.o" "''${files[@]}"
    ${e.cc} -dynamiclib "$name.o" "$@" "''${linker[@]}" -lswiftCore -lobjc -lSystem \
      -Wl,-install_name,"/usr/lib/swift/libswift$name.dylib" -Wl,-compatibility_version,1 -Wl,-current_version,1 \
      -o "$out_swift/libswift$name.dylib"
  }
  build_module _RegexParser
  for name in UnicodeData UnicodeScalarProps; do
    ${e.cc} -O2 -isysroot "$sdk" -c "${source}/Sources/_CUnicode/$name.c" -o "$name.o"
  done
  build_module _StringProcessing UnicodeData.o UnicodeScalarProps.o -lswift_RegexParser
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" -emit-object -o Probe.o ${./probe.swift}
  ${e.cc} Probe.o "''${linker[@]}" -lswift_StringProcessing -lswift_RegexParser -lswiftCore -lSystem \
    -o "$out/bin/regex-probe"
  cp ${source}/LICENSE.txt "$out/share/licenses/SwiftStringProcessing/LICENSE.txt"
''
