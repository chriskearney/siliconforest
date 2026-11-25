<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Chris Kearney and the SiliconForest contributors -->
# SAP formats

All JSON is parsed strictly by the client: UTF-8, no duplicate keys, integers only (no fractions or
exponents), at most 4 MiB for a manifest. Unknown fields are ignored unless the manifest names them
in `critical`, in which case a client that does not understand them refuses the manifest ("update SAP
first"). Hashes are lowercase hex SHA-256.

## Manifest: `v1/<channel>/manifest.json`, schema `siliconforest-update/1`

    {
      "schema": "siliconforest-update/1",
      "channel": "stable",
      "release": "0.6.0",
      "sequence": 42,                       # strictly increasing per channel
      "issued": "2026-11-25T18:00:00Z",
      "expires": "2026-12-25T18:00:00Z",
      "min_sap": null,                      # or "1.1.0"
      "critical": [],                       # names of fields a client must understand
      "base": {"release": "0.6.0", "sums_sha256": "<SHA-256 of the installer release's SHA256SUMS>"},
      "signing_key": {"fingerprint": "SHA256:…"},   # informational
      "allowed_prefixes": ["/"],
      "trust": {"version": 2, "keys": ["ssh-ed25519 AAAA…", …]},   # optional: anchor rotation
      "packages": [
        {"name": "vim", "version": "9.1.0-1", "kind": "files", "activate": "restart",
         "depends": [{"name": "libncurses", "version": ">= 6.4"}], "bytes": 12345,
         "record": {"url": "pool/vim_9.1.0-1.record.json", "sha256": "…"},
         "payload": {"url": "pool/vim_9.1.0-1.sappkg", "sha256": "…"}}
      ],
      "removed": [], "rollout": null, "delta": null
    }

Signature: `manifest.json.sig`, an OpenSSH SSHSIG (Ed25519, namespace `siliconforest-release`, hash
sha512 or sha256) over the exact bytes of `manifest.json`, as `ssh-keygen -Y sign` makes it.

Package kinds: `base` (sf-base: every root file no other package claims), `files`, `kc-input`
(kernel-collection inputs), `kc-recipe` (`sf-kernel-collection`), `boot-stage2` (`sf-boot`, target
SFBOOT). The last three need `--boot`. Version order: Debian-like `upstream-revision`, numeric
components compared as numbers.

## Package record: `pool/<name>_<version>.record.json`, schema `siliconforest-package/1`

    {"schema": "siliconforest-package/1", "name": "vim", "version": "9.1.0-1", "kind": "files",
     "summary": "…", "arch": "arm64",
     "depends": [{"name": "libncurses", "version": ">= 6.4"}], "conflicts": [], "replaces": [],
     "files": {"name": "vim_9.1.0-1.files.tsv", "count": 214, "bytes": 3456789, "sha256": "…"},
     "config_files": ["/private/etc/vimrc"],
     "services": [{"label": "org.siliconforest.vimd", "activate": "restart"}],
     "activate": "none" | "restart" | "reboot",
     "payload": {"name": "vim_9.1.0-1.sappkg", "format": "xz-bodies/1", "bytes": 1234567, "sha256": "…"},
     "target": "root" | "sfboot"}

`sf-kernel-collection` adds `kernel_collection` (`format`, `link_args`, `kc_base`, `kernel {path,
package}`, `tool {path, package, signing}`, `bundles [{dir, package, files [{path, mode,
root_path}]}]`, `collection_sha256`, `collection_bytes`) and `bootargs_template` (with
`@SF_FSUUID@`, `@SF_PARTUUID@`, `@SF_PART_LBA@`, whose values SAP recovers from the machine's current
boot arguments, never guesses). `sf-boot` holds `/sf/boot.bin` (slot-A stage 2) and optionally
`/sf/b/boot.bin` (slot-B stage 2).

## File list: `pool/<name>_<version>.files.tsv`

The installer's per-file manifest format, one row per path, sorted, tab-separated:

    # path	type	mode	uid	gid	size	sha256 or link target
    /usr/bin/vim	f	0755	0	0	3456789	<sha256>
    /usr/bin/vi	l	0777	0	0	3	vim
    /usr/share/vim	d	0755	0	0	0	-

Paths are absolute, without `.`, `..` or empty components, and are real paths (no component may be a
symlink on the machine or in the same update).

## Payload: `pool/<name>_<version>.sappkg`, format `xz-bodies/1`

One xz stream (CRC64) of the bodies of the `f` rows, concatenated in file-list order. Everything else
(type, mode, owner, link targets, directories) comes from the signed file list; each body is checked
against its row's SHA-256 before it is staged.

## Journal: `/private/var/db/sap/journal/<txn>.jsonl`

One JSON object per line; each has `record`, `time` and `prev` (SHA-256 of the previous line, so the
chain shows truncation or editing). Records: `begin` (the plan), `intent` (every operation, the commit
point), `swapped` (operation index done), then `done` or `aborted` (`recovered`: `forward`,
`rollback`, `nothing changed`).

Operations: `put` (staged path, backup path, old and new state, mode, owner), `remove`, `mkdir`,
`rmdir`, each on `area` `root` or `sfboot`, and `arm` (A/B slots: `path` is the slot's stage 2, `new`
its hash, `mode` the generation passed to `sf-bootslot arm`). States are `f:<sha256>`, `l:<target>`,
`d` or absent.

## Installed database: `/private/var/db/sap/`

`state.json` (`sap-state/1`: `highest_sequence`, `manifest_sha256`, `held`, `lineage`,
`anchor_version`); `installed/<name>.json` (`sap-installed/1`: name, version, kind, txn, the record)
and `installed/<name>.files.tsv` (the owned file list).

## Trust token (boot arguments)

`sf_trust=<version>:<base64 raw Ed25519 key>[,<key>…]` (no padding), in the CONFIG record of
kernel.bin. `sf_slot=b` marks a slot-B kernel (A/B boot).
