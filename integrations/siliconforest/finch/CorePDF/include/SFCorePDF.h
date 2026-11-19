/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Include after CoreGraphics/CoreGraphics.h.
   Opaque layout, node, and selection pointers for the private CorePDF calls
   Preview imports. This header does not redefine CGPDFPageRef or CGRect. */
#ifndef SF_COREPDF_H
#define SF_COREPDF_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stddef.h>

typedef struct SFCorePDFLayout *CGPDFLayoutRef;
typedef struct SFCorePDFNode *CGPDFNodeRef;
typedef struct SFCorePDFSelection *CGPDFSelectionRef;

CGPDFLayoutRef CGPDFPageGetLayout(CGPDFPageRef page);
void CGPDFPageRemoveLayout(CGPDFPageRef page);
CGPDFNodeRef CGPDFLayoutGetRootNode(CGPDFLayoutRef layout);
CGRect CGPDFNodeGetBounds(CGPDFNodeRef node);
int CGPDFNodeGetType(CGPDFNodeRef node);
CGPDFNodeRef CGPDFNodeGetChild(CGPDFNodeRef node, long index);
int CGPDFNodeGetChildCount(CGPDFNodeRef node);
double CGPDFNodeGetRotation(CGPDFNodeRef node);
CFRange CGPDFNodeGetTextRange(CGPDFNodeRef node);
long CGPDFNodeGetZ(CGPDFNodeRef node);
CGPDFNodeRef CGPDFNodeRetain(CGPDFNodeRef node);
void CGPDFNodeRelease(CGPDFNodeRef node);
CGRect CGPDFLayoutGetCharacterBounds(CGPDFLayoutRef layout, long index);
CGPDFSelectionRef CGPDFSelectionCreateInRect(CGPDFPageRef page, CGRect rect);
void CGPDFSelectionRelease(CGPDFSelectionRef selection);
long CGPDFSelectionGetNumberOfTextRanges(CGPDFSelectionRef selection);
CFRange CGPDFSelectionGetTextRange(CGPDFSelectionRef selection, long index);

#endif
