# SF-AH: VLC media player

Goal: the official VLC media player for macOS (arm64), unmodified, starts from a launcher of its
own on SiliconForest, opens a file and plays video with sound in its own window, with working
transport controls, on the M1.

Status on 18 November 2026, 08:25Z: **it plays, driven through its own interface, with hardware
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
| 11 | The picture, second output (`--vout=macosx`, NSOpenGLView): starts, then `CGLSetCurrentContext` fails (10004) when the video thread takes the context | with the traced CGL: `EGL_BAD_ACCESS`, the NSOpenGLContext stays current on the main thread, so the 250 ms wait of 0009 ends without it; then VLC asserts that `-[VLCOpenGLVideoView reshape]` runs on the main thread, which ours does not. Earlier note: VLC makes a context current on its own thread and locks it with `CGLLockContext`; our CGL sits on EGL, where a context is current on one thread at a time | open; not needed for the default output | **open** |
| 12 | Hardware decoding: `/dev/sfavd` is root's alone, so VideoToolbox's hardware decoder refuses the account `sf` ("Cannot open the AVD device: Permission denied") and VLC decodes in software | device permission | interim in the launcher, off by default and **not yet tried**: while still root it gives the node group staff and mode 0660 (lasts until reboot). The proper fix is a kernel item: see below | open |
| 15 | AppKit: `-[NSMenuItem parentItem]` missing; every VLC menu ended in an exception before it opened | missing method | `cocoa/patches/0322` | candidate, private; menus work |
| 16 | Foundation: `-performSelectorOnMainThread:withObject:waitUntilDone:NO` on the main thread ran the message at once. VLC's playlist adds an item while it holds its lock and sends itself the update this way; the update took the same lock and the interface stopped (its Open dialog never started a file; sampled: main thread waiting on the playlist mutex) | semantics differ from macOS, which queues it | `terminal-app/patches/foundation-main-thread-perform-is-queued.patch`: queued on the main run loop as on macOS | candidate, private (a core library: the QEMU rehearsal and the guarded installer before any system install; it changes when other programs' main-thread messages run) |
| 17 | The picture at scale 1: VLC's video layer kept `contentsScale` 1, so VLC rendered 1708x960 and the panel showed it enlarged 1.5x | AppKit gave custom backing layers no scale | `cocoa/patches/0323`: a layer made by the view's `-makeBackingLayer` follows the window's `backingScaleFactor`; a delegate answering `-layer:shouldInheritContentsScale:fromWindow:` decides | candidate, private; works |
| 18 | VLC sizes its window to the video in pixels (larger than the screen) and clamps to `NSScreen visibleFrame`, which here is the whole panel; the desktop gave the window less and AppKit laid it out for the size asked: the picture was cut on the right and the controls bar was below the visible area | AppKit/desktop | `cocoa/patches/0324`: when the desktop answers an application's larger request with a smaller size, the window keeps to that size until the desktop configures a larger one. The proper fix is the desktop telling clients its work area (`xdg_toplevel.configure_bounds`) and `visibleFrame` following it: a request for the desktop's owners | candidate, private; works |
| 19 | Fullscreen: VLC ended at its fullscreen button (`-[NSAnimation startWhenAnimation:reachesProgress:]` raised "not implemented"), and after that was fixed the main window stayed empty after leaving fullscreen (NSAnimation's `currentValue` stayed 0; VLC finishes its transition when it reaches 1) | missing AppKit behaviour | `cocoa/patches/0325`: linked animations, and the current value follows the progress through the curve or the delegate | candidate, private; fullscreen in and out works (the desktop's docks stay drawn over it) |
| 20 | Hardware decoding: `/dev/sfavd` root's alone; then VideoToolbox's pictures reached OpenGL green (VLC's IOSurface converter, `glconv_cvpx`) | permission; IOSurface texture path | the launcher (still root) gives the node group staff, mode 0660, until reboot (`"hardware_decode": true`); `--glconv=none` in the release's arguments makes VLC copy the decoded pictures to its textures itself (`cvpx` converter) | works with the copy; the IOSurface path is open; the proper device permission is a kernel item |
| 21 | Resizing the playing window by its corner (DEMO's film take, 18 November): black frames for about 67 ms and VLC's log "Failure setting current CGLContext: invalid context"; in the repeat, "Failure restoring previous CGLContext" and VLC aborted | **cause established** with a traced CGL (`SF_CGL_TRACE=1`), 12-drag sessions of DEMO's drag (40 moves 50 ms apart, 1280x813 <-> 1520x948, hardware decoding): every failed make-current was `EGL_BAD_ACCESS` (0x3002), 16 of 19 with the context still current on another thread when traced (the other 3 had just been let go). CGL lets a context be made current on one thread while another still has it (the application orders its use with CGLLockContext); EGL refuses it. VLC makes its context current on its video thread while the layer draws with it on another; the frame was not prepared or not drawn, and the layer read back from no context: a black frame | `firefox/cgl-patches/0009` (`cgl-gpu.nix --arg contextHandoff true`): a thread asking for a context another thread has current waits for it to be let go, at most 250 ms (`SF_CGL_HANDOFF_MS`). `cocoa/patches/0326`: CAOpenGLLayer makes the context current before locking it (VLC's order, so neither side waits holding what the other needs) and keeps its last picture when the context cannot be made current | private, works: before, installed CGL: 9 failures in 3 drags, then VLC aborted; traced CGL with the wait off: 19 failures in 10 drags, then VLC aborted; with both fixes: 0 failures, 0 black mid-drag captures, no abort in 2 x 12 drags; waits 0.5-10.6 ms. The one frame DEMO saw with the picture over the whole window was not seen in my captures: not shown fixed |
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
