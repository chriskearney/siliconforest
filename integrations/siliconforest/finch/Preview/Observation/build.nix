# SPDX-License-Identifier: MIT
let
  e = import ../../environment.nix;
  cross = import ../../Network/toolchain.nix;
  foundationURL = import ../foundation-url.nix;
  runtime = import ../../../terminal-app/build-swift-runtime.nix;
  swiftSource = e.pkgs.fetchFromGitHub {
    owner = "swiftlang";
    repo = "swift";
    rev = "swift-6.3.3-RELEASE";
    hash = "sha256-7/jT/U0sOsr4iWnCluyUWjnD/XH5CnPyAG9EQ+Nq+tI=";
  };
in e.pkgs.runCommand "siliconforest-preview-observation-arm64" {} ''
  sdk=${foundationURL}/compiler-sdk
  export DARWIN_SDK_ROOT="$sdk"
  module_dir=$out/usr/lib/swift/Observation.swiftmodule
  mkdir -p include "$module_dir" "$out/bin" "$out/share/licenses/Swift"
  cat > include/module.modulemap <<'MAP'
  module SFObservationLocks [system] {
    header "ObservationLocks.h"
    export *
  }
  MAP
  echo '#include <os/lock.h>' > include/ObservationLocks.h
  src=${swiftSource}/stdlib/public/Observation/Sources/Observation
  grep -q '^import Darwin.os.lock$' "$src/Locking.swift"
  sed -e 's/Darwin\.os\.lock/SFObservationLocks/g' \
      -e 's/^import SFObservationLocks$/internal import SFObservationLocks/' \
      "$src/Locking.swift" > Locking.swift
  swift_common=(
    -target arm64-apple-macosx26.5 -sdk "$sdk" -resource-dir ${cross}/resource
    -I${runtime.dev}/usr/lib/swift -I"$PWD/include"
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__
    -parse-as-library -swift-version 5 -O -module-cache-path "$TMPDIR/modules"
  )
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" \
    -module-name Observation -module-link-name swiftObservation -enable-library-evolution \
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 5.9:macOS 14' \
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 6.0:macOS 15' \
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 6.2:macOS 26' \
    -enable-experimental-feature Macros -enable-experimental-feature ExtensionMacros \
    -Xfrontend -disable-implicit-string-processing-module-import -wmo \
    -emit-module -emit-module-path "$module_dir/arm64-apple-macos.swiftmodule" \
    -emit-module-interface-path "$module_dir/arm64-apple-macos.swiftinterface" \
    -emit-private-module-interface-path "$module_dir/arm64-apple-macos.private.swiftinterface" \
    -emit-object -o Observation.o Locking.swift ${./SwiftUITracking.swift} \
    "$src"/{Observable,ObservationRegistrar,ObservationTracking,Observations,ThreadLocal}.swift
  ${e.cc} -O2 -isysroot "$sdk" -DXNU_PLATFORM_MacOSX=1 -c ${./ThreadLocal.c} -o ThreadLocal.o
  linker=(
    --ld-path=${e.ld} -nostdlib -isysroot "$sdk"
    -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${runtime}/usr/lib/swift
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  ${e.cc} -dynamiclib Observation.o ThreadLocal.o "''${linker[@]}" \
    -lswiftCore -lswift_Concurrency -lobjc -lSystem -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/usr/lib/swift/libswiftObservation.dylib -o "$out/usr/lib/swift/libswiftObservation.dylib"
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" -I"$out/usr/lib/swift" \
    -module-name ObservationProbe -emit-object -o Probe.o ${./probe.swift}
  ${e.cc} Probe.o "''${linker[@]}" -L"$out/usr/lib/swift" \
    -lswiftObservation -lswiftCore -lobjc -lSystem -o "$out/bin/observation-probe"
  cp ${swiftSource}/LICENSE.txt "$out/share/licenses/Swift/LICENSE.txt"
''
