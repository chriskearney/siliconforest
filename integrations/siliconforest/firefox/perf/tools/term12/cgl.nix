# TERM12 + bake-in step 5: canonical CGL (cgl-gpu.nix) with FXPERF2's 0303 (rect export, EGLImage per surface)
# and VLC's 0009 (cross-thread make-current handoff wait).
{ with0303 ? true, with0009 ? true, extra ? [ ] }:
let
  F = ../../..;   # integrations/siliconforest/firefox
  base = import (F + "/cgl-gpu.nix") { prefix = "/usr/local/lib/siliconforest/opengl/v1"; canonical = true; nv12Backing = true; };
in base.overrideAttrs (old: {
  patches = old.patches
    ++ (if with0303 then [ (F + "/perf/patches/0303-cgl-rectangle-export-and-image-per-surface.patch") ] else [ ])
    ++ (if with0009 then [ (F + "/cgl-patches/0009-make-current-waits-for-another-threads-context.patch") ] else [ ])
    ++ extra;
  installPhase = (old.installPhase or "") + ''
    # Bake-in step 5 (bk5 Java2D->Metal fallback): JBR's libawt_lwawt.dylib dlopens
    # /System/Library/Frameworks/OpenGL.framework/Versions/Current/Libraries/libGL.dylib
    # directly once DYLD_LIBRARY_PATH=$B/fwlib is removed. A stale Versions/Current
    # directory or stale top-level OpenGL file causes CGLGraphicsConfig to fail and
    # fall back to Metal (IllegalStateException: unable to initialize Metal).
    fw=$out/Frameworks/OpenGL.framework
    rm -rf "$fw/Versions/Current" "$fw/OpenGL" "$fw/Libraries"
    mkdir -p "$fw/Versions/A/Libraries"
    ln -s A "$fw/Versions/Current"
    ln -s ../OpenGL "$fw/Versions/A/Libraries/libGL.dylib"
    ln -s Versions/A/OpenGL "$fw/OpenGL"
    ln -s Versions/Current/Libraries "$fw/Libraries"
    # Cheap host-side layout check
    [ "$(readlink "$fw/Versions/Current")" = "A" ]
    [ "$(readlink "$fw/Versions/A/Libraries/libGL.dylib")" = "../OpenGL" ]
    [ "$(readlink "$fw/OpenGL")" = "Versions/A/OpenGL" ]
    [ "$(readlink "$fw/Libraries")" = "Versions/Current/Libraries" ]
    [ -f "$fw/Versions/Current/Libraries/libGL.dylib" ]
    [ -f "$fw/Libraries/libGL.dylib" ]
  '';
})
