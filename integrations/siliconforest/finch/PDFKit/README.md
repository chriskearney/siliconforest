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

Both probes build as arm64 Mach-O executables with Nix. Native builds of those
probe sources passed against the macOS 27.2.1 PDFKit on the M6. Independent
Poppler output agrees on the three page labels and color patches. A SiliconForest
PDFKit runtime pass, on-screen view behavior, printing, editing, and Preview app
integration are still pending.
