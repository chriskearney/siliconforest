/* SPDX-License-Identifier: MIT */
#import "Synapse.h"
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, const char *argv[])
{
    if (argc != 2) return 2;
    @autoreleasepool {
        NSURL *file = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        SYFormFillingDocumentAttributes *form =
            [SYFormFillingDocumentAttributes formFillingDocumentAttributesForFileAtURL:file error:&error];
        if (!form || [form formFillingCoachingDisabled] || error) return 3;
        if ([SYDocumentAttributes documentAttributesForFileAtURL:file error:&error] || error) return 4;

        form = [[SYFormFillingDocumentAttributes alloc] initWithFormFillingCoachingDisabled:YES];
        if (![form saveToFileURL:file error:&error] || error) return 5;
        SYDocumentAttributes *doc = [[SYDocumentAttributes alloc] initWithSourceBundleIdentifier:@"org.siliconforest.test"
            indexKey:@"sample" originalFileURL:file receivedDate:[NSDate dateWithTimeIntervalSince1970:1] sender:@"fixture"];
        if (![doc saveToFileURL:file error:&error] || error) return 6;
        SYDocumentAttributes *reopened = [SYDocumentAttributes documentAttributesForFileAtURL:file error:&error];
        if (!reopened || error || ![[reopened indexKey] isEqual:@"sample"] || ![[reopened sender] isEqual:@"fixture"]
            || ![[reopened originalFileURL] isEqual:file]) return 7;

        [SYFormFillingDocumentAttributes formFillingDocumentAttributesForFileAtURL:file
                                                                      completion:^(SYFormFillingDocumentAttributes *saved, NSError *err) {
            if (![NSThread isMainThread] || ![saved formFillingCoachingDisabled] || err) exit(8);
            SYDocumentWorkflowsClient *client = [SYDocumentWorkflowsClient new];
            [client hasOriginalDocumentForFileAtURL:file completion:^(BOOL found, NSError *err) {
                if (![NSThread isMainThread] || found || !err) exit(9);
                [client openLastModifiedDocumentForFileAtURL:file completion:^(id opened, NSError *err) {
                    if (![NSThread isMainThread] || opened || !err) exit(10);
                    puts("Synapse persisted local attributes; history reports unsupported");
                    exit(0);
                }];
            }];
        }];
    }
    CFRunLoopRun();
    return 11;
}
