# Public source build

<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->

The public entry builds on x86_64 Linux with Nix 2.34.9. Its release graph fetches
pinned public inputs; it does not read a workstation checkout, acquired firmware,
Apple application, or Mozilla application bundle. The complete build and desktop
proof are recorded in [the build receipt](../reports/build-repro/public-build-001.json).

```sh
git clone --branch build-repro https://github.com/chriskearney/siliconforest.git
cd siliconforest
nix --extra-experimental-features 'nix-command flakes' build --max-jobs 2 --cores 4 --no-link --print-out-paths \
  .#release .#qemu-image .#qemu-proof-image .#qemu-runner \
  .#root-image .#qemu-reference-image
```

This is the command used for the isolated proof. The branch remains `build-repro`
while the change is under review. The receipt identifies the exact tested commit.
The default output (`nix build`) is the same packaged release as `.#release`.
The build does not install boot files, modify a target disk, or contact a Mac.

## Outputs

| Output | Contents |
| --- | --- |
| `release` | Compressed root image, boot archive, root manifest and checksums; unsigned build products. |
| `root-image`, `root-tree` | The assembled ext4 root and the tree used by late-linked support libraries. |
| `m1-kernel`, `bootfiles` | Kernel-50-derived collection and release-bound boot files; built, not installed on hardware. |
| `boot-stage1`, `boot-stage2-release` | Public first stage and second stage bound to the release root UUID. |
| `qemu-reference-image` | The release root on a disk with QEMU's generic collection and firmware partition. |
| `qemu-image` | A desktop session for interactive keyboard testing, software rendering and a dock. |
| `qemu-proof-image` | A finite automated desktop/check profile. Building it does not itself prove that it booted. |
| `qemu-runner` | Pinned QEMU, arm64 firmware, Python, VNC capture and guest-record extraction tools. |
| `source-manifest` | Small public source-lock output used by CI. |
| `base-source`, `base-build-source` | Verified generated rename and the one-file linker-environment overlay used for builds. |

Individual user-space pieces are also exposed by `release/packages.nix`.
[The QEMU guide](release/QEMU.md) gives the helper-script route and its measured limits.
QEMU uses a generic kernel and firmware framebuffer; its result does not establish
M1 driver, GPU, network, audio or hardware compatibility.

## Inputs and reproducibility

`sources.lock` pins direct upstream URLs, revisions and content hashes, including
Homebrew's 64 bottles and client. Nixpkgs and the retained Cargo locks pin their
transitive dependencies. The Homebrew packages are fetched binaries; this entry
does not compile those bottles. Public cache access includes cache.nixos.org;
source and bottle downloads also require their public upstream hosts, including
ghcr.io. The build receipt records the actual container configuration.

`release/base.nix` generates the renamed primary upstream tree, and
`release/cocoa-base.nix` generates the earlier tree required by the Cocoa patch
series. Their recursive source hashes are checked. [The dependency inventory](build/DEPENDENCIES.md)
distinguishes the release graph from bench experiments and frozen evidence.

The locked renamed trees remain unchanged. A separate build-source overlay adds
ZERO_AR_DATE=1 to each base linker wrapper, so N_OSO timestamps are zero; desktop
and dock links use -Wl,-S to remove rustc's temporary debug-map paths. The corrected
desktop package passed a complete nix-store --check rebuild in the isolated store
with fresh, random temporary directories. Its entire NAR and both binaries match
an independent host build. The native spawn object is supplied only when the
linker runs: a temporary object path in RUSTFLAGS would also change Cargo crate
identities, even after the debug map is removed.
A controlled base-link test also remains identical after an object-mtime change;
the unwrapped control differs. These are scoped checks, not a claim that the whole
OS has been rebuilt twice to identical bytes across machines. UUIDs and source
pins alone do not establish that broader result.

One isolated desktop compile received SIGSEGV inside LLVM
AArch64PointerAuth during ThinLTO. The unchanged derivation succeeded on retry,
and its subsequent full rebuild check passed with identical output. No OOM event
was recorded and no core was retained; the cause remains unknown. The receipt
keeps that failed attempt separate from the successful builds.

## Isolation and resources

The proof used an initially clean container from the pinned public Nix image
`nixos/nix@sha256:53b5ec518b696373829ea305c3c07a8c870113e44648c88ec484ef078550fd4f`.
It had no host mounts or bind mounts, no privileged mode, an eight-CPU quota,
a 16 GiB memory limit and no swap. The bootstrap store was 614,460 KiB. Git cloned
the public repository anonymously; the build had no `sources/`, `artifacts/`,
`private/` or `runs/` input directory and used cache.nixos.org as its only substituter.

The isolation session started at 12:02:17 UTC on 18 November 2026. It reached
successful completion of the six-output command at 18:13:11 UTC (6 h 10 m 54 s);
resource collection finished at 18:14:54 UTC. That interval includes public-source
fixes, intentionally retired intermediate attempts and the desktop rebuild check.
The final command at commit `99312ab0555ab1e3dcfcf3fa9a6f0c33ef1f6bba` took
7 m 37 s using components already built from those earlier public revisions.
This was not one uninterrupted empty-store build at the final revision.

At completion the store occupied 62.03 GiB. The cumulative memory peak was
16.00 GiB at the configured limit; memory-limit pressure occurred, with zero OOM
or OOM-kill events and zero swap use. Cumulative container CPU time was 29.59 h.
These measurements cover the isolated build and its additional verification,
before the final QEMU session. Peak temporary disk usage was not measured.

CI evaluates the flake and builds `source-manifest` in the pinned public Nix
container. It does not perform this full cross build or boot a guest. A full CI
job needs a builder provisioned for the measured workload and compiler scratch
space, or a cache of the locked outputs. The union of the six outputs' runtime
closures is 863 paths, 16.60 GiB of uncompressed NAR data; this is not a measured
compressed-cache size or the full build-dependency closure. This branch supplies
no project binary cache.

## Material supplied separately

Apple applications and acquired firmware are not build inputs. The installer must
obtain target firmware from that user's Mac, and optional Apple apps come from
the user's own copy. Mozilla's Firefox bundle is also optional and obtained
separately. The included Activity Monitor pieces are open support libraries,
not Apple's application. No binary-distribution approval follows from this build.
The public corecrypto dependency is the MPL-2.0 reimplementation pinned in the
lock; its upstream README describes its experimental, unaudited status.

The release kernel's SFM1SPIHID member admits the same trackpad descriptor using
length 110 and SHA-256. Only the digest is public; acquired descriptor bytes remain
outside git. The build was not installed on the M1.

The public stage1 has the version tag siliconforest-stage1-public; the historical
installed-stub guard uses siliconforest-stage1-v1. The tag and independently
pinned toolchain change its bytes. Preserve the installed-stub guard: the public
stage1 SHA starts 840fd72f, the historical guard 44c1ef0b. A build is not permission
to overwrite an existing stub. The installer must use matching release boot files.

The release packaging/installer integration is separate from the public source
build. The current installer expects xz archives, a firmware slot and verified unpacker,
a root-growth policy, install.json and an icon in the boot archive. Those
integration items remain separate work. These zstd build products have not been
validated with the installer, and a QEMU pass does not establish that compatibility.
