# Canonical libSystem recipe (build-libsystem-pagesize.nix: baseline e7aa00a6 plus the
# vm_page_size patch) with one more patch: posix_spawnattr_init zeroes the whole
# attribute struct before setting its defaults. Source-only until reviewed.
let
  pd = (import ../rebase/pd.nix).pd;
in pd.packages.${pd.buildSystem}.libsystem-arm64.overrideAttrs (old: {
  pname = "siliconforest-libsystem-spawnattr";
  patches = (old.patches or []) ++ [ ./fix-root/vm-page-size-symbol.patch ./fix-spawnattr/posix-spawnattr-init-zero.patch ];
})
