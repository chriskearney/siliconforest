# ImageIO source compatibility for Preview

This private ImageIO wrapper reexports the existing ImageIO image as
`ImageIO.sf-under` in the same version directory. The wrapper has a
distinct install name so dyld can load both. The runtime copy of
`ImageIO.sf-under` comes from the tested SiliconForest installation.

Provider-backed source creation uses the existing CoreGraphics image
reader. Source format enumeration describes the six Onyx2D decoders.
Those decoders use the first frame as the primary image. The metadata
keys retain their values from the pinned Finch source. Codecs remain
in CoreGraphics/Onyx2D.

The native probe opens a PNG through a data provider, decodes its pixels,
checks the source format and primary index, and reads two metadata keys.

Image scaling draws into an 8-bit RGB bitmap with premultiplied alpha. It
supports the integer option values 0 and 1, caps the destination
allocation, and returns a newly owned image. The probe checks the scaled
dimensions and reads a pixel from the destination image.

The opaque-copy operation supports the null options argument and
skip-last alpha format used by Preview. It recovers straight RGB from
premultiplied samples before removing alpha. The probe checks that a
translucent red source becomes opaque without darkening its color.

The destination wrapper encodes PNG and TIFF using the installed Onyx2D
writers. It collects frames before writing to data, a consumer, or a file
URL. Unsupported auxiliary data and separate metadata cause finalization
to fail with the buffered destination unchanged. The probe encodes,
reopens, and decodes a PNG and checks that a gain-map request produces
no output.

The format query describes the PNG writer's alpha support and the TIFF
writer's alpha and multipage support. Sources created with data or a data
provider retain the input snapshot. A destination can copy that snapshot
verbatim when the type and frame count match, all frames decode, and no
metadata or encoding edits were requested. The probe checks byte equality
and confirms that a mismatched type leaves the output unchanged.

The container properties query returns the byte size for sources opened
by this wrapper and a frame-ordered array built from the existing Onyx2D
property dictionaries. The IPTC keyword setter stores the values in the
metadata model's Dublin Core subject tag.

For Open Fixed-layout Document (OFD) import, place `sf-ofd-to-pdf` beside
the ImageIO binary in `Versions/A`. Build it with `build-ofd.sh` from a
checkout of [zc310/ofd](https://github.com/zc310/ofd) at the script's pinned
revision and Go 1.27.1. The helper uses the upstream OFD reader and PDF
writer. It runs as a child process with bounded input, output, and
execution time. Conversion takes a local file URL and returns owned PDF
data on success. Missing helpers and unsuccessful conversions return
null. The native probe accepts an optional two-page OFD fixture.
