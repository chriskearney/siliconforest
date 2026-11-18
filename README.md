<h1 align="center">SiliconForest</h1>

<p align="center"><b>An open operating system on Darwin for Apple silicon. It boots natively on an M1 MacBook Pro and runs unmodified Mac apps.</b></p>

<p align="center">
  <a href="#what-is-this">What is this?</a> ·
  <a href="#gallery">Gallery</a> ·
  <a href="#status">Status</a> ·
  <a href="#hardware">Hardware</a> ·
  <a href="#safety">Safety</a> ·
  <a href="#credits-and-lineage">Credits</a> ·
  <a href="#roadmap">Roadmap</a>
</p>

![The SiliconForest desktop in the Canopy theme: Firefox showing a WebGL page, a terminal with system information, and Activity Monitor](docs/images/desktop-canopy.jpg)

> **Early, one machine, not released.** SiliconForest runs on a single 13-inch M1 MacBook Pro.
> Public source images can be built and tried in QEMU; a supported installer and binary release
> are still pending. Details under [Status](#status) and
> [Safety](#safety).

## What is this?

SiliconForest is an open-source operating system built on **Darwin**: Apple's open-source XNU
kernel with an open userland, the same foundation macOS stands on. It is a fork of
[PureDarwin](https://github.com/PureDarwin/PureDarwin), brought up on Apple silicon with
drivers ported from the [Asahi Linux](https://asahilinux.org) project, GPU acceleration
through Mesa, and the Chonkstep desktop.

Because it is Darwin, it can run software built for the Mac. Today that means exactly three
applications, all as unmodified binaries on reimplemented open-source frameworks:
**Mozilla's Firefox**, and **Apple's Terminal** and **Activity Monitor** from the author's own
copies of macOS. It is not general Mac app compatibility, and nothing of Apple's is in this
repository ([what that means](#software)).

![A ten-second preview: the desktop changing between its four themes, then Firefox playing a video and a WebGL demo](docs/images/desktop-preview.gif)

## Highlights

- 🌲 **[Boots natively on the M1 MacBook Pro](#hardware)**, from its own partition on the
  internal disk, beside macOS and Linux. No hypervisor.
- **[A GPU-accelerated desktop](#software)**: the Chonkstep Wayland compositor on the Apple
  M1 GPU, through the ported Asahi driver and Mesa, at 2560×1600 and 60 Hz.
- **[Firefox](#software)**: Mozilla's unmodified Mac build, with WebGL and GPU rendering.
- **[Hardware video decode](#hardware)**: H.264, HEVC and VP9 on the M1's video decoder.
- **[Apple's Terminal and Activity Monitor](#software)** run as unmodified binaries.
- **[Wi-Fi, keyboard, trackpad and the Touch Bar](#hardware)** work.
- **[Audio](#hardware)**: speakers with speaker protection, and the headphone jack.
- **[Four themes](#gallery)**: Clearing, Canopy, Wafer and Die Shot.

## Gallery

| | |
|---|---|
| ![Firefox playing a 1080p H.264 video on the SiliconForest desktop](docs/images/firefox-hardware-video.jpg) | ![A window's title-bar menu open over a terminal, with entries such as Maximize, Move to Space and Hide Menu Bar](docs/images/terminal-window-menu.jpg) |
| Firefox playing video through the M1's hardware decoder. Video: Big Buck Bunny © Blender Foundation, CC BY 3.0. | The window menu the desktop adds to every title bar. |
| ![The Clearing theme, a light theme with a pale forest wallpaper](docs/images/desktop-clearing.jpg) | ![The Die Shot theme, a dark theme with square window controls and a chip-layout wallpaper](docs/images/desktop-dieshot.jpg) |
| Theme: Clearing. | Theme: Die Shot. |
| ![The Wafer theme, a light theme with a wafer-pattern wallpaper, with Activity Monitor in front](docs/images/desktop-wafer-activity-monitor.jpg) | ![The Canopy theme, a dark theme with a night forest wallpaper](docs/images/desktop-canopy.jpg) |
| Theme: Wafer. | Theme: Canopy. |

Everything here was captured on the machine on 17 November 2026; the preview above is cut
from a 70-second film of that session (the film itself is not in the repository; the small
"Stop" pill at the top right is the desktop's own screen recorder). Input in the film was
synthetic test input, not someone at the keyboard.

## Status

**Early, and not released.**

- It runs on **one machine**: the author's 13-inch M1 MacBook Pro (2020; `MacBookPro17,1`,
  J293, T8103). No other Mac has been tried.
- There is **no published binary release or supported installation route** yet. The
  [public build entry](docs/BUILDING.md) produces root, boot and QEMU images.
- The public release entry built in an initially clean container with no workstation inputs,
  and its QEMU desktop accepted typed commands through a configured 1,500-second session.
  Historical bench recipes remain outside that entry: see [Building](#building).
- Things break. The filesystem driver has open defects that matter for your data
  ([Safety](#safety)).

What "works" means below: observed on that machine. Where something was only measured by a
test and never seen or heard by a person, or only recorded earlier and not re-checked for
this README, the table says so.

## Hardware

13-inch M1 MacBook Pro only.

| Area | State | Notes |
|---|---|---|
| Boot | Works | Natively, without a hypervisor, from SiliconForest's own partition on the internal NVMe, beside macOS and Linux. Linux is still the machine's default system; SiliconForest is started from it as a one-time boot choice. The disk driver can write only inside that partition. Restart works. |
| CPU | Works | All eight cores; frequency scaling, a thermal limit and fan control (measured on 11 November, not re-checked for this README). |
| Internal display | Works | 2560×1600 at 60 Hz through the display coprocessor; brightness control. |
| GPU | Works | The Asahi kernel driver ported to XNU, with Mesa's `asahi` driver: OpenGL / GLES for the compositor, WebRender and WebGL in Firefox. |
| Keyboard, trackpad | Works | Pointer, click, two-finger scrolling. Pinch and other gestures: partial. |
| Touch Bar | Works | A function and media key strip with touch. |
| Wi-Fi | Works | The built-in BCM4378 on WPA2 networks, with DHCP and name resolution. WPA3 is not done. |
| Speakers | Works | With a speaker-protection model in the kernel (ported from Asahi's speakersafetyd); it is new code driving real hardware, see [Safety](#safety). |
| Headphone jack | Works | Output and plug detection. |
| Video decode | Works | H.264, HEVC and VP9 on the M1's hardware decoder, used by Firefox. |
| Vulkan | Partial | Mesa's Honeykrisp driver passed its first tests (device listing, an off-screen triangle, `vkcube`) on 14 November; no conformance run, not re-checked since. |
| Microphones | Partial | The headset microphone records in tests. The built-in microphones deliver no signal yet. |
| Storage | Partial | Read and write on the project's own ext4 partition. The ext4 driver has known defects: writers stall during large deletes, and it has written metadata that Linux's `e2fsck` rejects (issues #59 and #61; a fix for the second is on a branch, not yet installed). |
| USB-C, Thunderbolt | Not working | Work in progress and paused: a Thunderbolt dock's PCI devices enumerate, nothing behind it is usable. |
| External displays | Not working | |
| Bluetooth | Not working | Not started beyond a plan. |
| Camera | Not working | Not started. |
| Sleep | Not working | The display blanks when idle (in tests); the machine does not suspend. |
| Power-off | Not working | Restart only. |
| Video encode | Not working | The hardware encoder port is paused. Screen recording uses a software encoder. |
| Metal | Not working | An experiment only. |

## Software

- **Chonkstep desktop.** A Wayland compositor, dock, launcher and terminal, ported to Darwin
  and rendering on the GPU. Four SiliconForest themes: Clearing, Canopy, Wafer and Die Shot.
  Keyboard shortcuts follow macOS habits. Screenshots and screen recording are built in.
- **Firefox.** Mozilla's Firefox 160 release for macOS, the unmodified bundle, running on
  SiliconForest's frameworks with GPU rendering, WebGL and hardware video decode. It is not
  in this repository; what is here is the launcher and the framework work it needed. A
  WebGL demo page reports 60 frames a second on the built-in display; ordinary scrolling
  measures a little under 60.
- **Mac apps: two of them.** Apple's Terminal and Activity Monitor run as unmodified
  binaries, from the author's own copies of macOS. That is all "runs Mac apps" means here:
  these two applications, on reimplemented open-source frameworks (PureDarwin's Cocoa stack
  with this project's patches, and frameworks adopted from the Finch project). It is not
  general Mac application compatibility, and most Mac software will not start.
  **Nothing of Apple's is in this repository**: no application, framework, font, firmware
  or SDK. You would have to supply your own copies, under whatever terms Apple gives you.
- **Command-line userland.** A Darwin shell environment with zsh; Homebrew's `brew` client
  and a number of its prebuilt packages have been run.

## How it is put together

| Layer | What it is | Where |
|---|---|---|
| Base tree | PureDarwin at one upstream revision: XNU, IOKit families, libSystem, dyld, its Cocoa reimplementation, its Nix build. Renamed to SiliconForest by one generated commit. | `integrations/siliconforest/rebase/`, `tools/sf_rename.py`, [`docs/design/siliconforest-naming.md`](docs/design/siliconforest-naming.md) |
| Drivers | Kernel extensions for the M1, most of them ports of Linux drivers from the Asahi Linux project (taken from Omacom's `linux-aurora` tree), plus OpenBSD's `bwfm` for Wi-Fi and sequences from m1n1. | `integrations/siliconforest/m1-*` |
| Graphics | Mesa's `asahi` and Honeykrisp drivers built for Darwin; a Linux-compatibility layer in the kernel that the Rust GPU driver runs on. | `m1-rust-kext`, `m1-mesa-asahi`, `m1-dcp`, `m1-vulkan` |
| Frameworks | Patches to PureDarwin's AppKit, QuartzCore, CoreText and others; media, audio and networking frameworks adopted from Finch. | `cocoa/`, `finch/`, `terminal-app/`, `firefox/` |
| Desktop | Chonkstep with its Darwin port. | `chonkstep-darwin/`, `desktop/`, `terminal-app/compositor/` |
| Boot | m1n1 as first stage, then a small second stage that loads the kernel collection from a boot partition. | `m1-native-boot/` |

The project components are built with Nix on Linux using open SDK sources. The included
Homebrew packages are pinned prebuilt bottles; this build fetches them rather than compiling
them. No Apple SDK is used.

### Building

The pinned release entry builds on **x86_64 Linux with Nix**. The complete public-input
build and a typed QEMU desktop run are recorded in [the build guide](docs/BUILDING.md).
The tested Nix version is 2.34.9.

```sh
git clone --branch build-repro https://github.com/chriskearney/siliconforest.git
cd siliconforest
nix --extra-experimental-features 'nix-command flakes' build --max-jobs 2 --cores 4 --no-link --print-out-paths \
  .#release .#qemu-image .#qemu-proof-image .#qemu-runner \
  .#root-image .#qemu-reference-image
```

`build-repro` is the public review branch. The receipt names the exact tested source
commit and records the initially clean container, public revision updates, time,
disk and memory use. A full first build takes hours; CI currently checks the source
manifest rather than compiling the whole release.

The release includes the kernel collection, boot files, open user space and desktop.
The Homebrew set comes from 64 pinned public bottles; this command does not compile
those bottles. Apple applications, acquired Mac firmware and Mozilla's application
bundle are outside the build. The [QEMU guide](docs/release/QEMU.md) runs the desktop
without acquired Mac firmware. The new M1 kernel/boot files have been built, not
installed or tested on hardware. See the build guide for the scope of reproducibility
checks and remaining installer integration.

## Safety

This is not a virtual machine. On a real Mac, SiliconForest:

- **needs its own partition**, made by shrinking macOS, and **writes boot files** to a boot
  partition, and may add an entry to the Mac's start-up picker;
- **writes to the internal disk** with a new NVMe driver. That driver refuses every write
  outside SiliconForest's own partition, and this has held on one machine; it is still new
  code next to your other systems' data;
- **has a filesystem driver with known defects** (see Storage above). Do not keep anything
  on it that you cannot lose, and do not mount its partition read-write from Linux without
  reading issue #61;
- **drives the speakers, the fan, CPU frequency and thermal limits itself**. Wrong speaker
  or thermal handling can damage hardware;
- **loads firmware** into the Wi-Fi chip and other coprocessors.

What can go wrong includes an unbootable SiliconForest, a Mac that starts in recovery mode
and needs a person in front of it, lost data on any partition, and damaged speakers. Have a
backup and a second computer. SiliconForest does not replace Apple's firmware, so Apple's
own restore from a second Mac should remain possible (not tested here); it erases the disk.

The software is provided **as is, without warranty of any kind**; see [`LICENSE`](LICENSE)
and the licences in [`LICENSES/`](LICENSES/).

## Credits and lineage

SiliconForest exists because of other people's work. The complete record, with revisions,
licences and what was taken from each, is [`NOTICE`](NOTICE); the short version:

- **[PureDarwin](https://www.puredarwin.org)** (BSD-2-Clause for its own files) is the base
  this project forks: a buildable, bootable Darwin with a Nix build, its own drivers, a
  Linux/FreeBSD compatibility layer in the kernel and a reimplementation of the Cocoa
  frameworks. SiliconForest tracks PureDarwin's upstream branch, adopts its commits with
  their authorship, and intends to send fixes back.
- **Apple's open-source releases** (Apple Public Source License 2.0 and others): XNU, the
  IOKit families, libSystem, dyld and the rest of Darwin, as PureDarwin builds them.
- **[Asahi Linux](https://asahilinux.org)** and the Linux kernel authors: the reverse
  engineering of Apple silicon and the drivers this project ports to XNU, including the
  Rust GPU driver, the display, DART, PCIe, audio, input, NVMe, video decoder and power
  drivers. They are GPL-2.0 (some files GPL-2.0 OR MIT) and are kept as such, with their
  notices. The copies ported here come from Omacom's `linux-aurora` integration tree.
- **[m1n1](https://github.com/AsahiLinux/m1n1)** (MIT), the Asahi boot loader and
  hypervisor: every early boot of this kernel ran under it, and it is still the first boot
  stage.
- **[Mesa](https://www.mesa3d.org)** (MIT): the `asahi` OpenGL driver and the Honeykrisp
  Vulkan driver.
- **OpenBSD**'s `bwfm` (ISC) by Patrick Wildt and others, with Linux's `brcmfmac`: the base
  of the Wi-Fi driver.
- **[Finch](https://github.com/calebtrueman/finch)** (MIT OR Apache-2.0): system frameworks
  adopted whole or in part, among them CoreMedia, CoreVideo, VideoToolbox, AudioToolbox,
  AVFoundation and CoreUI pieces, with Finch's notices kept.
- **Chonkstep** (GPL-3.0-only): the desktop.
- **FreeBSD** and **drm-kmod** (the LinuxKPI layer and DRM core, through PureDarwin),
  **smithay** (the compositor library), **speakersafetyd** (the speaker-protection model),
  the **aquarat** AVE driver, **Darling**'s Metal work (darling-metal, Indium), **FFmpeg**
  and **x264**, **VLC** and **cubeb**, **neofetch**, and the font projects named in
  `NOTICE`.
- **[Mozilla](https://www.mozilla.org)**: Firefox, which runs here unmodified. "Firefox" is
  Mozilla's trademark.

"Mac", "macOS" and "M1" are Apple's trademarks, used here only to say what hardware and
software this project works with. SiliconForest is not affiliated with or endorsed by Apple,
Mozilla, or any project named above.

If you see your work here credited wrongly or not at all, please open an issue: getting this
right matters to us.

## Licence

- The original SiliconForest code is under the **MIT License**: [`LICENSE`](LICENSE). What it covers and what keeps its own licence: [`LICENSING.md`](LICENSING.md).
- Ported and adopted code **keeps its own licence**, marked per file and per directory:
  GPL-2.0 for the Linux-derived drivers, GPL-3.0-only for Chonkstep and its patches,
  ISC, BSD-2-Clause, MPL-2.0, APSL-2.0, MIT OR Apache-2.0 and others.
- Full texts: [`LICENSES/`](LICENSES/). Who made what: [`NOTICE`](NOTICE) and the `NOTICE`
  file of each directory.

Some per-file licence marking is still incomplete; the open items are in
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md).

## Roadmap

Plans and state live in the issues: start at the
[Roadmap index](https://github.com/chriskearney/siliconforest/issues/23) (label `roadmap`),
which links one ticket per area and explains the shorthand the tickets use. The same material
is in [`docs/roadmap/`](docs/roadmap/). The nearest goals: a smoother Firefox (a steady 60
frames a second), the filesystem fixes, and completing the installer integration.

What must happen before this repository is called a release is in
[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md).

## Get involved

You can build the public release entry and try its desktop in QEMU with the commands
[above](#building). Reports from independent builders and reviews of the remaining installer
integration are welcome. A supported installation route and binary release are still pending.

Where else help would count:

- **Other M-series Macs.** Only the 13-inch M1 MacBook Pro has run this. If you know another
  model's hardware from the Asahi Linux side, the differences are worth writing down even
  before anything boots.
- **Drivers.** Bluetooth, USB-C and Thunderbolt, external displays, sleep, the camera, the
  built-in microphones, the hardware video encoder.
- **Frameworks.** Every Mac app that gets further needs more of AppKit, QuartzCore, CoreText
  and friends to behave. Much of that work belongs upstream in PureDarwin or Finch, and we
  would rather send it there.
- **Reviews.** Of the code, and of the credits and licences. If we have credited your work
  wrongly, tell us.

How to contribute, and the licence rules for contributions:
[`CONTRIBUTING.md`](CONTRIBUTING.md). Security reports: [`SECURITY.md`](SECURITY.md).

The first README of this repository (7 to 9 November 2026, when it was called `darwin-lab`)
is kept as [`docs/history/README-2026-11-09.md`](docs/history/README-2026-11-09.md).
