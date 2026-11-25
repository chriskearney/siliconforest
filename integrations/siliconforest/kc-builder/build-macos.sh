#!/bin/bash
# SPDX-License-Identifier: MIT
# Build the installer's kc-builder for macOS (Apple silicon) and sign it.
#
#   build-macos.sh OUT_DIR
#
# Source: ./prepare_source.py (PureDarwin kc-tools at the locked revision, with the same two patches as
# ./build-tools.nix). Compiled with the host's clang and the flags of kc-tools' CMakeLists.txt (C11 with GNU extensions, as CMake's default).
#
# Signing, by environment:
#   KC_SIGN_IDENTITY  a Developer ID Application identity: hardened runtime, secure timestamp
#   KC_SIGN_KEYCHAIN  optional keychain holding it (CI's temporary keychain)
#   neither           ad-hoc signature (codesign -s -). Fine for tests and rehearsals; a release must not
#                     ship it (OUT_DIR/kc-builder.signing says which one was used).
#
# Output: OUT_DIR/kc-builder, OUT_DIR/kc-builder.sha256 (of the signed file), OUT_DIR/kc-builder.signing,
# OUT_DIR/LICENSE.kc-tools (BSD-3-Clause, shipped next to the binary).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build-macos.sh OUT_DIR}
[ "$(uname -s)" = Darwin ] || { echo "build-macos.sh: macOS only" >&2; exit 2; }
mkdir -p "$out"
out=$(cd "$out" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 "$here/prepare_source.py" "$work/src" >/dev/null
cd "$work/src"
flags=(-std=gnu11 -O2 -Wall -Wno-unused-function -Wno-unused-variable -Wno-pointer-bool-conversion -Iinclude
       -arch arm64 -mmacosx-version-min=13.0)
clang "${flags[@]}" src/kc_builder.c src/fileset.c src/auxkc.c \
  lib/linker.c lib/macho_view.c lib/plist.c lib/prelink.c -o "$out/kc-builder"
cp LICENSE "$out/LICENSE.kc-tools"

if [ -n "${KC_SIGN_IDENTITY:-}" ]; then
  args=(--force --options runtime --timestamp --sign "$KC_SIGN_IDENTITY"
        --identifier org.siliconforest.kc-builder)
  [ -n "${KC_SIGN_KEYCHAIN:-}" ] && args+=(--keychain "$KC_SIGN_KEYCHAIN")
  codesign "${args[@]}" "$out/kc-builder"
  echo "developer-id" > "$out/kc-builder.signing"
else
  codesign --force --sign - --identifier org.siliconforest.kc-builder "$out/kc-builder"
  echo "ad-hoc" > "$out/kc-builder.signing"
  echo "build-macos.sh: no KC_SIGN_IDENTITY, signed ad-hoc (not for release)" >&2
fi
codesign --verify --strict --verbose=2 "$out/kc-builder"
shasum -a 256 "$out/kc-builder" | awk '{print $1}' > "$out/kc-builder.sha256"
echo "$out/kc-builder $(cat "$out/kc-builder.sha256") $(cat "$out/kc-builder.signing")"
