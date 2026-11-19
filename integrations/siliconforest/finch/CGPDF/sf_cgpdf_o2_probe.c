/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Headless check that page refs from CoreGraphics accept the Onyx-backed
   scanner and that drawing stays a CoreGraphics import. Not a glyph renderer. */
#include <CoreGraphics/CoreGraphics.h>
#include "SFCoreGraphicsPDF.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Scan {
    double size;
    char text[256];
};

static void on_tf(CGPDFScannerRef scanner, void *info)
{
    struct Scan *scan = info;
    CGPDFReal size = -1;
    const char *name = NULL;
    if (CGPDFScannerPopNumber(scanner, &size))
        scan->size = size;
    CGPDFScannerPopName(scanner, &name);
}

static void on_tj(CGPDFScannerRef scanner, void *info)
{
    struct Scan *scan = info;
    CGPDFStringRef string = NULL;
    CFStringRef text;
    if (!CGPDFScannerPopString(scanner, &string))
        return;
    text = CGPDFStringCopyTextString(string);
    if (!text)
        return;
    CFStringGetCString(text, scan->text, (CFIndex)sizeof scan->text, kCFStringEncodingUTF8);
    CFRelease(text);
}

int main(int argc, char **argv)
{
    FILE *file;
    unsigned char *bytes;
    long size;
    CGDataProviderRef provider;
    CGPDFDocumentRef document;
    size_t pages, i;
    int major = -1, minor = -1;
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc != 2)
        return 2;
    file = fopen(argv[1], "rb");
    if (!file)
        return 3;
    fseek(file, 0, SEEK_END);
    size = ftell(file);
    fseek(file, 0, SEEK_SET);
    bytes = malloc((size_t)size);
    if (!bytes || fread(bytes, 1, (size_t)size, file) != (size_t)size) {
        fclose(file);
        return 3;
    }
    fclose(file);
    provider = CGDataProviderCreateWithData(NULL, bytes, (size_t)size, NULL);
    document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    if (!document)
        return 4;
    CGPDFDocumentGetVersion(document, &major, &minor);
    pages = CGPDFDocumentGetNumberOfPages(document);
    printf("version=%d.%d pages=%zu encrypted=%d perms=%u\n", major, minor, pages,
        CGPDFDocumentIsEncrypted(document), CGPDFDocumentGetAccessPermissions(document));
    for (i = 1; i <= pages; i++) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, i);
        CGPDFDictionaryRef dict = CGPDFPageGetDictionary(page);
        CGPDFArrayRef box = NULL;
        CGPDFReal width = -1, height = -1;
        CGPDFOperatorTableRef table;
        CGPDFContentStreamRef stream;
        CGPDFScannerRef scanner;
        struct Scan scan;
        CGColorSpaceRef colorspace;
        CGContextRef context;
        size_t bw, bh, stride;
        unsigned char *pixels, *center;
        memset(&scan, 0, sizeof scan);
        scan.size = -1;
        if (dict && CGPDFDictionaryGetArray(dict, "MediaBox", &box) && box && CGPDFArrayGetCount(box) >= 4) {
            CGPDFArrayGetNumber(box, 2, &width);
            CGPDFArrayGetNumber(box, 3, &height);
        }
        table = CGPDFOperatorTableCreate();
        CGPDFOperatorTableSetCallback(table, "Tf", on_tf);
        CGPDFOperatorTableSetCallback(table, "Tj", on_tj);
        stream = CGPDFContentStreamCreateWithPage(page);
        scanner = stream ? CGPDFScannerCreate(stream, table, &scan) : NULL;
        if (scanner)
            CGPDFScannerScan(scanner);
        CGPDFScannerRelease(scanner);
        CGPDFContentStreamRelease(stream);
        CGPDFOperatorTableRelease(table);
        bw = width > 1 && width < 2000 ? (size_t)width : 72;
        bh = height > 1 && height < 2000 ? (size_t)height : 72;
        stride = bw * 4;
        colorspace = CGColorSpaceCreateDeviceRGB();
        context = CGBitmapContextCreate(NULL, bw, bh, 8, stride, colorspace,
            kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorspace);
        pixels = context ? CGBitmapContextGetData(context) : NULL;
        if (context && page)
            CGContextDrawPDFPage(context, page);
        center = pixels ? pixels + stride * (bh / 2) + 4 * (bw / 2) : NULL;
        printf("page=%zu number=%zu rotate=%d box=%.1f,%.1f tf=%.1f text=%s center=%u,%u,%u,%u\n",
            i, CGPDFPageGetPageNumber(page), CGPDFPageGetRotationAngle(page), width, height, scan.size, scan.text,
            center ? center[0] : 0, center ? center[1] : 0, center ? center[2] : 0, center ? center[3] : 0);
        if (context)
            CGContextRelease(context);
    }
    CGPDFDocumentRelease(document);
    free(bytes);
    return 0;
}
