# SF-AH: VLC media player

Goal: the official VLC media player for macOS (arm64), unmodified, starts from a launcher of its
own on SiliconForest, opens a file and plays video with sound in its own window, with working
transport controls, on the M1.

Status on 18 November 2026: **it plays, from a private prefix; acceptance is not done.** The
unmodified program starts, loads its macOS interface, opens a 1080p H.264/AAC MP4 and a VP9/Opus
WebM, decodes in software, shows the moving picture in its own window and plays the sound into the
system's audio server. A captured frame matches ffmpeg's decode of the same frame. Not done yet:
controls driven through the interface (pause, seek, fullscreen, quit), the 12 launch-play-quit
cycles, CPU and dropped-frame numbers, hardware decoding, `/Applications/VLC.app`, any system
install. Everything below says what was observed on the M1 and what was not.

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
| 11 | The picture, second output (`--vout=macosx`, NSOpenGLView): starts, then `CGLSetCurrentContext` fails (10004) when the video thread takes the context | not established yet. VLC makes a context current on its own thread and locks it with `CGLLockContext`; our CGL sits on EGL, where a context is current on one thread at a time | open; not needed for the default output | **open** |
| 12 | Hardware decoding: `/dev/sfavd` is root's alone, so VideoToolbox's hardware decoder refuses the account `sf` ("Cannot open the AVD device: Permission denied") and VLC decodes in software | device permission | interim in the launcher, off by default and **not yet tried**: while still root it gives the node group staff and mode 0660 (lasts until reboot). The proper fix is a kernel item: see below | open |
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
