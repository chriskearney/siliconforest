#!/usr/bin/env bash
# Build production GLVND libraries into a private DESTDIR; never install on host.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 "$root/scripts/sources.py" verify mesa
[[ $(uname -m) == aarch64 ]] || { echo 'Use an aarch64 package builder.' >&2; exit 1; }
if [[ -n ${LLVM_DIR:-} ]]; then export PATH="$LLVM_DIR/bin:$PATH"; fi
[[ $(clang --version) == *'clang version 22.1.8'* ]] || { echo 'Expected LLVM 22.1.8' >&2; exit 1; }
build="$root/build/mesa-package"
[[ ! -e $build ]] || { echo "Use a fresh build directory: $build" >&2; exit 1; }
meson setup "$build" "$root/sources/mesa" --prefix=/usr --libdir=lib \
  --buildtype=release -Db_ndebug=false -Dgallium-drivers=asahi,zink,softpipe -Dvulkan-drivers=asahi \
  -Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled \
  -Dglvnd=enabled -Dllvm=enabled -Ddraw-use-llvm=false -Dbuild-tests=true \
  -Dmesa-clc=enabled -Dprecomp-compiler=enabled -Dvideo-codecs= -Dgallium-va=disabled
meson compile -C "$build" -j "${JOBS:-4}"
meson test -C "$build" --suite asahi --print-errorlogs
DESTDIR="$root/dist/mesa-root" meson install -C "$build" --no-rebuild
printf 'Staged production libraries: %s/dist/mesa-root\n' "$root"
