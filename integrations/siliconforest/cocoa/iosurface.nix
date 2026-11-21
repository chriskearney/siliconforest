# SPDX-License-Identifier: MIT
# The system IOSurface (upstream's recipe) with Firefox's GPU transport (CODEX-FX's iosurface-patches 0001-0004 as
# 0230-0233, FXLEAD's lookup fix included) and TERM9's 0151 (libdrm loaded on the first GPU surface, so nothing links
# it): the per-session broker (SFFX_IOSURFACE_SERVICE, iosurfaced --standalone) and dma-buf storage
# (SFFX_IOSURFACE_GPU=1) act only for the processes that set them.
let
  a = import ./arm64.nix;
  drm = (import ../m1-vulkan/common.nix).p.libdrm-dri-arm64;
  src = a.pkgs.runCommand "siliconforest-IOSurface-src-cocoa" { } ''
    mkdir -p tree/src/Frameworks
    cp -r ${a.src}/src/Frameworks/IOSurface tree/src/Frameworks/
    chmod -R u+w tree
    cd tree
    for p in ${./patches/0230-iosurface-private-standalone-broker.patch} ${./patches/0231-iosurface-opt-in-dmabuf-fileport-storage.patch} \
        ${./patches/0232-iosurface-nv12-gpu-planes-and-local-use-count.patch} ${./patches/0233-iosurface-lookup-never-revives-a-finalizing-surface.patch} \
        ${./patches/0151-iosurface-libdrm-loaded-on-first-gpu-surface.patch} ${./patches/0234-iosurface-create-property-gpu-storage.patch}; do
      patch -p1 --no-backup-if-mismatch < $p
    done
    cp -r src/Frameworks/IOSurface $out
  '';
in (a.iosurface.override { inherit src; }).overrideAttrs (old: {
  buildPhase = builtins.replaceStrings [ "-Wall" ] [ "-Wall -I${drm}/include -I${drm}/include/libdrm" ] old.buildPhase;
})
