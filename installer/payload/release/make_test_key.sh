#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
#
# make_test_key.sh DIR: make a throwaway Ed25519 key for rehearsal releases, and its allowed_signers.
#
# THIS IS NOT THE RELEASE KEY. The release key is Chris's, made and kept offline by him
# (docs/installer/DESIGN.md section 10); it does not exist yet. The comment of this key carries
# TEST-ONLY, make_release.py signs a rehearsal only with such a key and refuses it for anything
# else, and verify_release.py marks a release signed by it as a rehearsal. Never commit DIR.
set -eu
dir=${1:?usage: make_test_key.sh DIR}
mkdir -p "$dir"
chmod 700 "$dir"
key="$dir/TEST-ONLY-release-key"
[ -e "$key" ] && { echo "$key exists" >&2; exit 1; }
ssh-keygen -q -t ed25519 -N '' -C 'siliconforest-release TEST-ONLY not-for-release' -f "$key"
printf 'siliconforest-release namespaces="siliconforest-release" %s\n' "$(cat "$key.pub")" > "$dir/allowed_signers"
echo "$key"
