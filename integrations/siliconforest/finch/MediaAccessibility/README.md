# MediaAccessibility

`installed-graphics.nix` builds the whole pinned Finch implementation against
Cocoa's actual ImageIO/CoreText declarations and implementations. Public
declarations here are ours; no Apple SDK headers are imported.
Numeric enum ABI facts were checked against the binding author's
[objc2-media-accessibility 0.3.2 source](https://docs.rs/objc2-media-accessibility/0.3.2/objc2_media_accessibility/).

The same Linux-built `probe.c` completes on the authorized M5, including an
own-PNG caption round-trip. On M1, default caption types/ranges pass, but the
caption round-trip fails: Cocoa0109 reads EXIF/TIFF metadata but neither reads
nor writes XMP. Its destination can finalize image pixels while discarding the
requested caption. Merely resolving the eight formerly missing symbols did
not establish file conformance.

Our patch checks the temporary file's caption before committing the rename.
An unsupported backend now returns false and preserves the original. The M1
negative check (`unsupported-test.py` running the ordinary probe) passes with
`write=0` and byte-identical input. The positive case remains FAIL; this
framework is still staged. There is no preference mutation or installation.

TERM5 has the exact request: persist and read a PNG XMP iTXt packet with
`Iptc4xmpExt:ArtworkContentDescription`, through the normal ImageIO metadata
options, preserving existing pixels/metadata. The report and both failures
remain in ignored `runs/sffinch/ma-stage-v{1,2}/candidate.json`; the identical
Linux-built native probe is in `m5-ma-v1-reference.json`. No image created or
rewritten on the Mac was copied back.

The image-source and mutable-metadata caption functions share the URL
functions' metadata path. On M1, `media-accessibility-probe --metadata` passed
caption storage, clearing the tag value, invalid-metadata error reporting,
and uncaptioned-source lookup. The test uses an uncaptioned PNG and leaves the
file unchanged. File caption persistence still depends on ImageIO XMP support.
