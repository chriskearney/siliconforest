/* SPDX-License-Identifier: MIT */
/* Reads defaults only; the sole mutation is our own PNG inside the test packet. */
#include <MediaAccessibility/MediaAccessibility.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

static bool has_caption(CGMutableImageMetadataRef metadata, CFStringRef path, CFStringRef expected)
{
    CGImageMetadataTagRef tag = CGImageMetadataCopyTagWithPath(metadata, NULL, path);
    if (!tag) return false;
    CFTypeRef value = CGImageMetadataTagCopyValue(tag);
    bool matches = value && CFEqual(value, expected);
    if (value) CFRelease(value);
    CFRelease(tag);
    return matches;
}

static int probe_metadata(const char *filename)
{
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)filename,
        strlen(filename), false);
    CGImageSourceRef source = url ? CGImageSourceCreateWithURL(url, NULL) : NULL;
    CGMutableImageMetadataRef metadata = CGImageMetadataCreateMutable();
    CFStringRef path = MAImageCaptioningCopyMetadataTagPath();
    CFErrorRef error = NULL;
    CFStringRef text = CFSTR("SiliconForest original caption fixture");
    bool wrote = metadata && path && MAImageCaptioningSetCaptionIntoMetadata(metadata, text, &error)
        && !error && has_caption(metadata, path, text);
    if (error) CFRelease(error);
    error = NULL;
    bool emptied = metadata && path && MAImageCaptioningSetCaptionIntoMetadata(metadata, NULL, &error)
        && !error && has_caption(metadata, path, CFSTR(""));
    if (error) CFRelease(error);
    error = NULL;
    bool rejected = !MAImageCaptioningSetCaptionIntoMetadata(NULL, text, &error) && error
        && CFEqual(CFErrorGetDomain(error), CFSTR("com.apple.media.accessibility"))
        && CFErrorGetCode(error) == 0;
    if (error) CFRelease(error);
    error = NULL;
    CFStringRef caption = source ? MAImageCaptioningCopyCaptionWithSource(source, &error) : NULL;
    bool no_caption = source && !caption && !error;
    if (caption) CFRelease(caption);
    if (error) CFRelease(error);
    if (path) CFRelease(path);
    if (metadata) CFRelease(metadata);
    if (source) CFRelease(source);
    if (url) CFRelease(url);
    printf("caption metadata write=%d clear=%d invalid=%d uncaptioned-source=%d\n",
        wrote, emptied, rejected, no_caption);
    return wrote && emptied && rejected && no_caption ? 0 : 5;
}

int main(int argc,char **argv){
    if (argc == 3 && strcmp(argv[1], "--metadata") == 0) return probe_metadata(argv[2]);
    if(argc!=2)return 2;
    CFArrayRef languages=MACaptionAppearanceCopySelectedLanguages(kMACaptionAppearanceDomainDefault);
    MACaptionAppearanceBehavior behavior=0;
    CGFloat opacity=MACaptionAppearanceGetForegroundOpacity(kMACaptionAppearanceDomainDefault,&behavior);
    int valid=languages && CFGetTypeID(languages)==CFArrayGetTypeID() && isfinite(opacity) && opacity>=0 && opacity<=1;
    if(languages)CFRelease(languages);
    CFStringRef path=MAImageCaptioningCopyMetadataTagPath();valid=valid && path && CFGetTypeID(path)==CFStringGetTypeID();if(path)CFRelease(path);
    printf("caption defaults/types/range=%d\n",valid);if(!valid)return 3;
    CFURLRef url=CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8*)argv[1],strlen(argv[1]),false);
    CFErrorRef error=NULL;CFStringRef text=CFSTR("SiliconForest original caption fixture");
    int wrote=MAImageCaptioningSetCaption(url,text,&error);if(error){CFRelease(error);error=NULL;}
    CFStringRef got=MAImageCaptioningCopyCaption(url,&error);int same=got && CFStringCompare(got,text,0)==kCFCompareEqualTo;
    printf("caption own-PNG write=%d roundtrip=%d error=%d\n",wrote,same,error!=NULL);
    if(got)CFRelease(got);if(error)CFRelease(error);CFRelease(url);
    return wrote && same?0:4;
}
