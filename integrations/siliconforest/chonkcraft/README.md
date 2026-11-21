# ChonkCraft on SiliconForest

The published macOS arm64 build of ChonkCraft (`ChonkCraft-0.1.1-beta22-macos-arm64.dmg`,
its own trimmed JetBrains Runtime 25) on the M1 under SiliconForest 26.5, without
changing the DMG's files in place or anything under `/System`.

Status (20 November 2026): the skirmish runs and draws in a normal window on the desk
(ALAMO.PUD, 64 units, 6 AI players, audio), and so does the opening cinematic of the
title sequence. The dock has a ChonkCraft icon that starts it. Still to do: system
fonts for Java (Swing text and the Swing launcher), see below.

## Pieces

| file | what |
| --- | --- |
| `stage.sh` | `ROOT=<copy of the M1's /System and /usr/lib> stage.sh ChonkCraft.app OUT`: the staged copy (below) |
| `fills.py` | builds `runtime/.../lib/sffill/{AppKit,ApplicationServices,CoreFoundation,CoreGraphics,IOKit}.dylib`: each re-exports the real framework and adds what `libawt_lwawt` imports and SiliconForest lacks (functions, NSString constants, and ObjC methods added at load) |
| `patch_loads.py` | points `libawt_lwawt.dylib`'s framework loads at `@loader_path/sffill/X.dylib` (only this runtime sees the fills) |
| `frameworks/` | JavaRuntimeSupport (fonts through CoreText, `JRSAppKitAWT`, JRSUI stubs), CoreMIDI (no endpoints), ExceptionHandling (empty), for `DYLD_FRAMEWORK_PATH` |
| `missing_symbols.py` | lists the imports of given images that the SiliconForest images do not export (follows re-exports) |
| `run-m1.sh` | test runner on the M1 (`launcher|game|probe SECS [java options]`), captures the desk with `chonkstep-darwin-desktop --screencapture` |
| `probe/AwtProbe.java` | a 640x400 Swing window of colour bars, for the Java2D path alone |
| `../desktop/system/sf-open-chonkcraft`, `../desktop/system/applications/net.chonkbase.chonkcraft.desktop` | the dock's launcher |

On the M1 the staged copy is `/private/var/db/sfchonkcraft` (`ChonkCraft.app`, `fw/`, `fwlib/`,
`data/packs/` with the asset pack, which is never committed).

## How a frame reaches the window

Java2D runs on its OpenGL pipeline (`SEVEN_JAVA2D_PIPELINE=opengl`: CGL on Mesa; there is no
Metal device). Java draws into `CGLLayer`, a `CAOpenGLLayer` that is the `AWTView`'s layer.
SiliconForest's QuartzCore composites such a layer through the layer renderer, which drew
this one at a 0x0 box (no texture), so the runtime uses AppKit's layer path without OpenGL
instead (`SFLayerRendering=0`) and `SF_CHONK_CPU_LAYER=1` makes the fill render the layer on
each `-setNeedsDisplay`: its own CGL context shared with Java2D's, Java's
`drawInCGLContext:`, a read back, the picture as the layer's contents. AppKit draws that
into the window. The log line `CAOpenGLLayer ...: no OpenGL (libEGL) on this system: the
layer is not drawn` is QuartzCore saying it will not draw the layer itself in that mode;
the fill does.

By default `sf-open-chonkcraft` shows Java's frames as GPU buffers instead
(`SF_CHONK_GPU_PRESENT=1`, the default; `SF_CHONK_GPU_PRESENT=0` forces the CPU layer path): the launcher runs the game under a private `iosurfaced`
(`$B/bin/surface-session`, the one Firefox's launcher uses, broker
`org.siliconforest.iosurfaced.sffx.chonkcraft.<pid>`) with `SFFX_GPU_PRESENT=1` and
`SFFX_IOSURFACE_GPU=1`. On each `-setNeedsDisplay` the fill has Java draw as before, copies
the framebuffer to a texture (`glCopyTexSubImage2D`) and draws it with a textured quad
(bilinear, top row first, alpha 1) into one of three window-pixel-size dma-buf IOSurfaces
(`CGLTexImageIOSurface2D`), `glFinish`es, registers it at 1:1 with
`_windowServerSFFXSetGPULayer` and presents with `_windowServerSFFXPresentLayers`. Any
failure falls back to the CPU layer path and logs why (`SF_CHONK GPU ...`); when the private
broker cannot start, the launcher runs the CPU path. `SF_CHONK_GPU_PRESENT=verify` renders
the buffers but keeps presenting through the CPU path and dumps frames 90 and 400 to
`$TMPDIR/gpu-verify-*.bgra` (the buffer through GL and through its CPU mapping, the source,
QuartzCore's `CGLSFFXCopyFramebuffer`). The CPU mapping is what WindowServer shows; a
`glReadPixels` of the IOSurface's own FBO comes back shifted by the 16384-byte dma-buf offset
on this Mesa, which is a read-back artifact only.

## Window size

AWT makes each window with the maximum size Java has not set yet, 0x0
(`-[AWTWindow setPropertiesForStyleBits:mask:]`), and SiliconForest's `-[NSWindow
setFrame:display:animate:tellWS:]` held every frame to it, so the game's window became 0x0
and its content 0x-22. `../cocoa/patches/0370` fixes it in AppKit for every application (a
maximum of zero on an axis is none, as macOS does not hold `-setFrame:` to it); it is in
`patched.nix` and builds, but is not installed (the installed AppKit is another build: it
goes in with the next guarded AppKit install). Until then the fill stores a zero maximum
as none, for this runtime only.

## Diagnostics

`SF_CHONK_TRACE=1` (layer render/draw counts and bounds, window frames, a backtrace when the
theme frame goes to 0x0), `SF_CHONK_KEEP_ZERO_MAX=1` (the old behaviour),
`SF_CHONK_TIMING=1` (`SF_CHONK FRAME`/`SF_CHONK STAT` lines: requests, main-thread CPU, fill time, GPU/CPU frames),
`J2D_TRACE_LEVEL=4`, `SF_CAOGL_TRACE=1`, `SF_CA_TRACE=1`, and `kill -3` for a Java thread dump.

## Not yet

- System fonts: `findFont2D` finds nothing for Java's logical fonts (macOS maps them to
  Lucida Grande), so Swing text throws; the Swing launcher (`launcher.Main`) stops there and
  the dock starts the game (`desktop.Main`) directly. The game draws with its own fonts.
- Aqua look and feel: needs JRSUI; Swing runs with Metal.
- The dock shows no running mark for the window (its app id is the java process's).
