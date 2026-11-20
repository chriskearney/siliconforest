// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// QuickLook and QuickLookUI, absence providers. SiliconForest has no Quick Look
// generators and no preview panel yet, so every entry reports that truthfully:
// no thumbnail can be made, and no document is being opened out of a preview.
// Written from the public API documentation; nothing here draws or previews.
// The Finch project's Quick Look (real thumbnails, a preview panel) is the
// intended replacement when the desktop wants previews.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define SF_EXPORT __attribute__((visibility("default")))

#if SF_KIND == 1 /* QuickLook */

SF_EXPORT const CFStringRef kQLThumbnailOptionIconModeKey = CFSTR("QLThumbnailOptionIconMode");
SF_EXPORT const CFStringRef kQLThumbnailOptionScaleFactorKey = CFSTR("QLThumbnailOptionScaleFactor");
SF_EXPORT NSString *const QLSeamlessOpeningDisplayStateTimeKey = @"QLSeamlessOpeningDisplayStateTime";

// The documented result when no thumbnail can be produced is NULL; callers fall back
// to the file's icon.
SF_EXPORT CGImageRef QLThumbnailImageCreate(CFAllocatorRef allocator, CFURLRef url, CGSize maxThumbnailSize,
                                            CFDictionaryRef options) {
    (void)allocator;
    (void)url;
    (void)maxThumbnailSize;
    (void)options;
    return NULL;
}

#elif SF_KIND == 2 /* QuickLookUI */

// An application asks this class whether a document it is about to open is already on
// screen in a Quick Look preview, so that the preview can grow into the document window.
// With no preview panel there is never such a preview: the answer is always "none".
SF_EXPORT
@interface QLSeamlessDocumentOpener : NSObject
+ (instancetype)seamlessDocumentOpenerForURL:(NSURL *)url;
@end

@implementation QLSeamlessDocumentOpener
+ (instancetype)seamlessDocumentOpenerForURL:(NSURL *)url {
    (void)url;
    return nil;
}
@end

#else
#error SF_KIND selects the framework: 1 QuickLook, 2 QuickLookUI
#endif
