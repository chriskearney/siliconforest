# SPDX-License-Identifier: MIT
# The Cocoa system root for arm64: everything a Mac GUI application needs at run time that
# the lab's base image does not have, as one tree laid out like the guest's root
# (System/Library/Frameworks, usr/lib, Applications, ...). All of it is upstream PureDarwin's
# own arm64 build of its application frameworks at the pinned commit (./pin.nix); see
# docs/roadmap/issues/SF-U-cocoa.md for what each part is and its licence.
#
#   parts   upstream's arm64 desktop bundle (AppKit, QuartzCore, CoreGraphics/Onyx2D,
#           CoreText, CoreVideo, IOSurface, OpenGL, Carbon, CoreServices, CoreData, Cocoa,
#           WindowServer, Terminal, Calculator, fonts) and the libraries below it that the
#           upstream bundle expects its target to have already.
#   extra   further derivations laid over it (our patched frameworks, test applications).
#   remove  paths taken out again (a launchd job whose daemon cannot run here).
#
#   nix-build --extra-experimental-features 'nix-command flakes' build-cocoa-root.nix --no-out-link
{ extra ? [ ], remove ? [ ] }:
let
  pd = import ./pin.nix;
  pkgs = (import ../../../release/cocoa-base.nix).pkgs;
  # upstream's Swift runtime with the Darwin module map of before the rename (../rebase/swift-darwin-module.nix)
  swiftRuntime = import ../rebase/swift-darwin-module.nix pd."swift-runtime-arm64";
  parts = [
    pd."argon-desktop-msm-arm64"
    (pd."framework-compat-arm64".override { swiftRuntime = swiftRuntime; })   # with the corrected Swift runtime below
    pd."freetype2-arm64"
    pd."fontconfig-arm64"
    pd."expat-arm64"
    pd."wayland-arm64"
    pd."libffi-arm64"
    pd."xkbcommon-arm64"
    pd."xkeyboardConfig-arm64"
    pd."mesa-msm-arm64"
    pd."libdrm-dri-arm64"
    pd."zlib-arm64"
    pd."libzDylib-arm64"
    pd."libcxxDylib-arm64"
    pd."libcxxabiDylib-arm64"
    pd."harfbuzz-arm64"
    pd."fribidi-arm64"
    pd."libpng-arm64"
    pd."libjpeg-arm64"
    pd."iokit-arm64"
    pd."llvm-arm64"            # libLLVM.dylib: Mesa's software rasteriser (llvmpipe) links it
    swiftRuntime               # framework-compat's Foundation re-exports libswiftFoundation
  ] ++ extra;
in pkgs.runCommand "siliconforest-cocoa-root-arm64" { } ''
  mkdir -p $out
  for d in ${toString parts}; do
    # symbolic links are kept (a framework's Versions/Current, a library's version links);
    # a link that points into the store is replaced by what it points to
    # (upstream's bundle was copied with links resolved: where a later part has the link, the
    # directory copy gives way to it)
    (cd $d && find . -type l) | while read -r l; do
      if [ -d "$out/$l" ] && [ ! -L "$out/$l" ]; then rm -rf "$out/$l"; fi
    done
    cp -a --no-preserve=mode,ownership $d/. $out/
  done
  find $out -type l | while read -r l; do
    t=$(readlink "$l")
    case "$t" in /nix/store/*) rm "$l"; cp -rL --no-preserve=mode,ownership "$t" "$l";; esac
  done
  # libraries installed under /lib whose install names are @rpath/<name> (wayland, libdrm):
  # nothing here carries an rpath, dyld finds them by leaf name in /usr/lib
  for l in $out/lib/*.dylib; do
    [ -e "$out/usr/lib/$(basename "$l")" ] || ln -s "../../lib/$(basename "$l")" "$out/usr/lib/$(basename "$l")"
  done
  for r in ${toString remove}; do rm -rf "$out/$r"; done
  # what only a build needs
  rm -rf $out/usr/include $out/include $out/nix-support $out/usr/lib/pkgconfig $out/lib/pkgconfig $out/usr/share/man \
         $out/share/man $out/share/doc $out/usr/share/doc $out/lib/cmake $out/usr/lib/cmake $out/usr/share/aclocal
  find $out \( -name '*.a' -o -name '*.la' \) -delete
  find $out -path '*/Headers' -prune -exec rm -rf {} +
  find $out -type f \( -name '*.dylib' -o -path '*/MacOS/*' -o -path '*.framework/*' -o -path '*/bin/*' -o -path '*/libexec/*' \) -exec chmod 755 {} + 2>/dev/null || true
''
