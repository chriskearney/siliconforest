<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->
# Operating a SAP channel

Everything here runs on the build host except signing, which happens where the release key lives
(offline, on the M3, as for installer releases). The publisher never reads a private key: signing is
`ssh-keygen -Y sign` with a key path, exactly like the release's `SHA256SUMS`.

## Publishing a release

Inputs: the release's root tree (or its per-file manifest TSV plus the tree), a package spec, the
installer release directory (for the kernel collection), and the stage 2 builds.

    python3 sap/tools/sap_build.py publish \
        --repo /srv/sap --release 0.6.0 \
        --tree /path/to/root --spec sap-spec.json \
        --kc-release /path/to/installer-release \
        --boot-bin sf-boot.bin --boot-bin-b sf-boot-slot-b.bin \
        --base-sums /path/to/installer-release/SHA256SUMS \
        --unsigned

* `--spec`: which paths make which package; everything else belongs to `sf-base`:

      {"base": {"name": "sf-base"},
       "packages": [{"name": "vim", "version": "9.1.0-1", "paths": ["/usr/bin/vim", "/usr/share/vim/**"],
                     "depends": ["libncurses >= 6.4"], "config_files": ["/private/etc/vimrc"],
                     "services": [{"label": "org.siliconforest.vimd", "activate": "restart"}],
                     "replaces": [], "conflicts": []}]}

* Versions: a package whose content did not change keeps its published version (clients download
  nothing for it). A changed package without an explicit version gets `<release>-1` or a bumped
  revision; an explicit version that did not move is refused unless `--bump-changed`.
* `--kc-release` splits the kernel collection into `sf-kc-builder`, `sf-kc-kernel`, one
  `sf-kext-<name>` per bundle and the `sf-kernel-collection` recipe (link order, options, expected
  `collection_sha256`), so a changed kext costs one small download plus a relink on the machine.
* `--root-tsv` uses the installer's per-file manifest instead of scanning (`sap_build.py scan TREE`
  writes the same format).
* Protected installer files (`/private/var/db/sf-boot-receipt`, `sf-firmware-slot`) are never packaged.
* The channel layout is static files: `v1/stable/manifest.json`, `manifest.json.sig`,
  `pool/<name>_<version>.{record.json,files.tsv,sappkg}`. Pool files are immutable; publishing never
  rewrites one with different content. Serve the directory over HTTPS or any mirror.
* `--sequence` defaults to the previous one plus one; `--expires-days` (30) bounds how long a mirror
  can replay an old manifest. Republish (even unchanged) before it expires.

## Signing (offline)

Copy `v1/stable/manifest.json` to the signing machine, then:

    python3 sap/tools/sap_build.py sign --key /path/to/release-key v1/stable/manifest.json

Bring back `manifest.json.sig` and check it before upload:

    python3 sap/tools/sap_build.py verify --repo /srv/sap \
        --allowed-signers installer/payload/release/allowed_signers --deep

`verify --deep` is the Python reference verifier (signature, schema, freshness, every pin and every
file hash); CI runs it against the Rust client on the same channels.

## Key handling

* The release key is the installer's Ed25519 key (`installer/payload/release/allowed_signers`); SAP
  uses the same namespace, `siliconforest-release`. It never leaves the offline machine, is never
  copied to the build host, CI or a test. Tests make throwaway keys (`sap_build.py test-key DIR`,
  comment `TEST-ONLY`).
* Machines trust, in order: the `sf_trust=<version>:<key>[,<key>]` token in the boot arguments of the
  kernel they booted (written by the installer, rewritten only by SAP with `--boot`); else the same
  token in `sf/trust` on SFBOOT (the installer writes it; IMAGE.md); else the keys
  compiled into `sap` (`sap/trust/release-keys`, kept identical to `allowed_signers` by
  `sap/tests/test_trust.py`), with a warning.
* The token for a key list: `sap_build.py anchor-token installer/payload/release/allowed_signers`.

## Rotating the key

1. Make the new key offline. Publish a release with both keys in the manifest, signed by the **old**
   key:

       sap_build.py publish … --trust-keys old-and-new.pub --trust-version 2 --unsigned

2. Machines that run `sap upgrade --boot` write `sf_trust=2:<old>,<new>` into kernel.bin (with A/B
   slots, into the staged slot). From the next start they accept either key.
3. Once enough machines have moved, publish with `--trust-keys new.pub --trust-version 3` signed by
   either key, then sign everything with the new key only.
4. Update `sap/trust/release-keys` (`# version N`) and `installer/payload/release/allowed_signers`
   together for new installs and the fallback.

A machine that missed step 2 still has only the old key: keep signing with the old key until the
rotation release is old enough, or reinstall such machines.

## Bootstrapping an installed image

Images built with `prepare_root.py --sap-bin` already carry a seeded database (IMAGE.md). Other
images built from a release that is also published as a channel get their database with:

    python3 sap/tools/sap_build.py seed-db --repo /srv/sap --root /mnt/image \
        --allowed-signers installer/payload/release/allowed_signers

It checks every file of every root package on the image and writes `/private/var/db/sap`. After that
`sap verify` is clean and `sap upgrade` downloads only what later releases change.

## Rolling back a bad release

Clients never accept a lower sequence. To undo a release, publish the previous content again with a
higher sequence: unchanged packages keep their versions; packages whose content goes back need a
higher version (`--bump-changed`). On a single machine, `sap rollback` undoes the last transaction from
its backups.
