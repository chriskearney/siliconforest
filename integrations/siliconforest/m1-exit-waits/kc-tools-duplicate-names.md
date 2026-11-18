# kc-tools bound duplicate names by chance (fixed in kernel 51's tool)

Found while proving kernel 51 (`../m1-kernel51/README.md`). Fix: `../m1-kc-bind/`.

## The defect

kc-tools links each kext against one table: the kernel's exported names plus every earlier
kext's, sorted by name with `qsort` (equal names in no defined order) and searched by bisection
(`lib/linker.c` `symtab_merge_from_linked`, `symtab_lookup`). In kernel 50's collection 82 names
are defined more than once, and six imports see two definitions: IO80211Family's compat copies
of `hz`, `m_adj`, `m_copydata`, `m_freem`, `m_gethdr` and `microuptime` are also kernel names.
Which copy an import got depended on where the bisection landed. That moves when the table
grows: the first kernel 51 build exported four more kernel names, and four bindings moved (ext4
`microuptime`, SFBwfm `m_freem` and `m_gethdr`, SFAppleCIO `hz`). Over 64 table sizes the old
lookup returns the kernel's `m_gethdr` 21 times and IO80211Family's 43 times (`test-bind.py`).

## The fix

`kc-tools-bind.patch` (`../m1-kc-bind/`, applied after `../m1-bringup/kc-tools-arm64-text.patch`)
resolves each import by these rules, in order:

1. a pin for this kext and name (`KC_BIND_PINS`);
2. a name with one definition binds to it, as before;
3. the kexts its `OSBundleLibraries` declares;
4. the kernel, the base every kext links against;
5. another kext, if only one address is left.

The build fails loudly in four cases:

- two declared libraries define the name at different addresses;
- two undeclared kexts are left and there is no kernel definition;
- a pin's provider has no such definition;
- a pin is not used by any import.

The kc-builder log prints every import that had two definitions, with the choice. It also notes
the imports that bind to a kext their importer does not declare: 49 today, IOUSBFamily →
IOStorageFamily (47) and AppleUSBMergeNub → IOUSBFamily (2). Those bindings are unchanged and
work, but the real kext linker would refuse them; declaring the libraries is a separate change.

## One exception, pinned: SFBwfm's `m_gethdr`

Under the rule, five of the six imports keep the binding they have in kernels 48–51. One moves:
SFBwfm declares IO80211Family, so the rule gives it IO80211Family's `m_gethdr` (a wrapper of
`mbuf_gethdr`). Today SFBwfm binds the kernel's `m_gethdr`, which the kernel exports only in
`com.apple.kpi.private` (`Private.exports`); SFBwfm does not declare that KPI. Its `m_adj`,
`m_copydata` and `m_freem` already bind IO80211Family's. No consistent rule keeps all six bindings
as they are. `pins-kernel48.txt` keeps this one as installed so that kernels 50 and 51 stay
byte-identical, until it is changed on purpose (delete the pin line). By source the two functions
allocate the same mbuf header (same wait and type values); that was read, not run.

## Proof (18 November, workstation; `nix-build ../m1-kc-bind/proof.nix -A <name>`)

| Collection | Result |
|---|---|
| `kernel50`: kernel 50, fixed tool + pin | collection file byte-identical to kernel 50's (sha256 66693bca…); `kernel.bin` repacked = 7d9ddaca… |
| `kernel51`: kernel 51, fixed tool + pin, now `../m1-kernel51/build-kc.nix` | collection identical to the old-tool kernel 51 (d421395e…); `kernel.bin` = 81033d24… |
| `kernel50-rule`: kernel 50, fixed tool, no pin | one pointer word differs: SFBwfm `m_gethdr` kernel → IO80211Family (plus the collection's UUID) |
| `variant-old`: kernel 51 with the four names exported, old tool | ext4, SFBwfm, SFAppleCIO differ from kernel 50 (`microuptime`, `m_gethdr`, `hz` → IO80211Family, `m_freem` → kernel) |
| `variant`: the same kernel, fixed tool + pin | all six bindings as kernel 50; the 56 kext entries at kernel 50's addresses, only pointers into the kernel differ, each to the same symbol |

`test-bind.py` compiles the patched `linker.c` into a harness that builds symbol tables and calls
`bind_lookup()`. It runs nine cases at four table sizes, under ASan and UBSan. Each of four
deliberate bugs in the patch makes it fail.

Kernel 51's link phase now differs from kernel 50's in two lines: the kernel and the kc-tools
store path. `KC_BIND_PINS` is set on the derivation. Other collection recipes keep
`../m1-bringup/kc-tools-fixed.nix` until they choose the fixed tool.
