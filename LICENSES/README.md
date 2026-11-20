# Licence texts

Copies of licence texts. They are not a map of which file is under which text.

The root [`LICENSE`](../LICENSE) is a notice: this repository is not licensed as a
whole under MIT. Original SiliconForest code is MIT-licensed under
[`LICENSE-SILICONFOREST-MIT`](../LICENSE-SILICONFOREST-MIT), which carries the
project's copyright notice. `MIT.txt` in this directory is a generic template
with `<year>` and `<copyright holders>` placeholders. It is not that grant.
Third-party code retains its existing terms. Some files still need provenance
review ([`docs/RELEASE_CHECKLIST.md`](../docs/RELEASE_CHECKLIST.md)). A directory
`NOTICE` does not assign a licence to every file under it. Which licence a file
is under is the licence of the code that file derives from. Provenance, with its
own "not verified" marks, is the top-level [`NOTICE`](../NOTICE).

These are unmodified copies. Each was taken from a copy that was already on the build
machine on 17 November 2026; none was typed in or fetched for this purpose.

| File | SPDX identifier | Used here by | Copied from |
|---|---|---|---|
| `MIT.txt` | MIT | template text also used by m1n1, speakersafetyd, Mesa patches, smithay, and dual-licensed Asahi files. The named SiliconForest grant is [`LICENSE-SILICONFOREST-MIT`](../LICENSE-SILICONFOREST-MIT), not this placeholder file | the Rust distribution's licence set (`/usr/share/doc/rustc/licenses/MIT.txt`, Arch package `rust` 1.98.0) |
| `GPL-2.0-only.txt` | GPL-2.0-only (also the text of GPL-2.0-or-later) | drivers ported from Linux and Asahi Linux, the AVE driver, FFmpeg/VLC glue | SPDX licence list as packaged by Arch (`/usr/share/licenses/spdx/`, package `licenses` 20240728) |
| `Linux-syscall-note.txt` | Linux-syscall-note (exception) | two UAPI headers taken from Linux | same package, `exceptions/` |
| `GPL-3.0-only.txt` | GPL-3.0-only | the vendored Chonkstep source and the patches derived from it | same package |
| `LGPL-2.1-or-later.txt` | LGPL-2.1-or-later | one FFmpeg-derived header in `m1-avd` | same package |
| `Apache-2.0.txt` | Apache-2.0 | files adopted from Finch (`MIT OR Apache-2.0`) | same package |
| `MPL-2.0.txt` | MPL-2.0 | patches to Mozilla, darling-metal and upstream's MPL files | same package |
| `BSD-2-Clause.txt` | BSD-2-Clause | patches to PureDarwin's own files, FreeBSD/ravynOS-derived files, dual-licensed files | the Rust distribution's licence set (`/usr/share/doc/rustc/licenses/`) |
| `ISC.txt` | ISC | the Wi-Fi driver (from OpenBSD's bwfm and Linux brcmfmac) | same |
| `OFL-1.1.txt` | OFL-1.1 | the font files inside the vendored Chonkstep copy (each also has its own OFL file with its copyright line beside it) | same |
| `APSL-2.0.txt` | APSL-2.0 | patches to files of Apple's open-source releases, five copies of `IOHIDEventService.cpp` | upstream PureDarwin's `APPLE_LICENSE.txt` at `c713d8fb` (Apple Public Source License, Version 2.0, August 6, 2003) |

## Other projects' own licence files

`third-party/` holds licence files of projects whose code is adopted here, with their
copyright lines, as those projects publish them:

| File | Project | Copied from |
|---|---|---|
| `third-party/PureDarwin-LICENSE.txt` | PureDarwin's own licence file only (BSD-2-Clause, "Copyright (c) 2007-Present The PureDarwin Project"). The PureDarwin tree is mixed: MPL-2.0, MPL-2.0 OR MIT, tri-licensed files, and APSL-2.0 Darwin code, per the maintainer comment linked from [`LICENSE`](../LICENSE). Per-file terms are PureDarwin's headers. | `PUREDARWIN_LICENSE.txt` at PureDarwin `c713d8fb` |
| `third-party/Finch-LICENSE-MIT.txt`, `third-party/Finch-LICENSE-APACHE.txt` | Finch ("Copyright (c) 2026 The Finch Project contributors") | the local clone at `2d9b1bb` |
| `third-party/m1n1-LICENSE.txt` | m1n1 (MIT, "Copyright The Asahi Linux Contributors") | the local clone at `121fcbf`; m1n1's bundled third-party parts have further licence files in its own tree |
| `third-party/Indium-LICENSE-0BSD.txt` | Indium and Iridium (0BSD) | the local clone at `e3a1f22`; only one patch to Indium is in this repository |

Licence files that were already in the tree stay where they are: `integrations/siliconforest/m1-ave/tools/upstream/COPYING`
(GPL-2.0, the AVE driver's), `integrations/siliconforest/m1-sound/safetyd/LICENSE` (MIT, speakersafetyd's),
and the `LICENSE` and font licence files inside the vendored Chonkstep copy.

## Not included

- **BSD-3-Clause**: one header is `(GPL-2.0+ WITH Linux-syscall-note) OR BSD-3-Clause`. No
  unmodified template copy of the BSD-3-Clause text was on the machine; the header is used
  under its GPL option's text above until one is added.
- **Swift-exception** (`Apache-2.0 WITH Swift-exception`, one file): no copy on the machine.
- **Apple's Binary Driver Software License Agreement** (`APPLE_DRIVER_LICENSE.txt` in
  upstream PureDarwin's tree) is not an open-source licence. Nothing in this repository is
  offered under it and its text is not copied here.
- Licences of things the build fetches but this repository does not contain (Firefox, FFmpeg,
  x264, VLC, LLVM, Rust crates, fonts fetched by recipes) travel with those sources.
