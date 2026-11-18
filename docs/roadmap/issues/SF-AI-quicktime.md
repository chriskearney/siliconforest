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

## State (18 November 2026, afternoon)
**Not launched.** No window has been opened and the application has not been started on this system yet.
What has now run on the M1 is our own probe against the private prefix, without a window:

- **All 154 names the prefix supplies are found by the real dyld** in the libraries the application binds
  them from (the 112 additions and the 42 of the loader libraries), and every behaviour check of the probe
  passes (file coordination, time formatting, export failing as documented, constraint layout, the time
  resolver, the class hierarchies the application subclasses, display lookup, the "no Spaces"/"no AirDrop"
  answers). Each system image is loaded exactly once; no class is defined twice.
- **The first attempt crashed, and why is understood** ("What the first run on the machine found").
- Offline, against the 15 November copy of the M1's libraries, the static scan still finds all 965 of the
  application's imports bound. That remains a prediction until the application is loaded.

Of the 112 names added last, 17 are real implementations, 37 are constants, 9 are models that hold values
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

## The 112 names
Kinds: **real** (implemented), **constant**, **model** (holds what it is given; nothing in the system acts on
it yet), **absence** (binds; when used it fails as its interface documents, or does nothing it cannot do
properly, and says so once on stderr as `SiliconForest: ...` or `AVKit: ...`). Source:
`integrations/siliconforest/finch/QuickTime/additions/` and `finch/AVKit/SFQuickTimeControls.m`; the same
table as data is `additions/symbols.json`. For every name, whether QuickTime Player binds it as code or as
data was read from the binary and matches what is supplied.

| Library | Name | Kind | What it is here |
|---|---|---|---|
| AppKit | `NSEnabledBinding` | constant | documented value |
|  | `NSFontTextStyleCaption1` | constant | value believed correct, not verified against macOS |
|  | `NSFontTextStyleLargeTitle` | constant | value believed correct, not verified against macOS |
|  | `NSFontTextStyleTitle1` | constant | value believed correct, not verified against macOS |
|  | `NSFontTextStyleTitle3` | constant | value believed correct, not verified against macOS |
|  | `NSHiddenBinding` | constant | documented value |
|  | `NSImageNameToolbarBookmarks` | constant | private name; value inferred; nothing in the system acts on it |
|  | `NSRecentDocumentsMenuName` | constant | private name; value inferred; nothing in the system acts on it |
|  | `NSTitleBinding` | constant | documented value |
|  | `NSToolTipBinding` | constant | documented value |
|  | `NSWindowWillOrderOnScreenNotification` | constant | private name; value inferred; nothing in the system acts on it |
|  | `class NSClickGestureRecognizer` | absence | keeps its configuration, recognises no clicks |
|  | `instance variable NSSystemInfoPanel._optionsDictionary` | absence | our class has no such variable: offset 0, said at load; the About panel will fail until AppKit gains it |
|  | `instance variable NSSystemInfoPanel.copyrightView` | real | resolved at load to our About panel class's copyright field (legalTextField) |
| AVFoundation | `class AVAssetCollection` | absence | cannot be created (nil) |
|  | `class AVAssetExportSession` | absence | every export session fails; no preset is compatible |
|  | `class AVAssetImageGenerator` | absence | every image request fails with an error |
|  | `class AVAssetReaderAudioMixOutput` | absence | cannot be created (nil) |
|  | `class AVCaptureAudioFileOutput` | absence | cannot be created (nil) |
|  | `class AVCaptureAudioPreviewOutput` | absence | cannot be created (nil) |
|  | `class AVCaptureConnection` | absence | cannot be created (nil) |
|  | `class AVCaptureMovieFileOutput` | absence | cannot be created (nil) |
|  | `class AVComposition` | absence | an empty composition; editing calls fail with an error |
|  | `class AVMutableAudioMix` | model | kept as given; the staged player does not apply it |
|  | `class AVMutableAudioMixInputParameters` | model | kept as given; the staged player does not apply it |
|  | `class AVMutableComposition` | absence | an empty composition; editing calls fail with an error |
|  | `class AVMutableVideoComposition` | model | kept as given; the staged player does not apply it |
|  | `class AVMutableVideoCompositionInstruction` | model | kept as given; the staged player does not apply it |
|  | `class AVMutableVideoCompositionLayerInstruction` | model | kept as given; the staged player does not apply it |
|  | `class AVTimeFormatter` | real | formats seconds and CMTime as [H:]MM:SS; other styles unknown |
|  | `metaclass AVCaptureAudioPreviewOutput` | absence | cannot be created (nil) |
| CoreMedia | `CMVideoFormatDescriptionGetVideoDynamicRange` | absence | dynamic range is not classified (0) |
|  | `FigAudioFormatDescriptionGetRichestDecodableFormatAndChannelLayout` | absence | arguments not established; returns -12782, writes nothing |
|  | `FigVideoFormatDescriptionContainsAlphaChannel` | real | reads the description's public alpha-channel extension |
| CoreAudio | `AudioObjectAddPropertyListenerBlock` | real | over the function-pointer listener; the block runs on the given queue |
| Foundation | `NSAppleScriptErrorBriefMessage` | constant | documented value |
|  | `NSKeyedArchiveRootObjectKey` | constant | documented value |
|  | `NSLocalizedFileSizeDescription` | absence | arguments not established; returns nil |
|  | `NSMetadataItemPixelHeightKey` | constant | documented value |
|  | `NSMetadataItemPixelWidthKey` | constant | documented value |
|  | `class NSAppleScript` | absence | no AppleScript runtime: scripts fail with error -1753 |
|  | `class NSFileCoordinator` | real | single process: the accessor runs at once; presenters are kept |
|  | `class NSFileWrapper` | real | this system's own class, from AppKit (Cocotron), re-exported: one class in the process; it lacks initWithURL:options:error: |
|  | `class NSMetadataItem` | absence | no Spotlight store: no item can be made |
|  | `class NSNameSpecifier` | model | holds container, key and name; nothing evaluates it |
|  | `_NSFullMethodName` | real | "-[Class selector]" for a receiver and selector |
| MediaToolbox | `FigAssetCreateWithURL` | absence | arguments not established; returns -12782, writes nothing |
| WebKit | `class WKWebsiteDataStore` | absence | no web engine: no data store (nil) |
| VideoToolbox | `VTCopyVideoDecoderExtensionProperties` | real | truthful capability answers (SF-AB): no extension decoder, no stereo decode |
|  | `VTIsStereoMVHEVCDecodeSupported` | real | truthful capability answers (SF-AB): no extension decoder, no stereo decode |
| Security | `SecCodeMapMemory` | absence | errSecUnimplemented |
|  | `SecKeychainItemFreeContent` | absence | errSecUnimplemented |
|  | `SecRequirementCreateWithData` | absence | errSecUnimplemented |
| AVFAudio | `class AVAudioRoutingArbiter` | real | no other devices to arbitrate with: completes at once, device unchanged |
|  | `class AVAudioSession` | absence | each request is refused with an error |
| CoreFoundation | `NSURLContentModificationDateKey` | constant | the key is its own name |
|  | `NSURLEffectiveIconKey` | constant | the key is its own name |
|  | `NSURLFileResourceIdentifierKey` | constant | the key is its own name |
|  | `NSURLFileSizeKey` | constant | the key is its own name |
|  | `NSURLHasHiddenExtensionKey` | constant | the key is its own name |
|  | `NSURLIsVolumeKey` | constant | the key is its own name |
|  | `NSURLNameKey` | constant | the key is its own name |
|  | `NSURLParentDirectoryURLKey` | constant | the key is its own name |
|  | `NSURLVolumeIsReadOnlyKey` | constant | the key is its own name |
|  | `NSURLVolumeNameKey` | constant | the key is its own name |
| CoreGraphics | `CGGetDisplaysWithRect` | real | over the display list |
|  | `CGSAddWindowsToSpaces` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSCopySpaces` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSHideSpaces` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSIsZoomed` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRegisterConnectionNotifyProc` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRemoveConnectionNotifyProc` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRemoveHotKey` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSRemoveWindowsFromSpaces` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSetHotKey` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSetHotKeyEnabled` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSShowSpaces` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSpaceCreate` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSpaceDestroy` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
|  | `CGSSpaceSetAbsoluteLevel` | absence | no window-server Spaces, hot keys or connection notifications; shapes from the community CGSInternal headers |
| CoreImage | `class CIRenderDestination` | absence | cannot be created (nil) |
| CoreServices | `LSSharedFileListCopyProperty` | absence | shared file lists keep no properties; unimpErr or NULL |
|  | `LSSharedFileListRemoveAllItems` | absence | shared file lists keep no properties; unimpErr or NULL |
|  | `LSSharedFileListSetProperty` | absence | shared file lists keep no properties; unimpErr or NULL |
|  | `_CSDeviceSupportsAirDrop` | real | false: this machine has no AirDrop |
|  | `_MDItemMarkAsUsedWithURL` | absence | no Spotlight store; the use is not recorded |
|  | `_kLSSharedFileListItemBeforeFirst` | constant | private name; value inferred; nothing in the system acts on it |
|  | `_kLSSharedFileListRecentDocumentItems` | constant | private name; value inferred; nothing in the system acts on it |
|  | `_kLSSharedFileListRecentItemsMaxAmount` | constant | private name; value inferred; nothing in the system acts on it |
|  | `kLSSharedFileListApplicationRecentDocuments` | constant | value believed correct, not verified against macOS |
|  | `kUTTypeAudiovisualContent` | constant | documented value |
|  | `kUTTypeQuickTimeMovie` | constant | documented value |
| CoreText | `CTFontDescriptorGetTextStyleSize` | absence | arguments not established; returns 0 |
|  | `kCTFontContentSizeCategoryL` | constant | value believed correct, not verified against macOS |
| ImageIO | `kCGImagePropertyDepth` | constant | documented value |
|  | `kCGImagePropertyHasAlpha` | constant | documented value |
| QuartzCore | `class CAConstraint` | real | constraint value object |
|  | `class CAConstraintLayoutManager` | real | lays sublayers out by their constraints, if our layers carry any |
|  | `class CAFilter` | model | keeps type and parameters; the compositor applies no filters |
|  | `class CAKeyframeAnimation` | model | keeps its keyframes; not interpolated by our QuartzCore |
|  | `class CATextLayer` | model | keeps text and attributes; not drawn by our QuartzCore |
|  | `class CATiledLayer` | real | an ordinary layer that remembers its tiling parameters; drawn whole |
|  | `kCAAlignmentCenter` | constant | documented value |
|  | `kCAFilterDestOut` | constant | documented value |
|  | `kCATruncationMiddle` | constant | documented value |
| AVKit | `AVAddAudibleMediaSelectionOptionsToMenu` | absence | menu left unchanged; track selection does not reach the player |
|  | `AVAddLegibleMediaSelectionOptionsToMenu` | absence | menu left unchanged; track selection does not reach the player |
|  | `class AVPlayerControllerTimeResolver` | real | holds the values our probes saw it hold and seeks the controller; not notification-exact |
|  | `class AVPlayerControlsViewController` | absence | base class for the application's edit controller: an empty view and the player controller; no built-in controls |
|  | `class AVTouchBarRecordingControlsProvider` | absence | no Touch Bar items for recording (nil) |
|  | `class AVVolumeControlSlider` | real | a working slider with mute, delegate callbacks and key-view loop |
|  | `metaclass AVPlayerControlsViewController` | absence | base class for the application's edit controller: an empty view and the player controller; no built-in controls |

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
| `finch/QuickTime/loader-check.nix`, `additions-check.nix` | static checks: 42 of 42 and 112 of 112 names exported from the right libraries (pass; nothing is run) |
| `tests/test_quicktime_loader.py` | unit tests of the export check, the symbol table and the prefix assembler, on synthetic input |
| `terminal-app/build-swift-runtime-cgfloat.nix` | proposal: CGFloat in the Swift CoreFoundation overlay |
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
