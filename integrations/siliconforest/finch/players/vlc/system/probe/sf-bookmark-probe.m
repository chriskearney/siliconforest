// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
// Status 0 only with a libFoundation whose NSURL makes and resolves bookmark data (cocoa 0365, QuickTime Player's
// Open Recent): a file's bookmark is made, resolved back to the same path and not stale. The libFoundation before
// 0365 refuses -bookmarkDataWithOptions:... (nil): status 1. The guarded installer's proof
// (../../../../macos-compat/sf-lib-install.sh) for step 7b of VLC's system install (SF-AH-vlc.md).
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>
int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    char tmpl[] = "/private/tmp/sf-bookmark-probe.XXXXXX";
    int fd = mkstemp(tmpl);
    if (fd < 0) { printf("sf-bookmark-probe: no temporary file: FAIL\n"); return 2; }
    write(fd, "x", 1); close(fd);
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:tmpl]];
    NSError *error = nil;
    NSData *data = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    BOOL stale = YES;
    NSURL *back = data ? [NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error] : nil;
    int ok = data != nil && back != nil && !stale && [[back path] isEqualToString:[url path]];
    printf("sf-bookmark-probe: bookmark %lu bytes, resolved %s, stale %d: %s\n", (unsigned long)[data length],
           back ? [[back path] UTF8String] : "(nil)", (int)stale, ok ? "ok" : "FAIL");
    unlink(tmpl);
    [pool release];
    return ok ? 0 : 1;
}
