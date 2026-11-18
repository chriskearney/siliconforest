#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

set -euo pipefail
version=$1
root=$2
bootfiles=$3
artwork=$4
output=$5
scripts=$(cd -- "$(dirname -- "$0")" && pwd)
boot=$(mktemp -d)
trap 'rm -rf -- "$boot"' EXIT
stem=siliconforest-$version
cp -- "$bootfiles"/* "$boot/"
python3 -I -B "$scripts/make-icon.py" "$artwork" "$boot/siliconforest.icns"
tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C "$boot" -cf - . \
    | xz -T1 -6 > "$output/$stem-boot.tar.xz"
xz -T2 -1 --stdout "$root/siliconforest-root.ext4" \
    | split -b 1900000000 -d -a 2 - "$output/$stem-root.ext4.xz."
cp -- "$root/root.manifest.tsv" "$output/$stem-root.manifest.tsv"
python3 -I -B "$scripts/package.py" "$version" "$root" "$boot" "$output"
