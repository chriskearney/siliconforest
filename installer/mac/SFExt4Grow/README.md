<!-- SPDX-License-Identifier: MIT -->
# SFExt4Grow

`sf-ext4grow` and the `SFExt4` library: the installer's offline ext4 root grower (step S48), clean-room Swift with no GPL
code. Design, refusals, write order, recovery and results: [`docs/installer/EXT4GROW.md`](../../../docs/installer/EXT4GROW.md).

```sh
swift build -c release
.build/release/sfext4grow-selftest                # pure checks
scripts/oracle-test.sh /tmp/ext4grow-test         # image tests; needs e2fsprogs (test oracle only) on PATH or in $E2FSPROGS_SBIN
SF_REAL_ROOT_DIR=<dir with siliconforest-root.ext4 + root.json> scripts/oracle-test.sh DIR   # adds the 96 GiB real-root run
```

Plain files and attached disk images only. There is no real-disk path in this package.
