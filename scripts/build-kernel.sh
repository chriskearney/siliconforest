#!/usr/bin/env bash
# Compile only. Package creation and installation are separate milestones.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$root/scripts/sources.py" verify linux

if [[ -n ${LLVM_DIR:-} ]]; then
  export PATH="$LLVM_DIR/bin:$PATH"
  export LIBCLANG_PATH="$LLVM_DIR/lib"
elif [[ -x /usr/lib/llvm22/bin/clang ]]; then
  export PATH="/usr/lib/llvm22/bin:$PATH"
  export LIBCLANG_PATH=/usr/lib/llvm22/lib
else
  export LIBCLANG_PATH=${LIBCLANG_PATH:-/usr/lib}
fi
export RUSTUP_TOOLCHAIN=1.93.1
export ARCH=arm64
export LLVM=1
: "${BINDGEN:?Set BINDGEN to the corrected generator built by sources/linux/tools/aurora-bindgen/build.py}"
export BINDGEN
for tool in make clang ld.lld llvm-ar rustc cargo bindgen bc flex bison cpio; do
  command -v "$tool" >/dev/null || { echo "Missing build dependency: $tool" >&2; exit 1; }
done
[[ $(clang --version) == *'clang version 22.1.8'* ]] || { echo 'Expected LLVM 22.1.8' >&2; exit 1; }
[[ $(ld.lld --version) == *'22.1.8'* ]] || { echo 'Expected LLD 22.1.8' >&2; exit 1; }
[[ $(rustc --version) == 'rustc 1.93.1 '* ]] || { echo 'Expected Rust 1.93.1 with rust-src' >&2; exit 1; }
# LLVM supplies the arm64 target compiler and linker on x86_64 as well.
case $(uname -m) in
  aarch64|x86_64) ;;
  *) echo 'Use a Linux aarch64 or x86_64 builder.' >&2; exit 1 ;;
esac

variant=${KERNEL_VARIANT:-normal}
case $variant in
  normal) output="$root/build/linux" ;;
  m3-native) output="$root/build/linux-m3-native" ;;
  *) echo 'KERNEL_VARIANT must be normal or m3-native' >&2; exit 1 ;;
esac
mkdir -p "$output"
cp "$root/configs/kernel.config" "$output/.config"
"$root/sources/linux/scripts/config" --file "$output/.config" --set-str LOCALVERSION '' --disable LOCALVERSION_AUTO
if [[ $variant == m3-native ]]; then
  "$root/sources/linux/scripts/config" --file "$output/.config" \
    --enable EXPERT --disable USB4 --enable SILICONFOREST_M3
fi
# Set a distinct module ABI name even for an otherwise identical source tree.
export LOCALVERSION
LOCALVERSION=-siliconforest-$variant-$(git -C "$root/sources/linux" rev-parse --short=12 HEAD)-layout1
export KBUILD_BUILD_USER=siliconforest
export KBUILD_BUILD_HOST=builder
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP=$(git -C "$root/sources/linux" show -s --format=%cD HEAD)
make -C "$root/sources/linux" O="$output" BINDGEN="$BINDGEN" BINDGEN_LAYOUT_TESTS=1 olddefconfig
if [[ $variant == m3-native ]]; then
  grep -qx 'CONFIG_SILICONFOREST_M3=y' "$output/.config" || { echo 'Native kernel option was not admitted' >&2; exit 1; }
  if grep -Eq '^CONFIG_USB4=[ym]$' "$output/.config"; then echo 'Native profile requires USB4 disabled' >&2; exit 1; fi
fi
make -C "$root/sources/linux" O="$output" BINDGEN="$BINDGEN" BINDGEN_LAYOUT_TESTS=1 rustavailable
make -C "$root/sources/linux" O="$output" BINDGEN="$BINDGEN" BINDGEN_LAYOUT_TESTS=1 -j"${JOBS:-4}" Image modules dtbs
make -s -C "$root/sources/linux" O="$output" kernelrelease > "$output/kernelrelease"
python3 "$root/scripts/kernel_layout.py" "$output" "$(command -v "$BINDGEN")"
printf 'Built %s\nOutput: %s\n' "$(cat "$output/kernelrelease")" "$output"
