# SF-AI: Apple's QuickTime Player on SiliconForest (GitHub issue 62)

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

## State (18 November 2026, evening)
**A movie's document window is on screen.** On the M1, from the private prefix (nothing installed), the
application opens a movie named at launch and shows its document window: the menu strip ("QuickTime
Player  File  Edit  View  Window  Help"), the movie's first frame and the transport bar. Started without
a file, it shows its Open panel, as on macOS. How it got there: "Stage 1 on the machine". Before that,
our own probe ran against the prefix without a window:

- **All 154 names the prefix supplies are found by the real dyld** in the libraries the application binds
  them from (the 112 additions and the 42 of the loader libraries), and every behaviour check of the probe
  passes (file coordination, time formatting, export failing as documented, constraint layout, the time
  resolver, the class hierarchies the application subclasses, display lookup, the "no Spaces"/"no AirDrop"
  answers). Each system image is loaded exactly once; no class is defined twice.
- **The first attempt crashed, and why is understood** ("What the first run on the machine found").
- **28 general names have moved into the frameworks** (Cocoa patches 0340-0347 and the framework wrappers: "Names
  moved into the frameworks"). They build; static checks find all 28 exported where the application binds them,
  and against a root with those frameworks the shrunk prefix still leaves none of the 965 imports unbound, with
  no name defined twice. None of it is installed, and the new code has not run anywhere yet: its conformance
  program is built and waits for a machine.
- Offline, against the 15 November copy of the M1's libraries, the static scan still finds all 965 of the
  application's imports bound. That remains a prediction until the application is loaded.

Of the 112 names added last, 19 are real implementations, 37 are constants, 7 are models that hold values
nothing acts on, and 49 are absences: they bind, and when used they fail the way their interface documents
(or do nothing they cannot do properly) and say so once on stderr. The table "The 112 names" lists every one.

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
"Bound" is how many of the symbols QuickTime Player binds from that library SiliconForest provided **before
this ticket's additions**, by the static scan: it shows where the gaps were and who should own each in the
long run. With the additions every row is complete ("The 112 names"). The root is a copy of the M1's system libraries taken on 15 November with the staged
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

Beyond symbols: 393 of the 3,538 selectors are implemented by no class in the scanned system (459 before
the additions). Most are
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
2. **Symbol binding.** Predicted cleared: the 112 names that were unbound are supplied by the additions
   libraries and the staged AVKit ("The 112 names"). Constants carry their documented values; classes and
   functions without an implementation here are absences that fail visibly. Never a symbol that pretends to work.
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
| 0. Binary loads | dyld binds everything and `main` runs (first log line of the application) | done offline (static scan: 0 unbound); to be proven by the load test, then whatever the current system and the real dyld disagree about | 1 to 2 days once the machine is free |
| 1. Menu bar and Open panel | the application's menus are on screen and File > Open shows a panel | document-controller behaviour, private service answers, window-server no-ops, XPC service launch | 2 to 5 days |
| 2. First frame | a movie's first picture is in a document window | asynchronous document open, asset loading, the player view's private messages, layer-hosted video in a window | 1 to 2 weeks |
| 3. Playback with sound | the movie plays in sync to its end, space bar pauses | the staged player made unbounded (streamed, not prepared), device changes, end-of-movie behaviour | 3 to 6 days |
| 4. Transport bar | floating controls: play, scrub, volume, time, full screen | AVKit controls drawn by us in the style of macOS, keyboard and menu commands, chapter and frame stepping | 1 to 2 weeks |

After stage 4 come the features listed as "may fail visibly", each its own piece: audio-only documents
(`AVAudioView`), Open Recent, trimming, export, recording.

## The private prefix
Nothing in this ticket is installed at a system path. Everything QuickTime Player needs beyond the installed
system lives in one directory that only its launcher names, through `DYLD_FRAMEWORK_PATH` and
`DYLD_LIBRARY_PATH`, the way Firefox's private library families are found. Two reasons:

- The SwiftUI here is a binding subset. Installed system-wide, a real SwiftUI application would bind against
  it and then stop; in a private prefix it can only meet the one application it was written for.
- The additions put names in front of system frameworks (AppKit, Foundation, CoreFoundation and fourteen
  others). Each is a small library with the framework's install name that defines the missing names and
  re-exports the system's own image, linked beside it as `<Name>.sf-under`. The process still loads the
  system's file, once; no system file changes. A name that proves itself moves into the real framework
  (a Cocoa patch) and is then left out of the additions (`additions.nix { omit = [...]; }`).

`qt_prefix.py` assembles the prefix and reports any name that both an additions library and the system
image under it export, so that a system that has moved on is noticed rather than shadowed.

`CGFloat`: SwiftUI's frame modifier is mangled with `CoreGraphics.CGFloat`, which our Swift CoreFoundation
overlay lacks. The subset carries its own copy (Finch's `CGFloat.swift`) inside the private prefix only.
The proper change, CGFloat in `libswiftCoreFoundation`, is proposed as
`integrations/siliconforest/terminal-app/build-swift-runtime-cgfloat.nix`; it replaces a library every
Swift program loads, so it goes through the core-library rehearsal, not through this ticket.

## What the first run on the machine found
The coordinator ran the load test without the application (`--no-launch`): the probe died with SIGSEGV
before printing anything. Found by bisection on the M1 (one framework added at a time, core frameworks
last) and read back from dyld's own source and output:

- **dyld folds a library onto a loaded image with the same install name.** `checkandAddImage` in
  `dyld2.cpp` deletes a newly mapped dylib whose install name equals that of any image already loaded and
  hands back the loaded one. Our additions library carried the framework's own install name, and so did
  the system image it re-exports. 15 of the 17 system images have exactly that name.
- **Directly** (13 frameworks), the system image was folded onto ours, so our library became its own
  re-exported library. dyld's "circular reference" retry then reloads the name without a loader path,
  cannot resolve `@loader_path/…`, and the load fails ("Library not loaded … image not found"), taking
  every framework that needs it down too.
- **Through a SiliconForest wrapper** (CoreServices, QuartzCore): the image at those framework paths is a
  compatibility wrapper named `…​.sfcompat` that re-exports the original library `…​.pd`, which carries
  the canonical name. That one was folded onto ours, making a re-export cycle. dyld's
  `ImageLoaderMachO::findExportedSymbol` searches re-exports with no record of where it has been; the first
  lazy bind of a name neither image defines recursed 130,714 times and overflowed the stack. The probe's
  own fault handler showed it (no crash report is written for a command-line program on this system).
- Not involved: the symbolic link (a copy fails identically), initialiser order, chained fixups.
  Compatibility versions are not enforced for libraries built for macOS 10.14 or later.

**The change:** each additions library is found at the framework's path in the prefix but carries the
install name `<that path>.sf-additions`. dyld matches requests by path, never by install name (apart from
`@rpath`), so nothing else changes. `qt_prefix.py` now refuses a prefix in which an install name occurs
twice on any re-export chain, and refuses a class our libraries define that any loadable system image also
defines. That check found one: `NSFileWrapper` is AppKit's class on this system, so the Foundation additions
now re-export AppKit's class instead of defining a second one. Each framework's other directories
(Resources and the rest) are linked into the prefix, so that a bundle found from the binary's path in the
prefix keeps its resources.

After the change the same bisection rises steadily from 42 to 154 of 154 names found, with no crash at any
step. The full log stays in the lab's run directory.

**Where these names belong in the long run.** The additions are a way to give one application names the
system lacks, without changing a system file. Many of them are not QuickTime-specific: the binding and
text-style names, `NSFileCoordinator`, `NSMetadataItem` keys, `CAConstraint` and its layout manager,
`CATextLayer`, `CAKeyframeAnimation`, the URL resource keys, `CGGetDisplaysWithRect`, the block-based audio
property listener. They belong in the frameworks themselves, through the Cocoa patch series, where every
application gets them. Each such move removes that name from the additions (`additions.nix { omit = … }`),
and `qt_prefix.py` reports the names the system has gained so that none is defined twice.

## Names moved into the frameworks
The additions are a way to give one application names the system lacks without changing a system file. 28 of
the 112 are not QuickTime Player's alone, and now live where every application finds them:

| Patch or file | Framework | What it adds |
|---|---|---|
| Cocoa patch 0340 | AppKit | the enabled, hidden, title and tool-tip binding names; the eleven text-style names and `+[NSFont preferredFontForTextStyle:options:]` (sizes and weights from Apple's macOS text-style table); `NSClickGestureRecognizer`, which keeps its configuration and recognises nothing, as this AppKit's other recognisers do |
| Cocoa patch 0341 | AppKit | `NSFileWrapper`'s URL interface over its path one (`initWithURL:options:error:`, `readFromURL:`, `writeToURL:`, `matchesContentsOfURL:`); a recycled child wrapper was over-released when a folder was read again |
| Cocoa patch 0342 | CoreGraphics | `CGGetDisplaysWithRect` and `CGGetDisplaysWithPoint` (declared but missing) over the active display list |
| Cocoa patch 0343 | QuartzCore | `CATextLayer`: string or attributed string through CoreText, wrapping, truncation with an ellipsis, alignment, the documented defaults |
| Cocoa patch 0344 | QuartzCore | `CAKeyframeAnimation`, interpolated by the renderer for opacity, position, anchor point and bounds (key times, per-segment timing functions, discrete mode; paced and cubic drawn as linear, paths not followed). Also: an animation the renderer cannot interpolate now leaves the layer at its model value; it drew it at 0 |
| Cocoa patch 0345 | QuartzCore | `CAConstraint`, `CAConstraintLayoutManager`, `CALayer`'s `layoutManager` and `preferredFrameSize`; autoresizing applies only without a layout manager, as on macOS; layers lay out at once when their constraints or sublayers change |
| Cocoa patch 0346 | CoreAudio | `AudioObjectAddPropertyListenerBlock` and `…RemovePropertyListenerBlock` over the function-pointer listeners (applied by `m1-sound/sysaudio/build-sysaudio.nix`) |
| Cocoa patch 0347 | libFoundation | `-[NSURL getResourceValue:forKey:error:]` answers the parent directory, volume, read-only, hidden-extension and file-identity keys (applied by `terminal-app/build-foundation.nix`) |
| `terminal-app/compat/CoreFoundation.m` | CoreFoundation wrapper | the ten URL resource key names QuickTime Player binds from CoreFoundation |
| `terminal-app/compat/Foundation.m` | Foundation wrapper | `NSFileCoordinator` (moved from the additions) |

`additions.nix` now leaves these names out by default and then needs no additions for CoreFoundation or
CoreAudio at all: two fewer frameworks with a library of ours in front of them, one of them a core framework.
`additions.nix { movedInFrameworks = false; }` builds the full set for a system without the patched frameworks;
the load test uses it until they are installed. Installing them is the guarded core-library procedure's
business (libFoundation, CoreFoundation and Foundation are loaded by every program), after the
Firefox/Terminal/Activity Monitor checks; nothing here installs anything.

The conformance program `cocoa/conformance/qtp-names.m` checks each moved name without a window and builds for
macOS as well, so the believed constant values (the text-style names above all) can be compared there.

## Stage 1 on the machine (18 November)
Bounded launches on the M1, each under the GUI lock, with the owner-input check, on a Space of its own,
from a private directory: nothing installed, the application's own process only, stopped after seconds.
Every launch inserts a small library of ours (`finch/QuickTime/exitwatch.nix`) that records why the
program ends (exit, abort, a fatal signal or an uncaught exception, each with a backtrace) and prints the
main thread's stack on request.

- **The early end was a crash, not the environment.** The application asks at launch for an internal
  resources bundle that only Apple's own builds carry. `+[NSBundle bundleWithPath:]` got a nil path and
  handed NULL to CoreFoundation (SIGSEGV after 0.26 s, no crash report). On macOS the answer is nil.
  libFoundation patch 0348 does the same; the next missing name on that path,
  `+[NSString pathWithComponents:]`, is patch 0349.
- **Then it runs, idle, with no window.** Its delegate declines an untitled document
  (`applicationShouldOpenUntitledFile:` answers NO). On macOS the application still shows an Open
  panel at launch: document applications that keep their documents in iCloud get the Open panel
  instead of an untitled document (the `NSShowAppCentricOpenPanelInsteadOfUntitledFile` default
  turns this off). Our AppKit did not, so nothing appeared. AppKit patch 0350 does it (also when
  the application is reopened with no windows). It also hands files named at launch to the
  document controller when the delegate takes none, as macOS does.
- **Document types by identifier.** The application declares every document type by uniform type
  identifier only (`LSItemContentTypes`, no extensions, no type names). The document controller
  matched extensions only, so it found no type for any movie. AppKit patch 0351 names such types by
  identifier, finds a file's type through the conformance table in CoreServices, asks
  `-typeForContentsOfURL:error:` (the application overrides it), and makes documents with
  `-initWithContentsOfURL:ofType:error:` (the only initialiser the application implements).
- **On the way to the document window.** With a movie named at launch the application reads it
  (`-[MGPlayerDocument readFromURL:ofType:error:]`, type `com.apple.quicktime-movie`) and starts loading
  the asset. Each step stopped at a message nothing answered; the next ones were found ahead of time
  from the application's own call sites (the receiver from the message before, the types from the
  registers) so that one build round covers several:
  libFoundation 0352 (`-[NSURL fileReferenceURL]`: there are no reference URLs here, so the file's
  path URL, and `-isFileReferenceURL` says NO); AppKit 0353 (the document window's layer-hosting
  request and title-bar opacity, kept and answered with no effect; the document's window title name;
  the window's frame view, whose title bar has no versions button here; `isModalPanel`; menus by name;
  a menu item's key-equivalent match; the light and medium system fonts; system-spacing anchors);
  the slow-motion rate of a movie's frame rate (1: slow motion is not offered, so every movie plays at
  its own rate); and in our AVKit, the player view's player controller, its layer's layout mode and
  frame (the content's aspect fit), and the settings it keeps without acting on them (floating
  controls' margin, zoom, hiding controls, stereo eyes, display sleep, time display style; each says so
  once on stderr where it matters), the controller's initialiser, content size, looping, autoplay and
  frame stepping, and "no" for chapters, alternative audio, subtitles and sharing, which this player
  does not read.
- **The document window (18 November, evening).** Nine more bounded launches, each ending at the next
  message nothing answered, brought the window up: to-many change notifications (libFoundation 0354),
  the player item's track field mode and "has video", the player view's remaining settings
  (slow-motion range, unobscured content, share controller: none, edit controls: none), the
  application's gesture event mask, menu item identifiers and a document's restorable state (AppKit
  0357; nothing is restored here). Written ahead from the call sites in the same rounds: libFoundation
  0355 (file manager URL forms, set union, security scope: none here, locale names) and AppKit 0356
  (title-bar height, symbol images, writing direction, layer coordinates).
- **Where the menu bar is.** This desktop has no global menu bar: an application's main menu is
  drawn in the first row of each of its titled windows that is not a panel. The Open panel is a panel,
  so the menus appear with the first document window.

The load test now takes a capture and the window list 3 s before it stops the application, records
the exit reason, refuses to start the application while the owner is at the machine, and passes
`--movie` as the `NSOpen` default (the way AppKit is told about a file named at launch).

## Playback and the controls on the machine (18 November)
- **Streamed playback.** The staged player decoded a whole file into memory before playing (capped at
  512 MiB, about 5 s of 1080p). It now keeps about a second of pictures ahead of the display and reads
  the sound as the queue needs it (`finch/AVFoundation/player`, checked by `stream-probe.nix`). On the M1,
  Big Buck Bunny's 30 s 1080p cut matches an independent FFmpeg decode in all 900 pictures (time and
  NV12 MD5), and QuickTime Player plays it with its sound through coreaudiod without underruns.
- **The window.** A large movie opens fitting the screen, as on macOS (libFoundation 0361: an unbounded
  rectangle meets a finite one in NSIntersectionRect).
- **The controls.** QuickTime Player asks for AVKit's floating controls. They are drawn by our AVKit from
  shapes, over the bottom of the picture: volume (the speaker mutes), skip back and forward 15 s,
  play/pause, full screen (the window's own full screen), and the scrubber between the elapsed and the
  remaining time, which seeks by a click or a drag. They hide while a movie plays and the pointer rests for
  3 s, and come back when it moves. Space plays and pauses, the arrows step a picture.
- **The picture rate (QTP2, 18 November).** DEMO's film showed the picture moving one to three times a second.
  Measured without the recorder (the desk's `WMPACING` for QuickTime's window, 20 s of the 1080p30 cut): 20
  commits per 10 s, 2 a second. Cause, from a sampling profiler inside the process: the main
  thread drew each 1080p picture twice into the 2444x1375-pixel view through Onyx2D's bilinear resampler (AVKit's
  own `drawRect:` and AppKit's draw of the hosted player layer; the prefix has no EGL, so layers are drawn by the
  CPU), about 150 ms each. Changes: AVKit no longer draws the picture (AppKit draws the layer once) and fills
  black only where the picture is not; the view tells the player layer the picture's size in device pixels and
  the staged player makes each picture at that size in the window's own pixel layout (B, G, R, a skipped byte),
  scaled and converted in one pass by swscale on four threads, its buffers reused; Onyx2D 0363 copies such a
  picture instead of resampling it; AVKit's 30 Hz clock no longer redraws the whole view (a new picture does: two
  redraws out of step were 52 commits a second, 16 shown); the per-picture MD5 is taken only for the test that
  compares it (`SF_PLAYER_DIGESTS=1`). Result on the M1, private prefix: 297-301 commits and 270-293 shown per
  10 s without the recorder; 231-233 commits, 229-232 shown with the desk's recorder running, and the recording
  shows the picture changing 21-25 times a second. The main thread's CPU went from 9.0 s to 4.4 s in 15 s.
  The decoder was never the limit (900 hardware jobs per pass, 0 errors).
- **Colours.** HD pictures (720 lines and more) are now converted from YUV with BT.709's matrix, as players do when
  the stream does not say; smaller ones with BT.601's. Before, every picture used swscale's default, BT.601.
- **The black flashes (QTP2).** DEMO's take had the picture area black for 0.3 s when the window opened, for 0.25 s
  (its lower part) when space started playback, and for 0.1 s at a click on the strip's File. Cause: each redraw
  filled the whole view black and then drew the picture through the resampler for 150-300 ms; a frame presented in
  between showed the black (the lower part: rows not yet drawn). Now the black is only where the picture is not, the
  picture is copied in a few milliseconds, and the window's first drawing asks the player layer for the first picture
  instead of waiting for its next tick. Recordings with the desk's recorder (`runs/qtp/tools/black_frames.py`, the
  picture area): DEMO's take 13 frames with 30 % or more black; pass c1 (open, space, panel clicks, File menu) 2
  frames at the window's opening; pass c3 (with the first-picture change; open, play, full screen in and out) none,
  not even 5 % black.
- **Panel clicks (QTP2).** Play/pause by a click works (pass c1: a click paused at 0:05, the next resumed; skip and
  the File menu by clicks in the same pass). A tracer of `-[NSWindow sendEvent:]` (`runs/qtp/m1/hittrace`) shows each
  press on the panel landing on the panel itself: no view of QuickTime's lies over it, and no reordering of the
  views is needed (QTP's per-picture reordering broke every panel click in pass m2 and is not used). The panel's
  full-screen button takes the window to full screen and back (passes c3, c5, c8); DEMO's failed return click came
  while a redraw took 300 ms.
- **Full screen (AppKit 0362).** The strip is hidden in full screen, slides in over the picture while the pointer is
  at the top edge and goes when it leaves (pass c3: captures with the pointer in the middle, at the top, away);
  `+[NSWindow _sfMenuStripFullScreenModeForOptions:]` gives auto-hide for macOS's default full-screen options, hidden
  for `NSApplicationPresentationHideMenuBar`, kept for options without a menu-bar bit (the conformance program on the
  M1, private prefix). In full screen the picture is shown 17-20 times a second (passes c8, c9), against 28-29 in a
  window: QuickTime's main thread is three quarters idle there, its commits come every ~49 ms and the desk shows one
  in four refreshes; the window's buffer is 2561x1601 pixels for a 2560x1600 output (AppKit's full-screen frame is
  1707.33 points, its backing store whole pixels of whole points). On the compositor's next build (DESKPERF's, 16:4xZ)
  full screen shows 27 a second (pass ab-a: 273 commits, 266 shown per 10 s). After leaving full screen the window was
  2556x1550 pixels instead of 2556x1475, over the desk's bottom bar: the panel's buttons acted on the press, so the
  window left full screen under the held button and the release landed on its new top edge, which the desk took as
  the end of a resize by 50 points (WindowServer trace: size limits unchanged, button up above the window, then the
  taller configure). The panel's buttons now act on the release over the same button, as buttons do, and the window
  keeps its size (pass t1: 2556x1475 before and after).
- **For the compositor's owner (desk side, not changed here).** Each full-window commit of QuickTime's window
  costs the desk's commit handler 12.6 ms (`WMPACING ... commit handler`, 2556x1437 px of shared memory per
  picture, about 30 a second: ~380 ms of the desk's time each second). Between 7 and 104 of ~300 commits per 10 s
  were replaced before any flip showed them, depending on the run. A path without that copy, for this player and
  any CPU-drawn video: the picture handed to the desk as a dma-buf (a subsurface for the video, or the whole-window
  GPU presenter that Firefox's windows use, 0209w), or the desk uploading only the damaged rows.
- **The About panel (QTP2, AppKit 0364).** It showed nothing ("Cannot load NSSystemInfoPanel.nib": the installed
  AppKit has none of its nibs). QuickTime Player also replaces `-showInfoPanel:` and `-windowWillClose:` of AppKit's
  `NSSystemInfoPanel`, reads its `copyrightView` and `_optionsDictionary` by offset and calls `-loadNib` and
  `-unloadNib:`, as macOS's class has them. 0364 gives the class those (the nib, Cocotron's own from this tree, loaded
  when the panel is shown and let go when it closes; the options kept and applied), and the recipe installs the nib.
  On the M1 (private prefix, passes a1, a2): the panel shows QuickTime Player's icon, name, "10.5 (1252.3)" and its
  copyright; it closes and opens again; 16 s later (QuickTime's own timer re-lays it out) it is unchanged and nothing
  failed; the load-time warning about the missing variables is gone. Its text is drawn in a serif face (the nib's
  font is not installed: the general font fallback). Apple's Terminal and Activity Monitor have not been tried with
  it (QTP2 launches only its own QuickTime Player): for the guarded install's lifecycle set.
- **Open Recent (QTP2: libFoundation 0365, AppKit 0366 and 0367).** It showed only "Clear Menu". QuickTime Player keeps
  its recent documents as URL bookmarks (refused here until 0365, which makes and resolves them as macOS's API does:
  by the path, stale when another file is there, no lookup by file ID) and fills the menu by overriding
  NSDocumentController's private `-_populateOpenRecentMenu:includingIcons:`, `-_depopulateOpenRecentMenu:` and
  `-_installOpenRecentMenus`; it is the delegate of its own Export menu only. 0366 has the shared controller fill
  every menu named `_NSRecentDocumentsMenu` each time it shows (`-[NSMenu update]`) and gives `+[NSMenu
  _menusWithName:]`; QuickTime's titles then sent `-setBaseWritingDirection:range:` to a string Foundation made, which
  is an `NSAttributedString` object even when mutable, so AppKit's categories of `NSMutableAttributedString` never
  answered: 0367 gives those methods to the bridged strings too. On the M1 (passes t2, t3): the menu lists the two
  movies opened before, and choosing one opens it in a second window. Bookmarks: the conformance program's nine checks
  pass on the M1.
- **Open.** The playback-speed menu: the staged player plays at rate 1 only, on purpose (no time-stretched sound);
  speeds need time-stretched sound in the player, a larger piece of work not started. Sharing and AirPlay buttons
  (absent), subtitles and alternative audio (absent), trimming.

## Recorded cadence recovery (18 November, DESKPERF)

The 30 Hz player timer was firing, but direct use of the output queue's stepped
audio position selected repeated pictures followed by skipped pictures. An M1
trace measured 29.998 timer calls/s and only 18.366 distinct picture indices/s;
the counter advanced in 1024/48000-second steps. Flooring those observations
to movie PTS reproduced the loss. The compositor was showing almost every
commit and the recorder reported no buffer or GPU losses.

`finch/AVFoundation/player/SFPlaybackClock.h` now advances a continuous
monotonic clock while keeping it within 40 ms of the audio counter. It freezes
through stalled output and resets for pause/resume, queue replacement and
seeks. The source-built candidate ran from a separate private library overlay;
the existing QuickTime prefix and compositor were preserved.

On the M1, original BBB playback with the candidate produced 300 commits and
300 shown per ten seconds, including with the recorder. A separate BBB-derived
test clip carried a machine-readable picture counter to distinguish actual
movie changes from dock redraws and lossy compression differences. Without a
diagnostic interposer, its eight-second recordings contained 241 consecutive
picture changes (30.124/s) windowed and 240 (29.999/s) full screen, with no
skipped source pictures; 97.93% and 98.75% of changes were two refreshes apart.
Input was synthetic on the virtual seat. This is recording/trace evidence,
not a physical panel or acoustic witness.

Pause/resume and forward seeking were exercised in a 95-second original-BBB
trace. A second pass sought forward to 120 seconds, back to 15 seconds, and
resumed after holding the picture and audio position constant while paused.
The corrected clock stayed within -31.1 to +33.9 ms of the queue counter
across the two passes. Seeking had a temporary late picture while the reader settled; these
transition samples are separate from steady playback. Host regression covers
128 counter phases, drift, stalls, pause/resume, seeks and clock discontinuities.

## General pieces for the system install
These are corrections or additions any application can meet; they live in the private prefix until the
guarded install: libFoundation 0347, 0348, 0349, 0352, 0354, 0355, 0359, 0361; AppKit 0340, 0341, 0350,
0351, 0353, 0356, 0357, 0358, 0360, 0362 (in full screen the menu strip auto-hides as macOS's menu bar does: a
change every application on the desk sees, to be checked with Firefox, Terminal and Activity Monitor first), 0364 with the
About panel's nib installed among AppKit's resources (`patched.nix`: every application's About panel failed with "Cannot
load NSSystemInfoPanel.nib", the recipe installed only the string tables), 0366 (the Open Recent menu filled by the
document controller each time it shows), 0367 (AppKit's methods for mutable attributed strings answered by Foundation's
bridged strings too); libFoundation 0365 (NSURL bookmarks); Onyx2D 0363 (an opaque image drawn within two pixels of its own size on
device pixels is copied, not resampled: every application that draws such an image, through the guarded install
only, to be checked with Firefox, Terminal and Activity Monitor; `O2_NO_IMAGE_FAST_PATH=1` turns it off and
`O2_IMAGE_TRACE=1` says why an image was resampled); CoreGraphics 0342; QuartzCore 0343-0345; CoreAudio 0346; the URL key
names and NSFileCoordinator in the framework wrappers. QuickTime Player's own prefix keeps only what is
its alone (the additions, the private frameworks' absences, the AVKit and AVFoundation stages).

## The 112 names
Kinds: **real** (implemented), **constant**, **model** (holds what it is given; nothing in the system acts on
it yet), **absence** (binds; when used it fails as its interface documents, or does nothing it cannot do
properly, and says so once on stderr as `SiliconForest: ...` or `AVKit: ...`). **Provided by**: where the name
lives on a system with the Cocoa patches 0340-0347 and the current framework wrappers. 28 of the 112 have moved
into the frameworks ("Names moved into the frameworks"); on a system without those frameworks (the M1 as installed
on 18 November) the full additions still supply them (`additions.nix { movedInFrameworks = false; }`). Source:
`integrations/siliconforest/finch/QuickTime/additions/` and `finch/AVKit/SFQuickTimeControls.m`; the same
table as data is `additions/symbols.json`. For every name, whether QuickTime Player binds it as code or as
data was read from the binary and matches what is supplied.

| Library | Name | Kind | Provided by | What it is |
|---|---|---|---|---|
| AppKit | `NSEnabledBinding` | constant | AppKit 0340 | documented value |
|  | `NSFontTextStyleCaption1` | constant | AppKit 0340 | value believed correct, to be compared on macOS (conformance/qtp-names.m); +[NSFont preferredFontForTextStyle:options:] gives the font |
|  | `NSFontTextStyleLargeTitle` | constant | AppKit 0340 | value believed correct, to be compared on macOS (conformance/qtp-names.m); +[NSFont preferredFontForTextStyle:options:] gives the font |
|  | `NSFontTextStyleTitle1` | constant | AppKit 0340 | value believed correct, to be compared on macOS (conformance/qtp-names.m); +[NSFont preferredFontForTextStyle:options:] gives the font |
|  | `NSFontTextStyleTitle3` | constant | AppKit 0340 | value believed correct, to be compared on macOS (conformance/qtp-names.m); +[NSFont preferredFontForTextStyle:options:] gives the font |
|  | `NSHiddenBinding` | constant | AppKit 0340 | documented value |
|  | `NSImageNameToolbarBookmarks` | constant | QuickTime additions | private name; value inferred; nothing in the system acts on it |
|  | `NSRecentDocumentsMenuName` | constant | QuickTime additions | private name; value inferred; nothing in the system acts on it |
|  | `NSTitleBinding` | constant | AppKit 0340 | documented value |
|  | `NSToolTipBinding` | constant | AppKit 0340 | documented value |
|  | `NSWindowWillOrderOnScreenNotification` | constant | QuickTime additions | private name; value inferred; nothing in the system acts on it |
|  | `class NSClickGestureRecognizer` | absence | AppKit 0340 | keeps its configuration, recognises no clicks |
|  | `instance variable NSSystemInfoPanel._optionsDictionary` | absence | QuickTime additions | our class has no such variable: offset 0, said at load; the About panel will fail until AppKit gains it |
|  | `instance variable NSSystemInfoPanel.copyrightView` | real | QuickTime additions | resolved at load to our About panel class's copyright field (legalTextField) |
| AVFoundation | `class AVAssetCollection` | absence | QuickTime additions | cannot be created (nil) |
|  | `class AVAssetExportSession` | absence | QuickTime additions | every export session fails; no preset is compatible |
|  | `class AVAssetImageGenerator` | absence | QuickTime additions | every image request fails with an error |
|  | `class AVAssetReaderAudioMixOutput` | absence | QuickTime additions | cannot be created (nil) |
|  | `class AVCaptureAudioFileOutput` | absence | QuickTime additions | cannot be created (nil) |
|  | `class AVCaptureAudioPreviewOutput` | absence | QuickTime additions | cannot be created (nil) |
|  | `class AVCaptureConnection` | absence | QuickTime additions | cannot be created (nil) |
|  | `class AVCaptureMovieFileOutput` | absence | QuickTime additions | cannot be created (nil) |
|  | `class AVComposition` | absence | QuickTime additions | an empty composition; editing calls fail with an error |
|  | `class AVMutableAudioMix` | model | QuickTime additions | kept as given; the staged player does not apply it |
|  | `class AVMutableAudioMixInputParameters` | model | QuickTime additions | kept as given; the staged player does not apply it |
|  | `class AVMutableComposition` | absence | QuickTime additions | an empty composition; editing calls fail with an error |
|  | `class AVMutableVideoComposition` | model | QuickTime additions | kept as given; the staged player does not apply it |
|  | `class AVMutableVideoCompositionInstruction` | model | QuickTime additions | kept as given; the staged player does not apply it |
|  | `class AVMutableVideoCompositionLayerInstruction` | model | QuickTime additions | kept as given; the staged player does not apply it |
|  | `class AVTimeFormatter` | real | QuickTime additions | formats seconds and CMTime as [H:]MM:SS; other styles unknown |
|  | `metaclass AVCaptureAudioPreviewOutput` | absence | QuickTime additions | cannot be created (nil) |
| CoreMedia | `CMVideoFormatDescriptionGetVideoDynamicRange` | absence | QuickTime additions | dynamic range is not classified (0) |
|  | `FigAudioFormatDescriptionGetRichestDecodableFormatAndChannelLayout` | absence | QuickTime additions | arguments not established; returns -12782, writes nothing |
|  | `FigVideoFormatDescriptionContainsAlphaChannel` | real | QuickTime additions | reads the description's public alpha-channel extension |
| CoreAudio | `AudioObjectAddPropertyListenerBlock` | real | CoreAudio 0346 | over the function-pointer listener; the block runs on the given queue |
| Foundation | `NSAppleScriptErrorBriefMessage` | constant | QuickTime additions | documented value |
|  | `NSKeyedArchiveRootObjectKey` | constant | QuickTime additions | documented value |
|  | `NSLocalizedFileSizeDescription` | absence | QuickTime additions | arguments not established; returns nil |
|  | `NSMetadataItemPixelHeightKey` | constant | QuickTime additions | documented value |
|  | `NSMetadataItemPixelWidthKey` | constant | QuickTime additions | documented value |
|  | `class NSAppleScript` | absence | QuickTime additions | no AppleScript runtime: scripts fail with error -1753 |
|  | `class NSFileCoordinator` | real | Foundation wrapper | single process: the accessor runs at once; presenters are kept |
|  | `class NSFileWrapper` | real | QuickTime additions | this system's own class, from AppKit, re-exported: one class in the process; its URL interface is cocoa patch 0341 (on a system without it, initWithURL:options:error: is missing) |
|  | `class NSMetadataItem` | absence | QuickTime additions | no Spotlight store: no item can be made |
|  | `class NSNameSpecifier` | model | QuickTime additions | holds container, key and name; nothing evaluates it |
|  | `_NSFullMethodName` | real | QuickTime additions | "-[Class selector]" for a receiver and selector |
| MediaToolbox | `FigAssetCreateWithURL` | absence | QuickTime additions | arguments not established; returns -12782, writes nothing |
| WebKit | `class WKWebsiteDataStore` | absence | QuickTime additions | no web engine: no data store (nil) |
| VideoToolbox | `VTCopyVideoDecoderExtensionProperties` | real | QuickTime additions | truthful capability answers (SF-AB): no extension decoder, no stereo decode |
|  | `VTIsStereoMVHEVCDecodeSupported` | real | QuickTime additions | truthful capability answers (SF-AB): no extension decoder, no stereo decode |
| Security | `SecCodeMapMemory` | absence | QuickTime additions | errSecUnimplemented |
|  | `SecKeychainItemFreeContent` | absence | QuickTime additions | errSecUnimplemented |
|  | `SecRequirementCreateWithData` | absence | QuickTime additions | errSecUnimplemented |
| AVFAudio | `class AVAudioRoutingArbiter` | real | QuickTime additions | no other devices to arbitrate with: completes at once, device unchanged |
|  | `class AVAudioSession` | absence | QuickTime additions | each request is refused with an error |
| CoreFoundation | `NSURLContentModificationDateKey` | constant | CoreFoundation wrapper 0347 | the key is its own name |
|  | `NSURLEffectiveIconKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; no icon is given (Foundation has none) |
|  | `NSURLFileResourceIdentifierKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; libFoundation answers it (cocoa patch 0347) |
|  | `NSURLFileSizeKey` | constant | CoreFoundation wrapper 0347 | the key is its own name |
|  | `NSURLHasHiddenExtensionKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; libFoundation answers it (cocoa patch 0347) |
|  | `NSURLIsVolumeKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; libFoundation answers it (cocoa patch 0347) |
|  | `NSURLNameKey` | constant | CoreFoundation wrapper 0347 | the key is its own name |
|  | `NSURLParentDirectoryURLKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; libFoundation answers it (cocoa patch 0347) |
|  | `NSURLVolumeIsReadOnlyKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; libFoundation answers it (cocoa patch 0347) |
|  | `NSURLVolumeNameKey` | constant | CoreFoundation wrapper 0347 | the key is its own name; libFoundation answers it (cocoa patch 0347) |
| CoreGraphics | `CGGetDisplaysWithRect` | real | CoreGraphics 0342 | over the display list |
|  | `CGSAddWindowsToSpaces` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSCopySpaces` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSHideSpaces` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSIsZoomed` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRegisterConnectionNotifyProc` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRemoveConnectionNotifyProc` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRemoveHotKey` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRemoveWindowsFromSpaces` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSetHotKey` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSetHotKeyEnabled` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSShowSpaces` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSpaceCreate` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSpaceDestroy` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSpaceSetAbsoluteLevel` | absence | QuickTime additions | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
| CoreImage | `class CIRenderDestination` | absence | QuickTime additions | cannot be created (nil) |
| CoreServices | `LSSharedFileListCopyProperty` | absence | QuickTime additions | shared file lists keep no properties; unimpErr or NULL |
|  | `LSSharedFileListRemoveAllItems` | absence | QuickTime additions | shared file lists keep no properties; unimpErr or NULL |
|  | `LSSharedFileListSetProperty` | absence | QuickTime additions | shared file lists keep no properties; unimpErr or NULL |
|  | `_CSDeviceSupportsAirDrop` | real | QuickTime additions | false: this machine has no AirDrop |
|  | `_MDItemMarkAsUsedWithURL` | absence | QuickTime additions | no Spotlight store; the use is not recorded |
|  | `_kLSSharedFileListItemBeforeFirst` | constant | QuickTime additions | private name; value inferred; nothing in the system acts on it |
|  | `_kLSSharedFileListRecentDocumentItems` | constant | QuickTime additions | private name; value inferred; nothing in the system acts on it |
|  | `_kLSSharedFileListRecentItemsMaxAmount` | constant | QuickTime additions | private name; value inferred; nothing in the system acts on it |
|  | `kLSSharedFileListApplicationRecentDocuments` | constant | QuickTime additions | value believed correct, not verified against macOS |
|  | `kUTTypeAudiovisualContent` | constant | QuickTime additions | documented value |
|  | `kUTTypeQuickTimeMovie` | constant | QuickTime additions | documented value |
| CoreText | `CTFontDescriptorGetTextStyleSize` | absence | QuickTime additions | arguments not established; returns 0 |
|  | `kCTFontContentSizeCategoryL` | constant | QuickTime additions | value believed correct, not verified against macOS |
| ImageIO | `kCGImagePropertyDepth` | constant | QuickTime additions | documented value |
|  | `kCGImagePropertyHasAlpha` | constant | QuickTime additions | documented value |
| QuartzCore | `class CAConstraint` | real | QuartzCore 0345 | constraint value object |
|  | `class CAConstraintLayoutManager` | real | QuartzCore 0345 | lays sublayers out by their constraints; CALayer asks its layout manager |
|  | `class CAFilter` | model | QuickTime additions | keeps type and parameters; the compositor applies no filters |
|  | `class CAKeyframeAnimation` | real | QuartzCore 0344 | interpolated by the renderer for opacity, position, anchor point and bounds; paced and cubic drawn as linear, paths not followed |
|  | `class CATextLayer` | real | QuartzCore 0343 | draws its string with CoreText: wrapping, truncation, alignment |
|  | `class CATiledLayer` | real | QuickTime additions | an ordinary layer that remembers its tiling parameters; drawn whole |
|  | `kCAAlignmentCenter` | constant | QuartzCore 0343 | documented value |
|  | `kCAFilterDestOut` | constant | QuickTime additions | documented value |
|  | `kCATruncationMiddle` | constant | QuartzCore 0343 | documented value |
| AVKit | `AVAddAudibleMediaSelectionOptionsToMenu` | absence | staged AVKit | menu left unchanged; track selection does not reach the player |
|  | `AVAddLegibleMediaSelectionOptionsToMenu` | absence | staged AVKit | menu left unchanged; track selection does not reach the player |
|  | `class AVPlayerControllerTimeResolver` | real | staged AVKit | holds the values our probes saw it hold and seeks the controller; not notification-exact |
|  | `class AVPlayerControlsViewController` | absence | staged AVKit | base class for the application's edit controller: an empty view and the player controller; no built-in controls |
|  | `class AVTouchBarRecordingControlsProvider` | absence | staged AVKit | no Touch Bar items for recording (nil) |
|  | `class AVVolumeControlSlider` | real | staged AVKit | a working slider with mute, delegate callbacks and key-view loop |
|  | `metaclass AVPlayerControlsViewController` | absence | staged AVKit | base class for the application's edit controller: an empty view and the player controller; no built-in controls |

Not in any import table but needed by a nib: `AVAudioView` (the audio-only document's view) exists in the
staged AVKit as a placeholder panel that says so; its real interface is unknown.

Superclasses the application subclasses: `AVPlayerView` (Finch's, over our staged player), `AVCaptureView`
(exists; creation returns nil, there is no capture), `AVPlayerControlsViewController` (above),
`AVCaptureAudioPreviewOutput` (above).

## The load test
Prepared in the lab's run directory (outside git): a bundle of the staged libraries, the probe program
(`additions-probe.m`, built by `additions-probe.nix`) and the unmodified application; one command sends it to
a fresh private directory on the M1 and runs three steps there: assemble the prefix against the machine's
own libraries, run the probe (154 symbol lookups through the real dyld and about 25 behaviour checks,
no window), then start the application with the prefix's environment for 20 seconds and stop exactly that
process. The report classifies the outcome: a missing library, the first unbound symbol, or "past dyld"
with the list of absences the application actually used and the selectors nothing answered.

What the offline numbers cannot say, and the test will:
- The scan root is two days older than the M1's disk. AppKit, Foundation, CoreGraphics, QuartzCore and
  CoreText have changed since; some of the 112 names may exist there now (reported, and then left out), and
  the count of unanswered selectors will be lower.
- The staged AVFoundation and AVKit are linked against the build's base libraries; a symbol they need that
  the current system lacks would stop the load in one of our libraries, not in the application.
- Placing a library of ours in front of CoreFoundation, Foundation and AppKit for one process now works for
  our probe ("What the first run on the machine found"); the application itself has not been loaded.
- Nothing here was run in QEMU either: the QEMU image has neither the media frameworks nor these stages, and
  building such an image was left for when it is needed. The workstation proves linking and export tables only.

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
- **Additions in front of core frameworks.** Works for our probe since the install-name change; the application
  binds far more through them, and the first launch tells whether anything else in dyld or the runtime minds.
- **arm64e.** The slice uses pointer authentication; SiliconForest already runs arm64e Apple binaries (Terminal,
  Activity Monitor), so this is a known path, not a new one.

## What exists in the tree for this ticket
| Path | What |
|---|---|
| `integrations/siliconforest/finch/QuickTime/loader.nix`, `loader/` | the six loader libraries (SwiftUI binding subset, DeveloperToolsSupport, Swift `os`, QuickLook, QuickLookUI, Quartz), the names bound from them, `check_exports.py` |
| `finch/QuickTime/additions.nix`, `additions/` | the additions libraries for 17 frameworks, their sources, `symbols.json` (the table above as data) |
| `finch/AVKit/SFQuickTimeControls.m` | the rest of AVKit's names: controls view controller, time resolver, volume slider, Touch Bar provider, menu builders, `AVAudioView` |
| `finch/QuickTime/qt_prefix.py` | assembles the private prefix; reports names the system has gained |
| `finch/QuickTime/additions-probe.m`, `additions-probe.nix` | our probe program for the prefix, to run on SiliconForest |
| `finch/QuickTime/loader-check.nix`, `additions-check.nix` | static checks: 42 of 42 loader names; the full additions 112 of 112, the shrunk additions 82 of 82 and the frameworks 30 of 30 (with AppKit 0364), each from the right library (pass; nothing is run) |
| `tests/test_quicktime_loader.py` | unit tests of the export check, the symbol table and the prefix assembler, on synthetic input |
| `terminal-app/build-swift-runtime-cgfloat.nix` | proposal: CGFloat in the Swift CoreFoundation overlay |
| `cocoa/patches/0340-…0347-…` | the names moved into AppKit, CoreGraphics, QuartzCore, CoreAudio and libFoundation |
| `terminal-app/compat/CoreFoundation.m`, `Foundation.m` | the URL key names and `NSFileCoordinator`, in the framework wrappers |
| `cocoa/conformance/qtp-names.m` | no-window conformance program for the moved names (builds here and on macOS; not yet run) |
| `finch/QuickTime/` (rest), `finch/AVKit/`, `finch/AVFoundation/player/`, `finch/MediaToolbox/` | SF-AB's staged providers this ticket builds on |

Reproduce the scan: build `loader.nix` and SF-AB's stages, then run `sf_gapscan.py --root <copy of the
system libraries> --overlay <each stage> --app "<QuickTime Player.app>=/System/Applications/QuickTime Player.app"
--arch arm64e`. The full output (import lists, class maps, nib class lists) stays outside git.

## Next steps
1. Run the load test on the M1. Read the verdict against "The 112 names"; fix what the real dyld and the
   current system disagree about. That closes stage 0.
2. Stage 1 from what the application then does: the absences it reports using first are the work list.
3. Our own small document-based test application that opens a movie in an `AVPlayerView` window through the
   same calls QuickTime Player makes, so that stages 2 to 4 are proven with our code before Apple's binary
   meets them.
4. The private messages to `AVPlayerView` (about seventy) and `AVAudioView`'s interface: observe them with our
   metadata probe, as was done for the other private AVKit classes, before writing them.
