// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <Foundation/NSTask.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <string.h>

CFDataRef OFDCreatePDFDataFromURL(CFURLRef url, CFDictionaryRef options)
{
    if (![(NSURL *)url isFileURL] || (options && CFDictionaryGetCount(options)))
        return NULL;

    Dl_info image;
    if (dladdr((const void *)OFDCreatePDFDataFromURL, &image) == 0 || !image.dli_fname)
        return NULL;
    NSString *library = [NSString stringWithUTF8String:image.dli_fname];
    NSString *helper = [[library stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"sf-ofd-to-pdf"];
    if (!helper)
        return NULL;

    NSPipe *output = [NSPipe pipe];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:helper];
    [task setArguments:@[[(NSURL *)url path]]];
    [task setStandardOutput:output];
    if (![task launchAndReturnError:NULL])
        return NULL;

    NSData *document = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if ([task terminationStatus] != 0 || [document length] < 5 || memcmp([document bytes], "%PDF-", 5) != 0)
        return NULL;
    return (CFDataRef)[document copy];
}
