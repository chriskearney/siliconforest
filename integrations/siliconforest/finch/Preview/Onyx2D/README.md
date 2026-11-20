# Onyx2D PDF 1.5 overlay

`onyx2d_pdf15.m` repairs PDF 1.5 xref streams and object streams, nested
parentheses in literal strings, RFC 2083 PNG predictors, 24-bit RGB
stride, and TJ width scaling. It reexports Onyx2D.

The rectangle-operand fix already on this branch stays in
`integrations/siliconforest/finch/PDFKit/patches/0002-onyx-pdf-rectangle-operands.patch`.
This overlay does not repeat it.

Vendored Onyx2D bases and build outputs are not included. The overnight
build script hardcodes nix store paths and is not included.
