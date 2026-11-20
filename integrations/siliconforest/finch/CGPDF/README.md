# SFCoreGraphicsPDF

Two libraries live here. `build.nix` is the original reader and the PDFKit compile fixture. Its draw path is a small bitmap glyph renderer. `build-o2.nix` is the app path: public read and scanner calls on retained Onyx2D objects, with `int`/`float` widened to `long`/`double`. It does not export `CGPDFDocumentCreateWithProvider` or `CGContextDrawPDFPage`, so pages stay `O2PDFPage` and drawing stays in CoreGraphics and Onyx. `CGPDFContextSetOutline` is not exported. Encrypted `/P` bits and named outline destinations are not decoded.



Open-source CGPDF reader for the Finch PDFKit port on SiliconForest. It supplies the document, page, scanner, text, and `CGContextDrawPDFPage` calls that retained CoreGraphics does not export. It is original C (SPDX MIT OR Apache-2.0). It is not Apple code, and it does not wrap the Onyx2D PDF objects.

## Why this is not an Onyx2D alias

Retained Onyx2D (`O2PDFScannerPopNumber`, `O2PDFObject_Integer`, `O2PDFObject_Real`) stores `O2PDFInteger` as `int` and `O2PDFReal` as `float`. Public arm64 LP64 `CGPDFInteger` is `signed long` and `CGPDFReal` is `double`. `CGRect` is four doubles. `CGAffineTransform` is six doubles, returned indirectly. Passing `&CGPDFReal` into `O2PDFScannerPopNumber` writes four bytes into an eight-byte slot. The coordinator already saw that as white rectangles on the M1 while text still drew. Their operand-widening patch stays in their tree. This library writes eight-byte values at the public boundary and exports its own document and page objects, so PDFKit must not mix them with `O2PDFDocument`.

## What the host proof covers

`sf_cgpdf_host.c` links the reader on the Linux host and checks a real parse, not a success stub:

- the one-page `PDFKit/fixture.py` file at this commit (`%PDF-1.4`, media 72 by 72, title `Finch fixture`, content `Finch PDF fixture`, font `F1` at size 6)
- a three-page reconstruction of the reading fixture: filled rectangles of about 8640 red, green, and blue pixels, some dark glyph pixels, and an unpainted origin
- FlateDecode round-trip of `BT (Hi) Tj ET` through zlib
- UTF-16BE `FE FF 00 41` to `A`, and PDFDocEncoding byte `0x80` to U+2022
- an outline title and destination page
- a 90-degree drawing transform `a=0 b=-1 c=1 d=0 tx=0 ty=72`, with rotation left as written
- an encrypted trailer that stays locked: unlock returns false, permissions are 0, the page number is 0, and the box is null

Build and run that proof from this directory:

```sh
gcc -std=c11 -Wall -Wextra -Werror -O2 -o /tmp/sf-cgpdf-host sf_cgpdf.c sf_cgpdf_host.c -lz -lm
python3 ../PDFKit/fixture.py /tmp/sf-one.pdf
/tmp/sf-cgpdf-host /tmp/sf-one.pdf
```

That binary is a host stand-in for CoreFoundation. It is not the arm64 dylib. The arm64 build is `nix-build build.nix`. The dylib sha256 is the receipt under that output's `share/SFCoreGraphicsPDF.sha256`. This seat does not run the dylib on M1 or M6.

## Link

Include `include/SFCoreGraphicsPDF.h` after `CoreGraphics/CGPDFDocument.h`. Its `-I` directory is `include/`, not a `CoreGraphics/` directory, so it does not shadow `CoreGraphics/CoreGraphics.h`. The header does not redeclare the eleven calls already in the retained headers, and it does not redeclare `CGContextDrawPDFPage`.

```text
-I $out/include
-L $out/usr/lib -lSFCoreGraphicsPDF -lCoreGraphics
```

`install_name` is `/System/Library/Frameworks/SFCoreGraphicsPDF.framework/Versions/A/SFCoreGraphicsPDF`. Put this library before `-lCoreGraphics` so two-level lookup binds the overlapping document, page, and draw symbols here. Leave the retained CoreGraphics and Onyx2D files in place.

## Limits

Classic cross-reference tables only. An xref stream fails closed. There is no object stream, JPEG2000, JBIG2, or CCITT. `FlateDecode` uses zlib inflate; a predictor above 1, a second filter, or an unknown filter makes `CGPDFStreamCopyData` return `NULL`.

`/Encrypt` is detected and the document stays locked. There is no password handler. Missing outline, encryption, or writer calls are failures, not invented success.

`CGPDFContextBeginPage`, `CGPDFContextEndPage`, and `CGPDFContextSetOutline` are absent from `exports.txt`. A PDF writer remains a separate dependency. Do not satisfy those names with empty functions.

The bitmap renderer draws `rg`, `re`, `f`/`F`/`f*`, and the text show operators `Tj`, `'`, and `"`. It does not draw `TJ`, `T*`, `q`/`Q`, or general paths. PDFKit text extraction uses the scanner callback path, which does pop arrays. The procedural glyphs are a 5-by-7 stand-in, not an Apple font. Filled-rectangle pixels are the render proof.

Preview's private `CGPDFLayout*`, `CGPDFNode*`, and `CGPDFSelection*` imports are outside the 56 Finch PDFKit calls.

## Provenance

- Reader semantics for boxes, the drawing transform, PDFDocEncoding, the operator list, and the unencrypted permission mask follow Finch `userland/CoreGraphics/CGPDF*.cpp` (SPDX MIT OR Apache-2.0) and ISO 32000-1. Those C++ files are a reference. `build.sh` there uses the Apple SDK, so they are not compiled into this dylib.
- Permission bit positions match `PDFKit/include/PDFKit/Numeric.h`, which records objc2 framework bindings 0.3.2.
- Object type numbers match the Onyx `kO2PDFObjectTypeNull = 1` sequence that `PDFKit.m` passes to `CGPDFObjectGetValue`.
- FlateDecode is zlib, linked from `p.zlib-arm64` (`libz.a`). The zlib header is copied into the build output `share/zlib.h` as the license-bearing header for that dependency. zlib's own copyright stays in that header.
- Onyx2D remains MIT, Copyright 2007 Christopher J. W. Lloyd, and is not the implementation of these symbols.
