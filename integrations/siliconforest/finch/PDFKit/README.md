# Finch PDFKit for SiliconForest

The recipe builds the pinned Finch document, page, selection, and view sources.
The declarations are generated from Finch method signatures with local types and
public numeric values. The AppKit patch uses the retained NSGraphicsContext
graphics port. It adds no Apple implementation or SDK headers to the framework.

PDFView and PDFThumbnailView compile as an arm64 object. Linking the framework
still requires a CoreGraphics PDF provider with compatible public declarations
and implementations. The retained CoreGraphics and Onyx2D audit found 11 of
the 56 CGPDF functions used by PDFKit.m. Onyx2D has parser and scanner code,
but its integer and real output types differ from the arm64 CoreGraphics API.

A caller can supply a candidate CoreGraphics derivation by overriding the
recipe's `coregraphics` attribute. The recipe takes the public headers and
library from that same output. The provider audit checks exports before staging,
and the linker checks required symbols when building PDFKit.

```sh
nix-build --no-out-link integrations/siliconforest/finch/PDFKit/tests.nix
python3 integrations/siliconforest/finch/PDFKit/fixture.py NEW_DOCUMENT.pdf
python3 integrations/siliconforest/finch/PDFKit/fixture.py --view NEW_READING.pdf
python3 integrations/siliconforest/finch/PDFKit/provider-audit.py \
  --source sources/finch/userland/PDFKit/PDFKit.m \
  --provider CAPTURED_CoreGraphics --provider CAPTURED_Onyx2D --output AUDIT.json
```

The probes dynamically load PDFKit. The document probe checks the original
single-page fixture's metadata, bounds, text, and search. The view probe opens
the three-page fixture, uses PDFView to draw and navigate the pages, checks the
red, green, and blue center pixels, searches for a word on the second page,
and requests a thumbnail. Set the optional second argument of the view probe
to the private staged dylib path.

The document, view and Preview support probes build as arm64 Mach-O executables
with Nix. Native builds of the document and view probes passed against the
macOS 27.2.1 PDFKit on the M6. Independent Poppler output agrees on the three
page labels and color patches.

The retained M1 CoreGraphics opens the three-page fixture and draws its text.
It leaves the expected rectangle pixels white because the Onyx2D PDF scanner
writes float operands through pointers to double geometry members. The
`onyx-render.nix` candidate converts the operands after reading them. With that
Onyx2D loaded from a private prefix, a direct CoreGraphics probe on the M1
produced the expected red, green, and blue center pixels. The system Onyx2D
framework was untouched.

The `read.nix` build uses the retained `SFCGPDFRead` derivation by default.
It keeps drawing in CoreGraphics and Onyx2D. Missing CropBox entries
fall back to MediaBox, and missing bleed, trim, and art boxes fall back
to the effective CropBox. The drawing transform uses the same resolved box.
This recipe supports reading. Regenerating edited documents requires a writer.

The retained build passed all three probes on the M1 with private SFCGPDFRead
and Onyx2D providers. The Preview support probe checks annotation addition,
content changes, removal, and the read-only PDF encryption controls.
A separate PaperKit integration probe opened the three-page fixture through
PaperViewController and repeated the page navigation, pixel, text search,
and thumbnail checks. Preview's on-screen behavior still needs verification.
