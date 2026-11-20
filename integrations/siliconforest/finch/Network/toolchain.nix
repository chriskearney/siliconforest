# SPDX-License-Identifier: MIT
# Linux Swift compiler + PD's OSS declarations and own open-source Swift runtime.
# This assembles a cross-build sysroot; it never reads an Apple SDK or contacts a Mac.
let
  e = import ../environment.nix;
  inherit (e) pkgs p sdk libsystem;
  foundation = import ../../terminal-app/build-foundation.nix;
  swiftRuntime = import ../../terminal-app/build-swift-runtime.nix;
  modules = swiftRuntime.dev;
  hostSwift = p.swift-toolchain;
  overlays = "${e.pd.outPath}/src/Libraries/SwiftOverlays";
in pkgs.runCommand "siliconforest-finch-swift-cross-sysroot" {} ''
  mkdir -p $out/resource
  cp -rL ${sdk} $out/sdk
  chmod -R u+w $out/sdk
  cp -rL ${p.libobjc-arm64}/usr/include/. $out/sdk/usr/include/
  cp -rL ${foundation}/usr/include/. $out/sdk/usr/include/
  chmod -R u+w $out/sdk
  F=$out/sdk/System/Library/Frameworks
  rm -rf $F/CoreFoundation.framework
  cp -rL ${p.coreFoundation-arm64}/System/Library/Frameworks/CoreFoundation.framework $F/
  chmod -R u+w $out/sdk
  mkdir -p $F/CoreFoundation.framework/Modules $F/Foundation.framework/Modules
  ln -sfn ../../../../usr/include/Foundation $F/Foundation.framework/Headers
  cp ${overlays}/modules/Foundation.modulemap $F/Foundation.framework/Modules/module.modulemap
  cp ${overlays}/modules/Foundation.apinotes $out/sdk/usr/include/Foundation/
  cp ${overlays}/modules/ObjectiveC.modulemap $out/sdk/usr/include/objc/module.modulemap
  cp $out/sdk/usr/include/dispatch/darwin/module.modulemap $out/sdk/usr/include/dispatch/module.modulemap
  cat > $F/CoreFoundation.framework/Modules/module.modulemap <<'MAP'
framework module CoreFoundation [extern_c] [system] {
  umbrella header "CoreFoundation.h"
  export *
  module * { export * }
}
MAP
  # Generate the same public Darwin module used to build PD's Swift overlays.
  # sf_pthread_sched.h defines XNU_KERNEL_PRIVATE and must stay out of that module, as it did under
  # its old name (the generator's name pattern predates the rename; ../../rebase/swift-darwin-module.nix
  # has the whole story). With it in, the Darwin module does not build and nothing can import Foundation.
  mv $out/sdk/usr/include/sf_pthread_sched.h $TMPDIR/sf_pthread_sched.h.aside
  sh ${overlays}/gen-darwin-modulemap.sh $out/sdk ${hostSwift}/bin/clang arm64-apple-macosx13.0
  mv $TMPDIR/sf_pthread_sched.h.aside $out/sdk/usr/include/sf_pthread_sched.h
  if grep -q sf_pthread_sched $out/sdk/usr/include/module.modulemap; then echo "sf_pthread_sched.h is in the Darwin module"; exit 1; fi
  ln -s ${modules}/usr/lib/swift $out/resource/macosx
  ln -s ${modules}/usr/lib/swift/shims $out/resource/shims
  ln -s ${hostSwift}/lib/swift/clang $out/resource/clang
  cat > $out/swiftc <<'SH'
#!${pkgs.bash}/bin/bash
exec ${hostSwift}/bin/swiftc -target arm64-apple-macosx26.5 -sdk "$out/sdk" -resource-dir "$out/resource" -I${modules}/usr/lib/swift -Xcc -DXNU_PLATFORM_MacOSX=1 -Xcc -U__OPTIMIZE__ -Xfrontend -disable-objc-attr-requires-foundation-module "$@"
SH
  substituteInPlace $out/swiftc --replace-fail '$out' "$out"
  chmod +x $out/swiftc
''
