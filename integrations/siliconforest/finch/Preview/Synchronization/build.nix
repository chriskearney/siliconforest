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
in e.pkgs.runCommand "siliconforest-preview-synchronization-arm64" { nativeBuildInputs = [ e.pkgs.python3 ]; } ''
  sdk=${foundationURL}/compiler-sdk
  export DARWIN_SDK_ROOT="$sdk"
  swift_dir="$out/usr/lib/swift"
  module="$swift_dir/Synchronization.swiftmodule"
  mkdir -p "$module" "$out/include" "$out/bin" "$out/share/licenses/Swift"
  cat > "$out/include/module.modulemap" <<'MAP'
  module SFSynchronizationLocks [system] {
    header "SynchronizationLocks.h"
    export *
  }
  MAP
  printf '%s\n' '#include <os/lock.h>' > "$out/include/SynchronizationLocks.h"
  src=${swiftSource}/stdlib/public/Synchronization
  for name in AtomicIntegers AtomicStorage; do
    python3 ${swiftSource}/utils/gyb --line-directive "" "$src/Atomics/$name.swift.gyb" -o "$name.swift"
  done
  sed 's/^import Darwin$/import SFSynchronizationLocks/' "$src/Mutex/DarwinImpl.swift" > DarwinImpl.swift
  swift_common=(
    -target arm64-apple-macosx26.5 -sdk "$sdk" -resource-dir ${cross}/resource
    -I${runtime.dev}/usr/lib/swift -I"$out/include" -I"$swift_dir"
    -Xcc -fmodule-map-file=${runtime.dev}/usr/lib/swift/shims/module.modulemap
    -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__
    -parse-as-library -swift-version 5 -O -wmo -enable-library-evolution -module-cache-path "$TMPDIR/modules"
    -Xfrontend -disable-implicit-concurrency-module-import -Xfrontend -disable-implicit-string-processing-module-import
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 6.0:macOS 15'
    -enable-experimental-feature 'AvailabilityMacro=SwiftStdlib 6.1:macOS 15.4'
  )
  linker=(
    --ld-path=${e.ld} -nostdlib -isysroot "$sdk"
    -L${e.libsystem}/usr/lib -L${e.p.libobjc-arm64}/usr/lib -L${runtime}/usr/lib/swift -L"$swift_dir"
    "-Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib"
    -Wl,-platform_version,macos,26.5,26.5
  )
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" -module-name Synchronization -module-link-name swiftSynchronization \
    -enable-builtin-module -enable-experimental-feature RawLayout -enable-experimental-feature StaticExclusiveOnly \
    -enable-experimental-feature Extern -enable-experimental-feature NoncopyableGenerics2 \
    -enable-experimental-feature SuppressedAssociatedTypes -enable-experimental-feature SE427NoInferenceOnExtension \
    -enable-experimental-feature NonescapableTypes -enable-experimental-feature LifetimeDependence \
    -enable-experimental-feature InoutLifetimeDependence -enable-experimental-feature LifetimeDependenceMutableAccessors \
    -emit-module -emit-module-path "$module/arm64-apple-macos.swiftmodule" \
    -emit-module-interface-path "$module/arm64-apple-macos.swiftinterface" \
    -emit-object -o Synchronization.o "$src"/Atomics/*.swift "$src"/Cell.swift "$src"/Mutex/Mutex.swift DarwinImpl.swift \
    AtomicStorage.swift AtomicIntegers.swift
  ${e.cc} -dynamiclib Synchronization.o "''${linker[@]}" -lswiftCore -lobjc -lSystem \
    -Wl,-install_name,/usr/lib/swift/libswiftSynchronization.dylib -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -o "$swift_dir/libswiftSynchronization.dylib"
  ${e.p.swift-toolchain}/bin/swiftc "''${swift_common[@]}" -module-name SynchronizationProbe \
    -emit-object -o Probe.o ${./probe.swift}
  ${e.cc} Probe.o "''${linker[@]}" -lswiftSynchronization -lswiftCore -lobjc -lSystem -o "$out/bin/synchronization-probe"
  cp ${swiftSource}/LICENSE.txt "$out/share/licenses/Swift/"
''
