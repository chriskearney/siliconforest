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
CGImageRef CGImageCreateCopyWithAlphaInfo(CGImageRef, const void *, CGImageAlphaInfo);

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

static void testOpaqueCopy(void)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 2, 2, 8, 8, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    assert(context);
    CGContextSetRGBFillColor(context, 1, 0, 0, 0.5);
    CGContextFillRect(context, CGRectMake(0, 0, 2, 2));
    CGImageRef input = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    assert(input);
    CGImageRef opaque = CGImageCreateCopyWithAlphaInfo(input, NULL, kCGImageAlphaNoneSkipLast);
    assert(opaque && CGImageGetAlphaInfo(opaque) == kCGImageAlphaNoneSkipLast);
    assert(CGImageGetWidth(opaque) == 2 && CGImageGetHeight(opaque) == 2);
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(opaque));
    assert(data && CFDataGetLength(data) >= 16);
    const UInt8 *pixel = CFDataGetBytePtr(data);
    assert(pixel[0] > 240 && pixel[1] < 5 && pixel[2] < 5);
    CFRelease(data);
    CGImageRelease(opaque);
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
    testOpaqueCopy();
    puts("ImageIO PASS for provider decode, source formats, metadata keys, bitmap scaling and opaque copies");
    return 0;
}
