# kc-builder for the installer: the same collection on Linux and macOS

The installer links the kernel collection on the user's Mac instead of shipping one prelinked binary
(`docs/installer/PAYLOAD.md`, "Kernel collection"). The Mac's link has to produce the very bytes the
release vouches for. This directory holds the kc-tools build that does that, its proof and its checks.

| File | What it is |
|---|---|
| `kc-tools-sym-order.patch` | a stable sort for kc-builder's symbol table and a first-definition lookup (below) |
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

The sort alone left which copy the bisection landed on depending on the size of the table: the G2
RAM-boot collection bound SFBwfm's four `m_*` to IO80211Family's copies, the G6 installed-system collection
to the kernel's. Chris chose (24 November 2026, 17:58 PT) a fixed rule: **first definition wins**.
`symtab_lookup` returns the lowest index holding the name, which after the stable sort is the copy added
first: the kernel's, else the earliest kext in link order. G6 binds as before (`b3115d93…`, unchanged); G2
now binds the kernel's `m_*` too, so its collection changes from `ef49aa0a…` to `ff0238cc…`.

## Proof (24 November 2026)

Linux: i9, `nix-build`, glibc, `build-tools.nix`. macOS: M5 (macOS 26.5.2, arm64), Apple clang 21,
`build-macos.sh` (ad-hoc), linking FROM the separate files `release-inputs.nix` produced, with
`link-args.txt`.

| Collection | Recipe | Before (kc-tools-fixed) | Linux, patched | macOS, unpatched | macOS, patched |
|---|---|---|---|---|---|
| G6 installed system (54 kexts) | `m1-storage/build-kc-native-rw-halt.nix` | `b3115d93…` | `b3115d93…` | `910a4df0…` | `b3115d93…` |
| G2 RAM boot (59 kexts) | `rebase/build-kc.nix` | `ef49aa0a…` | `ff0238cc…` | `0ee596d1…` | `ff0238cc…` |

Full hashes with the first-definition patch: G6 `b3115d93b1932c3ef86d2ca39bf638ddddb29872421c297ced960f7f653a6a99`,
G2 `ff0238cc345bbf33e90c39e7a909eef002c85113394b67fb5137d4857499812c` (i9 `nix-build`, and the M5's
`build-macos.sh` kc-builder linking from `release-inputs.nix`'s files; no kext skipped on either).

`release-inputs.nix` itself links from its copies, so its `kernel` equals the recipe's (`b3115d93…`,
`ff0238cc…`). Harness digest `0892d7d86ab47e7d` on both hosts (`c00ce981b7966302` before the lookup
change). Replacing the merge sort with `qsort` fails it on macOS, making the merge unstable fails it on
Linux, and the old bisecting lookup fails it everywhere (43,609 failures).

Rerun:

    cd integrations/siliconforest/kc-builder
    nix-build release-inputs.nix                                   # G6; G2: --arg collection 'import ../rebase/build-kc.nix { }'
    ./build-macos.sh /tmp/kcb                                      # on the Mac
    cd <out>/inputs && /tmp/kcb/kc-builder $(sed 's#@OUTPUT@#/tmp/kc#' link-args.txt) && shasum -a 256 /tmp/kc

No collection, kernel or kext is committed: they are built from Apple open-source parts and the
collection is never published (PAYLOAD.md).

## Decisions and open points

- **Duplicate names.** Decided: first definition wins (above). The J313 G2 packet pinned in
  `../m1-j313-g2/g2-pins.json` was built and tested with the old `ef49aa0a…` collection and keeps that pin;
  a rebuilt packet links `ff0238cc…` and must be re-pinned (and re-reviewed) then.
- **Signing.** The M5 has no Developer ID Application identity in its keychain, so the local build is
  ad-hoc. CI already holds one (`MAC_SIGNING_IDENTITY`, `installer-release.yml`); the release build signs
  kc-builder with it. No new certificate is needed.
