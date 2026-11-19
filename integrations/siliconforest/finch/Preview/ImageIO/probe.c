// SPDX-License-Identifier: MIT
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGBitmapContext.h>
#include <CoreGraphics/CGContext.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImageSource.h>

CGImageRef CGImageCreateByScaling(CGImageRef, uint32_t, uint32_t, int32_t);

static void testScaling(void)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 4, 4, 8, 16, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    assert(context);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 4, 4));
    CGImageRef input = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    assert(input);
    CGImageRef scaled = CGImageCreateByScaling(input, 12, 7, 1);
    assert(scaled && CGImageGetWidth(scaled) == 12 && CGImageGetHeight(scaled) == 7);
    CFDataRef pixels = CGDataProviderCopyData(CGImageGetDataProvider(scaled));
    assert(pixels && CFDataGetLength(pixels) >= 12 * 7 * 4);
    const UInt8 *pixel = CFDataGetBytePtr(pixels) + 3 * CGImageGetBytesPerRow(scaled) + 6 * 4;
    assert(pixel[0] > 240 && pixel[1] < 5 && pixel[2] < 5 && pixel[3] > 240);
    CFRelease(pixels);
    CGImageRelease(scaled);
    assert(CGImageCreateByScaling(input, 0, 7, 1) == NULL);
    CGImageRelease(input);
}

CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef, CFDictionaryRef);
CFArrayRef CGImageSourceCopyTypeIdentifiers(void);
size_t CGImageSourceGetPrimaryImageIndex(CGImageSourceRef);
extern const CFStringRef kCGImagePropertyPNGDictionary;
extern const CFStringRef kCGImagePropertyPixelFormat;

int main(int argc, char **argv)
{
    assert(argc == 2);
    FILE *file = fopen(argv[1], "rb");
    assert(file && fseek(file, 0, SEEK_END) == 0);
    long length = ftell(file);
    assert(length > 0 && fseek(file, 0, SEEK_SET) == 0);
    UInt8 *bytes = malloc((size_t)length);
    assert(bytes && fread(bytes, 1, (size_t)length, file) == (size_t)length);
    fclose(file);
    CFDataRef data = CFDataCreate(NULL, bytes, length);
    free(bytes);
    assert(data);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    assert(provider);
    CGImageSourceRef source = CGImageSourceCreateWithDataProvider(provider, NULL);
    CGDataProviderRelease(provider);
    assert(source && CGImageSourceGetCount(source) == 1);
    assert(CGImageSourceGetPrimaryImageIndex(source) == 0);
    assert(CFEqual(CGImageSourceGetType(source), CFSTR("public.png")));
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    assert(image && CGImageGetWidth(image) && CGImageGetHeight(image));
    CGImageRelease(image);
    CGImageSourceRelease(source);
    assert(CGImageSourceCreateWithDataProvider(NULL, NULL) == NULL);

    CFArrayRef formats = CGImageSourceCopyTypeIdentifiers();
    assert(formats && CFArrayContainsValue(formats, CFRangeMake(0, CFArrayGetCount(formats)), CFSTR("public.png")));
    CFRelease(formats);
    assert(CFEqual(kCGImagePropertyPNGDictionary, CFSTR("{PNG}")));
    assert(CFEqual(kCGImagePropertyPixelFormat, CFSTR("PixelFormat")));
    testScaling();
    puts("ImageIO PASS for provider decode, source formats, metadata keys and bitmap scaling");
    return 0;
}
