/* SPDX-License-Identifier: MIT */
#import "PaperBridge.h"
#import <AppKit/NSImage.h>
#import <AppKit/NSImageView.h>
#import <string.h>

/* The coordinator's open PDFKit supplies these public operations. */
@interface NSObject(SFPaperPDFOperations)
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithFrame:(NSRect)frame;
- (void)setDocument:(id)document;
@end

static void fail(NSInteger code, NSString *reason, NSURL *url)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:reason forKey:NSLocalizedDescriptionKey];
    if (url)
        [info setObject:url forKey:NSURLErrorKey];
    NSError *error = [NSError errorWithDomain:@"org.siliconforest.PaperKit" code:code userInfo:info];
    @throw [NSException exceptionWithName:@"SFPaperDisplayException" reason:reason
                                userInfo:@{NSUnderlyingErrorKey:error}];
}

void SFPaperDisplay(NSViewController *controller, NSURL *url, BOOL readOnly)
{
    if (!controller || !url || ![url isFileURL]) {
        fail(1, @"Paper document display requires a local file URL.", url);
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) {
        fail(2, @"The requested document could not be read.", url);
        return;
    }
    NSRect frame = NSMakeRect(0, 0, 640, 480);
    if ([data length] >= 5 && memcmp([data bytes], "%PDF-", 5) == 0) {
        Class documentClass = NSClassFromString(@"PDFDocument");
        Class viewClass = NSClassFromString(@"PDFView");
        if (!documentClass || !viewClass) {
            fail(3, @"PDFKit's document and view providers are unavailable.", url);
            return;
        }
        id document = [[documentClass alloc] initWithURL:url];
        if (!document) {
            fail(4, @"PDFKit could not open this document.", url);
            return;
        }
        id view = [[viewClass alloc] initWithFrame:frame];
        if (![view respondsToSelector:@selector(setDocument:)]) {
            [view release]; [document release];
            fail(5, @"PDFKit's document view is unavailable.", url);
            return;
        }
        [view setDocument:document];
        [controller setView:view];
        [view release]; [document release];
    } else {
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
        if (!image) {
            fail(6, @"This file could not be decoded as an image.", url);
            return;
        }
        NSImageView *view = [[NSImageView alloc] initWithFrame:frame];
        [view setImage:image];
        [controller setView:view];
        [view release]; [image release];
    }
    /* This adapter displays files only. It exposes no edit or save operation.
     * readOnly is not interpreted as a request to pretend edits are supported. */
    (void)readOnly;
}
