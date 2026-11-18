# Build dependency inventory

This source inventory was generated on 18 November 2026 while the public build
entry was under validation. The complete isolated build and QEMU boot are still
pending. It is not an end-to-end build receipt.

[The full inventory](../../reports/build-repro/dependency-inventory-001.json)
records every matching tracked text file, its classification, and matching line
numbers. It does not copy matched host paths, store paths, or file contents.
Counts below are files containing a pattern, rather than occurrences.

| Pattern | Files |
| --- | ---: |
| `local_fetch` | 54 |
| `home_path` | 496 |
| `store_literal` | 405 |
| `lab_input` | 1534 |
| `fetch` | 25 |

| Classification | Files with matches |
| --- | ---: |
| bench-or-documentation-outside-static-release-graph | 1078 |
| frozen-evidence | 902 |
| release-source-candidate | 48 |

The conservative static graph reaches 1604 tracked files. It follows literal Nix
references, the release recipe wrapper, and variable-selected framework recipes.
Inactive fallbacks may appear in the graph. No candidate Nix recipe matches the
home-path or local-fetch patterns in this scan.

- Release candidates need inspection and, ultimately, an isolated build. Some
  matches are public pinned fetches, comments, guest filesystem paths, or inactive
  bench fallbacks. A pattern match alone does not establish a workstation input.
- Bench and documentation records outside that graph remain available for
  historical experiments. They are not inputs to the intended release entry.
- Frozen evidence remains unchanged, including hash-pinned controllers,
  validation records, reports, and archived implementation attempts.

`tools/build_inventory.py` reads tracked files only; it never opens ignored lab
inputs. Run it from the repository to regenerate an inventory for another
revision:

```sh
python3 tools/build_inventory.py --output /tmp/siliconforest-input-inventory.json
```

The public source pins live in `sources.lock`. The generated primary and Cocoa
source trees have locked recursive content hashes. Nixpkgs and retained Cargo
lockfiles pin their transitive dependencies. Building the release in a fresh
public clone with no workstation mounts is the check of the executed build path;
the static scan cannot substitute for it.
