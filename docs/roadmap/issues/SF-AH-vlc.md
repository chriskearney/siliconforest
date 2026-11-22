# SF-AH: VLC media player

Goal: the official VLC media player for macOS (arm64), unmodified, starts from a launcher of its
own on SiliconForest, opens a file and plays video with sound in its own window, with working
transport controls, on the M1.

Status on 18 November 2026, 10:50Z (see items 21 and 22 and the cycles below for what changed since 08:25Z): **it plays, driven through its own interface, with hardware
decoding, from a private prefix.** `/Applications/VLC.app` starts the unmodified VLC through the launcher; File >
Open File opens a movie; play, pause, resume, seeking on the timeline, fullscreen and back, resizing the
window, playing to the end and Quit (menu and Command-Q, no process left) were each seen working on the M1
with synthetic input on the compositor's virtual seat. The picture is rendered at the panel's own pixel
size (35.0 dB against ffmpeg's decode of the same frame, from 27.7 dB when it was rendered at scale 1 and
enlarged). H.264 is decoded by the M1's video decoder through VideoToolbox (decoder jobs rise at the frame
rate while it plays and stop when it is paused). Sound: heard by the owner on 18 November; the speakers
were muted in coreaudiod from 08:13Z. Not done yet: the 12 launch-play-quit cycles, CPU and dropped-frame
numbers, `--vout=macosx`, VideoToolbox's IOSurface path to OpenGL (green picture), any system install of the
framework changes.

## The program

| | |
|---|---|
| Release | VLC 3.0.24 for macOS, arm64 (`vlc-3.0.24-arm64.dmg`) |
| Source | `https://get.videolan.org/vlc/3.0.24/macosx/vlc-3.0.24-arm64.dmg` (the current 3.0 release on 17 November 2026) |
| SHA-256 | `64a89d93cdd30b0e97131743e246373db82d6826ea882d265d46d74b136da2b7`, equal to VideoLAN's published `.sha256` |
| Licence | GPL-2.0-or-later; the libraries it carries keep their own |

The disk image and the unpacked bundle are kept outside the repository. Nothing in the bundle is
changed, re-signed or replaced on disk; the launcher (below) says what it does around it.

## What stood in the way, and what was done

Found offline first with `homebrew/sf_gapscan.py` (VLC, its two libraries, 345 plug-ins and the
three frameworks it carries, against a copy of the M1's system libraries), then in the order the
program met them on the M1.

| # | Gap | Kind | What was done | State |
|---|---|---|---|---|
| 1 | `sys_errlist`, `sys_nerr` (libvlccore); `exc_server`, `exception_raise`, `bootstrap_subset`, `bootstrap_create_server`, `bootstrap_create_service` (the Breakpad framework VLC links) | symbols missing from libSystem; dyld refused to start the program | All seven are built from this tree's own sources (libc `gen/errlst.c`, libsystem_kernel `exc.defs`, libxpc `libbootstrap.c`): added to the export list, and the generated exception server is now compiled in. `libsystem-default/patches/legacy-mach-and-errno-exports.patch`, recipe `build-libsystem-legacy-exports.nix`. 2679 exports before, 2686 after, none lost | candidate, used from a private directory; **not installed** (a core file: QEMU rehearsal and the guarded installer first) |
| 2 | VLC refuses to run as root; the desktop session is root's | policy of the program | The launcher gives up root for the account `sf` (as `brew` does), after connecting to the compositor's socket (root's alone) and passing the descriptor on as `WAYLAND_SOCKET` | works |
| 3 | `NSGregorianCalendar` (interface plug-in, Growl) | symbol missing from CoreFoundation | added to the CoreFoundation wrapper (`terminal-app/compat/CoreFoundation.m`) | candidate, private |
| 4 | `NSAppleScript` | class missing from Foundation | added to the Foundation wrapper (`terminal-app/compat/Foundation.m`): keeps its source text; compiling or running returns an error dictionary (-1753), nothing is executed | candidate, private |
| 5 | `FSGetCatalogInfo`, `FSGetVolumeParms`, `LSCopyAllHandlersForURLScheme` | symbols missing from CoreServices | `macos-compat/patches/coreservices-catalog-info-and-url-handlers.patch`: real `stat`/`statfs` data and the registered applications' URL schemes; metadata this system does not have is refused | candidate, private |
| 6 | AddressBook, ScriptingBridge, WebKit | frameworks missing; the interface plug-in links them | providers that say the feature is absent (`finch/players/compat/unavailable.m`): no contacts, no Apple Events, no web engine; every factory returns nil or an error | private |
| 7 | MediaPlayer (weak) | framework missing; VLC then read a null constant and crashed (`EXC_BAD_ACCESS` in the interface plug-in, when playback starts) | `finch/MediaPlayer`: Now Playing information and remote commands kept locally; there is no system Now Playing service and no command is ever delivered | private |
| 8 | Sparkle (VLC's own copy) needs libxar, WebKit, `NSURLDownload`, Security transforms | VLC's updater cannot load | **replaced at load time** by a provider with the same interface that reports "no updates available/unavailable" (`finch/players/compat/unavailable.m`); the copy in the bundle is untouched | private; agreed by the owner's coordinator on 18 November |
| 9 | Two OpenGL libraries in one process: the system's CGL uses the GPU Mesa, while AppKit, QuartzCore and CoreVideo name the older `/usr/lib/libGL.1.dylib`; VLC's shader calls landed in the library without a context | system inconsistency | the launcher puts the GPU Mesa's directories first on the library path, as the Firefox launcher does | works around; the system fix is one libGL for the system's frameworks and its CGL |
| 10 | The picture, VLC's default output (`caopengllayer`): the window stayed black, then showed only the first frame | two faults in QuartzCore | `cocoa/patches/0320`: an opaque `CAOpenGLLayer`'s picture is taken without its alpha (VLC draws its video with alpha 0 into an opaque layer). `0321`: a layer context gives its root layer the pointer back that AppKit's re-parenting of the view had cleared, so new contents ask for a frame again | candidate, private; **the picture works** |
| 11 | The picture, second output (`--vout=macosx`, NSOpenGLView): starts, then `CGLSetCurrentContext` fails (10004) when the video thread takes the context; then VLC aborted (`-reshape` off the main thread) | **fixed, opt-in**: `cocoa/patches/0327` (a frame flushed from another thread is drawn into its view on the main thread; `-reshape` runs on the main thread and at once when the frame changes; a best-resolution view's drawable is sized in pixels) and 0009's lending (`SF_CGL_LEND=1`: a context's binding follows its `CGLLockContext` between threads). With both, VLC's NSOpenGLView output shows the whole picture, sharp, with menus and controls; without lending its video thread still waits out 250 ms per frame. Lending is off by default: in one 12-drag run of the default output it coincided with 1 failure (since fixed: a context is reserved before it is bound) | Earlier note: `EGL_BAD_ACCESS`, the NSOpenGLContext stays current on the main thread, so the 250 ms wait of 0009 ends without it; then VLC asserts that `-[VLCOpenGLVideoView reshape]` runs on the main thread, which ours does not. Earlier note: VLC makes a context current on its own thread and locks it with `CGLLockContext`; our CGL sits on EGL, where a context is current on one thread at a time | open; not needed for the default output | **open** |
| 12 | Hardware decoding: `/dev/sfavd` is root's alone, so VideoToolbox's hardware decoder refuses the account `sf` ("Cannot open the AVD device: Permission denied") and VLC decodes in software | device permission | interim in the launcher, off by default and **not yet tried**: while still root it gives the node group staff and mode 0660 (lasts until reboot). The proper fix is a kernel item: see below | open |
| 15 | AppKit: `-[NSMenuItem parentItem]` missing; every VLC menu ended in an exception before it opened | missing method | `cocoa/patches/0322` | candidate, private; menus work |
| 16 | Foundation: `-performSelectorOnMainThread:withObject:waitUntilDone:NO` on the main thread ran the message at once. VLC's playlist adds an item while it holds its lock and sends itself the update this way; the update took the same lock and the interface stopped (its Open dialog never started a file; sampled: main thread waiting on the playlist mutex) | semantics differ from macOS, which queues it | `terminal-app/patches/foundation-main-thread-perform-is-queued.patch`: queued on the main run loop as on macOS | candidate, private (a core library: the QEMU rehearsal and the guarded installer before any system install; it changes when other programs' main-thread messages run) |
| 17 | The picture at scale 1: VLC's video layer kept `contentsScale` 1, so VLC rendered 1708x960 and the panel showed it enlarged 1.5x | AppKit gave custom backing layers no scale | `cocoa/patches/0323`: a layer made by the view's `-makeBackingLayer` follows the window's `backingScaleFactor`; a delegate answering `-layer:shouldInheritContentsScale:fromWindow:` decides | candidate, private; works |
| 18 | VLC sizes its window to the video in pixels (larger than the screen) and clamps to `NSScreen visibleFrame`, which here is the whole panel; the desktop gave the window less and AppKit laid it out for the size asked: the picture was cut on the right and the controls bar was below the visible area | AppKit/desktop | `cocoa/patches/0324`: when the desktop answers an application's larger request with a smaller size, the window keeps to that size until the desktop configures a larger one. The proper fix is the desktop telling clients its work area (`xdg_toplevel.configure_bounds`) and `visibleFrame` following it: a request for the desktop's owners | candidate, private; works |
| 19 | Fullscreen: VLC ended at its fullscreen button (`-[NSAnimation startWhenAnimation:reachesProgress:]` raised "not implemented"), and after that was fixed the main window stayed empty after leaving fullscreen (NSAnimation's `currentValue` stayed 0; VLC finishes its transition when it reaches 1) | missing AppKit behaviour | `cocoa/patches/0325`: linked animations, and the current value follows the progress through the curve or the delegate | candidate, private; fullscreen in and out works (the desktop's docks stay drawn over it) |
| 20 | Hardware decoding: `/dev/sfavd` root's alone; then VideoToolbox's pictures reached OpenGL green (VLC's IOSurface converter, `glconv_cvpx`) | permission; IOSurface texture path | the launcher (still root) gives the node group staff, mode 0660, until reboot (`"hardware_decode": true`); `--glconv=none` in the release's arguments makes VLC copy the decoded pictures to its textures itself (`cvpx` converter) | works with the copy; the IOSurface path is open; the proper device permission is a kernel item |
| 21 | Resizing the playing window by its corner (DEMO's film take, 18 November): black frames for about 67 ms and VLC's log "Failure setting current CGLContext: invalid context"; in the repeat, "Failure restoring previous CGLContext" and VLC aborted | **cause established** with a traced CGL (`SF_CGL_TRACE=1`), 12-drag sessions of DEMO's drag (40 moves 50 ms apart, 1280x813 <-> 1520x948, hardware decoding): every failed make-current was `EGL_BAD_ACCESS` (0x3002), 16 of 19 with the context still current on another thread when traced (the other 3 had just been let go). CGL lets a context be made current on one thread while another still has it (the application orders its use with CGLLockContext); EGL refuses it. VLC makes its context current on its video thread while the layer draws with it on another; the frame was not prepared or not drawn, and the layer read back from no context: a black frame | `firefox/cgl-patches/0009` (`cgl-gpu.nix --arg contextHandoff true`): a thread asking for a context another thread has current waits for it to be let go, at most 250 ms (`SF_CGL_HANDOFF_MS`). `cocoa/patches/0326`: CAOpenGLLayer makes the context current before locking it (VLC's order, so neither side waits holding what the other needs) and keeps its last picture when the context cannot be made current | private, works: before, installed CGL: 9 failures in 3 drags, then VLC aborted; traced CGL with the wait off: 19 failures in 10 drags, then VLC aborted; with both fixes: 0 failures, 0 black mid-drag captures, no abort in 2 x 12 drags; waits 0.5-10.6 ms. The one frame DEMO saw with the picture over the whole window was not seen in my captures: not shown fixed |
| 22 | DEMO's second take: during the corner drag, 26 of 1366 recorded frames showed VLC's picture over the whole window, without menu strip or control bar | **AppKit, established from the compositor's own recording** (`dragrec.py`, the compositor's `--screencapture` recorder, 8 drags): 301 of 1741 frames without the menu strip; in them the window's content is transparent (the desktop and the Terminal behind show through) except VLC's picture. A resize gives the window a new, empty backing store; the next layers-only frame (VLC's video layer has a new picture 30 times a second) drew the layer into that store and flushed it before the window's views were drawn | `cocoa/patches/0328`: the first layers-only frame after a window was resized draws the window whole instead | private, works: 0 of 1742 frames (8 drags) and 0 of 2521 frames (12 drags) without the menu strip |
| 23 | DEMO's third take (18 November, 11:00Z): 5 consecutive recorded frames mid-drag with VLC's picture area entirely black, the menu strip and control bar drawn (lending off, private set of 10:55Z); my earlier recording `rC2` had one such episode of 8 frames, which the menu-strip check did not count | **VLC's own threading meets our read-back, established with a per-render trace** (`dragtrace.py`: the compositor's recording, each frame's picture area tested for black, beside every render of the layer, `SF_CAOGL_TRACE=2`): in run `rD1` (12 drags) one render on the main thread right after a resize step read back luma 0, the next render on the video thread 4 ms later luma 233; the recording shows black frames at that moment. VLC's caopengllayer output keeps "the context current before" in one field shared by all its threads: when its video thread asks for the context while the main thread draws a resize frame, the main thread's draw ends by making no context current, and the layer read its picture back from no context | `cocoa/patches/0329`: CAOpenGLLayer reads its picture back only from its own context; where the application's drawing left another context current, or none, the layer keeps its last picture (`SF_CAOGL_TRACE=1` says when; `=2` logs every render) | private, works: `rD2` 0 black frames (2 renders kept), `rD3` 0 (10 kept), with lending `rL1` 0 (4 kept), all 12 drags, 0 frames without the strip, 0 CGL failures |
| 24 | Re-qualifying lending (`SF_CGL_LEND=1`) with the reservation fix, `--vout=macosx` (NSOpenGLView): 0 CGL failures, but 46 black-picture episodes (186 of 2525 frames) in 12 drags (`rM1`), one at nearly every resize step | AppKit: our NSOpenGLView has no GL surface of its own; its frames are read back at each flush and drawn into the window. After a resize the window's backing store is new: the view's region stayed empty until the next frame arrived, and a frame drawn into the view alone and flushed before the window was drawn showed the window without its menus and controls | candidate `cocoa/patches/0330` (not committed): the view shows its last flushed frame whenever the window draws it, at its own size from the top left, and after a resize a frame waits for the window's display instead of being flushed alone | candidate draws cleanly: `rM9` (M1 healthy, 1456 recorded frames) 0 black, 0 without the strip, 0 CGL failures; earlier `rM7` likewise but with a stuck process's window on screen. **Not qualified further: this output with lending is suspended on the M1 (item 25).** Also: under this output VLC's main thread is about 90 % busy drawing each frame in software (Onyx2D point sampling): a GPU path for NSOpenGLView would be the real fix |
| 25 | **A VLC process stuck in exit (kernel or driver item).** Run `rM3` (11:35Z, NSOpenGLView output, `SF_CGL_LEND=1`, 12 corner drags, the compositor recording): the harness sent TERM and, 5 s later, KILL. The process stayed in state `?E` with no threads for 70 minutes and kept its Wayland connection, so its dead window stayed on screen with keyboard focus. Signals cannot remove it. The restart to clear it **hung in shutdown and needed an external reset** (the root then held only the reset's orphan list) | not established. While it was stuck, `kern.sf_dri` clone_slots showed `used=4`; it is 3 with no VLC running, so the process still held its DRM descriptor. `sf_avd` contexts 0, speakers idle. **Suspect 1:** closing the DRM descriptor or tearing down its GPU context never completes after the KILL interrupted a GPU submission or wait (an `agx-bo-cache` thread is alive during teardown). **Suspect 2 (ruled out by the second case):** the diagnostic wrapper `sf-catch` holding VLC's exception ports. Why KILL lands mid-teardown: with the NSOpenGLView output, VLC's main thread spends about 90 % of its time drawing each flushed frame into the window in software (Onyx2D point sampling under `sfDrawFrameInView`, `sample`: 1105 of 1252), so VLC needs 5-6 s to act on TERM | harness: 15 s before KILL (`vlc_m1.py stop`), `SFVLC_NOCATCH=1` for drag runs; **the NSOpenGLView output with lending is not run on the M1 until the kernel item is fixed** (each case cost an external reset). The kernel side is open (no kernel built here); the tools on the M1 give user stacks only (`sample`), and `lsof` lists mapped images, not descriptors | not reproduced in 3 tries after the reboot without drags (the inject instrument was not running): TERM only, gone after 6.2 s; TERM then KILL at 5.1 s, gone at 5.6 s; the harness's stop, gone. **Reproduced by the next drag run with this output**: `rM9` (12:53Z, NSOpenGLView output, lending, AppKit candidate 0330, 12 drags, recording clean), stuck in `?Es` from 12:54:47Z, the moment its audio session closed normally (`SFSpeakers: stopped (end of data)`). That run had **no** `sf-catch` wrapper (parent launchd), which rules out suspect 2. It held a DRM clone slot again (`used=4`), and `sample` could not attach (task_for_pid fails). Both cases: NSOpenGLView output with lending, after corner drags; none in dozens of default-output runs. Records `runs/vlc/exit-x2.txt`, `exit-x3.txt`, `exit-rM9-stuck.txt` (not in git). **Third case, on the default output with the new IOSurface/GPU path (IOSURF, `d1`)**: VLC started 15:48:47Z (pid 39503, account sf, release launcher with `SFVLC_WRAP=/private/var/db/sfvlc/iosurf/wrap`, `--glconv=any`, no `sf-catch`, no lending: `SF_CGL_LEND` unset; CGL 0009 v3 76585563 from the prefix). That path: VideoToolbox gives VLC IOSurface-backed NV12 pictures, the cvpx GL converter binds them with `CGLTexImageIOSurface2D`; `SFFX_IOSURFACE_GPU=1` gives every IOSurface of the process GPU (dma-buf) storage; QuartzCore 0331 copies CAOpenGLLayer's picture on the GPU into one of two GPU IOSurfaces (re-made at every new size) that the layer renderer binds as EGLImages; `SFFX_GPU_PRESENT=1` with the render thread hands each window frame to the desktop as a dma-buf (`FXWSPRESENT ... transport=dmabuf`). The run: 12 corner drags (1280x813 <-> 1520x948, 40 moves 50 ms apart, so many surface re-creations), the desk's recorder 42 s, recording clean (2521 frames, 0 black, 0 without the menu strip; VLC 2264 shown, 1 lost); then SIGTERM only (no KILL) at about 15:50:07Z. Its audio session closed normally at about 15:50:13Z (`SFSpeakers: stopped (end of data)`, dmesg 10270.97 s); from then on `?Es`, ppid 1, CPU time 0, still so at 16:24Z; `kern.sf_dri` clone_slots `used=4` again (it held its DRM descriptor). The same new path quit cleanly in every run without drags: TERM after playback in p4, p4r, p5, c2, c3, f1 (f1 with full screen in and out), and Quit from VLC's menu in k2 and k3 (VLC gone 1.2 s after the menu item). So all three cases: corner drags (many GPU surface/buffer re-allocations at changing sizes), then the end of the process; NSOpenGLView/lending is not required. Not tried yet: drags on the new path ending with a menu Quit instead of TERM |
| 13 | Button pictures (`VLCPlayTemplate`, ...) not found; subtitle font `HelveticaNeue.dfont` absent | AppKit named-image lookup in the bundle; font | open | open |
| 14 | DiskArbitration (Blu-ray plug-in), Growl's Carbon and Secure Transport calls, `SecTrustGetResult` and others in the TLS plug-in | not on the path to playing a local file | not done; those plug-ins fail to load and VLC goes on without them | listed |

## The launcher

`finch/players/vlc/vlc-sf` (Python, as the Firefox launcher):

1. as root, connects to the compositor's Wayland socket and keeps the descriptor (`WAYLAND_SOCKET`);
2. becomes the account `sf` (uid 501, group staff, `HOME=/Users/sf`);
3. puts this release's private libraries first: `DYLD_LIBRARY_PATH` = the directory with the
   libSystem candidate and the two re-exported libraries `CoreServices.pd` and `QuartzCore.pd`,
   and the two GPU Mesa directories; `DYLD_FRAMEWORK_PATH` = the private frameworks of rows 3 to
   8. VLC's own Sparkle updater is among those replaced: the launcher loads a provider that says
   updates are unavailable, so VLC on SiliconForest does not update itself;
4. executes the vendor's `Contents/MacOS/VLC` with the arguments it was given.

No interposing library is inserted and no VLC option is forced.

## Observed on the M1 (18 November 2026, kernel 50)

All runs: the vendor binary (SHA-256 of `Contents/MacOS/VLC`
`26a122e5b2e3b3ac31634cbfd671d7c9c4648ba0618931e75424289a9c9b42b2`, equal on the workstation and
on the M1 before its first run), started by the launcher from the private prefix, the owner idle,
**no synthetic input** (the compositor that was running has no test instrument), captures by the
compositor's own `--screencapture`. Each pass ended its own VLC with SIGTERM.

- `VLC --version` prints 3.0.24; all plug-ins but the Blu-ray one load (459 modules).
- Without a file: the interface loads; the controls window and VLC's first-run question ("Check
  for album art and metadata?") are on the screen.
- 1080p30 H.264 High + AAC in MP4 (30 s of Big Buck Bunny): VLC's libavcodec (six threads) and
  faad; the video window opens with the clip's title and VLC's menus; the picture moves.
- **Frame comparison** (`finch/players/vlc` test `t3`): two captures while playing, about 7 s
  apart. Each was matched against all 900 frames of ffmpeg's decode of the same file; the best
  matches were frames 190 (6.33 s) and 402 (13.40 s), 7.07 s apart, as the captures were. PSNR
  against ffmpeg's frame scaled to the picture's size on screen: 27.6 and 27.7 dB (28.4 dB when
  ffmpeg's frame goes through the same two scalings); mean colour error at most 2.7 of 255 per
  channel; the neighbouring frames score lower and the frame before a cut scores 10 dB. Side by
  side the two pictures look the same. The picture is rendered at 1708x960 and scaled by 1.5 to
  the panel (the layer is drawn at scale 1 on a 150 % desktop), which is what limits the PSNR:
  sharpness at the panel's own resolution is open.
- VP9 + Opus in WebM: plays; best matches frames 185 and 397.
- Sound: the audio output opens the default device ("analog output successfully opened"); the
  audio server's log for those clients: 789,504 frames in 21.4 s and 764,928 in 20.9 s, 0
  underruns. Nobody listened; lip sync has not been judged.
- SIGTERM ends the program cleanly while it plays (no process left). With only the first-run
  question on the screen it did not end within 5 s and was killed.
- One sample of `ps` during VP9 playback showed 129 % of one core for VLC; not a measurement.

Not yet done: everything that needs input (pause, resume, seek, fullscreen, quit from the menu,
the first-run question answered), play to the end, the 12 cycles, CPU and dropped frames, the
Firefox/Terminal/Activity Monitor regression set (nothing in the system has been changed),
`/Applications/VLC.app` and the dock.

## How the picture gets to the window

VLC's `caopengllayer` output gives its view a backing layer of its own class (a `CAOpenGLLayer`)
and calls `-display` on it from its video thread for every picture. Our `CAOpenGLLayer` makes
VLC's own CGL context current, lets VLC draw into the context's offscreen surface, reads the
pixels back and sets them as the layer's contents; the view's layer context then renders the
tree and AppKit puts it into the window. That is a copy through the CPU per frame. A path without
the copy (the layer's surface handed to the window server, as Firefox's layers are) is the next
step for speed.

## For later: the decoder device (kernel item, not built)

`/dev/sfavd` is created by the decoder driver as root:wheel 0600. A player that does not run as
root cannot open it. Proper fixes, either of: the driver creates the node with an owner and mode
meant for it (group `staff` or a `video` group, 0660), as it does for `/dev/sfaudio` (0666); or a
small root broker opens the device and passes the descriptor. Until then the launcher can change
the node while it is still root (off by default; it does not survive a reboot).

## Recipes and the installed files

This branch changes sources of files the system has installed. Until they are installed, the
recipes' outputs differ from the machine's files:

| File | Installed (SHA-256) | This branch's recipe |
|---|---|---|
| `CoreFoundation.framework/Versions/A/CoreFoundation` (wrapper) | `6f280f666d1f…` | `8ce243b9bd97…` |
| `Foundation.framework/Versions/C/Foundation` (wrapper) | `a660d7509392…` | `48d077840a4c…` |
| `CoreServices.framework/Versions/A/CoreServices.pd` | `04b372fef7d3…` | `b0ee9dbe9304…` |
| `QuartzCore.framework/Versions/A/QuartzCore.pd` | `af3667bff448…` | `2d1b6c3485c2…` |
| `/usr/lib/libSystem.B.dylib` | `f32061c60173…` | unchanged by default; the candidate recipe gives `8230d18f9fa9…` |

Before this branch the recipes reproduced the first three byte for byte.

## Installed

Nothing in the system. On the M1, under `/private/var/db/sfvlc` only (remove the directory to
go back): the vendor bundle, the libSystem candidate
(`8230d18f9fa9ca9c28ddcf978270fbebce877d90ad0a8d0b02b730006f1bdaea`), `QuartzCore.pd`
(`2d1b6c3485c28e4d595377c9baff63922bd4051a873d6d222aaf04eca729e18e`), `CoreServices.pd`, the private frameworks,
the launcher and test tools. VLC's own preferences and caches are in `/Users/sf/Library`.

## Tests

`finch/players/vlc/vlcw.py` (workstation) and `vlc_m1.py` (on the machine): each pass takes the
shared screen lock, waits until the owner has been idle, starts and stops only its own VLC, and
captures through the compositor. Input, where a pass needs it, goes through the compositor's
test instrument on its virtual seat into the test's own window.

Test clip: Big Buck Bunny, (c) Blender Foundation, CC BY 3.0, https://peach.blender.org; cut on
the workstation, never committed.

## Cycles, CPU and dropped frames (18 November)

**12 launch-play-quit cycles, 12 passed** (`finch/players/vlc/cycles.py`). Each cycle, as a person would: `open -a
/Applications/VLC.app` with the 30-second 1080p H.264/AAC clip; after 8 s a window with a moving picture (capture),
the M1's decoder working (456-789 decoder jobs during the cycle), sound to the audio server (each session 826,368 to
1,341,440 frames; 0 underruns in 11 sessions, 1 underrun in one); Command-Q; no VLC process left within 10 s; no
failure, assertion or exception in VLC's log. 20-31 s per cycle. Repeated with the final private set (AppKit with 0327 and
0328, CGL 0009 with the reservation): 12 of 12 again. Again at 13:05Z with QuartzCore 0329 (the committed recipes'
set): 12 of 12, 16-19 s per cycle, 365-408 decoder jobs per cycle; coreaudiod's underruns are now recorded per session
rather than judged: 5 of the speaker sessions closed inside a cycle's window, each with 0 underruns (the server keeps
the device open for a while after the last client leaves, so the other sessions closed between cycles).

**One minute of 1080p30 H.264 with hardware decoding** (`perf.py`, the 3-minute clip, 63.5 s measured after 10 s of
playback, window 2444x1550 panel pixels, nothing else playing): VLC's own counters: 1,898 frames displayed, **0 frames
lost**, 0 audio buffers lost (29.9 frames a second). The decoder: 1,905 jobs, 30.0 a second. CPU, as process time over
the minute: **VLC 128.7 % of one core** (of 8), the compositor 15.9 %, coreaudiod 1.1 %. Repeated with the final private
set: 1,890 frames displayed in 63.2 s, 0 lost in the minute (1 in the 10 s of start-up before it), VLC 128.7 %, the
compositor 15.6 %, coreaudiod 1.0 %, the decoder 30.0 jobs a second. Most of VLC's share is the
two copies per frame (the decoded picture into textures; the drawn frame read back for the window). Not measured:
the panel's own frame timing, lip sync.

## Proposal: installing VLC's changes system-wide (steps 1-6 DONE on 18 November; see "System install record" below)

Today everything VLC needs beyond the system lives in `/private/var/db/sfvlc` and reaches VLC through its launcher's
`DYLD_LIBRARY_PATH` and `DYLD_FRAMEWORK_PATH`. A system install moves each piece into the system in its own step, each
with the previous file kept beside it as `<file>.pre-vlc`, one restore script (`sf_vlc_restore.sh`, tried first in QEMU,
then on the M1), and the lifecycle set after every step. After the last step the launcher keeps only what cannot be
system-wide: becoming the account `sf`, the stand-in for VLC's own Sparkle (it must win over the copy inside VLC's
bundle, which only `DYLD_FRAMEWORK_PATH` can do), and the interim decoder permission.

**The lifecycle set** (after every step, on the M1, owner idle, synthetic input on the virtual seat):
Firefox starts, loads a page, plays a video with sound, opens and closes a second window, quits with no process left;
Terminal opens two tabs, types, quits; Activity Monitor opens, switches tabs, quits; the four themes apply; VLC plays
the 3-minute clip with hardware decoding, is resized by its corner (12 drags, as in item 21), goes fullscreen and back,
quits; QuickTime Player's current state is unchanged (QTP's own check). Each step also compares the exports of each
replaced library with the file before (a superset, or every removal explained).

| Step | Files | Built by | What else it touches | Gate |
|---|---|---|---|---|
| 1 | new `AddressBook`, `ScriptingBridge`, `WebKit`, `MediaPlayer` frameworks in `/System/Library/Frameworks` | `finch/players/compat/frameworks-system-foundation.nix` (only those three), `finch/MediaPlayer/build.nix` | anything that weak-links them: a scan of every installed program first (`sf_gapscan.py --system`) | lifecycle set |
| 2 | CoreFoundation and Foundation (`Versions/C`) wrappers; `CoreServices.pd` | `terminal-app/build-compat.nix`, `macos-compat/build-coreservices.nix` | additions only (`NSGregorianCalendar`, `NSAppleScript`, `FSGetCatalogInfo`, `FSGetVolumeParms`, `LSCopyAllHandlersForURLScheme`): export audit | lifecycle set |
| 3 | `QuartzCore.pd` with 0320, 0321, 0326, 0329 | `cocoa/patched.nix -A quartzcore` | 0320, 0326 and 0329 change only CAOpenGLLayer; **0321 changes `-[CALayerContext setLayer:]` for every layer tree, Firefox's included** | lifecycle set, plus Firefox scrolling and video presentation checks of its own stream |
| 4 | `AppKit` with 0322-0328 | `cocoa/patched.nix -A appkit` | 0322 adds a method; **0323 changes the scale of custom backing layers (Firefox has some)**; **0324 changes programmatic window resizes for every app**; 0325 changes NSAnimation (Terminal and Activity Monitor panels); 0327 changes NSOpenGLView/NSOpenGLContext only; **0328 draws a window whole on its first layers-only frame after a resize (every application with layers, Firefox included)** | lifecycle set, plus Firefox at 150 % checked for sharpness and window geometry |
| 5 | `/usr/lib/libFoundation.dylib` with the main-thread perform change (a core file) | `terminal-app/build-foundation-networking.nix` | **every Cocoa program: a main-thread `performSelectorOnMainThread:…waitUntilDone:NO` now runs later, not at once** | QEMU rehearsal and fresh boot (`sf_terminal.sh install-stage`, `qemu NAME`, `qemu NAME second`: compat check `failed=0`, `QDDESK_PASS`, `sf-kvo-probe`), then the guarded installer (`sf_terminal.sh install core`, `macos-compat/sf-lib-install.sh`), then the lifecycle set and an hour of Firefox use |
| 6 | `/usr/lib/libSystem.B.dylib` with the seven exports (a core file) | `libsystem-default/build-libsystem-legacy-exports.nix` (the optimised default plus one export patch; dyld unchanged) | exports only: the image's code is the default's | as step 5 |
| 7 | CGL with `contextHandoff` (0009): `OpenGL.framework` and `libGL.1.dylib` | `firefox/cgl-gpu.nix --arg canonical true --arg nv12Backing true --arg contextHandoff true` | **Firefox's GL** | see below; until then VLC keeps its private CGL |

**What 0009 needs before Firefox's CGL can take it.** 0009 is off by default (`contextHandoff`); the canonical build
Firefox uses is unchanged. With it on, one rule changes behaviour for any program: a thread asking for a context
another thread has current waits for it (at most 250 ms, `SF_CGL_HANDOFF_MS`; the context is reserved for the waiting
thread before it binds, so no third thread slips in between) instead of failing at once with `kCGLBadContext`. A second
rule is opt-in only (`SF_CGL_LEND=1`): a context's EGL binding leaves a thread when that thread lets go of the
context's `CGLLockContext` completely, and comes back when it locks or makes it current again; on macOS a context may
be current on several threads at once, EGL allows one, and VLC's NSOpenGLView output needs this. Before Firefox's
build takes 0009:
1. Read Gecko's use of CGL (`GLContextCGL`, its compositor and render threads): every place that makes a context
   current on more than one thread; whether any thread relies on a make-current failing fast (a 250 ms wait instead
   would be a stall); and, if lending is ever wanted, whether any thread calls GL after `CGLUnlockContext` without
   making the context current again.
2. Build the Firefox cohort with `contextHandoff` and run its own qualification (FX's presentation series, video at
   1080p60 and 4K, WebGL, popups, resize, twelve rounds) against the same build without it, comparing frame times.
3. Only then a canonical CGL install, through Firefox's own installer and rollback (`install-canonical-graphics.py`).

**Not part of the install.** The decoder device's permission is a kernel item (the driver creating `/dev/sfavd` with an
owner and mode meant for it, or a broker); the launcher's step stays until then. The `/Applications/VLC.app` wrapper and
its launcher entry are already installed and are removed by `/private/var/db/sfvlc/app/uninstall.sh`.

## System install record (SYSINSTALL, 18 November 2026)

Steps 1-6 of the proposal are installed on the M1 (owner's approval: "System wide install yes"), each built from this
branch's recipes, byte-identical to the file VLC ran privately, put in by `system/sf_vlc_restore.sh` (old file kept
beside the path as `<file>.pre-vlc`, the same inode), steps 5 and 6 through the guarded installer, and followed by
the lifecycle set (`system/lifecycle/`: synthetic input on the virtual seat, own windows on Space 2, owner idle).

| Step | File (old -> new sha256, first 8) | Installed (UTC) |
|---|---|---|
| 1 | AddressBook 6148edaf, ScriptingBridge 28e0eb67, WebKit 0e3c4c22, MediaPlayer b80e206a frameworks (18 new paths) | 16:48 |
| 2 | CoreFoundation wrapper 6f280f66 -> 8ce243b9; Foundation (Versions/C) a660d750 -> 48d07784; CoreServices.pd 04b372fe -> b0ee9dbe | 16:58 |
| 3 | QuartzCore.pd af3667bf -> 4500d69f (0320, 0321, 0326, 0329) | 17:04 |
| 4 | AppKit dde63492 -> e4ca36be (0322-0328) | 17:13 |
| 5 | /usr/lib/libFoundation.dylib 4d9ee43e -> e71a0cb9 (guarded installer, probe sf-kvo-probe) | 17:35 |
| 6 | /usr/lib/libSystem.B.dylib f32061c6 -> 8230d18f (guarded installer, probe sf-vlc-libsystem-probe) | 17:43 |

- Before: every replaced library's exports a superset of the installed file's (llvm-objdump exports trie), load
  commands identical, new imports present in the installed libraries. QEMU rehearsal r6: boot 1 84 ok / 1 FAIL, boot 2
  (fresh boot with the six) 25 ok / 1 FAIL; forward and back, in one boot and across a boot, every staged path as
  before; cold compare 25/25 identical. The one FAIL (both boots) is the guest's headless VLC check: first cause found
  and fixed (no plugins.dat + `--no-plugins-scan`), a second cause inside the rehearsal root not established.
- Lifecycle set after each step: Firefox (own profile: page, scroll, H.264 video with the decoder's job count, second
  window, quit from its menu), Terminal (two tabs) with the four themes and the owner's look put back, Activity
  Monitor's tabs, About panels, VLC through VLC.app (hardware decoding, Half/Normal Size recorded: 0 black frames, 0
  without the strip, full screen and back; no corner drags: they can leave VLC stuck in exit, item 25), QuickTime
  Player from QTP2's private set: all PASS after every step; About FAIL throughout, as before the install. One FAIL
  after step 5 (Firefox exited at start) was the test profile, not the file (same failure with the step put back; a
  fresh profile passes): SF-AG-firefox-defects.md.
- The coordinator restarted the M1 after step 6 and installed kernel 51; the post-restart set passed on it (all 14
  files as staged, features 19/19, lifecycle all PASS but About).
- Launcher trimmed (18:16Z): VLC.app's manifest prefix is `/private/var/db/sfvlc/after-system` (Sparkle stand-in, CGL
  0009 OpenGL.framework and libGL/libGLU only; the proposal's CGL step stays deferred); `system/sf_vlc_launcher_trim.sh`
  (undo: `... undo`). VLC passed once more. The private prefix stays on disk for a later clean-up.
- Way back for everything: `sh /private/var/db/sfsysinst/stage/sf_vlc_restore.sh back` (one step: `back N`).
- Step 7 (QuickTime Player's AppKit 0340-0367 + About nib, Onyx2D 0363, libFoundation 0365, recipe commit dc3088981;
  sub-steps 7a/7b/7c, staged on the M1): NOT installed; the permission for the install was refused in the installing
  session. Its baseline (menus, full screen, QuickTime private and on the system AppKit) is recorded.
