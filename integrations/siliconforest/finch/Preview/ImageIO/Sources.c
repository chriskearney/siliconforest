// SPDX-License-Identifier: MIT
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImageSource.h>

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
