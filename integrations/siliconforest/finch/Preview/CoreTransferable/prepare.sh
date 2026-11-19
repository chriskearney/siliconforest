#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
source_file=$1
output_dir=$2
echo "ea60f79c93c8d10d38efccc80f4d904d536da2b1583a0055359833baf9c9f15a  $source_file" | sha256sum -c
mkdir "$output_dir"
sed '/^\/\/ MARK: - NSItemProvider/,$d' "$source_file" > "$output_dir/CoreTransferable.swift"
patch --batch "$output_dir/CoreTransferable.swift" < "$here/core-transferable.patch"
