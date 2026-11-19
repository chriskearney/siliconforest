# ImageIO source compatibility for Preview

This private ImageIO wrapper reexports the existing ImageIO image as
`ImageIO.sf-under` in the same version directory. The wrapper has a
distinct install name so dyld can load both. The runtime copy of
`ImageIO.sf-under` comes from the tested SiliconForest installation.

Provider-backed source creation uses the existing CoreGraphics image
reader. Source format enumeration describes the six Onyx2D decoders.
Those decoders use the first frame as the primary image. The metadata
keys retain their values from the pinned Finch source. Codecs remain
in CoreGraphics/Onyx2D. Destination and gain-map format behavior is
outside this wrapper.

The native probe opens a PNG through a data provider, decodes its pixels,
checks the source format and primary index, and reads two metadata keys.
