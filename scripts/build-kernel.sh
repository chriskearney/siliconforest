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

output="$root/build/linux"
mkdir -p "$output"
cp "$root/configs/kernel.config" "$output/.config"
"$root/sources/linux/scripts/config" --file "$output/.config" --set-str LOCALVERSION '' --disable LOCALVERSION_AUTO
# Set a distinct module ABI name even for an otherwise identical source tree.
export LOCALVERSION
LOCALVERSION=-siliconforest-dev-$(git -C "$root/sources/linux" rev-parse --short=12 HEAD)
export KBUILD_BUILD_USER=siliconforest
export KBUILD_BUILD_HOST=builder
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP=$(git -C "$root/sources/linux" show -s --format=%cD HEAD)
make -C "$root/sources/linux" O="$output" olddefconfig
make -C "$root/sources/linux" O="$output" rustavailable
make -C "$root/sources/linux" O="$output" -j"${JOBS:-4}" Image modules dtbs
make -s -C "$root/sources/linux" O="$output" kernelrelease > "$output/kernelrelease"
printf 'Built %s\nOutput: %s\n' "$(cat "$output/kernelrelease")" "$output"
