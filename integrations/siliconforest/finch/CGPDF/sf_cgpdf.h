/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Standalone prototypes for this reader. PDFKit includes include/SFCoreGraphicsPDF.h
   after CoreGraphics; the layouts here match that header and arm64 LP64. */
#ifndef SF_CGPDF_STANDALONE_H
#define SF_CGPDF_STANDALONE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef long CGPDFInteger;
typedef double CGPDFReal;
typedef unsigned char CGPDFBoolean;
typedef uint32_t CGPDFAccessPermissions;

typedef struct CGPoint {
    double x, y;
} CGPoint;
typedef struct CGSize {
    double width, height;
} CGSize;
typedef struct CGRect {
    CGPoint origin;
    CGSize size;
} CGRect;
typedef struct CGAffineTransform {
    double a, b, c, d, tx, ty;
} CGAffineTransform;

enum {
    kCGPDFMediaBox = 0,
    kCGPDFCropBox = 1,
    kCGPDFBleedBox = 2,
    kCGPDFTrimBox = 3,
    kCGPDFArtBox = 4
};

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

typedef struct SfPdfDoc *CGPDFDocumentRef;
typedef struct SfPdfPage *CGPDFPageRef;
typedef struct SfPdfObj *CGPDFObjectRef;
typedef struct SfPdfObj *CGPDFArrayRef;
typedef struct SfPdfObj *CGPDFDictionaryRef;
typedef struct SfPdfObj *CGPDFStreamRef;
typedef struct SfPdfObj *CGPDFStringRef;
typedef struct SfPdfCs *CGPDFContentStreamRef;
typedef struct SfPdfScan *CGPDFScannerRef;
typedef struct SfPdfOps *CGPDFOperatorTableRef;
typedef void *CGDataProviderRef;
typedef void *CGContextRef;
typedef void *CFStringRef;
typedef void *CFDataRef;
typedef void *CFDictionaryRef;
typedef void *CFTypeRef;

typedef void (*CGPDFDictionaryApplierFunction)(const char *key, CGPDFObjectRef value, void *info);
typedef void (*CGPDFOperatorCallback)(CGPDFScannerRef scanner, void *info);

CGPDFDocumentRef CGPDFDocumentCreateWithProvider(CGDataProviderRef provider);
CGPDFDocumentRef CGPDFDocumentRetain(CGPDFDocumentRef doc);
void CGPDFDocumentRelease(CGPDFDocumentRef doc);
size_t CGPDFDocumentGetNumberOfPages(CGPDFDocumentRef doc);
CGPDFPageRef CGPDFDocumentGetPage(CGPDFDocumentRef doc, size_t pageNumber);
void CGPDFDocumentGetVersion(CGPDFDocumentRef doc, int *major, int *minor);
bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef doc);
bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef doc);
bool CGPDFDocumentUnlockWithPassword(CGPDFDocumentRef doc, const char *password);
CGPDFAccessPermissions CGPDFDocumentGetAccessPermissions(CGPDFDocumentRef doc);
bool CGPDFDocumentAllowsPrinting(CGPDFDocumentRef doc);
bool CGPDFDocumentAllowsCopying(CGPDFDocumentRef doc);
CGPDFDictionaryRef CGPDFDocumentGetInfo(CGPDFDocumentRef doc);
CFDictionaryRef CGPDFDocumentGetOutline(CGPDFDocumentRef doc);

CGPDFPageRef CGPDFPageRetain(CGPDFPageRef page);
void CGPDFPageRelease(CGPDFPageRef page);
CGRect CGPDFPageGetBoxRect(CGPDFPageRef page, int box);
CGAffineTransform CGPDFPageGetDrawingTransform(CGPDFPageRef page, int box, CGRect rect, int clockwiseDegrees, bool preserveAspectRatio);
CGPDFDictionaryRef CGPDFPageGetDictionary(CGPDFPageRef page);
int CGPDFPageGetRotationAngle(CGPDFPageRef page);
size_t CGPDFPageGetPageNumber(CGPDFPageRef page);
void CGContextDrawPDFPage(CGContextRef context, CGPDFPageRef page);

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

const char *sf_cgpdf_error(void);

#endif
