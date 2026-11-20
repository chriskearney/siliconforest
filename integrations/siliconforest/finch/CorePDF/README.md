# CorePDF

SPDX-License-Identifier: MIT OR Apache-2.0

Private read and layout subset for the 17 C calls Preview imports from
`/System/Library/PrivateFrameworks/CorePDF.framework/Versions/A/CorePDF`
(current and compatibility 1.0.0). It does not export a document or page
creator. Those stay in CoreGraphics, so a `CGPDFPageRef` is the retained
Onyx page object.

`build.nix` builds the arm64 library for a private prefix. Use the retained
Onyx2D provider from `../PDFKit/onyx-render.nix` in that process. It keeps
indirect PDF objects alive across layout rebuilds and autorelease pool drains.

## What the calls do

`CGPDFPageGetLayout` walks the page content, including Resources and Contents
inherited through `O2PDFGetPageObjectForKey`. Text bytes are shown one at a
time with `O2ContextShowText`, so the width is that call's advance. The
origin is the text-matrix baseline and the height is the current Tf size.
`re` operands are widened from `O2PDFReal` to a double rectangle. The root
node type is `0x601`. Each text run and each rectangle is a type `1` child.
A rectangle child has an empty text range. `CGPDFPageRemoveLayout` drops the
cache. There is no layout release import.

`CGPDFSelectionCreateInRect` returns ranges of characters whose recorded
rectangles overlap the query. No overlap returns NULL. A zero advance stays
zero width; the overlap test still includes that baseline segment.

## Limits

Rotation is 0. Call sites compare that double with 0, and the unit of a
non-zero value was not established. Node types other than 1, 0x202, 0x203,
and 0x601 were not established; this subset emits 1 and 0x601 only.
ToUnicode and multi-byte font encodings are not decoded: one content byte is
one character. Path bounds are the `re` operands, not a filled raster.
Encrypted documents, outline writing, and ImageCaptureCore or MetalKit are
out of this library.
