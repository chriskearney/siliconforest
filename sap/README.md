<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->
# sap/

The SiliconForest system updater. Documentation: [docs/sap/](../docs/sap/README.md).

| Directory | What |
|---|---|
| `client/` | `sap` and `sf` (Rust; `cargo test`, `cargo test --features testing`) |
| `tools/sap_build.py` | publisher, offline signing step, reference verifier, `seed-db`, `anchor-token` |
| `trust/release-keys` | public release keys compiled into `sap` (same as the installer's) |
| `tests/` | end-to-end tests: `cd sap/tests && python3 -m unittest discover -s .` |

The `testing` feature adds hooks the end-to-end tests need (`SAP_FAULT`, `SAP_NOW`,
`SAP_ALLOW_NONROOT`, `SAP_LAUNCHCTL`); release builds do not have them (CI checks).

Building for SiliconForest (aarch64-apple-darwin) follows the userland recipe that already ships Rust
programs (chonkstep's `darwin-linker.py`):

    cargo build --release --locked --target aarch64-apple-darwin   # with the SF linker wrapper configured

Install `target/aarch64-apple-darwin/release/sap` as `/usr/bin/sap` and `sf` as `/usr/bin/sf` (as the
`sap` package of the channel). Not run on hardware yet.
