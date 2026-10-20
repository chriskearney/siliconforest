# Replaceable stage-2 artwork

The neutral stage-1 Recovery migration does not change stage 2. Unbranded
stage-2 packages still draw the built-in Asahi logo. m1n1 already supports a
custom, data-only `m1n1_logo_256128` payload: its header and opaque RGBA pixels
(256 square, then 128 square) must be the first payload after the padded loader,
before the DTB. Inserting it later does not override the logo shown at startup.

Generate the artwork with the source artwork exporter, then compose it with:

```sh
python3 scripts/stage2-logo.py --artwork ARTWORK_EXPORT --output BUILD/stage2-logo.bin
```

The m1n1 packaging step includes this file when present. A matched release opts
in using `boot.stage2_logo_sha256`. Both the package verifier and stage-2 image
composer check this digest and the payload format. Missing, modified, truncated,
or non-opaque artwork is refused. Releases without the field retain exactly
their previous byte composition. Artwork changes require a new signed package
and matched release; updating a file on the ESP by hand would be overwritten by
the package boot hook and fail the matched-chain check.

This changes no executable m1n1 bytes, kernel, DTB, U-Boot or GPU handoff options.
Future artwork can be changed through Linux and the signed installer without a
second stage-1 Recovery migration. The M3 release must also explicitly admit the
neutral stage-1 identity after that migration; this is an exact identity added
to the attended manifest, not a relaxation of the boot or graphics guards.

Host tests cover payload position, unchanged boot components, malformed assets,
tampered package contents and compatibility with old manifests. Actual boot
and visual verification are separate hardware checks.
