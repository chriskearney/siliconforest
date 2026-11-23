# Kernel 51: kernel 50 + kern.sf_exitwait

Kernel 50 (`../m1-kernel50/build-kc.nix`: kernel 48's 57 members with the fsck-clean ext4) with
one member replaced: the kernel, built from kernel 48's kernel recipe with
`../m1-exit-waits/kernel.patch` added after its patch series. The patch adds the
`kern.sf_exitwait` report (off by default, root only; see `../m1-exit-waits/README.md`) and
nothing else. No fix of the stuck exit is in this kernel.

    nix-build build-kc.nix --no-out-link              the collection ($out/kernel)
    nix-build build-kc.nix -A kernel --no-out-link    the changed member
    nix-build build-kc.nix -A members --no-out-link   all members as built (kernel 48's kexts,
                                                      kernel 50's ext4, this kernel), for
                                                      ../m1-exit-waits/symbolicate.py

## Proof that only the kernel changed

1. Derivations: the collection's link phase (`kernel48-link-phase.sh`) is kernel 50's with two
   lines different: `KERNEL_BIN=` naming the new kernel, and kc-builder from kc-tools with
   `../m1-kc-bind/kc-tools-bind.patch` (`KC_BIND_PINS` set on the derivation). Its other 19 store
   inputs (the boot kexts, the 17 added kexts, the strip and compaction tools) are the same store
   paths as kernel 50's. Linked with the old tool, kernel 51 is the same file byte for byte, and so
   is kernel 50 linked with the new one (`../m1-exit-waits/kc-tools-duplicate-names.md`).
2. The linked collections, entry by entry (`compare-collections.py`, results in the kit): every
   kext entry is at the same addresses; its code and constant segments are identical, and the
   only bytes that differ in its data segments are chained-fixup pointers into the kernel whose
   targets name the same kernel symbol at the same offset before and after (the kernel's
   functions moved because code was added). Checked first on kernel 48 → 50, where it reports
   exactly the ext4 entry as changed.
3. The kernel member itself (`compare-kernel-functions.py`, masked for placement): the new
   functions of the diagnostic; `reboot_kernel` with one call added (and the `__LINE__` of an
   assertion, five lines later in the file); two progress-meter sysctl handlers that differ only
   by the linker's adrp+ldr → ldr-literal rewrite (read as disassembly); every other function the
   same. The diagnostic's functions that cross between its two files are private externs, so the
   kernel exports exactly kernel 50's names (see below).
4. The kit's `kernel.bin` carries kernel 50's configuration record unchanged
   (`../m1-kernel48/pack-kernel-bin.py`; repacking kernel 50's collection with it reproduces
   kernel 50's `kernel.bin`, sha256 7d9ddaca…, byte for byte).

Results (18 November; kit in `runs/kexit/kit51/`, not in git): collection
`/nix/store/skhagcbh…-siliconforest-kc-kernel51` (34,453,462 bytes); all 56 kext entries at kernel
50's addresses with code and constant segments identical and only pointer words into the kernel
different, each naming the same symbol (56 "rebound", 0 "differs"); `__PRELINK_INFO` differs in
the 56 `_PrelinkExecutableFileOffset` values (+0x1000 each, the kernel's file part grew by one
page) and `_PrelinkKCID`; kernel: 24,525 exported names, the same list as kernel 50's; 10 new
functions, 3 changed as described. `kernel.bin` 10,353,360 bytes, sha256
`81033d245c244e3f243924186daf58ecc9f9e83eafc6a45eb1dc7662d7713032`, configuration record byte
for byte kernel 50's; `boot.bin` = the installed stage 2 (fc8883a3…). Never booted.

Install (coordinator only): from the M1's Linux with
`m1-native-boot/install/linux/sf-bootbin-install.sh <PARTUUID> boot.bin kernel.bin`, stage 2
unchanged (the installer leaves an identical file and its `.old` alone). `kernel.bin.old` then is
kernel 50, but `boot.bin.old` stays the old-name stage 2 (81d58f1b), so `--rollback` refuses the
pair: the way back to kernel 50 is the normal install of the same `boot.bin` with
`runs/ext4-state/kit50/kernel.bin`.

## Found while proving it: kexts bind duplicate names by chance (fixed in the tool)

Now fixed in kc-tools for this recipe: `../m1-kc-bind/`, `../m1-exit-waits/kc-tools-duplicate-names.md`.
The note as first written:


kc-tools links each kext against one flat table: the kernel's exported names plus every earlier
kext's, sorted by name with `qsort` and searched by bisection (`lib/linker.c`
`symtab_merge_from_linked`, `symtab_lookup`). Names defined twice are found by where the bisection
lands, which moves when the table grows. The first kernel 51 build exported four new names
(the diagnostic's cross-file functions) and that alone moved four bindings between the kernel and
IO80211Family's compat copies: ext4's `microuptime` (kernel → IO80211Family), SFBwfm's `m_freem`
(IO80211Family → kernel) and `m_gethdr` (kernel → IO80211Family), SFAppleCIO's `hz` (kernel →
IO80211Family). By source the pairs do the same (IO80211Family's `hz` is 100, its mbuf functions
call the mbuf KPI; its `microuptime` was not read), but it is not the collection kernel 50 is.
With the four functions made private externs the kernel's exported names are kernel 50's and the
bindings are kernel 50's (`compare-collections.py` checks each one). Any later kernel that adds
an exported name can move them again; resolving each import against the kext's own
OSBundleLibraries (or the kernel first) in kc-tools would end it, as its own change.
