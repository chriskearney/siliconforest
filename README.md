# SiliconForest

A personally maintained Apple Silicon kernel and m1n1 release project for
existing Omarchy installations, maintained by [iconidentify](https://github.com/iconidentify).
Independent of Omacom, Aurora Silicon, and Asahi Linux; derived from their work
with its original history, attribution, and licenses preserved.

**Development setup only. There is no qualified SiliconForest binary release or
public install command yet.** The installer and package repository are upcoming
milestones. Building a payload does not establish that a Mac boots it.

## Repositories

| Purpose | Repository / branch |
| --- | --- |
| Release tooling, source lock, configuration, plan | [iconidentify/siliconforest](https://github.com/iconidentify/siliconforest) |
| Kernel source | [iconidentify/siliconforest-linux — siliconforest/next](https://github.com/iconidentify/siliconforest-linux/tree/siliconforest/next) |
| m1n1 source | [iconidentify/m1n1 — siliconforest/next](https://github.com/iconidentify/m1n1/tree/siliconforest/next) |
| Existing hardware test infrastructure | [iconidentify/maclab](https://github.com/iconidentify/maclab) |

The kernel lives in a separate, independently maintained repository with the full
Linux history preserved. The previous kernel repository stays archived and is
outside this project's workflow.

The initial sources come from Omacom's `integration/aurora` branches on
2026-10-18. `sources.lock.json` records full commits rather than following moving
branches. The kernel starts at 7.1.12. The m1n1 fork drops the inherited
`AGENTS.md` at its owner's direction; its source code matches the pinned baseline.
Neither a current branch name nor an old upstream validation result is an
SiliconForest support claim.

## Developer setup

On Linux, with Git and Python 3.9 or newer:

```sh
git clone https://github.com/iconidentify/siliconforest.git
cd siliconforest
make sources
make verify
make check
```

`make check` also requires ShellCheck. Source fetching uses only the personal
repositories and pinned submodules. Existing source checkouts are verified rather than
reset, switched, or cleaned. A failed initial clone can leave a partial directory;
inspect it before removing it and retrying.

LLVM builds run on Linux x86_64 or aarch64. Install dependencies in a dedicated
builder. The build scripts do not update the host's package database or install
anything into its boot partition.

| Build | Prerequisites |
| --- | --- |
| Kernel | LLVM/Clang/LLD 22.1.8, Rust 1.93.1 with rust-src, bindgen >= 0.71.1, make, host C compiler, bc, flex, bison, cpio, perl, Python, libelf, OpenSSL development files, pahole, kmod |
| m1n1 stage 2 | LLVM/Clang/LLD 22.1.8, llvm-objcopy, make, Rust 1.89.0 with `aarch64-unknown-none-softfloat` |

For an already provisioned Rust builder:

```sh
rustup toolchain install 1.93.1 --profile minimal --component rust-src
rustup toolchain install 1.89.0 --profile minimal --target aarch64-unknown-none-softfloat
make build-m1n1
JOBS=8 make build-kernel
```

Set `LLVM_DIR` to a nonstandard LLVM installation prefix if needed. The kernel
script also recognizes `/usr/lib/llvm22`. m1n1 builds use the selected LLVM on
`PATH`. The first kernel configuration is the inherited release20 configuration;
the build removes its `-ARCH` suffix and adds a distinct SiliconForest development
release suffix. It runs `olddefconfig`, so retain the generated `.config` with
every artifact. Do not advertise the inherited experimental features as tested.

Outputs:

- `build/linux/arch/arm64/boot/Image`, modules, Apple DTBs, and `.config`.
- `dist/m1n1-<commit>/m1n1.bin`, build flags, source lock, and checksums.

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

An [experimental M3 G15 source branch](https://github.com/iconidentify/siliconforest-linux/tree/siliconforest/m3-g15-review-20261018)
imports Eryk's M3 Pro stack and Naeem's M3 Max additions, with local fixes for
reserved-RAM admission, stream-validation limits, and J516C board admission.
Its original commits and dependencies are pinned in
[the candidate manifest](candidates/m3-g15-20261018.json), with findings in
[the code review](https://github.com/iconidentify/siliconforest-linux/blob/siliconforest/m3-g15-review-20261018/SILICONFOREST-M3-REVIEW.md).
This is a separate candidate line: the maintained source lock remains unchanged
while its prerequisite framework, machine data, m1n1, Mesa, and integration are
reviewed. It is not an installation or release candidate.

The target experience is one bootstrap command adding your signed pacman
repository and installing `linux-siliconforest` plus the qualified boot components.
Afterward, normal package upgrades deliver the updates you choose to publish.
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
