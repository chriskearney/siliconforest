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
  postInstall = (old.postInstall or "") + ''
    mkdir -p $out/Frameworks/OpenGL.framework/Versions/A/Libraries
    ln -s ../OpenGL $out/Frameworks/OpenGL.framework/Versions/A/Libraries/libGL.dylib
    ln -s Versions/Current/Libraries $out/Frameworks/OpenGL.framework/Libraries
  '';
})
