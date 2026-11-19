// SPDX-License-Identifier: MIT
#import <PDFKit/PDFKit.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

enum { width = 240, height = 180, stride = width * 4 };

static BOOL checkPage(PDFView *view, PDFPage *page, CGContextRef context,
                      const unsigned char *pixels, unsigned int channel) {
    if (view.currentPage != page) {
        fprintf(stderr, "Navigation did not select page %u\n", channel + 1);
        return NO;
    }
    CGContextSaveGState(context);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextRestoreGState(context);
    [view drawPage:page toContext:context];
    const unsigned char *center = pixels + (height / 2) * stride + (width / 2) * 4;
    printf("page=%u center=%u,%u,%u,%u\n",
           channel + 1, center[0], center[1], center[2], center[3]);
    for (unsigned int i = 0; i < 4; ++i) {
        if (center[i] != (i == channel || i == 3 ? 255 : 0) || pixels[i] != 255)
            return NO;
    }
    return YES;
}

int main(int argc, char **argv) {
    if (argc != 2 && argc != 3) {
        fprintf(stderr, "usage: pdfkit-view-probe FIXTURE [path/to/PDFKit]\n");
        return 2;
    }

    @autoreleasepool {
        const char *library = argc == 3 ? argv[2] :
            "/System/Library/Frameworks/PDFKit.framework/Versions/A/PDFKit";
        if (!dlopen(library, RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "PDFKit load: %s\n", dlerror());
            return 3;
        }
        Class documentClass = NSClassFromString(@"PDFDocument");
        Class viewClass = NSClassFromString(@"PDFView");
        Class thumbnailClass = NSClassFromString(@"PDFThumbnailView");
        if (!documentClass || !viewClass || !thumbnailClass) return 4;

        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        PDFDocument *document = [[[documentClass alloc] initWithURL:url] autorelease];
        if (document.pageCount != 3) {
            fprintf(stderr, "Expected three pages, got %lu\n", (unsigned long)document.pageCount);
            return 5;
        }
        PDFView *view = [[[viewClass alloc] initWithFrame:NSMakeRect(0, 0, width, height)] autorelease];
        view.displayMode = kPDFDisplaySinglePage;
        view.document = document;

        CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, stride, colorspace,
            kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorspace);
        if (!context) return 6;
        const unsigned char *pixels = CGBitmapContextGetData(context);
        if (!pixels) {
            CGContextRelease(context);
            return 6;
        }

        PDFPage *first = [document pageAtIndex:0];
        PDFPage *middle = [document pageAtIndex:1];
        PDFPage *last = [document pageAtIndex:2];
        BOOL okay = YES;
        @autoreleasepool {
            okay = checkPage(view, first, context, pixels, 0);
        }
        @autoreleasepool {
            [view goToNextPage:nil];
            okay = checkPage(view, middle, context, pixels, 1) && okay;
        }
        @autoreleasepool {
            [view goToLastPage:nil];
            okay = checkPage(view, last, context, pixels, 2) && okay;
        }
        @autoreleasepool {
            [view goToPage:first];
            okay = checkPage(view, first, context, pixels, 0) && okay;
        }
        CGContextRelease(context);
        if (!okay) return 7;

        NSArray *matches = [document findString:@"Canopy" withOptions:0];
        PDFSelection *selection = matches.firstObject;
        if (matches.count != 1 || selection.pages.count != 1 || selection.pages.firstObject != middle)
            return 8;
        [view goToPage:middle];
        [view setCurrentSelection:selection];
        if (view.currentPage != middle || ![view.currentSelection.string isEqualToString:@"Canopy"])
            return 9;
        PDFThumbnailView *thumbnails = [[[thumbnailClass alloc] initWithFrame:NSMakeRect(0, 0, 120, 180)] autorelease];
        thumbnails.PDFView = view;
        NSImage *thumbnail = [middle thumbnailOfSize:NSMakeSize(60, 45) forBox:kPDFDisplayBoxMediaBox];
        if (thumbnails.PDFView != view || thumbnail.size.width <= 0 || thumbnail.size.height <= 0)
            return 10;

        puts("PDFKit rendering, page navigation, search, and thumbnail generation passed");
        return 0;
    }
}
