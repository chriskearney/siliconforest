# Public source build

The public build entry is under validation. A clean-store build of the complete
release and a desktop boot are required before this guide can claim an end-to-end
build. The README's current limitation remains in force.

On an x86_64 Linux host with Nix 2.34.9, this command builds the source manifest:

```sh
nix --extra-experimental-features 'nix-command flakes' build .#source-manifest
```

This is a small check of the entry point, not an operating-system build. Its inputs
are pinned by public URL, revision and content hash in `sources.lock`, including
the upstream base's Nix input graph. Nixpkgs and the retained Cargo lockfiles pin
their transitive dependencies. `release/base.nix` generates the renamed upstream
tree; `release/cocoa-base.nix` generates the earlier base still used by the Cocoa
patch series. Neither needs a workstation checkout.

Named outputs include `m1-kernel`, `qemu-base`, `root-base`, `desktop`, `terminal`,
`boot-stage1`, `boot-stage2`, `boot-stage2-release`, and the individual user-space
pieces in `release/packages.nix`. Integrated outputs `root-image`, `bootfiles`,
`release` (also the default), and `qemu-image` are under validation. Their presence
is not yet evidence of a successful complete build.

`boot-stage2` defaults to RAM roots only. A disk build explicitly binds its stage
to the release root filesystem's UUID through `release/boot-stages.nix`. Partition
identifiers and the write fence belong in installer-generated configuration. No
build command installs boot files, modifies a disk, or contacts a Mac.

The public stage 1 is a new build, not a byte reproduction of the owner's installed
stub. Its embedded version tag ends in `siliconforest-stage1-public`; the historical
installer recipe used `siliconforest-stage1-v1`. That tag alone changes the bytes;
the public recipe also pins its compiler and image-conversion tools independently.
The locally verified public image's SHA-256 starts `840fd72f`, while the historical
installed-stub guard starts `44c1ef0b`. Keep that guard intact. The installer for a
new machine must construct its stub from the matching release stage 1. No test
here replaced the owner's stub or established hardware compatibility of this build.

The release kernel derives from kernel 50. Its `SFM1SPIHID` member checks the same
trackpad descriptor identity using its length and SHA-256, replacing an untracked
reference header. Only the digest is public. This build has not been installed on
hardware. The raw descriptor and historical build records remain outside this
new source closure.

Apple applications and firmware are user-supplied inputs outside the build.
The Firefox binary bundle is optional and obtained separately. The base's
corecrypto dependency is the public MPL-2.0 reimplementation pinned in the lock,
not an Apple binary; its upstream README describes its experimental, unaudited
status. These build recipes do not make a binary-distribution licensing decision.

CI evaluates the flake's source-manifest output and builds it in a pinned public
Nix container. That inexpensive job does not establish a full release build or a
QEMU boot. Full-build resource requirements and isolated-build receipts will be
added after measurement.
