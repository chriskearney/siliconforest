# SF-AH: VLC media player

Goal: the official VLC media player for macOS (arm64), unmodified, starts from a launcher of its
own on SiliconForest, opens a file and plays video with sound in its own window, with working
transport controls, on the M1.

Status on 18 November 2026: **not playing yet.** The unmodified program starts, loads its
macOS interface, shows its video window with its menus, opens an H.264/AAC MP4, decodes it in
software and plays the sound into the system's audio server. The picture area of the window is
black: the frames VLC draws with OpenGL do not reach the window yet. Everything below says what
was observed on the M1 and what was not.

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
| 8 | Sparkle (VLC's own copy) needs libxar, WebKit, `NSURLDownload`, Security transforms | VLC's updater cannot load | **replaced at load time** by a provider with the same interface that reports "no updates available/unavailable" (`finch/players/compat/unavailable.m`); the copy in the bundle is untouched | private; a decision the owner may overrule |
| 9 | Two OpenGL libraries in one process: the system's CGL uses the GPU Mesa, while AppKit, QuartzCore and CoreVideo name the older `/usr/lib/libGL.1.dylib`; VLC's shader calls landed in the library without a context | system inconsistency | the launcher puts the GPU Mesa's directories first on the library path, as the Firefox launcher does | works around; the system fix is one libGL for the system's frameworks and its CGL |
| 10 | The picture: `caopengllayer` output (VLC's default) starts and receives pictures, the window stays black | QuartzCore `CAOpenGLLayer` presentation | open | **open** |
| 11 | The picture, second output: `macosx` (NSOpenGLView) starts, then `CGLSetCurrentContext` fails (10004) when the video thread takes the context | CGL allows a context to move between threads; ours is an EGL context held by another thread | open | **open** |
| 12 | Hardware decoding: `/dev/sfavd` is root's alone, so VideoToolbox's hardware decoder refuses the account `sf` and VLC decodes in software | device permission | open (needs a decision; no kernel change made) | open |
| 13 | Button pictures (`VLCPlayTemplate`, ...) not found; subtitle font `HelveticaNeue.dfont` absent | AppKit named-image lookup in the bundle; font | open | open |
| 14 | DiskArbitration (Blu-ray plug-in), Growl's Carbon and Secure Transport calls, `SecTrustGetResult` and others in the TLS plug-in | not on the path to playing a local file | not done; those plug-ins fail to load and VLC goes on without them | listed |

## The launcher

`finch/players/vlc/vlc-sf` (Python, as the Firefox launcher):

1. as root, connects to the compositor's Wayland socket and keeps the descriptor (`WAYLAND_SOCKET`);
2. becomes the account `sf` (uid 501, group staff, `HOME=/Users/sf`);
3. puts this release's private libraries first: `DYLD_LIBRARY_PATH` = the libSystem candidate's
   directory and the two GPU Mesa directories; `DYLD_FRAMEWORK_PATH` = the private frameworks of
   rows 3 to 8;
4. executes the vendor's `Contents/MacOS/VLC` with the arguments it was given.

No interposing library is inserted and no VLC option is forced.

## Observed on the M1 (18 November 2026, kernel 50)

All runs: the vendor binary (SHA-256 of `Contents/MacOS/VLC`
`26a122e5b2e3b3ac31634cbfd671d7c9c4648ba0618931e75424289a9c9b42b2`, equal on the workstation and
on the M1 before its first run), started by the launcher from a private prefix, the owner idle,
no synthetic input. Captures are the compositor's own (`--screencapture`).

- `VLC --version` prints 3.0.24; all plug-ins but the Blu-ray one load (459 modules).
- Without a file: the interface loads completely; the controls window and VLC's first-run
  question ("Check for album art and metadata?") are on the screen.
- With a 1080p H.264/AAC MP4 (Big Buck Bunny, 10 s): demuxed, decoded by VLC's own libavcodec
  (six threads), audio decoded by faad; the audio output opens the default device ("analog
  output successfully opened"); the system audio server's log for that client: 48,128 frames
  written in 6.0 s, 0 underruns. Nobody listened.
- The video window opens with the title of the clip and VLC's menus (Edit, View, Playback,
  Audio, Video, Subtitles, Window, Help). The picture area is black in both captures of that run
  (mean of the area 0,0,0): row 10.
- SIGTERM ends the program cleanly while it plays (no process left); with only the first-run
  question on the screen it did not end within 5 s and was killed.

Not yet done: transport controls, seeking, fullscreen, a second container, the comparison of a
captured frame with ffmpeg's, the 12 launch-play-quit cycles, CPU and dropped-frame numbers, the
Firefox/Terminal/Activity Monitor regression set (nothing in the system has been changed, so there
is nothing for it to catch yet), `/Applications/VLC.app` and the dock.

## Installed

Nothing in the system. On the M1, under `/private/var/db/sfvlc` only (remove the directory to
go back): the vendor bundle, the libSystem candidate
(`8230d18f9fa9ca9c28ddcf978270fbebce877d90ad0a8d0b02b730006f1bdaea`), the private frameworks,
the launcher and test tools. VLC's own preferences and caches are in `/Users/sf/Library`.

## Tests

`finch/players/vlc/vlcw.py` (workstation) and `vlc_m1.py` (on the machine): each pass takes the
shared screen lock, waits until the owner has been idle, starts and stops only its own VLC, and
captures through the compositor. Input, where a pass needs it, goes through the compositor's
test instrument on its virtual seat into the test's own window.

Test clip: Big Buck Bunny, (c) Blender Foundation, CC BY 3.0, https://peach.blender.org; cut on
the workstation, never committed.
