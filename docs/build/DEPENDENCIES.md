# Build dependency inventory

The public release entry completed an initially clean container build and a typed
QEMU desktop session on 18 November 2026. [The measured receipt](../../reports/build-repro/public-build-001.json)
records isolation, intermediate public-source fixes and the final output tuple.
[The build guide](../BUILDING.md) explains the command and limits.

[Inventory 002](../../reports/build-repro/dependency-inventory-002.json) is the static
tracked-file snapshot at source revision `99312ab0555ab1e3dcfcf3fa9a6f0c33ef1f6bba`,
before the documentation-only receipt commit. Inventory 001 remains frozen.
Counts below are files containing a pattern, not occurrences. Only line numbers
are recorded; matched workstation values are not copied.

| Pattern | Files |
| --- | ---: |
| `local_fetch` | 54 |
| `home_path` | 496 |
| `store_literal` | 404 |
| `lab_input` | 1535 |
| `fetch` | 24 |

| Classification | Files with matches |
| --- | ---: |
| bench-or-documentation-outside-static-release-graph | 1061 |
| frozen-evidence | 902 |
| release-source-candidate | 64 |

The conservative static graph reaches 1,699 tracked files and includes inactive
fallbacks. No candidate Nix recipe matches a home-path or local-fetch pattern.
The separately evaluated six-output graph has 5,684 derivations, 2,161 fixed
outputs and 2,147 URL fetches, all hashed; no home/local URL or direct nonfixed
network-command matches were found. Static inspection alone is not a build proof.

Bench and documentation records outside the release entry remain available for
historical experiments. Frozen evidence is unchanged. Regenerate another snapshot
with `python3 tools/build_inventory.py --output /tmp/siliconforest-input-inventory.json`.
The public pins live in `sources.lock`; Nixpkgs and retained Cargo locks pin
transitive dependencies. Homebrew bottles are fetched binaries. See the build
receipt for the public-only executed build and scoped determinism checks.
