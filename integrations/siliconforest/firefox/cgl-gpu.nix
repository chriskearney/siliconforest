# SPDX-License-Identifier: MIT
# GPU IOSurface bridge; private prefix by default, explicit canonical packaging.
{prefix ? "/private/var/db/sffx/gl-gpu-v3", canonical ? false, nv12Backing ? false,
 contextLocalFBO ? false, imageCache ? false, frameIdentity ? false,
 nv12GPUCopy ? false, nv12BatchCopy ? false,
 # (VLC) a thread asking for a context another thread has current waits for it, bounded (cgl-patches/0009)
 contextHandoff ? false}:
assert !nv12GPUCopy || nv12Backing;
assert !nv12BatchCopy || nv12GPUCopy;
let base=import ./cgl.nix {inherit prefix canonical;};
in base.overrideAttrs(old:{patches=old.patches++[./cgl-patches/0002-gpu-iosurface-alias-and-rectangle-blit.patch ./cgl-patches/0003-export-framebuffer-and-import-layer-gpu-storage.patch ./cgl-patches/0004-opt-in-export-framebuffer-resource-cache.patch]++
 (if nv12Backing then [./cgl-patches/0005-nv12-rectangle-gpu-planes-and-completion-lease.patch] else [])++
 (if contextLocalFBO then [./cgl-patches/0006-framebuffer-tracking-is-context-local.patch] else [])++
 (if imageCache then [./perf/patches/0303-cgl-rectangle-export-and-image-per-surface.patch
                     ./cgl-patches/0007-bound-iosurface-image-cache-and-snapshot-lock.patch] else [])++
 (if frameIdentity then [./cgl-patches/0008-private-exported-video-frame-identity.patch] else [])++
 (if contextHandoff then [./cgl-patches/0009-make-current-waits-for-another-threads-context.patch] else []);
}//(if frameIdentity || nv12GPUCopy then {postPatch=(old.postPatch or "")+
 (if frameIdentity then ''
   cp ${./frame-id-export.h} src/Frameworks/OpenGL/sffx-frame-id-export.h
   cp ${../finch/firefox-media/frame-id-decode.h} src/Frameworks/OpenGL/sffx-frame-id-decode.h
 '' else "")+
 (if nv12GPUCopy then ''
   cp ${if nv12BatchCopy then ../finch/firefox-media/strict-nv12-batched-plane.h else ../finch/firefox-media/strict-nv12-plane.h} src/Frameworks/OpenGL/sffx-strict-nv12-plane.h
   cat >> src/Frameworks/OpenGL/CGL.c <<'SF_NV12_COPY'
   #include "sffx-strict-nv12-plane.h"
   SF_NV12_COPY
 '' else ""); } else {}))
