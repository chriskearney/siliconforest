// SPDX-License-Identifier: MIT
#include <stdint.h>
#include <CoreGraphics/CGBitmapContext.h>
#include <CoreGraphics/CGColorSpace.h>
#include <CoreGraphics/CGContext.h>

CGImageRef CGImageCreateByScaling(CGImageRef image, uint32_t width, uint32_t height, int32_t options)
{
    if (!image || !width || !height || (options != 0 && options != 1))
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
    if (!context)
        return NULL;

    CGContextSetInterpolationQuality(context, options ? kCGInterpolationHigh : kCGInterpolationDefault);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return scaled;
}
