# SF-AI: Apple's QuickTime Player on SiliconForest

## Goal
The unmodified QuickTime Player (version 10.5, build 1252.3, from the owner's macOS 26.5.2; a git-ignored
copy that is never committed) launches on the SiliconForest desktop of the 13" M1 MacBook Pro, opens a movie
in a window, and plays it with sound and a transport bar. It is the capstone of the media work in SF-AB
(`SF-AB-finch-frameworks.md`) and SF-W: the application is a thin shell over AVKit, AVFoundation, CoreMedia and
VideoToolbox, so it only plays when every one of them behaves.

The method is the one that brought up Apple's Terminal (SF-Y) and Activity Monitor (SF-AA): read the binary's
interface (which libraries it loads, which symbols it binds, which classes and selectors it uses, what its nib
files instantiate), supply each missing piece as our own code written from public documentation and observed
behaviour, and stage it beside the system until the application runs. Nothing from Apple's bundle, SDK or
private headers is in this repository; only names appear here, because names are the interface.

## State (17 November 2026)
**Not launched.** The last real load on the M1 (15 November) stopped in dyld at a library that did not exist,
before any symbol was bound. Everything below this line is static analysis and workstation builds: a
prediction of what dyld and the Objective-C runtime will ask for, not a run. This phase had no access to the M1.

What changed in this phase:
- The dependency map was redone from the real binary (next section), including what earlier scans did not
  look at: the nib files, the application's own class hierarchy, its Swift types, entitlements and XPC service.
- The six libraries that stopped the load now exist as a stage (`integrations/siliconforest/finch/QuickTime/loader.nix`).
  With them, the static scan finds **no library that dyld must load missing** (three Swift overlay libraries
  are absent, all weakly linked, which dyld skips) and **112 symbols still unbound, down from 153**.
- SwiftUI turned out to be a small problem, not a large one (see "SwiftUI").

## What the binary asks for
Measured on the arm64e slice with `llvm-otool`, `llvm-nm` and the lab's own Mach-O reader
(`integrations/siliconforest/homebrew/hb_macho.py`, `sf_gapscan.py`), which understands chained fixups.

| | |
|---|---|
| Libraries linked | 57 (41 required, 16 weak). All by absolute system path: no `@rpath`, no bundled frameworks, no plug-ins |
| Symbols bound at load | 965 (chained fixups: every one is bound before `main`, so one missing symbol stops the launch) |
| Objective-C | 148 classes of its own, 24 categories on system classes, 49 protocols, 3,538 selectors sent |
| Swift | 5 types: a feature-flag key, a logger, a resource-bundle class and **one** SwiftUI view |
| Nib files | 20, all in the NIBArchive format our AppKit already loads for Terminal. `MainMenu` (17 menus, 114 items) at launch; a two-view nib per document kind at open |
| Embedded helpers | one XPC service that links only Foundation and CoreFoundation (it vends bookmark data and AVCHD folder lookups) |
| Sandbox | the application is sandboxed, with camera, microphone, user-selected files and network-client entitlements, plus private ones for screen capture, FairPlay and audio routing |
| Document types | 21; movies and audio map to one playback document class, AVCHD folders and image sequences to two others |

The application is Objective-C and AppKit. Its player view is a subclass of `AVPlayerView`; its trim/edit
controller is a subclass of the private `AVPlayerControlsViewController`; its recording view is a subclass of
`AVCaptureView`. A superclass must exist for the subclass to be usable at all, so these are launch
requirements, not features. One more class is named only inside a nib (`AVAudioView`, the audio-only document's
view), which no import table shows: it is looked up by name when an audio file is opened.

### Framework table
"Bound" is how many of the symbols QuickTime Player binds from that library a SiliconForest root provides, by
the static scan. The root is a copy of the M1's system libraries taken on 15 November with the staged
providers of SF-AB and this ticket laid over it; it predates two days of AppKit work and must be re-measured
against the machine (label: **snapshot, not today's disk**).

| Library | Kind | Bound | Who supplies the rest | Needed |
|---|---|---|---|---|
| AppKit | public | 167 of 181 | ours: binding names, text-style names, a click gesture recogniser, two instance variables of the About panel class | launch |
| Foundation | public | 104 of 115 | ours: file coordination, file wrappers, Spotlight item, AppleScript and scripting specifier classes (honest "unavailable" bodies first) | launch (binding), features later |
| CoreFoundation | public | 70 of 80 | ours: ten URL resource-key names | launch |
| CoreGraphics | public + private | 59 of 74 | ours: one display query; fourteen private window-server calls (Spaces, hot keys) that must answer "no such thing" | launch (binding); full screen |
| CoreServices | public + private | 9 of 20 | ours: recent-documents list calls, two type identifiers, Spotlight "used" mark | launch (binding); Open Recent |
| QuartzCore | public + private | 12 of 21 | ours: keyframe animation, text and tiled layers, constraint layout, filters | open (controls and overlays) |
| CoreText, ImageIO | public | 0 of 2, 4 of 6 | ours: text-style size, two image property names | launch (binding) |
| Security | public + private | 5 of 8 | ours | launch (binding); sharing |
| AVFoundation | public | 97 of 114 | Finch has the model for composition, export and image generation; capture outputs are ours ("no device") | launch (binding); editing, export, recording |
| AVFAudio | public | 6 of 8 | ours: audio session and routing arbiter shells | open |
| CoreMedia | public + private | 60 of 63 | ours: dynamic-range query and two private format queries | open |
| CoreVideo, AudioToolbox, Accelerate, IOKit, SystemConfiguration, libSystem, libobjc, Swift core | public | all | installed | launch |
| VideoToolbox | public | 3 of 5 | staged in SF-AB (two capability queries) | open |
| MediaToolbox | public + private | 6 of 7 | ours: one private asset constructor whose calling convention is still unknown | launch (binding) |
| CoreAudio | public | 2 of 3 | ours: block-based property listener | open (device changes) |
| CoreImage | public | 5 of 6 | Finch has it | export |
| **AVKit** | public + private | 11 of 18 | staged in SF-AB (Finch's `AVPlayerView` over our player); ours: controls view controller, time resolver, volume slider, recording-controls provider, two menu builders | **open: this is the player** |
| WebKit | public | 2 of 3 | staged absence facade; one class more | launch (binding); only the YouTube sign-in uses it |
| **SwiftUI** | public | 34 of 34 | this ticket: binding subset | launch (binding only) |
| DeveloperToolsSupport, Swift `os` | public | 2 of 2 each | this ticket | launch (binding) |
| QuickLook, QuickLookUI, Quartz | public + private | 3 of 3, 1 of 1, umbrella | this ticket: absence providers | launch (binding) |
| CoreMediaIO | public | 1 of 1 | staged in SF-AB (absence) | recording |
| TCC, PhotosFormats, MediaRemote, GeoKit, MobileAsset, MonitorPanel, PerformanceAnalysis, FeatureFlags | private | all 21 | staged in SF-AB (eight absence providers; real Swift metadata for FeatureFlags) | launch (binding); they answer "denied" or "none" |

Beyond symbols: 459 of the 3,538 selectors are implemented by no class in the scanned system. Most are
delegate callbacks the application itself implements for frameworks to call. About seventy are messages it
sends to AVKit objects that the public `AVPlayerView` does not declare (controls placement, time display
styles, chapter and frame stepping, trimming, looping, layer layout modes): that list is the real size of the
AVKit work, and it only shows at run time, as an unrecognised selector.

### SwiftUI
Earlier notes treated SwiftUI as a wall ("needs a SwiftUI runtime"). The binary says otherwise. It binds 34
SwiftUI symbols, all belonging to one view built from `Text`, `Image(systemName:)`, a `Button`, a frame
modifier and an if/else. It imports **no hosting class** (`NSHostingView`, `NSHostingController`), so this
binary cannot put that view on screen by itself. Inferred, not yet observed: the view is not reached at
launch or at open. What is certain is that dyld needs the 34 names. `loader/SwiftUI.swift` declares that part
of the public interface with the real Swift compiler and library evolution, so the compiler emits the same
mangled names, descriptors and witness tables; anything that would actually render stops with a message. The
real framework (OpenSwiftUI, which the Finch project builds) remains the long-term answer and is a separate
piece of work that QuickTime Player does not wait for.

## The launch path, in the order things will fail
1. **Library loading.** Was the failure on 15 November. Predicted cleared by `loader.nix`.
2. **Symbol binding: 112 symbols in 16 libraries** (table above). About 38 are constants (names of keys and
   notifications), 36 are classes (plus two metaclasses and two instance variables), about 34 are functions. Smallest honest form: constants with their
   documented values; classes whose creation fails or whose methods report "unavailable" where we have no
   implementation (as SF-AB does for capture); functions that return the documented failure. Never a symbol
   that pretends to work.
3. **Class realisation.** Three application classes inherit from AVKit classes, one from an AVFoundation capture
   class; categories extend six AVFoundation classes and, in AppKit, the private About-panel class.
4. **`NSApplicationMain`.** A principal class that overrides termination, then `MainMenu.nib`: two custom
   objects (the delegate and a document controller subclass), 65 action connections, a shared user-defaults
   controller. Our nib loader has done this for Terminal and Activity Monitor; the document controller is new
   ground (QuickTime Player is document-based, those two are not).
5. **Launch notifications.** The delegate queries private services: media-support assets, privacy preflight
   for screen capture, now-playing state, feature flags. Each staged provider answers "none". The window
   server calls for Spaces and hot keys must return without effect. Expected visible result: the menu bar,
   and (as on macOS, where the application opens no window by itself) an Open panel.
6. **Opening a movie.** The asynchronous document-opening call of `NSDocumentController`, type lookup by
   uniform type identifier, an asset loader that asks `AVURLAsset` for tracks, duration, natural size and
   format descriptions, then a window built in code and a nib holding the player view.
7. **The player view.** The subclass of `AVPlayerView` is configured with the private messages listed above,
   and key-value observes the player controller. This is where the "about seventy selectors" land.
8. **The picture.** `AVPlayerLayer` under the player view. SF-AB's staged player decodes through VideoToolbox
   on the M1's hardware decoder and has put real frames into the layer off screen; a layer-hosted video
   picture in a window on our QuartzCore is unproven.
9. **Sound and time.** The staged player drives an audio queue and takes its clock from the output device. It
   prepares a bounded amount of media before playing (about two minutes of video), which is a limit to remove.
10. **Controls.** AVKit's floating transport bar: play/pause, scrubbing, volume, time display, full screen.

What may fail visibly for a long time without blocking the goal: screen, camera and audio recording
(no capture devices), trimming and the clip editor, export and "Save As" presets, sharing services, AirPlay,
iCloud documents and versions, AppleScript, Picture in Picture, the YouTube sign-in. Each must fail with the
application's own error path, not a crash.

## Stages
Each ends in something a person can see. Sizes are counts from the scan; times are rough, for one work stream
with the M1 available, and are the least certain numbers on this page.

| Stage | Ends when | Work | Estimate |
|---|---|---|---|
| 0. Binary loads | dyld binds everything and `main` runs (first log line of the application) | 112 symbols in 16 libraries: ~38 constants, 36 classes, ~34 functions; six loader libraries (done as a stage) | 2 to 4 days |
| 1. Menu bar and Open panel | the application's menus are on screen and File > Open shows a panel | document-controller behaviour, private service answers, window-server no-ops, XPC service launch | 2 to 5 days |
| 2. First frame | a movie's first picture is in a document window | asynchronous document open, asset loading, the player view's private messages, layer-hosted video in a window | 1 to 2 weeks |
| 3. Playback with sound | the movie plays in sync to its end, space bar pauses | the staged player made unbounded (streamed, not prepared), device changes, end-of-movie behaviour | 3 to 6 days |
| 4. Transport bar | floating controls: play, scrub, volume, time, full screen | AVKit controls drawn by us in the style of macOS, keyboard and menu commands, chapter and frame stepping | 1 to 2 weeks |

After stage 4 come the features listed as "may fail visibly", each its own piece: audio-only documents
(`AVAudioView`), Open Recent, trimming, export, recording.

## Where the code comes from
- **Installed already (SF-AB, SF-W):** CoreMedia, CoreVideo, VideoToolbox on the hardware decoder, AudioToolbox,
  AVFAudio and the asset/reader side of AVFoundation, adopted from the Finch project or written here.
- **Staged, not installed (SF-AB):** Finch's `AVPlayer` model with our local-file backend; Finch's `AVPlayerView`
  with our transport drawing and eleven of the eighteen AVKit names; eight private-framework absence providers.
- **Finch can supply more:** composition, export session and image generator models in AVFoundation, CoreImage,
  a real Quick Look, and OpenSwiftUI as a whole SwiftUI. Whole Finch frameworks may be adopted where they fit;
  notices are kept and the "Taken from Finch" table in SF-AB is updated.
- **Must be written here:** the private AVKit surface (nobody has it), the window-server and recent-documents
  calls, the document-architecture gaps in our AppKit, QuartzCore's missing layer classes.
- **Darling:** its media frameworks live in the main Darling repository, which is GPL-3.0, so no code is taken
  from them (they were not examined beyond the licence). Darling's permissively licensed parts are its Metal
  stack, which is SF-AE's subject and which QuickTime Player does not link.
- **Expected from the VLC bring-up, which is running now:** a movie picture in an AppKit window on the M1, the
  CoreAudio output path under a real player, full-screen video, and opening a document from the desktop.
  QuickTime Player needs the same AppKit and QuartzCore ground; it will reuse whatever VLC proves.

## Risks
- **Private AVKit.** The largest unknown. The interface is visible (names and argument shapes); the behaviour
  the application depends on is learned only by running it. SF-AB's notes already record a strict test of the
  staged controller that fails on one frame in 150.
- **`AVPlayer` semantics.** Key-value observing of status, rate, time and item changes in the order the
  application expects; seeking; end-of-item. The staged backend handles local files, rate 1, pause and seek.
- **Layer-hosted video.** Our QuartzCore's path from a decoded frame to pixels in a window, without a copy per
  frame, is the same open question SF-AH (cross-process layers) and the Firefox work have met.
- **The sandbox and XPC.** The application expects a container and an XPC helper. We do not enforce the sandbox;
  whether the helper is contacted at launch or only for recents and AVCHD folders is not yet known.
- **SwiftUI.** Small if the inference above holds. If the view is reached after all, the subset stops the
  program with a clear message and the real SwiftUI becomes a prerequisite.
- **arm64e.** The slice uses pointer authentication; SiliconForest already runs arm64e Apple binaries (Terminal,
  Activity Monitor), so this is a known path, not a new one.

## What exists in the tree for this ticket
| Path | What |
|---|---|
| `integrations/siliconforest/finch/QuickTime/loader.nix` | builds the six loader libraries: SwiftUI (binding subset), DeveloperToolsSupport, the Swift `os` module, QuickLook, QuickLookUI, Quartz |
| `integrations/siliconforest/finch/QuickTime/loader/` | their sources, the list of symbols QuickTime Player binds from them (`imports.json`, names only) and `check_exports.py` |
| `integrations/siliconforest/finch/QuickTime/loader-check.nix` | static check: all 42 symbols are exported by the library with the right install name (passes; nothing is run) |
| `tests/test_quicktime_loader.py` | unit tests of the check on synthetic images |
| `integrations/siliconforest/finch/QuickTime/`, `finch/AVKit/`, `finch/AVFoundation/player/`, `finch/MediaToolbox/` | SF-AB's staged providers this ticket builds on |

Reproduce the scan: build `loader.nix` and SF-AB's stages, then run `sf_gapscan.py --root <copy of the
system libraries> --overlay <each stage> --app "<QuickTime Player.app>=/System/Applications/QuickTime Player.app"
--arch arm64e`. The full output (import lists, class maps, nib class lists) stays outside git.

## Next steps
1. On the M1: load the unchanged application against the stage and record where dyld stops now (expected: the
   first of the 112 symbols). Re-run the scan against today's system libraries.
2. Stage 0 in three batches: constants; "unavailable" classes and functions; the QuartzCore and AVKit classes
   that need real behaviour.
3. Our own small document-based test application that opens a movie in an `AVPlayerView` window through the
   same calls QuickTime Player makes, so that stages 2 to 4 are proven with our code before Apple's binary
   meets them.
