/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* CoreFoundation / CoreGraphics glue for the arm64 dylib. Not used by the host proof. */
#include "sf_cgpdf_glue.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGBitmapContext.h>
#include <CoreGraphics/CGContext.h>
#include <CoreGraphics/CGDataProvider.h>
#include <stdlib.h>
#include <string.h>

const CFStringRef kCGPDFOutlineTitle = CFSTR("Title");
const CFStringRef kCGPDFOutlineChildren = CFSTR("Children");
const CFStringRef kCGPDFOutlineDestination = CFSTR("Destination");

int sf_copy_provider(void *provider, uint8_t **bytes, size_t *n)
{
    CFDataRef data;
    const UInt8 *p;
    CFIndex len;
    if (!provider || !bytes || !n)
        return 0;
    data = CGDataProviderCopyData((CGDataProviderRef)provider);
    if (!data)
        return 0;
    p = CFDataGetBytePtr(data);
    len = CFDataGetLength(data);
    if (len < 0)
        len = 0;
    *bytes = malloc((size_t)len ? (size_t)len : 1);
    if (!*bytes) {
        CFRelease(data);
        return 0;
    }
    if (len && p)
        memcpy(*bytes, p, (size_t)len);
    *n = (size_t)len;
    CFRelease(data);
    return 1;
}

int sf_bitmap(void *context, uint8_t **data, size_t *width, size_t *height, size_t *stride, double ctm[6])
{
    CGAffineTransform t;
    void *px;
    size_t w, h, row;
    if (!context || !data || !width || !height || !stride || !ctm)
        return 0;
    px = CGBitmapContextGetData((CGContextRef)context);
    w = CGBitmapContextGetWidth((CGContextRef)context);
    h = CGBitmapContextGetHeight((CGContextRef)context);
    row = CGBitmapContextGetBytesPerRow((CGContextRef)context);
    if (!px || !w || !h || row < w * 4)
        return 0;
    t = CGContextGetCTM((CGContextRef)context);
    *data = px;
    *width = w;
    *height = h;
    *stride = row;
    ctm[0] = t.a;
    ctm[1] = t.b;
    ctm[2] = t.c;
    ctm[3] = t.d;
    ctm[4] = t.tx;
    ctm[5] = t.ty;
    return 1;
}

void sf_cf_release(void *object)
{
    if (object)
        CFRelease(object);
}

void *sf_cf_empty_string(void) { return (void *)CFStringCreateWithCString(NULL, "", kCFStringEncodingUTF8); }

void *sf_cf_string_utf8(const char *bytes, size_t n)
{
    return (void *)CFStringCreateWithBytes(NULL, (const UInt8 *)(bytes ? bytes : (const char *)""), (CFIndex)n, kCFStringEncodingUTF8, false);
}

void *sf_cf_data(const uint8_t *bytes, size_t n)
{
    return (void *)CFDataCreate(NULL, bytes ? bytes : (const UInt8 *)"", (CFIndex)n);
}

void *sf_cf_dict(void)
{
    return CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

void *sf_cf_array(void) { return CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks); }

void *sf_cf_number_long(long value)
{
    return (void *)CFNumberCreate(NULL, kCFNumberLongType, &value);
}

static CFStringRef key_string(const char *key)
{
    return (CFStringRef)CFStringCreateWithBytes(NULL, (const UInt8 *)key, (CFIndex)strlen(key), kCFStringEncodingUTF8, false);
}

void sf_cf_dict_set(void *dict, const char *key, void *value)
{
    CFStringRef k;
    if (!dict || !key || !value)
        return;
    k = key_string(key);
    if (!k)
        return;
    CFDictionarySetValue((CFMutableDictionaryRef)dict, k, value);
    CFRelease(k);
}

void sf_cf_array_add(void *array, void *value)
{
    if (array && value)
        CFArrayAppendValue((CFMutableArrayRef)array, value);
}

int sf_cf_string_get_utf8(void *string, char *buf, size_t n)
{
    if (!string || !buf || n == 0)
        return 0;
    return CFStringGetCString((CFStringRef)string, buf, (CFIndex)n, kCFStringEncodingUTF8) ? 1 : 0;
}

void *sf_cf_dict_get(void *dict, const char *key)
{
    CFStringRef k;
    const void *v;
    if (!dict || !key)
        return NULL;
    k = key_string(key);
    if (!k)
        return NULL;
    v = CFDictionaryGetValue((CFDictionaryRef)dict, k);
    CFRelease(k);
    return (void *)v;
}

long sf_cf_number_value(void *number)
{
    long v = 0;
    if (number)
        CFNumberGetValue((CFNumberRef)number, kCFNumberLongType, &v);
    return v;
}

size_t sf_cf_array_count(void *array)
{
    return array ? (size_t)CFArrayGetCount((CFArrayRef)array) : 0;
}

void *sf_cf_array_at(void *array, size_t index)
{
    if (!array || index >= sf_cf_array_count(array))
        return NULL;
    return (void *)CFArrayGetValueAtIndex((CFArrayRef)array, (CFIndex)index);
}
