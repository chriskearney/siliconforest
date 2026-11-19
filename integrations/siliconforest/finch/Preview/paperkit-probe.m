/* SPDX-License-Identifier: MIT */
/* Headless class/value/error-path check. No view or window is requested. */
#import "PaperBridge.h"
#import <AppKit/NSImageView.h>
#import <AppKit/NSImage.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSObject(SFPaperProbeEntry)
- (void)sfDisplayURL:(NSURL *)url readOnly:(BOOL)readOnly;
@end
static void need(BOOL condition, const char *message)
{
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
int main(int argc, const char **argv)
{
    @autoreleasepool {
        const char *symbols[] = {
            "$s8PaperKit0A14ViewControllerCMa",
            "$s8PaperKit0A14ViewControllerCMn",
            "$s8PaperKit0A14ViewControllerC7display_8readOnlyy10Foundation3URLV_SbtFTj"
        };
        for (unsigned i = 0; i < 3; i++)
            need(dlsym(RTLD_DEFAULT, symbols[i]) != NULL, "exact Swift export resolves");
        Class cls = NSClassFromString(@"_TtC8PaperKit19PaperViewController");
        need(cls != Nil, "Swift Objective-C class registered");
        id controller = [cls new];
        need(controller && [controller isKindOfClass:[NSViewController class]], "real AppKit superclass");
        need([controller respondsToSelector:@selector(sfDisplayURL:readOnly:)], "probe bridge available");
        BOOL caught = NO;
        @try {
            [controller sfDisplayURL:[NSURL URLWithString:@"https://example.invalid/never-requested"] readOnly:YES];
        } @catch (NSException *exception) {
            NSError *error = [[exception userInfo] objectForKey:NSUnderlyingErrorKey];
            caught = [[exception name] isEqualToString:@"SFPaperDisplayException"] &&
                [[error domain] isEqualToString:@"org.siliconforest.PaperKit"] && [error code] == 1;
        }
        need(caught, "Swift URL path rejects nonlocal URL with explicit error");
        if (argc == 2) {
            [controller sfDisplayURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]] readOnly:YES];
            NSView *view = [controller view];
            need([view isKindOfClass:[NSImageView class]], "real image view installed");
            NSImage *image = [(NSImageView *)view image];
            NSSize size = [image size];
            need(image != nil && size.width > 0 && size.height > 0, "real image decode");
            printf("PAPERKIT image-view=NSImageView decoded-size=%.0fx%.0f window-not-requested=YES\n", size.width, size.height);
        }
        [controller release];
        printf("PAPERKIT exports=3 class=NSViewController URL-bridge=PASS nonlocal-error=PASS window-not-requested=YES\n");
    }
    return 0;
}
