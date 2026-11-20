#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

if (($# != 2)); then
    printf 'Usage: %s /path/to/zc310-ofd /path/to/sf-ofd-to-pdf\n' "$0" >&2
    exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
repository=$(cd "$1" && pwd)
output=$(realpath -m "$2")
test "$(git -C "$repository" rev-parse HEAD)" = 1f37d9f7c02f44dc1497b01ce5fc1e9b143578c1
git -C "$repository" diff --quiet HEAD

workspace=$(mktemp -d)
trap 'rm -rf -- "$workspace"' EXIT
git -C "$repository" archive HEAD | tar -xf - -C "$workspace"
mkdir -p "$workspace/cmd/sf-ofd-to-pdf"
cp "$here/ofd-to-pdf.go" "$workspace/cmd/sf-ofd-to-pdf/main.go"
cd "$workspace"
GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 "${GO:-go}" build \
    -mod=readonly -buildvcs=false -trimpath -ldflags '-s -w' -o "$output" ./cmd/sf-ofd-to-pdf
