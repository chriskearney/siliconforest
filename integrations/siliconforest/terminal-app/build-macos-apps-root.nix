# SPDX-License-Identifier: MIT
# What a SiliconForest root gets so that macOS applications built for arm64e against the
# macOS 26 SDK run on it (first: Apple's Terminal.app; GitHub issue 52,
# docs/roadmap/issues/SF-Y-terminal-app.md): one tree rooted at /, every file from a recipe.
#
#   usr/lib/dyld, usr/lib/libSystem.B.dylib      ./build-libsystem.nix (optimised; SF_LIBSYSTEM=debug: -O0)
#   usr/lib/libobjc.A.dylib                      ./build-libobjc.nix (SF_POOL_TRACE read once; SF_LIBOBJC=old:
#                                                not in the tree, the root keeps SiliconForest's)
#   usr/lib/libFoundation.dylib                  ./build-foundation-networking.nix (its CA bundle in Foundation's
#                                                Resources; SF_FOUNDATION=plain: ./build-foundation.nix)
#   usr/lib/libCoreFoundation.dylib              ./build-corefoundation.nix (-O2; CFAutorelease autoreleases)
#   usr/lib/swift/*.dylib                        ./build-swift-runtime.nix
#   usr/lib/libWindowServer.dylib, AppKit.framework (binary and resources), CoreText.framework,
#     CoreGraphics.framework, Onyx2D.framework (binaries)   ../cocoa/patched.nix (the Cocoa
#                                                stream's stack with patches 0001 to 0026)
#   ApplicationServices.framework, ImageIO.framework   ../cocoa/build-firefox-root.nix
#   the framework wrappers (CoreFoundation, Foundation, QuartzCore, Carbon, CoreServices,
#     AudioToolbox, IOKit; each wrapped library beside its wrapper as <name>.pd, IOKit re-exporting
#     /usr/lib/libIOKitCF.dylib as CoreFoundation does), ColorSync,
#     DataDetectorsCore, CoreAnalytics, libScreenReader      ./build-compat.nix
#   usr/bin/open                                 ./system/open.c: `open -a Terminal`, `open <bundle>`
#   usr/bin/login                                ./system/login.c: `login -pf <user>` (a terminal's session)
#   usr/share/terminfo                           ./build-terminfo.nix (ncurses' whole database:
#                                                tmux-256color, screen-*, vt*, ...)
#   System/Library/Fonts/NotoSansMonoCJK, NotoEmoji   ./build-fonts-extra.nix (open fonts for CJK and
#                                                emoji, found by CoreText's fallback)
#   System/Library/FeatureFlags/Domain/Terminal.plist   ./system/FeatureFlags/Terminal.plist
#                                                (libSystem's os_feature_enabled reads it:
#                                                DirectColor on, as on macOS 26)
#   usr/share/sf-test/sf-*-probe                 ./probe: what the installer proves each of
#                                                dyld, libSystem, libFoundation and the two
#                                                wrappers with before it replaces the file in use
#
# Which of these replace a file every program loads (and so go through the QEMU pass and the
# guarded procedure) is decided by ./tools/sf_terminal.sh (install-stage); this recipe only says
# what the files are. A root image built from recipes lays this tree over the base.
#
#   nix-build --extra-experimental-features 'nix-command flakes' --no-out-link build-macos-apps-root.nix
let
  pd = (import ../rebase/pd.nix).pd;
  p = pd.packages.${pd.buildSystem};
  pkgs = pd.buildPkgs;
  libsystem = import ./build-libsystem.nix;
  optimised = builtins.getEnv "SF_LIBSYSTEM" != "debug";
  libobjc = if builtins.getEnv "SF_LIBOBJC" == "old" then null else import ./build-libobjc.nix;
  # (TERM7) libFoundation with Foundation's networking (NSURLSession ...; ./build-foundation-networking.nix), as
  # installed on the M1 since 15 November; SF_FOUNDATION=plain: the one without it
  foundation = if builtins.getEnv "SF_FOUNDATION" == "plain" then import ./build-foundation.nix else import ./build-foundation-networking.nix;
  corefoundation = import ./build-corefoundation.nix { };
  swift = import ./build-swift-runtime.nix;
  compat = import ./build-compat.nix;
  cocoa = import ../cocoa/patched.nix;
  firefoxRoot = import ../cocoa/build-firefox-root.nix;
  terminfo = import ./build-terminfo.nix;
  fontsExtra = import ./build-fonts-extra.nix;
  sdk = "${p.apple-sdk}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  F = "System/Library/Frameworks";
in pkgs.runCommand "siliconforest-macos-apps-root-arm64" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -o pipefail
  mkdir -p $out/usr/lib/swift $out/${F} $out/usr/share/sf-test
  cp -L ${libsystem}/usr/lib/dyld ${libsystem}/usr/lib/libSystem.B.dylib ${foundation}/usr/lib/libFoundation.dylib $out/usr/lib/
  cp -L ${corefoundation}/usr/lib/libCoreFoundation.dylib $out/usr/lib/
  # the CA bundle Foundation's TLS reads (Foundation.framework/Versions/A/Resources/ca-bundle.crt) and its notices
  if [ -d ${foundation}/${F}/Foundation.framework/Versions/A/Resources ]; then mkdir -p $out/${F}/Foundation.framework/Versions/A/Resources; cp -rL ${foundation}/${F}/Foundation.framework/Versions/A/Resources/. $out/${F}/Foundation.framework/Versions/A/Resources/; fi
  ${if libobjc == null then "" else "cp -L ${libobjc}/usr/lib/libobjc.A.dylib $out/usr/lib/"}
  cp -L ${swift}/usr/lib/swift/*.dylib $out/usr/lib/swift/
  cp -L ${cocoa.windowserver}/usr/lib/libWindowServer.dylib $out/usr/lib/
  mkdir -p $out/${F}/AppKit.framework/Versions/A $out/${F}/AppKit.framework/Versions/C
  cp -L ${cocoa.appkit}/${F}/AppKit.framework/Versions/A/AppKit $out/${F}/AppKit.framework/Versions/A/
  cp -rL ${cocoa.appkit}/${F}/AppKit.framework/Versions/A/Resources $out/${F}/AppKit.framework/Versions/A/
  ln -s ../A/AppKit $out/${F}/AppKit.framework/Versions/C/AppKit
  for n in CoreText:${cocoa.coretext} CoreGraphics:${cocoa.coregraphics} Onyx2D:${cocoa.onyx2d}; do
    f=''${n%%:*}; mkdir -p $out/${F}/$f.framework/Versions/A; cp -L ''${n#*:}/${F}/$f.framework/Versions/A/$f $out/${F}/$f.framework/Versions/A/
  done
  cp -a ${firefoxRoot}/${F}/ApplicationServices.framework ${firefoxRoot}/${F}/ImageIO.framework $out/${F}/
  chmod -R u+w $out
  cp -a ${compat}/System ${compat}/usr $out/ 2>/dev/null || { cp -a ${compat}/System $out/; cp -a ${compat}/usr/. $out/usr/; }
  chmod -R u+w $out
  mkdir -p $out/usr/share; cp -r ${terminfo}/usr/share/terminfo $out/usr/share/; chmod -R u+w $out/usr/share/terminfo
  mkdir -p $out/System/Library/Fonts; cp -r ${fontsExtra}/System/Library/Fonts/. $out/System/Library/Fonts/; chmod -R u+w $out/System/Library/Fonts
  mkdir -p $out/System/Library/FeatureFlags/Domain; cp ${./system/FeatureFlags/Terminal.plist} $out/System/Library/FeatureFlags/Domain/Terminal.plist

  # ---- /usr/bin/open (./system/open.c): start an application bundle on the desktop
  mkdir -p $out/usr/bin
  ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang -isysroot ${sdk} -mmacosx-version-min=26.5 -O1 -Wall -isystem ${sdk}/usr/include -I${libsystem}/usr/include -I${p.coreFoundation-arm64}/include \
    ${./system/open.c} -fuse-ld=${p.native-ld}/bin/ld -nostdlib -Wl,-syslibroot,$out -L${p.coreFoundation-arm64}/usr/lib -Wl,-platform_version,macos,26.5,26.5 \
    -lCoreFoundation $out/usr/lib/libSystem.B.dylib -o $out/usr/bin/open
  # ---- /usr/bin/login (./system/login.c): what a terminal emulator starts a session with
  ${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang -isysroot ${sdk} -mmacosx-version-min=26.5 -O1 -Wall -isystem ${sdk}/usr/include -I${libsystem}/usr/include -I${p.coreFoundation-arm64}/include \
    ${./system/login.c} -fuse-ld=${p.native-ld}/bin/ld -nostdlib -Wl,-syslibroot,$out -L${p.coreFoundation-arm64}/usr/lib -Wl,-platform_version,macos,26.5,26.5 \
    $out/usr/lib/libSystem.B.dylib -o $out/usr/bin/login

  # ---- the installer's probes
  CC=${p.arm64-cross-toolchain}/bin/arm64-apple-darwin20.4-clang
  CF="-isysroot ${sdk} -mmacosx-version-min=26.5 -O1 -fno-objc-arc -fobjc-exceptions -fblocks -Wno-nullability-completeness -Wno-objc-root-class -Wno-deprecated-declarations -isystem ${sdk}/usr/include -I${libsystem}/usr/include -I${p.libobjc-arm64}/usr/include -I${p.coreFoundation-arm64}/include -I${foundation}/usr/include"
  ln -s libSystem.B.dylib $out/usr/lib/libSystem.dylib      # for the links below only
  LF="-fuse-ld=${p.native-ld}/bin/ld -nostdlib -Wl,-syslibroot,$out -L$out/usr/lib -L${p.libobjc-arm64}/usr/lib -L${p.coreFoundation-arm64}/usr/lib -Wl,-platform_version,macos,26.5,26.5"
  T=$out/usr/share/sf-test; P=${./probe}
  $CC $CF ${if optimised then "-DSF_REQUIRE_OPTIMISED" else ""} $P/sf-libsystem26-probe.c $LF $out/usr/lib/libSystem.B.dylib -o $T/sf-libsystem26-probe
  $CC $CF $P/sf-kvo-probe.m $LF -lobjc -lFoundation -lCoreFoundation -lSystem -o $T/sf-kvo-probe
  $CC $CF $P/sf-cf-autorelease-probe.c $LF $out/usr/lib/libCoreFoundation.dylib -lobjc -lSystem -o $T/sf-cf-autorelease-probe
  $CC $CF $P/sf-cf-o2-probe.c $LF $out/usr/lib/libCoreFoundation.dylib -lSystem -o $T/sf-cf-o2-probe
  $CC $CF -DPROBE_COREFOUNDATION $P/sf-framework-probe.c $LF $out/${F}/CoreFoundation.framework/Versions/A/CoreFoundation -lSystem -o $T/sf-corefoundation-framework-probe
  $CC $CF -DPROBE_FOUNDATION $P/sf-framework-probe.c $LF $out/${F}/Foundation.framework/Versions/C/Foundation -lSystem -o $T/sf-foundation-framework-probe
  $CC $CF -DPROBE_IOKIT $P/sf-framework-probe.c $LF -L${p.iokit-arm64}/usr/lib $out/${F}/IOKit.framework/Versions/A/IOKit -lSystem -o $T/sf-iokit-framework-probe
  # a plain arm64 program with the arm64e subtype in its header: the dyld in use refuses to load
  # arm64 libraries into it, the new one finds that signing does nothing and runs it
  $CC $CF $P/sf-arm64e-probe.c $LF -lSystem -o $T/sf-arm64e-probe.arm64
  python3 - $T/sf-arm64e-probe.arm64 $T/sf-arm64e-probe <<'PYEOF'
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
magic, cpu, sub = struct.unpack_from('<IiI', d)
assert magic == 0xfeedfacf and cpu == 0x0100000c, 'not a thin arm64 Mach-O'
struct.pack_into('<I', d, 8, 0x80000002)                    # CPU_SUBTYPE_ARM64E, ptrauth ABI version 0
open(sys.argv[2], 'wb').write(d)
PYEOF
  ${if libobjc == null then "" else "$CC $CF $P/sf-objc-probe.c $LF $out/usr/lib/libobjc.A.dylib -lSystem -o $T/sf-objc-probe"}
  ${if !optimised then "" else ''
  # the optimised dyld's proof: arm64e in its header as sf-arm64e-probe, and libobjc from DYLD_LIBRARY_PATH
  $CC $CF $P/sf-dyld-probe.c $LF -lobjc -lSystem -o $T/sf-dyld-probe.arm64
  python3 - $T/sf-dyld-probe.arm64 $T/sf-dyld-probe <<'PYEOF'
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
magic, cpu, sub = struct.unpack_from('<IiI', d)
assert magic == 0xfeedfacf and cpu == 0x0100000c, 'not a thin arm64 Mach-O'
struct.pack_into('<I', d, 8, 0x80000002)
open(sys.argv[2], 'wb').write(d)
PYEOF
  rm $T/sf-dyld-probe.arm64''}
  rm $T/sf-arm64e-probe.arm64 $out/usr/lib/libSystem.dylib
  find $out -type d -exec chmod 755 {} +
  find $out -type f \( -name '*.dylib' -o -name dyld -o -path '*.framework/Versions/*/*' -o -path '*/sf-test/*' -o -path '*/usr/bin/*' \) -not -path '*/Resources/*' -exec chmod 755 {} +
''
