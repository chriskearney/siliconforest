# SPDX-License-Identifier: MIT
# No ModelIO API is implemented. This satisfies only the observed zero-import
# strong load command; a typed consumer must get a real implementation.
let e = import ../environment.nix; in
e.pkgs.runCommand "siliconforest-preview-modelio-load-contract-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  F=$out/System/Library/Frameworks/ModelIO.framework
  mkdir -p $F/Versions/A/Resources/Source $out/bin
  CF="-O2 -Wall -Wextra -Werror -isysroot ${e.sdk} -isystem ${e.libsystem}/usr/include"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  ${e.cc} $CF -dynamiclib ${./ModelIOLoadContract.c} $LF \
    -Wl,-install_name,/System/Library/Frameworks/ModelIO.framework/Versions/A/ModelIO \
    -Wl,-compatibility_version,1 -Wl,-current_version,268.2.2 -o $F/Versions/A/ModelIO
  ${e.cc} $CF ${./modelio-load-probe.c} $LF -o $out/bin/modelio-load-probe
  ln -s A $F/Versions/Current
  ln -s Versions/Current/ModelIO $F/ModelIO
  cp ${./ModelIOLoadContract.c} $F/Versions/A/Resources/Source/
  cat >$F/Versions/A/Resources/SCOPE.txt <<'SCOPE'
  Not a ModelIO implementation. No Apple function/class or asset APIs supplied.
  Preview's mandatory load identity only; direct/current-closure API imports 0.
  Dynamic lookups and absent future providers are not covered by this audit.
  SCOPE
''
