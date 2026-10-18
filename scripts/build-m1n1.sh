#!/usr/bin/env bash
# Build an uninstalled m1n1 stage 2 payload using the personal fork's pinned source.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$root/scripts/sources.py" verify m1n1
export RUSTUP_TOOLCHAIN=1.89.0
if [[ -n ${LLVM_DIR:-} ]]; then
  export PATH="$LLVM_DIR/bin:$PATH"
fi
for tool in make clang ld.lld llvm-objcopy rustc cargo; do
  command -v "$tool" >/dev/null || { echo "Missing build dependency: $tool" >&2; exit 1; }
done
[[ $(rustc --version) == 'rustc 1.89.0 '* ]] || { echo 'Expected Rust 1.89.0' >&2; exit 1; }
[[ $(clang --version) == *'clang version 22.1.8'* ]] || { echo 'Expected LLVM 22.1.8' >&2; exit 1; }
[[ $(ld.lld --version) == *'22.1.8'* ]] || { echo 'Expected LLD 22.1.8' >&2; exit 1; }
source_dir="$root/sources/m1n1"
revision=$(git -C "$source_dir" rev-parse --short=12 HEAD)
# This upstream Makefile builds inside the source tree. Clean cached objects so
# a previous developer's stage 1 flags cannot leak into the stage 2 payload.
make -C "$source_dir" clean
make -C "$source_dir" -j"${JOBS:-4}" RELEASE=1 CHAINLOADING=0 USE_CLANG=1 \
  ARCH=aarch64-linux-gnu M1N1_VERSION_TAG="v1.6.1-omakernel.dev.g$revision"
grep -qx '#define RELEASE' "$source_dir/build/build_cfg.h"
if grep -Eq '^#define (CHAINLOADING|J613_ESP_STAGE1|ESP_STAGE2|J700_CDC_PROXY|T8140_KIS_PROXY)( |$)' "$source_dir/build/build_cfg.h"; then
  echo 'Unexpected stage 1 or proxy build flags' >&2
  exit 1
fi
destination="$root/dist/m1n1-$revision"
mkdir -p "$destination"
cp "$source_dir/build/m1n1.bin" "$source_dir/build/build_cfg.h" "$destination/"
cp "$root/sources.lock.json" "$destination/"
(cd "$destination" && sha256sum m1n1.bin build_cfg.h sources.lock.json > SHA256SUMS)
printf 'Built stage 2 payload: %s/m1n1.bin\n' "$destination"
