// SPDX-License-Identifier: MIT
#include <CoreFoundation/CoreFoundation.h>

typedef struct CGImageMetadata *CGMutableImageMetadataRef;
typedef const struct CGImageMetadataTag *CGImageMetadataTagRef;
extern bool CGImageMetadataSetValueWithPath(CGMutableImageMetadataRef, CGImageMetadataTagRef, CFStringRef, CFTypeRef);

bool CGImageMetadataSetValueMatchingImageProperty(CGMutableImageMetadataRef metadata, CFStringRef dictionary,
                                                   CFStringRef property, CFTypeRef value)
{
    if (!metadata || !dictionary || !property || !value)
        return false;

    const struct {
        CFStringRef dictionary;
        CFStringRef property;
        CFStringRef path;
    } matches[] = {
        {CFSTR("{TIFF}"), CFSTR("Orientation"), CFSTR("tiff:Orientation")},
        {CFSTR("{TIFF}"), CFSTR("Make"), CFSTR("tiff:Make")},
        {CFSTR("{TIFF}"), CFSTR("Model"), CFSTR("tiff:Model")},
        {CFSTR("{TIFF}"), CFSTR("Software"), CFSTR("tiff:Software")},
        {CFSTR("{TIFF}"), CFSTR("DateTime"), CFSTR("tiff:DateTime")},
        {CFSTR("{Exif}"), CFSTR("DateTimeOriginal"), CFSTR("photoshop:DateCreated")},
        {CFSTR("{IPTC}"), CFSTR("Keywords"), CFSTR("dc:subject")},
    };

    for (size_t i = 0; i < sizeof(matches) / sizeof(matches[0]); i++) {
        if (CFEqual(dictionary, matches[i].dictionary) && CFEqual(property, matches[i].property))
            return CGImageMetadataSetValueWithPath(metadata, NULL, matches[i].path, value);
    }
    return false;
}
