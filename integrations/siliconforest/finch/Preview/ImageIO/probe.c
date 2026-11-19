// SPDX-License-Identifier: MIT
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGBitmapContext.h>
#include <CoreGraphics/CGContext.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImageSource.h>
#include <CoreGraphics/CGImageDestination.h>

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

void CGImageDestinationAddAuxiliaryDataInfo(CGImageDestinationRef, CFStringRef, CFDictionaryRef);

CFArrayRef CGImageDestinationCopyImageFormats(CFStringRef);
bool CGImageDestinationCopyImageSource(CGImageDestinationRef, CGImageSourceRef, CFDictionaryRef, CFErrorRef *);

static void testDestinationFormats(void)
{
    CFArrayRef png = CGImageDestinationCopyImageFormats(CFSTR("public.png"));
    CFArrayRef tiff = CGImageDestinationCopyImageFormats(CFSTR("public.tiff"));
    assert(png && tiff);
    assert(CFArrayGetCount(png) == 1 && CFArrayGetCount(tiff) == 2);
    assert(CFArrayContainsValue(png, CFRangeMake(0, 1), CFSTR("kCGImageDestinationCanAlpha")));
    assert(CFArrayContainsValue(tiff, CFRangeMake(0, 2), CFSTR("kCGImageDestinationCanMultiPage")));
    assert(CGImageDestinationCopyImageFormats(CFSTR("public.jpeg")) == NULL);
    CFRelease(tiff);
    CFRelease(png);
}

static void testCopyImageSource(CGImageSourceRef source, CFDataRef original)
{
    CFMutableDataRef bytes = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef copy = CGImageDestinationCreateWithData(bytes, CFSTR("public.png"), 1, NULL);
    CFErrorRef error = NULL;
    assert(copy && CGImageDestinationCopyImageSource(copy, source, NULL, &error));
    assert(error == NULL && CFEqual(bytes, original));
    assert(!CGImageDestinationFinalize(copy));
    CFRelease(copy);

    CGImageDestinationRef different = CGImageDestinationCreateWithData(bytes, CFSTR("public.tiff"), 1, NULL);
    assert(different && !CGImageDestinationCopyImageSource(different, source, NULL, &error));
    assert(error && CFEqual(bytes, original));
    CFRelease(error);
    CFRelease(different);
    CFRelease(bytes);
}

static void testDestinations(CGImageRef image)
{
    CFMutableDataRef bytes = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef good = CGImageDestinationCreateWithData(bytes, CFSTR("public.png"), 1, NULL);
    assert(good);
    CGImageDestinationAddImage(good, image, NULL);
    assert(CFDataGetLength(bytes) == 0);
    assert(CGImageDestinationFinalize(good) && CFDataGetLength(bytes) > 0);
    assert(!CGImageDestinationFinalize(good));
    CGImageSourceRef decoded = CGImageSourceCreateWithData(bytes, NULL);
    assert(decoded && CGImageSourceGetCount(decoded) == 1);
    CGImageRef written = CGImageSourceCreateImageAtIndex(decoded, 0, NULL);
    assert(written && CGImageGetWidth(written) == CGImageGetWidth(image));
    CGImageRelease(written);
    CGImageSourceRelease(decoded);
    CFRelease(good);

    CFIndex originalLength = CFDataGetLength(bytes);
    CGImageDestinationRef pending = CGImageDestinationCreateWithData(bytes, CFSTR("public.png"), 1, NULL);
    assert(pending);
    CGImageDestinationAddImage(pending, image, NULL);
    CFDictionaryRef auxiliary = CFDictionaryCreate(NULL, NULL, NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CGImageDestinationAddAuxiliaryDataInfo(pending, CFSTR("kCGImageAuxiliaryDataTypeHDRGainMap"), auxiliary);
    CFRelease(auxiliary);
    assert(!CGImageDestinationFinalize(pending));
    assert(CFDataGetLength(bytes) == originalLength);
    CFRelease(pending);
    CFRelease(bytes);
}

CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef, CFDictionaryRef);
CFArrayRef CGImageSourceCopyTypeIdentifiers(void);
size_t CGImageSourceGetPrimaryImageIndex(CGImageSourceRef);
extern const CFStringRef kCGImagePropertyPNGDictionary;
extern const CFStringRef kCGImagePropertyPixelFormat;

typedef struct CGImageMetadata *CGMutableImageMetadataRef;
typedef const struct CGImageMetadata *CGImageMetadataRef;
typedef const struct CGImageMetadataTag *CGImageMetadataTagRef;
CGMutableImageMetadataRef CGImageMetadataCreateMutable(void);
bool CGImageMetadataSetValueMatchingImageProperty(CGMutableImageMetadataRef, CFStringRef, CFStringRef, CFTypeRef);
CGImageMetadataTagRef CGImageMetadataCopyTagWithPath(CGImageMetadataRef, CGImageMetadataTagRef, CFStringRef);
CFTypeRef CGImageMetadataTagCopyValue(CGImageMetadataTagRef);

static void testImageMetadata(void)
{
    CGMutableImageMetadataRef metadata = CGImageMetadataCreateMutable();
    assert(metadata);
    const void *words[] = {CFSTR("mountains"), CFSTR("night")};
    CFArrayRef keywords = CFArrayCreate(NULL, words, 2, &kCFTypeArrayCallBacks);
    assert(CGImageMetadataSetValueMatchingImageProperty(metadata, CFSTR("{IPTC}"), CFSTR("Keywords"), keywords));
    CGImageMetadataTagRef tag = CGImageMetadataCopyTagWithPath(metadata, NULL, CFSTR("dc:subject"));
    CFTypeRef value = tag ? CGImageMetadataTagCopyValue(tag) : NULL;
    assert(value && CFEqual(value, keywords));
    assert(!CGImageMetadataSetValueMatchingImageProperty(metadata, CFSTR("{IPTC}"), CFSTR("Unknown"), keywords));
    CFRelease(value);
    CFRelease(tag);
    CFRelease(keywords);
    CFRelease(metadata);
}

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
    assert(provider);
    CGImageSourceRef source = CGImageSourceCreateWithDataProvider(provider, NULL);
    CGDataProviderRelease(provider);
    assert(source && CGImageSourceGetCount(source) == 1);
    assert(CGImageSourceGetPrimaryImageIndex(source) == 0);
    assert(CFEqual(CGImageSourceGetType(source), CFSTR("public.png")));
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    assert(image && CGImageGetWidth(image) && CGImageGetHeight(image));
    testDestinationFormats();
    testImageMetadata();
    testCopyImageSource(source, data);
    CFRelease(data);
    testDestinations(image);
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
    puts("ImageIO PASS for provider decode, source formats, metadata keys, scaling, opaque copies and deferred exports");
    return 0;
}
