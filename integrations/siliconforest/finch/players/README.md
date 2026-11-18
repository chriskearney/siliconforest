# Third-party media target

**Resumed 17 November 2026 for VLC:** the unmodified vendor binary now starts through
`vlc/vlc-sf`; state, gap table and what is still open are in
[SF-AH](../../../../docs/roadmap/issues/SF-AH-vlc.md). The text below is the earlier record, which
used a rebuilt entry program; that approach is retired.

**Parked 2026-11-15 by owner direction:** work is reassigned to Firefox media.
Keep existing installs and evidence. Fresh VLC headless v7 and GUI v22 remain
host-prepared, unexecuted, with no queued M1 launch. No input injection.

Current bounded results and the owner-input invalidation are recorded in
[the15 November qualification](VLC-2026-11-15.md). The step history below is
retained; its earlier headless results are not a current visible-playback claim.

Verified publisher downloads are described in downloads.json: [VLC's checksum](https://get.videolan.org/vlc/3.0.24/macosx/vlc-3.0.24-arm64.dmg.sha256)
and [IINA's release page](https://iina.io/download/). DMGs, extracted apps,
bundled libraries and signatures stay in ignored private/mac-apps/third-party/.
No third-party app binaries are committed. Existing licenses remain bundled.

`fetch.py --execute` verifies published SHA256. Extract locally with Nix 7zz.
`prepare.py` requires that verified DMG and a new stage; records hashes of its
copied bundle, and copies our generated H264+AAC movie. Run sf_gapscan.py per
SF-Y against the staged app and current root plus all selected media/interface
plugins. GAPS.md preserves direct missing imports/classes/selectors by provider.
Plugin scan: runs/sffinch/player-scan-v2/vlc-plugins-live-root.md.

VLC has62 direct imports,0 missing; its loaded closure initially lacks two errno
globals and five Breakpad Mach service APIs. IINA has2202 direct imports,783
missing strong,30 missing classes and407 selectors absent throughout its closure.
VLC is the smaller target. The installed CoreMedia/CoreVideo, VideoToolbox,
Accelerate, ColorSync and CoreImage cover the listed direct imports with no
reported gaps in those providers. IINA's bundled FFmpeg gaps remain bundled
library-version issues; root media providers do not supply private libavcodec
symbols. A load/export match is not a functional playback test.

VLC plugin gaps filed to TERM6: strong AddressBook/ScriptingBridge/WebKit loads,
CAOpenGLLayer, five AppKit constants, three display fade functions plus OpenGL
acceleration query, Foundation NSAppleScript and CoreServices catalog/handler
functions. The auhal plugin has no actual missing CoreAudio import in this scan.
The four VideoToolbox field/deinterlace keys are now installed and match native
M5. Unsupported deinterlacing returns -12900/null; software fallback is required.
Standalone plugin @executable_path diagnostics must be evaluated in the real app
entry context; missing Sparkle/libvlccore paths there are not proven app gaps.

Staged attempt history:

- Original open-a returns0 but no surviving process. Direct diagnostic aborts
  before main on _sys_errlist. Own prefix-only system-compat.c builds actual
  strerror-backed tables and reexports existing libSystem; no core replacement.
- With that facade, vendor main reaches its intentional root refusal. Existing
  nobody cannot access the desktop Wayland socket. No global permissions or
  identity-return APIs were changed.
- vlc-main.nix rebuilds the public GPL upstream darwinvlc.m on Linux with the
  upstream ALLOW_RUN_AS_ROOT option. Breakpad is excluded at compile time; no
  pretend Mach crash-service success functions. Original vendor main is retained
  in each bundle. Our CFBundleExecutable selects the named rebuilt entry.
- First rebuilt entry lacked @rpath/libvlc search path; direct dyld failure is
  retained. Recipe supplies @executable_path/lib.
- Corrected Mac flags are --ignore-config and no --one-instance (not a Mac
  option in this build). Process-local SF_VLC_LOG captures original-main
  checkpoints. v8/v9 reaches libvlc_new, returns NULL, exits1; public error
  API supplies no message. These failures remain recorded.
- Upstream Darwin config_GetLibDir recognizes an executable image ending in
  VLC. The staged entry is now SiliconForest-VLC, so unchanged plugin discovery
  reaches real plugins. v10 reports missing CAOpenGLLayer (QuartzCore),
  NSImageNameNetwork (AppKit/Growl) and VT DeinterlaceMode; direct bounded run
  then exits SIGSEGV. No successful window or playback is claimed. Exact
  runtime evidence and dependency requests are filed to TERM6.

`launch.py --capture` uses open-a, local movie, own file log and same-uid
compositor capture only when its own VLC process survives. It sends no synthetic
screen input and never signals another application. Missing clicks go to TERM6
in requests-for-TERM5.md. Playback, decoded counts, HAL accepts and capture are
still unproven; open success alone is not launch/playback evidence.

REA confirmed original thin arm64 entry identity; its Mach-O utility requires
macOS and deep providers are unavailable on this Linux session. No REA execution
or decompilation claim is made. sf_gapscan and actual M1 stderr are the relevant
import/startup evidence here. Preserve failed receipts under runs/sffinch/.

A separate bounded headless control (`prepare.py --minimal-headless`,
`launch.py --headless`) retains13 actual vendor plugins, moving excluded copies
outside the app search while leaving the verified original untouched. Dummy
interface/video are explicit; auhal and avcodec remain real. Our Linux-built
entry has an opt-in20s alarm, and headless mode refuses capture. In v2 on the
M1 the real engine loaded25 modules, opened the own2s MP4 with60 H264 video
samples/95 AAC packets, instantiated avcodec decoders and exited0. These are
container/engine observations, not a qualified rendered/decoded frame count.
No player window exists in this control. AUHAL enumerated real devices but
rejected CurrentDevice272 with-10851: the retained PD unit accepted only its
0x40 default alias. A source fix for actual validated output IDs is staged under
../AudioToolbox/units; native same-byte probe passes, M1 prefix qualification is
pending. `--audio-prefix` selects only the reviewed AudioToolbox framework in
this stage's audio-prefix directory; generated CoreAudio is never staged.

With the actual retained AUHAL candidate, v3 logs analog output opened; its
video output failed because the CLI plugin selection omitted libvdummy. Its
direct run later ended SIGSEGV after main logged0, preserved as a failure.
V4 adds actual vdummy and supporting configuration modules, opt-in own-process
HAL readFrame logging and an external sf-catch direct-run trace. It receives
its first real decoded picture using vdummy, reports104448 HAL-consumed frames
in the open-a run (104960 in direct), then the direct trace exits0/no exception.
The HAL count includes device buffering/silence and is not a decoded-AAC sample
count. Neither result establishes a window or screen capture. Exact frame
statistics remain pending: the attempted rc alias does not exist on macOS;
upstream only defines it on Windows. Fresh v5 uses the actual oldrc module and
reads only its stats command through our private stage socket. No screen input,
playback-changing control or canonical provider change is involved.

V5's actual oldrc module supplies5 statistics responses. Maximum vendor counters:
video decoded121, audio decoded189, frames displayed26 and buffers played94,
with zero reported lost frames/buffers. Our fixture contains60 video samples and
95 AAC packets (independently confirmed by Linux ffprobe). The reported decoder
counters therefore are not qualified unique-source-frame counts; accounting
remains unresolved. Open-a HAL observation reaches101376 consumed frames,
and the direct sf-catch run exits0 with103936. These establish real headless
vendor decoder/output activity, not60 confirmed presented frames or a window.
AudioToolbox is now canonically installed/CLI-qualified; fresh v6 checks the
same VLC path without the AudioToolbox framework prefix. That canonical run now
passes: no framework override, same vendor counters,104448 HAL-consumed frames
in both open-a and direct runs, direct exit0/no exception and no survivors.
No GUI/capture or unique-source-frame claim; qualified.json records the limits.
