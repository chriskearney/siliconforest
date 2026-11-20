/* SPDX-License-Identifier: MIT
   CGRect.frame(withWidth:using:) for TextEdit.

   TextEdit's arm64e draw path calls this Swift method (one site, in
   MultiplePageViewForAppKit2.draw). The registers at that call are:

     d0     frame width (CGFloat)
     x0     NSCompositingOperation
     d1-d4  the rectangle (self is last)

   NSFrameRectWithWidthUsingOperation, which AppKit.sf-under already
   exports, wants d0-d3 = rect, d4 = width, x0 = operation. The same
   binary's C call site leaves the rect in d0-d3, puts the width in d4,
   and the operation in w0. This stub only reorders the registers. */
.section __TEXT,__text,regular,pure_instructions
.globl _$sSo6CGRectV6AppKitE5frame9withWidth5usingy12CoreGraphics7CGFloatV_So22NSCompositingOperationVtF
.p2align 2
_$sSo6CGRectV6AppKitE5frame9withWidth5usingy12CoreGraphics7CGFloatV_So22NSCompositingOperationVtF:
	fmov	d5, d0
	fmov	d0, d1
	fmov	d1, d2
	fmov	d2, d3
	fmov	d3, d4
	fmov	d4, d5
	b	_NSFrameRectWithWidthUsingOperation
