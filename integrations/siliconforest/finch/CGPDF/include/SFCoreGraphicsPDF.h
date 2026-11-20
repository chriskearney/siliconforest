/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * Supplemental CGPDF declarations for the Finch PDFKit port.
 *
 * Include this only after CoreGraphics/CGPDFDocument.h. That header already
 * typedefs CGPDFDocumentRef and CGPDFPageRef and declares the eleven retained
 * document, page, and writer calls. This header adds the read, scanner, text,
 * and render calls those headers do not declare. It does not redefine
 * CGPDFDocumentRef, the box enum, or CGRect.
 *
 * CGPDFInteger is a signed long and CGPDFReal is a double on arm64 LP64.
 * O2PDFInteger and O2PDFReal are a different width and are not these types.
 *
 * CGPDFContextBeginPage and CGPDFContextEndPage are declared for the
 * Onyx-backed library, which forwards them to O2PDFContext. CGPDFContextSetOutline
 * stays absent. The original reader dylib does not export the page draw path.
 */
#ifndef SF_COREGRAPHICS_PDF_H
#define SF_COREGRAPHICS_PDF_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef long CGPDFInteger;
typedef double CGPDFReal;
typedef unsigned char CGPDFBoolean;
typedef uint32_t CGPDFAccessPermissions;

enum {
    kCGPDFObjectTypeNull = 1,
    kCGPDFObjectTypeBoolean = 2,
    kCGPDFObjectTypeInteger = 3,
    kCGPDFObjectTypeReal = 4,
    kCGPDFObjectTypeName = 5,
    kCGPDFObjectTypeString = 6,
    kCGPDFObjectTypeArray = 7,
    kCGPDFObjectTypeDictionary = 8,
    kCGPDFObjectTypeStream = 9
};

/* Same bit positions as PDFKit/include/PDFKit/Numeric.h (objc2 0.3.2). */
enum {
    kCGPDFAllowsLowQualityPrinting = 1 << 0,
    kCGPDFAllowsHighQualityPrinting = 1 << 1,
    kCGPDFAllowsDocumentChanges = 1 << 2,
    kCGPDFAllowsDocumentAssembly = 1 << 3,
    kCGPDFAllowsContentCopying = 1 << 4,
    kCGPDFAllowsContentAccessibility = 1 << 5,
    kCGPDFAllowsCommenting = 1 << 6,
    kCGPDFAllowsFormFieldEntry = 1 << 7
};

typedef struct SfPdfObj *CGPDFObjectRef;
typedef struct SfPdfObj *CGPDFArrayRef;
typedef struct SfPdfObj *CGPDFDictionaryRef;
typedef struct SfPdfObj *CGPDFStreamRef;
typedef struct SfPdfStr *CGPDFStringRef;
typedef struct SfPdfCs *CGPDFContentStreamRef;
typedef struct SfPdfScan *CGPDFScannerRef;
typedef struct SfPdfOps *CGPDFOperatorTableRef;

typedef void (*CGPDFDictionaryApplierFunction)(const char *key, CGPDFObjectRef value, void *info);
typedef void (*CGPDFOperatorCallback)(CGPDFScannerRef scanner, void *info);

extern const CFStringRef kCGPDFOutlineTitle;
extern const CFStringRef kCGPDFOutlineChildren;
extern const CFStringRef kCGPDFOutlineDestination;

/* Context keys referenced by PDFKit's write path. Defining the string is not
   a writer. CGPDFContextSetOutline stays undeclared: Onyx has no outline writer. */
extern const CFStringRef kCGPDFContextMediaBox;
extern const CFStringRef kCGPDFContextAuthor;
extern const CFStringRef kCGPDFContextSubject;
extern const CFStringRef kCGPDFContextKeywords;

void CGPDFDocumentGetVersion(CGPDFDocumentRef doc, int *major, int *minor);
bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef doc);
bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef doc);
bool CGPDFDocumentUnlockWithPassword(CGPDFDocumentRef doc, const char *password);
CGPDFAccessPermissions CGPDFDocumentGetAccessPermissions(CGPDFDocumentRef doc);
bool CGPDFDocumentAllowsPrinting(CGPDFDocumentRef doc);
bool CGPDFDocumentAllowsCopying(CGPDFDocumentRef doc);
CGPDFDictionaryRef CGPDFDocumentGetInfo(CGPDFDocumentRef doc);
CFDictionaryRef CGPDFDocumentGetOutline(CGPDFDocumentRef doc);

CGPDFDictionaryRef CGPDFPageGetDictionary(CGPDFPageRef page);
int CGPDFPageGetRotationAngle(CGPDFPageRef page);
size_t CGPDFPageGetPageNumber(CGPDFPageRef page);
/* CGContextDrawPDFPage stays in retained CoreGraphics. The Onyx-backed
   library does not define it, so a CGPDFPageRef remains an O2PDFPage and
   draw uses the real Onyx renderer and fonts.
   BeginPage and EndPage forward to O2PDFContext. They read a MediaBox only
   when pageInfo holds kCGPDFContextMediaBox as a CGRect-sized CFData. */

void CGPDFContextBeginPage(CGContextRef context, CFDictionaryRef pageInfo);
void CGPDFContextEndPage(CGContextRef context);

CGPDFContentStreamRef CGPDFContentStreamCreateWithPage(CGPDFPageRef page);
CGPDFObjectRef CGPDFContentStreamGetResource(CGPDFContentStreamRef stream, const char *category, const char *name);
void CGPDFContentStreamRelease(CGPDFContentStreamRef stream);

CGPDFOperatorTableRef CGPDFOperatorTableCreate(void);
void CGPDFOperatorTableRelease(CGPDFOperatorTableRef table);
void CGPDFOperatorTableSetCallback(CGPDFOperatorTableRef table, const char *name, CGPDFOperatorCallback callback);

CGPDFScannerRef CGPDFScannerCreate(CGPDFContentStreamRef stream, CGPDFOperatorTableRef table, void *info);
bool CGPDFScannerScan(CGPDFScannerRef scanner);
CGPDFContentStreamRef CGPDFScannerGetContentStream(CGPDFScannerRef scanner);
void CGPDFScannerRelease(CGPDFScannerRef scanner);
bool CGPDFScannerPopNumber(CGPDFScannerRef scanner, CGPDFReal *value);
bool CGPDFScannerPopInteger(CGPDFScannerRef scanner, CGPDFInteger *value);
bool CGPDFScannerPopName(CGPDFScannerRef scanner, const char **value);
bool CGPDFScannerPopString(CGPDFScannerRef scanner, CGPDFStringRef *value);
bool CGPDFScannerPopArray(CGPDFScannerRef scanner, CGPDFArrayRef *value);

bool CGPDFObjectGetValue(CGPDFObjectRef object, int type, void *value);
size_t CGPDFArrayGetCount(CGPDFArrayRef array);
bool CGPDFArrayGetNumber(CGPDFArrayRef array, size_t index, CGPDFReal *value);
bool CGPDFArrayGetString(CGPDFArrayRef array, size_t index, CGPDFStringRef *value);
bool CGPDFArrayGetDictionary(CGPDFArrayRef array, size_t index, CGPDFDictionaryRef *value);
bool CGPDFDictionaryGetInteger(CGPDFDictionaryRef dict, const char *key, CGPDFInteger *value);
bool CGPDFDictionaryGetNumber(CGPDFDictionaryRef dict, const char *key, CGPDFReal *value);
bool CGPDFDictionaryGetName(CGPDFDictionaryRef dict, const char *key, const char **value);
bool CGPDFDictionaryGetString(CGPDFDictionaryRef dict, const char *key, CGPDFStringRef *value);
bool CGPDFDictionaryGetArray(CGPDFDictionaryRef dict, const char *key, CGPDFArrayRef *value);
bool CGPDFDictionaryGetDictionary(CGPDFDictionaryRef dict, const char *key, CGPDFDictionaryRef *value);
bool CGPDFDictionaryGetStream(CGPDFDictionaryRef dict, const char *key, CGPDFStreamRef *value);
void CGPDFDictionaryApplyFunction(CGPDFDictionaryRef dict, CGPDFDictionaryApplierFunction function, void *info);

size_t CGPDFStringGetLength(CGPDFStringRef string);
const unsigned char *CGPDFStringGetBytePtr(CGPDFStringRef string);
CFStringRef CGPDFStringCopyTextString(CGPDFStringRef string);
CFDataRef CGPDFStreamCopyData(CGPDFStreamRef stream, int *format);

#endif
