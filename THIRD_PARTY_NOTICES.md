# Third-party materials

`configs/kernel.config` is copied unchanged from
`tools/aurora-sep/recipes/release20/kernel/config` in
[omacom/linux-aurora at 5d570a78a4ab29ac383ec8988be2356dfc6c8a75](https://github.com/omacom/linux-aurora/tree/5d570a78a4ab29ac383ec8988be2356dfc6c8a75).
Its original hash is recorded in `sources.lock.json`. Treat it as part of the
Linux kernel's GPL-2.0-only material; see the kernel repository's `COPYING` and
`LICENSES/preferred/GPL-2.0` for the license and syscall exception details.

`configs/rust-toolchain.toml` comes from the sibling file in that same recipe.
It records the upstream compiler selection and is retained with its original
source attribution.

The ignored `sources/` directories contain separate Linux and m1n1 repositories.
Their files keep their original notices and licenses. Cloned m1n1 artwork and
other submodules have their own licenses. They are not relicensed by this
repository's MIT license. Release packaging must carry applicable notices for
the components it distributes.

SiliconForest acknowledges the Linux contributors, Asahi Linux contributors,
Aurora Silicon contributors, Omacom contributors, and the other authors
identified in the original source history.
