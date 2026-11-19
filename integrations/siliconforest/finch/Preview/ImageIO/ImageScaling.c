// SPDX-License-Identifier: MIT
#include <stdint.h>
#include <CoreGraphics/CGBitmapContext.h>
#include <CoreGraphics/CGColorSpace.h>
#include <CoreGraphics/CGContext.h>
#include <CoreGraphics/CGDataProvider.h>

static CGContextRef makeImageBitmap(CGImageRef image, uint32_t width, uint32_t height)
{
    if (!image || !width || !height)
        return NULL;

    // The bitmap uses four 8-bit components. Bound the allocation before
    // passing its dimensions to the underlying context implementation.
    const size_t bytesPerRow = (size_t)width * 4;
    const size_t maxBytes = (size_t)512 * 1024 * 1024;
    if (bytesPerRow > maxBytes || height > maxBytes / bytesPerRow)
        return NULL;

    CGColorSpaceRef space = CGImageGetColorSpace(image);
    if (space && CGColorSpaceGetModel(space) == kCGColorSpaceModelRGB)
        CGColorSpaceRetain(space);
    else
        space = CGColorSpaceCreateDeviceRGB();
    if (!space)
        return NULL;

    CGContextRef context = CGBitmapContextCreate(
        NULL, width, height, 8, bytesPerRow, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return context;
}

CGImageRef CGImageCreateByScaling(CGImageRef image, uint32_t width, uint32_t height, int32_t options)
{
    if (options != 0 && options != 1)
        return NULL;
    CGContextRef context = makeImageBitmap(image, width, height);
    if (!context)
        return NULL;

    CGContextSetInterpolationQuality(context, options ? kCGInterpolationHigh : kCGInterpolationDefault);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return scaled;
}

// Preview's caller requests an opaque copy with the fourth byte skipped.
CGImageRef CGImageCreateCopyWithAlphaInfo(CGImageRef image, const void *options, CGImageAlphaInfo alpha)
{
    if (!image || options || alpha != kCGImageAlphaNoneSkipLast)
        return NULL;

    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width > UINT32_MAX || height > UINT32_MAX)
        return NULL;
    CGContextRef context = makeImageBitmap(image, (uint32_t)width, (uint32_t)height);
    if (!context)
        return NULL;

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    size_t stride = CGBitmapContextGetBytesPerRow(context);
    UInt8 *bytes = CGBitmapContextGetData(context);
    if (!bytes) {
        CGContextRelease(context);
        return NULL;
    }

    for (size_t y = 0; y < height; ++y) {
        UInt8 *pixel = bytes + y * stride;
        for (size_t x = 0; x < width; ++x, pixel += 4) {
            unsigned opacity = pixel[3];
            for (size_t channel = 0; channel < 3; ++channel) {
                unsigned straight = opacity ? (pixel[channel] * 255U + opacity / 2) / opacity : 0;
                pixel[channel] = straight > 255 ? 255 : straight;
            }
            pixel[3] = 255;
        }
    }

    CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)(stride * height));
    CGDataProviderRef provider = data ? CGDataProviderCreateWithCFData(data) : NULL;
    if (data)
        CFRelease(data);
    CGImageRef opaque = NULL;
    if (provider) {
        opaque = CGImageCreate(width, height, 8, 32, stride, CGBitmapContextGetColorSpace(context),
            kCGImageAlphaNoneSkipLast, provider, NULL, CGImageGetShouldInterpolate(image),
            CGImageGetRenderingIntent(image));
        CGDataProviderRelease(provider);
    }
    CGContextRelease(context);
    return opaque;
}
