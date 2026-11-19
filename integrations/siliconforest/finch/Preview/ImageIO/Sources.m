// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImageSource.h>

@interface O2ImageSource : NSObject
+ (id)newImageSourceWithData:(CFDataRef)data options:(CFDictionaryRef)options;
@end

static char sourceDataKey;

CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options)
{
    if (!data)
        return NULL;
    NSData *snapshot = [(NSData *)data copy];
    id source = [O2ImageSource newImageSourceWithData:(CFDataRef)snapshot options:options];
    if (source)
        objc_setAssociatedObject(source, &sourceDataKey, snapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [snapshot release];
    return (CGImageSourceRef)source;
}

// Borrow the exact immutable bytes passed to the decoder for this source.
__attribute__((visibility("hidden")))
NSData *SFPreviewImageSourceData(CGImageSourceRef source)
{
    return objc_getAssociatedObject((id)source, &sourceDataKey);
}

CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef provider, CFDictionaryRef options)
{
    if (!provider)
        return NULL;

    CFDataRef data = CGDataProviderCopyData(provider);
    if (!data)
        return NULL;

    CGImageSourceRef source = CGImageSourceCreateWithData(data, options);
    CFRelease(data);
    return source;
}

CFArrayRef CGImageSourceCopyTypeIdentifiers(void)
{
    // The codecs registered by +[O2ImageSource newImageSourceWithDataProvider:options:].
    const void *types[] = {
        CFSTR("public.png"),
        CFSTR("public.tiff"),
        CFSTR("public.jpeg"),
        CFSTR("com.microsoft.bmp"),
        CFSTR("com.compuserve.gif"),
        CFSTR("com.apple.icns"),
    };
    return CFArrayCreate(NULL, types, sizeof(types) / sizeof(types[0]), &kCFTypeArrayCallBacks);
}

size_t CGImageSourceGetPrimaryImageIndex(CGImageSourceRef source)
{
    // In this codec set the primary image is always the first frame.
    (void)source;
    return 0;
}
