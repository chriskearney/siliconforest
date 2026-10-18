# SiliconForest

A personally maintained Apple Silicon kernel, Mesa and m1n1 stack for
existing Omarchy installations, maintained by [iconidentify](https://github.com/iconidentify).
Upstream history, attribution and licenses are preserved.

Install the [2026-10-18 release](https://github.com/iconidentify/siliconforest/releases/tag/v2026.10.18.1)
on an existing Apple Silicon Omarchy installation:

```sh
curl -fsSL https://github.com/iconidentify/siliconforest/releases/download/v2026.10.18.1/install.sh | bash
```

Qualified pairs are **M1 Air J313 with OS firmware 13.5** and **M3 Pro 16-inch
J516S with 14.7**, with the exact loader/U-Boot versions in their signed manifests.
Default boot, the native desktop, OpenGL/Vulkan pixel readback and rebooted
rollback passed on both. Other M1/M2 models, M3 Pro variants and M3 Air remain
pending; the installer refuses unqualified combinations.

The command downloads signed prebuilt packages from each component's own public
GitHub release. It preserves recovery entries, installs the matched set and
leaves the reboot to you. It does not build on the recipient's machine or perform
a full system upgrade. [Installation, scope and recovery](release/README.md).

Signing fingerprint: `97DC8D8AFCBC08DB7283EC3CFFB366AB95783E75`.

## Repositories

| Purpose | Repository / branch |
| --- | --- |
| Release tooling, source lock, configuration, plan | [iconidentify/siliconforest](https://github.com/iconidentify/siliconforest) |
| Kernel source | [iconidentify/siliconforest-linux — siliconforest/next](https://github.com/iconidentify/siliconforest-linux/tree/siliconforest/next) |
| m1n1 source | [iconidentify/siliconforest-m1n1 — siliconforest/next](https://github.com/iconidentify/siliconforest-m1n1/tree/siliconforest/next) |
| Mesa source | [iconidentify/siliconforest-mesa — siliconforest/next](https://github.com/iconidentify/siliconforest-mesa/tree/siliconforest/next) |
| Existing hardware test infrastructure | [iconidentify/maclab](https://github.com/iconidentify/maclab) |

The kernel lives in a separate, independently maintained repository with the full
Linux history preserved. The previous kernel repository stays archived and is
outside this project's workflow.

The initial sources come from Omacom's `integration/aurora` branches on
2026-10-18. `sources.lock.json` records full commits rather than following moving
branches. The kernel starts at 7.1.12. The maintained m1n1 now combines the current Asahi upstream with the reviewed M3
handoffs and an owner-authorized AI policy. Neo, M4 and M5 research is preserved
in explicit separate profiles; see its source review and validation reports.
Neither a current branch name nor an old upstream validation result is a
SiliconForest support claim.

## Developer setup

The [three-package installer](release/README.md) uses pinned public sources and
board/firmware qualification reports. The broader source target catalog is a
build list; only the released, qualified pairs above are admitted by the public
installer.

On Linux, with Git and Python 3.11 or newer:

```sh
git clone https://github.com/iconidentify/siliconforest.git
cd siliconforest
make sources
make verify
make check
```

`make check` also requires ShellCheck, GnuPG, libarchive tools, a C compiler and
Wayland development libraries. Weston enables the real headless compositor case. Source fetching uses only the personal
repositories and pinned submodules. Existing source checkouts are verified rather than
reset, switched, or cleaned. A failed initial clone can leave a partial directory;
inspect it before removing it and retrying.

LLVM builds run on Linux x86_64 or aarch64. Install dependencies in a dedicated
builder. The build scripts do not update the host's package database or install
anything into its boot partition.

| Build | Prerequisites |
| --- | --- |
| Kernel | LLVM/Clang/LLD 22.1.8, Rust 1.93.1 with rust-src, the corrected bindgen from `sources/linux/tools/aurora-bindgen/`, make, host C compiler, bc, flex, bison, cpio, perl, Python, libelf, OpenSSL development files, pahole, kmod |
| m1n1 stage 2 | LLVM/Clang/LLD 22.1.8, llvm-objcopy, make, Rust 1.99.0 with `aarch64-unknown-none-softfloat` |

For an already provisioned Rust builder:

```sh
rustup toolchain install 1.93.1 --profile minimal --component rust-src
rustup toolchain install 1.99.0 --profile minimal --target aarch64-unknown-none-softfloat
make build-m1n1
python3 sources/linux/tools/aurora-bindgen/build.py --output-dir "$PWD/build/kernel-bindgen"
BINDGEN="$PWD/build/kernel-bindgen/rust-bindgen-0.73.2/target/release/bindgen" JOBS=8 make build-kernel
```

Set `LLVM_DIR` to a nonstandard LLVM installation prefix if needed. The kernel
script also recognizes `/usr/lib/llvm22`. m1n1 builds use the selected LLVM on
`PATH`. The first kernel configuration is the inherited release20 configuration;
the build removes its `-ARCH` suffix and adds a distinct SiliconForest development
release suffix. It runs `olddefconfig`, so retain the generated `.config` with
every artifact. Every kernel build enables compile-time C/Rust layout assertions;
the `-layout1` ABI suffix keeps it separate from the initial unchecked builds.
Stock bindgen 0.73.1 produced incorrect task field offsets in the initial M3 Pro
candidate and caused a kernel fault on GPU submissions. Those initial kernel
packages must not be distributed. Do not advertise inherited experimental
features as tested.

Outputs:

- `build/linux/arch/arm64/boot/Image`, modules, Apple DTBs, and `.config`.
- `build/linux-m3-native/` when explicitly built with `KERNEL_VARIANT=m3-native`.
- `dist/m1n1-<commit>/m1n1.bin`, build flags, source lock, and checksums.
- `dist/mesa-root/` after `make build-mesa` on a provisioned ARM64 builder.

The m1n1 helper runs `make clean` in its dedicated source checkout to prevent
old build flags from being reused. Its output is a **stage 2 payload**, not a
complete `boot.bin`: the latter also needs the matching kernel DTBs, U-Boot,
and the target machine's existing configuration.

For a local maclab kernel artifact after a successful kernel build:

```sh
lab pack --build "$PWD/build/linux" -o "$PWD/dist/siliconforest-dev.tar.zst"
```

This does not test or install the m1n1/DTB pair. maclab's ordinary kernel job uses
the device tree already supplied by the installed boot chain. Boot-chain changes
need separate qualification and recovery, as described in the plan.

## Publishing direction

Eryk's M3 Pro stack and Naeem's M3 Max additions are integrated into
`siliconforest/next` behind **`CONFIG_SILICONFOREST_M3` (default off)**, following
[the adversarial review](https://github.com/iconidentify/siliconforest-linux/blob/siliconforest/next/SILICONFOREST-M3-REVIEW.md).
The existing GPU/display implementations and normal board DTBs remain in place.
The development profile selects a matched alternative GPU, display, power, PHY,
Type-C and UAPI stack; USB4 is excluded pending its tunnel API port.

[The source manifest](candidates/m3-g15-20261018.json) records the merged source,
original PRs, fixes and validation. All 43 host checks passed, along with arm64
compilation of the enabled driver targets and Apple DTBs. This does not establish
complete kernel/module linkage or hardware qualification. The reviewed m1n1 and
Mesa sources are now pinned. The kernel's alternative native UAPI
(`CONFIG_SILICONFOREST_M3=y`) is required by the native Mesa M3 Pro/Max/Neo
profile; its normal UAPI is incompatible. Source-derived J516C board data and
hardware qualification remain release requirements. The normal build helper keeps the maintained configuration (the experimental option stays off). See the
review for the separate development profile and DTB paths.

The target experience is one bootstrap command adding your signed pacman
repository and installing `linux-siliconforest` plus the qualified boot components.
Updates use a newly signed, matched three-package transaction; the guard refuses
an independent component upgrade that would mix boot or graphics contracts.
There will be an explicit testing channel and a stable channel.

See [the implementation and maintenance plan](docs/PLAN.md) for packaging,
signing, hardware qualification, installation, and rollback. Apple vendor firmware
continues to come from each machine's existing installation.

## Attribution and licenses

Original tools in this repository use the MIT license. The inherited kernel
configuration and Rust toolchain settings are documented in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Linux and m1n1 keep their original
licenses in their respective source repositories. Public binaries must include
the applicable notices and corresponding source references.


## Current bootloader and graphics source profiles

The source repos use one namespace: `siliconforest-linux`, `siliconforest-mesa`
and `siliconforest-m1n1`. The archived historical kernel repository stays frozen.

The default m1n1 integrates upstream through 2026-10-18, Eryk's J514S native
panel/external display/HDMI/SIO work, the four M3 Max handoff commits, and the
public M3 Air 26.6.2 ISP heap fix. It preserves exact firmware/board admission,
adds transactional J514S DT publication, and requires explicit
`chosen.asahi,t6031-gpu=1` before the Max GPU powered probe.

`experimental/neo` is a separate built and host-tested m1n1 profile; use it for
J700 research rather than substituting its broad boot-path changes for the M3
firmware profile. `experimental/m4` and `experimental/m5-t6050` retain public
research without a build or graphics support claim. The lock records exact tips.
M3 Air firmware families use their corresponding Mesa compatibility branch,
rather than the default M3 Pro/Max/Neo Mesa profile.

The main m1n1 build and 54 Python tests pass (7 skips, 10 subtests), and the Neo
build and 80 Python tests pass (7 skips). Ten inherited old G15 stand-in fixture
failures reproduce identically at the original source pin; the complete G15
suite is not green. The new normal kernel has booted on the M1 Air and passed boot-health.
Full-stack installation, GPU rendering and rollback qualification remain in
progress; no board has a qualified SiliconForest release yet.

[Bootloader review and evidence](https://github.com/iconidentify/siliconforest-m1n1/blob/siliconforest/next/SILICONFOREST-REVIEW.md)
and [Mesa validation](https://github.com/iconidentify/siliconforest-mesa/blob/siliconforest/next/SILICONFOREST-VALIDATION.md)
record the remaining limits. The package/installer milestones in the plan remain
future release work; these public source repositories are not an installable
replacement-kernel release.


## J613 DTB and kernel pairing floor

The lock now pairs kernel `17a9930f20a0895b5980385b0b2d67edda8a24be`
with the bootloader's J613 external-firmware marker. The kernel includes the
camera, thermal, HDMI-hold and lid-closed second-display carries in PRs #2–#6.
Marius Gehrmann's public m1n1 patch is imported with author credit and its MIT
notice; no Signed-off-by was invented.

The bootloader reserves external firmware after the internal display handoff,
then writes `apple,t8122-dcpext-firmware-ready = <1>`. The external controller,
DARTs, mailbox, crossbars and routes remain disabled for the kernel gate. Failed
reservation/publication leaves no new readiness marker or partial DT update.

**Build the J613 DTB and kernel from one locked source revision.** J613 DTBs
containing the new disabled internal Type-C route must not accompany kernels
older than the pairing floor above. Those older panel drivers reject the route
container. The new panel driver also waits for atcphy1 to probe. The 25G83
DT includes the same base tree, so its panel has the same dependency and
kernel pairing floor.

These external-display/clamshell changes are intentionally limited to the normal
kernel display profile and require exactly three firmware compatibility cells:
`14 7 0`. The paired kernel has no J613 external-display support on 26.6.2;
camera support is separate. The alternative M3 drivers have no T8122/J613
support. Roll back the kernel and DTBs together. The source lock records these
rules; there is no binary installer that overrides them.
