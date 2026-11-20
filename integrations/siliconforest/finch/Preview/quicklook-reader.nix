# SPDX-License-Identifier: MIT OR Apache-2.0
# Preserve the open QTP subset; add three Finch keys and a narrow real reader.
let
  e = import ../environment.nix;
  a = import ../../cocoa/arm64.nix;
in e.pkgs.runCommand "siliconforest-preview-quicklook-reader-arm64" {} ''
  export DARWIN_SDK_ROOT=${e.sdk}
  cp ${./QuickLookReader.h} QuickLookReader.h
  CF="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness -fblocks -fobjc-exceptions -fexceptions -fobjc-arc-exceptions -fobjc-arc -isysroot ${e.sdk} -I$PWD -isystem ${e.libsystem}/usr/include -isystem ${a.base.libobjc}/usr/include -isystem ${a.base.foundation}/usr/include -isystem ${a.base.corefoundation}/include -isystem ${a.appDeps.appkit}/usr/include -isystem ${a.appDeps.coregraphics}/usr/include -isystem ${a.appDeps.onyx2d}/usr/include -isystem ${a.appDeps.quartzcore}/usr/include -isystem ${a.src}/src/Frameworks -isystem ${a.mesa}/usr/include -F${a.openglFramework}/System/Library/Frameworks"
  LF="--ld-path=${e.ld} -nostdlib -isysroot ${e.sdk} -L${e.libsystem}/usr/lib -L${a.base.libobjc}/usr/lib -L${a.base.foundation}/usr/lib -L${a.base.corefoundation}/usr/lib -L${a.appDeps.appkit}/usr/lib -L${a.appDeps.coregraphics}/usr/lib -lAppKit -lCoreGraphics -lFoundation -lCoreFoundation -lobjc -lSystem -Wl,-dylib_file,/usr/lib/system/libdyld.dylib:${e.libsystem}/usr/lib/system/libdyld.dylib -Wl,-platform_version,macos,26.5,26.5"
  for kind in 1 2; do
    ${e.cc} $CF -fno-objc-arc -DSF_KIND=$kind -c ${../QuickTime/loader/QuickLook.m} -o Baseline$kind.o
  done
  ${e.cc} $CF -c ${./QuickLookAdditions.m} -o Keys.o
  ${e.cc} $CF -c ${./QuickLookReader.m} -o Reader.o
  Q=$out/System/Library/Frameworks/QuickLook.framework
  U=$out/System/Library/Frameworks/QuickLookUI.framework
  mkdir -p $Q/Versions/A/Resources $U/Versions/A/Resources $out/bin
  ${e.cc} -dynamiclib Baseline1.o Keys.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/System/Library/Frameworks/QuickLook.framework/Versions/A/QuickLook -o $Q/Versions/A/QuickLook
  ${e.cc} -dynamiclib Baseline2.o Reader.o $LF -Wl,-compatibility_version,1 -Wl,-current_version,1 \
    -Wl,-install_name,/System/Library/Frameworks/QuickLookUI.framework/Versions/A/QuickLookUI -o $U/Versions/A/QuickLookUI
  for name in QuickLook QuickLookUI; do
    F=$out/System/Library/Frameworks/$name.framework
    ln -s A $F/Versions/Current
    ln -s Versions/Current/$name $F/$name
    ln -s Versions/Current/Resources $F/Resources
    mkdir -p $F/Versions/A/Resources/Source $F/Versions/A/Resources/Licenses
    cp ${./QuickLookAdditions.m} ${./QuickLookReader.h} ${./QuickLookReader.m} $F/Versions/A/Resources/Source/
    cp ${../QuickTime/loader/QuickLook.m} $F/Versions/A/Resources/Source/QTP-QuickLook.m
    cp ${./QUICKLOOK.md} $F/Versions/A/Resources/
    cp ${e.finch}/LICENSE-MIT ${e.finch}/LICENSE-APACHE $F/Versions/A/Resources/Licenses/
    cp ${../../../../LICENSE} $F/Versions/A/Resources/Licenses/LICENSE-SiliconForest-MIT
  done
  ${e.cc} $CF -fno-objc-arc ${./quicklook-reader-probe.m} $LF \
    -F$out/System/Library/Frameworks -framework QuickLook -framework QuickLookUI -o $out/bin/quicklook-reader-probe
''
