#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# rehearse.sh OUT [--base ROOTFS_DIR] [--boot BOOT_DIR | --stage1 SF_STAGE1_BIN] [--names NAMES.tsv] [--grow BYTES]
#                  [--kc KC_INPUTS --kc-builder TOOL [--kc-link-tool HOST_TOOL] [--kc-expect SHA256]]
#
# One rehearsal release, end to end, on ordinary files (docs/installer/PAYLOAD.md section 10):
#   base root -> prepare_root.py -> grow_check.py -> throwaway TEST-ONLY key -> make_release.py
#   -> verify_release.py (deep) -> a tampered copy must be refused.
# Without --base a synthetic root stands in (synthetic_base.py), and without --boot the boot files
# are labelled placeholders; --stage1 puts a real stage 1 (boot/build_stage1.sh) among them, and make_release
# then checks it as a release would. Without --kc the kernel collection is synthetic inputs linked by the
# rehearsal stand-in (release/rehearsal_kc_builder.py); with --kc, a release-inputs directory
# (integrations/siliconforest/kc-builder/release-inputs.nix) and the macOS kc-builder (build-macos.sh,
# shipped as ad-hoc in a rehearsal) with a host kc-builder for the expected hash. Nothing is published and no device is opened. The key is made in OUT
# and is a test key: never commit OUT.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
out=${1:?usage: rehearse.sh OUT [--base DIR] [--boot DIR] [--names TSV] [--grow BYTES]}; shift
base= boot= stage1= names="$here/firmware/names/13.5-22G74-J313.tsv" grow=$((8 << 30)) version=0.0.0-rehearsal
kc= kcb= kclink= kcexpect=
while [ $# -gt 0 ]; do
    case $1 in
        --base) base=$2; shift 2;; --boot) boot=$2; shift 2;; --stage1) stage1=$2; shift 2;; --names) names=$2; shift 2;;
        --grow) grow=$2; shift 2;; --version) version=$2; shift 2;;
        --kc) kc=$2; shift 2;; --kc-builder) kcb=$2; shift 2;; --kc-link-tool) kclink=$2; shift 2;;
        --kc-expect) kcexpect=$2; shift 2;; *) echo "unknown $1" >&2; exit 2;;
    esac
done
export PATH="$PATH:/sbin:/usr/sbin"
mkdir -p "$out"
[ -z "$(ls -A "$out")" ] || { echo "$out is not empty" >&2; exit 1; }
if [ -z "$base" ]; then
    python3 "$here/image/synthetic_base.py" "$out/base" --mib 96 >/dev/null
    base=$out/base
fi
if [ -z "$boot" ]; then
    boot=$out/boot; mkdir -p "$boot"
    for f in sf-stage1.bin boot.bin; do printf 'SF-REHEARSAL placeholder %s\n' "$f" > "$boot/$f"; done
    [ -z "$stage1" ] || cp "$stage1" "$boot/sf-stage1.bin"
    printf 'rd=uuid boot-uuid=@SF_FSUUID@ sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@\n' > "$boot/bootargs.template"
fi
if [ -z "$kc" ]; then
    kc=$(python3 "$here/release/rehearsal_kc_builder.py" --synthetic "$out/kc-inputs")
    kcb=$here/release/rehearsal_kc_builder.py signing=rehearsal-stand-in
else
    [ -n "$kcb" ] || { echo "--kc needs --kc-builder" >&2; exit 2; }
    signing=ad-hoc
fi
kcargs=(--kc-inputs "$kc" --kc-builder "$kcb" --kc-builder-signing "$signing")
[ -n "$kclink" ] && kcargs+=(--kc-link-tool "$kclink")
[ -n "$kcexpect" ] && kcargs+=(--kc-expect "$kcexpect")
echo "== prepare root"; python3 "$here/image/prepare_root.py" "$base" "$out/root"
echo "== grow to $grow bytes"; python3 "$here/image/grow_check.py" "$out/root" "$grow"
echo "== test key (TEST-ONLY, not the release key)"; sh "$here/release/make_test_key.sh" "$out/keys" >/dev/null
echo "== release"
python3 "$here/release/make_release.py" --root-dir "$out/root" --boot-dir "$boot" --firmware-names "$names" \
    --profiles "$here/../profiles" --version "$version" --sequence 1 --key "$out/keys/TEST-ONLY-release-key" \
    "${kcargs[@]}" --out "$out/release" --rehearsal
echo "== verify"; python3 "$here/release/verify_release.py" "$out/release" --allowed-signers "$out/keys/allowed_signers" --allow-rehearsal
if python3 "$here/release/verify_release.py" "$out/release" --allowed-signers "$out/keys/allowed_signers" >/dev/null 2>&1; then
    echo "a rehearsal verified without --allow-rehearsal" >&2; exit 1
fi
cp -r "$out/release" "$out/tampered"; printf x >> "$out/tampered/boot.bin"
if python3 "$here/release/verify_release.py" "$out/tampered" --allowed-signers "$out/keys/allowed_signers" --allow-rehearsal >/dev/null 2>&1; then
    echo "a tampered release verified" >&2; exit 1
fi
rm -rf "$out/tampered"
echo "REHEARSAL_OK $out/release"
