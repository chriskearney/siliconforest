# kc-builder for the installer: the same collection on Linux and macOS

The installer links the kernel collection on the user's Mac instead of shipping one prelinked binary
(`docs/installer/PAYLOAD.md`, "Kernel collection"). The Mac's link has to produce the very bytes the
release vouches for. This directory holds the kc-tools build that does that, its proof and its checks.

| File | What it is |
|---|---|
| `kc-tools-sym-order.patch` | a stable sort for kc-builder's symbol table (below) |
| `build-tools.nix` | `../m1-bringup/kc-tools-fixed.nix` + the patch; `../rebase/build-kc.nix` links with it |
| `prepare_source.py` | the same patched source without Nix: locked revision, commit id checked, same patches, same order |
| `build-macos.sh` | the installer's kc-builder for Apple silicon, Developer ID signed (hardened runtime) or ad-hoc |
| `release-inputs.nix`, `capture-kc-builder.sh` | a recipe's link as separate files plus its options, and the collection linked FROM them |
| `test_sym_order.py` | harness over the real `symtab_add`/`sym_sort`, ASan/UBSan, digest compared across hosts in CI |
| `../../../.github/workflows/kc-builder.yml` | Linux and macOS jobs; the digests must be equal |

## The defect

kc-builder keeps one table of exported names (the kernel's, then each linked kext's) and finds an
import by bisection (`lib/linker.c`, `symtab_lookup`). After every kext it re-sorts the table with
`qsort` by name only. `qsort` is not stable, and C libraries differ: glibc's merge sort keeps equal names
in the order they were added, Apple's libc does not. When a name is defined twice the bisection lands on
whichever copy the sort put there. So the same inputs linked on macOS gave a different collection: in the
J313 installed-system collection SFBwfm's `m_adj`, `m_copydata`, `m_freem` and `m_gethdr` exist both in
the kernel and in IO80211Family, and three of SFBwfm's pointers changed (`910a4df0…` on macOS against
`b3115d93…` on Linux).

## The fix

`kc-tools-sym-order.patch` replaces the two `qsort` calls with a merge sort that keeps equal names in the
order they were added: glibc's order, on every host. It does not change which copy is chosen on Linux, so
every collection linked with it on glibc is byte-identical to before; it only makes macOS agree.
An address tie-break was tried and rejected: the kexts sit *below* the kernel in the collection, so
address order is not the order added, and it changed the collection.

What it does not fix: which copy the bisection lands on still depends on the size of the table. In the
G2 RAM-boot collection SFBwfm binds IO80211Family's four `m_*`; in the G6 installed-system collection it
binds the kernel's. Each is now the same on every host, but they differ from each other. A rule that
does not depend on the table (first definition wins, or `../m1-kc-bind/`'s declared-library rule) changes
one of the two collections by four pointers, so it waits for a decision (below).

## Proof (24 November 2026)

Linux: i9, `nix-build`, glibc, `build-tools.nix`. macOS: M5 (macOS 26.5.2, arm64), Apple clang 21,
`build-macos.sh` (ad-hoc), linking FROM the separate files `release-inputs.nix` produced, with
`link-args.txt`.

| Collection | Recipe | Before (kc-tools-fixed) | Linux, patched | macOS, unpatched | macOS, patched |
|---|---|---|---|---|---|
| G6 installed system (54 kexts) | `m1-storage/build-kc-native-rw-halt.nix` | `b3115d93…` | `b3115d93…` | `910a4df0…` | `b3115d93…` |
| G2 RAM boot (59 kexts) | `rebase/build-kc.nix` | `ef49aa0a…` | `ef49aa0a…` | `0ee596d1…` | `ef49aa0a…` |

`release-inputs.nix` itself links from its copies, so its `kernel` equals the recipe's (`b3115d93…`,
`ef49aa0a…`). Harness digest `c00ce981b7966302` on both hosts; replacing the merge sort with `qsort`
fails it on macOS (2733 failures), and making the merge unstable fails it on Linux.

Rerun:

    cd integrations/siliconforest/kc-builder
    nix-build release-inputs.nix                                   # G6; G2: --arg collection 'import ../rebase/build-kc.nix { }'
    ./build-macos.sh /tmp/kcb                                      # on the Mac
    cd <out>/inputs && /tmp/kcb/kc-builder $(sed 's#@OUTPUT@#/tmp/kc#' link-args.txt) && shasum -a 256 /tmp/kc

No collection, kernel or kext is committed: they are built from Apple open-source parts and the
collection is never published (PAYLOAD.md).

## Needs a decision

- **Duplicate names.** Keep the table-size-dependent bisection (G2 and G6 as built and as tested), or
  adopt a fixed rule for the release collection, which moves four SFBwfm pointers in one of them.
- **Signing.** The M5 has no Developer ID Application identity in its keychain, so the local build is
  ad-hoc. CI already holds one (`MAC_SIGNING_IDENTITY`, `installer-release.yml`); the release build signs
  kc-builder with it. No new certificate is needed.
