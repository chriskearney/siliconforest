// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <CoreGraphics/CGImageDestination.h>
#import <objc/runtime.h>

// The CoreGraphics destination and consumer handles used here are Onyx2D objects.
extern CGImageDestinationRef O2ImageDestinationCreateWithData(CFMutableDataRef, CFStringRef, size_t, CFDictionaryRef);
extern void O2ImageDestinationSetProperties(CGImageDestinationRef, CFDictionaryRef);
extern void O2ImageDestinationAddImage(CGImageDestinationRef, CGImageRef, CFDictionaryRef);
extern bool O2ImageDestinationFinalize(CGImageDestinationRef);
extern CGDataConsumerRef O2DataConsumerRetain(CGDataConsumerRef);
extern size_t O2DataConsumerPutBytes(CGDataConsumerRef, const void *, size_t);
__attribute__((visibility("hidden"))) NSData *SFPreviewImageSourceData(CGImageSourceRef);

@interface SFPreviewImageFrame : NSObject {
@public
    CGImageRef image;
    NSDictionary *properties;
}
@end
@implementation SFPreviewImageFrame
- (void)dealloc
{
    CGImageRelease(image);
    [properties release];
    [super dealloc];
}
@end

@interface SFPreviewImageDestination : NSObject {
@public
    NSMutableData *data;
    CGDataConsumerRef consumer;
    NSURL *url;
    NSString *type;
    NSDictionary *properties;
    NSMutableArray *frames;
    size_t count;
    BOOL unsupported;
    BOOL finalized;
}
@end
@implementation SFPreviewImageDestination
- (void)dealloc
{
    [data release];
    if (consumer)
        CGDataConsumerRelease(consumer);
    [url release];
    [type release];
    [properties release];
    [frames release];
    [super dealloc];
}
@end

static char unsupportedLegacyKey;

static SFPreviewImageDestination *ownDestination(CGImageDestinationRef destination)
{
    id object = (id)destination;
    return [object isKindOfClass:[SFPreviewImageDestination class]] ? object : nil;
}

static SFPreviewImageDestination *makeDestination(CFStringRef format, size_t count, CFDictionaryRef options)
{
    if (!format || !count)
        return nil;
    BOOL tiff = CFEqual(format, CFSTR("public.tiff"));
    if (!tiff && (count != 1 || !CFEqual(format, CFSTR("public.png"))))
        return nil;
    SFPreviewImageDestination *result = [[SFPreviewImageDestination alloc] init];
    result->type = [(NSString *)format copy];
    result->properties = [(NSDictionary *)options copy];
    result->frames = [[NSMutableArray alloc] init];
    result->count = count;
    return result;
}

CGImageDestinationRef CGImageDestinationCreateWithData(CFMutableDataRef data, CFStringRef format,
                                                        size_t count, CFDictionaryRef options)
{
    SFPreviewImageDestination *destination = data ? makeDestination(format, count, options) : nil;
    if (destination)
        destination->data = [(NSMutableData *)data retain];
    return (CGImageDestinationRef)destination;
}

CGImageDestinationRef CGImageDestinationCreateWithDataConsumer(CGDataConsumerRef consumer, CFStringRef format,
                                                                size_t count, CFDictionaryRef options)
{
    SFPreviewImageDestination *destination = consumer ? makeDestination(format, count, options) : nil;
    if (destination)
        destination->consumer = O2DataConsumerRetain(consumer);
    return (CGImageDestinationRef)destination;
}

CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef format,
                                                       size_t count, CFDictionaryRef options)
{
    SFPreviewImageDestination *destination = [(NSURL *)url isFileURL] ? makeDestination(format, count, options) : nil;
    if (destination)
        destination->url = [(NSURL *)url retain];
    return (CGImageDestinationRef)destination;
}

CFArrayRef CGImageDestinationCopyTypeIdentifiers(void)
{
    const void *formats[] = {CFSTR("public.png"), CFSTR("public.tiff")};
    return CFArrayCreate(NULL, formats, sizeof(formats) / sizeof(formats[0]), &kCFTypeArrayCallBacks);
}

CFArrayRef CGImageDestinationCopyImageFormats(CFStringRef type)
{
    if (!type)
        return NULL;
    const void *capabilities[] = {
        CFSTR("kCGImageDestinationCanAlpha"),
        CFSTR("kCGImageDestinationCanMultiPage"),
    };
    CFIndex count = 0;
    if (CFEqual(type, CFSTR("public.tiff")))
        count = 2;
    else if (CFEqual(type, CFSTR("public.png")))
        count = 1;
    else
        return NULL;
    return CFArrayCreate(NULL, capabilities, count, &kCFTypeArrayCallBacks);
}

void CGImageDestinationSetProperties(CGImageDestinationRef destination, CFDictionaryRef properties)
{
    if (!destination)
        return;
    SFPreviewImageDestination *own = ownDestination(destination);
    if (!own) {
        O2ImageDestinationSetProperties(destination, properties);
    } else if (!own->finalized) {
        NSDictionary *copy = [(NSDictionary *)properties copy];
        [own->properties release];
        own->properties = copy;
    }
}

void CGImageDestinationAddImage(CGImageDestinationRef destination, CGImageRef image, CFDictionaryRef properties)
{
    if (!destination || !image)
        return;
    SFPreviewImageDestination *own = ownDestination(destination);
    if (!own) {
        if (!objc_getAssociatedObject((id)destination, &unsupportedLegacyKey))
            O2ImageDestinationAddImage(destination, image, properties);
        return;
    }
    if (own->finalized || own->unsupported)
        return;
    if ([own->frames count] == own->count) {
        own->unsupported = YES;
        return;
    }
    SFPreviewImageFrame *frame = [[SFPreviewImageFrame alloc] init];
    frame->image = CGImageRetain(image);
    frame->properties = [(NSDictionary *)properties copy];
    [own->frames addObject:frame];
    [frame release];
}

void CGImageDestinationAddImageFromSource(CGImageDestinationRef destination, CGImageSourceRef source,
                                          size_t index, CFDictionaryRef properties)
{
    if (!destination || !source || index >= CGImageSourceGetCount(source))
        return;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, index, NULL);
    if (!image)
        return;
    NSDictionary *original = (NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    NSMutableDictionary *merged = original ? [original mutableCopy] : [[NSMutableDictionary alloc] init];
    [original release];
    if (properties)
        [merged addEntriesFromDictionary:(NSDictionary *)properties];
    CGImageDestinationAddImage(destination, image, (CFDictionaryRef)merged);
    [merged release];
    CGImageRelease(image);
}

static void rejectUnencodableData(CGImageDestinationRef destination)
{
    SFPreviewImageDestination *own = ownDestination(destination);
    if (own)
        own->unsupported = YES;
    else if (destination)
        objc_setAssociatedObject((id)destination, &unsupportedLegacyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void CGImageDestinationAddAuxiliaryDataInfo(CGImageDestinationRef destination, CFStringRef type, CFDictionaryRef info)
{
    if (type && info)
        rejectUnencodableData(destination);
}

struct CGImageMetadata;
void CGImageDestinationAddImageAndMetadata(CGImageDestinationRef destination, CGImageRef image,
                                            const struct CGImageMetadata *metadata, CFDictionaryRef options)
{
    if (metadata)
        rejectUnencodableData(destination);
    else
        CGImageDestinationAddImage(destination, image, options);
}

static bool publishData(SFPreviewImageDestination *own, NSData *encoded)
{
    if (own->data) {
        [own->data appendData:encoded];
        return true;
    }
    if (own->url)
        return [encoded writeToURL:own->url atomically:YES];
    const void *bytes = [encoded bytes];
    size_t size = [encoded length];
    return O2DataConsumerPutBytes(own->consumer, bytes, size) == size;
}

bool CGImageDestinationCopyImageSource(CGImageDestinationRef destination, CGImageSourceRef source,
                                        CFDictionaryRef options, CFErrorRef *error)
{
    if (error)
        *error = NULL;
    SFPreviewImageDestination *own = ownDestination(destination);
    NSData *encoded = source ? SFPreviewImageSourceData(source) : nil;
    CFStringRef format = encoded ? CGImageSourceGetType(source) : NULL;
    if (!own || own->finalized || own->unsupported || [own->frames count] ||
        [own->properties count] || (options && CFDictionaryGetCount(options)) || ![encoded length] ||
        !format || !CFEqual(format, (CFStringRef)own->type) ||
        CGImageSourceGetCount(source) != own->count) {
        if (error)
            *error = CFErrorCreate(NULL, CFSTR("org.siliconforest.ImageIO"), 1, NULL);
        return false;
    }
    for (size_t index = 0; index < own->count; index++) {
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, index, NULL);
        if (!image) {
            if (error)
                *error = CFErrorCreate(NULL, CFSTR("org.siliconforest.ImageIO"), 2, NULL);
            return false;
        }
        CGImageRelease(image);
    }
    own->finalized = YES;
    bool complete = publishData(own, encoded);
    if (!complete && error)
        *error = CFErrorCreate(NULL, CFSTR("org.siliconforest.ImageIO"), 3, NULL);
    return complete;
}

bool CGImageDestinationFinalize(CGImageDestinationRef destination)
{
    if (!destination)
        return false;
    SFPreviewImageDestination *own = ownDestination(destination);
    if (!own) {
        BOOL unsupported = objc_getAssociatedObject((id)destination, &unsupportedLegacyKey) != nil;
        bool result = O2ImageDestinationFinalize(destination);
        return result && !unsupported;
    }
    if (own->finalized)
        return false;
    own->finalized = YES;
    if (own->unsupported || [own->frames count] != own->count)
        return false;

    NSMutableData *encoded = [NSMutableData data];
    CGImageDestinationRef writer = O2ImageDestinationCreateWithData((CFMutableDataRef)encoded,
        (CFStringRef)own->type, own->count, (CFDictionaryRef)own->properties);
    if (!writer)
        return false;
    for (SFPreviewImageFrame *frame in own->frames) {
        NSMutableDictionary *merged = own->properties ? [own->properties mutableCopy] : [[NSMutableDictionary alloc] init];
        if (frame->properties)
            [merged addEntriesFromDictionary:frame->properties];
        O2ImageDestinationAddImage(writer, frame->image, (CFDictionaryRef)merged);
        [merged release];
    }
    bool complete = O2ImageDestinationFinalize(writer);
    [(id)writer release];
    if (!complete || [encoded length] == 0)
        return false;

    return publishData(own, encoded);
}
