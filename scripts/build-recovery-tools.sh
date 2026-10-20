#!/bin/bash
# SPDX-License-Identifier: MIT
# Generated-by: LLM
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
out=${1:-"$root/build/recovery-tools"}
compiler=${GO:-go}
mkdir -p "$out"
CGO_ENABLED=0 "$compiler" build -trimpath -ldflags='-s -w' -o "$out/sf-sha256-host" "$root/tools/recovery-sha256/main.go"
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 "$compiler" build -trimpath -ldflags='-s -w' -o "$out/sf-sha256-darwin-arm64" "$root/tools/recovery-sha256/main.go"
"$out/sf-sha256-host" --self-test
