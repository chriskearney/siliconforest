/* SPDX-License-Identifier: MIT */
#import "VisionKitCore.h"
#include <stdio.h>
#include <stdlib.h>

static void need(BOOL condition, const char *message)
{
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static BOOL isUnsupported(NSError *error)
{
    return [[error domain] isEqualToString:SFVisionKitUnsupportedErrorDomain] &&
        [error code] == SFVisionKitAnalysisUnsupported;
}
static void throwsUnsupported(void (^operation)(void))
{
    BOOL caught = NO;
    @try { operation(); }
    @catch (NSException *exception) {
        caught = [[exception name] isEqualToString:@"SFVisionKitUnsupportedOperationException"] &&
            isUnsupported([[exception userInfo] objectForKey:NSUnderlyingErrorKey]);
    }
    need(caught, "operation without error callback throws unsupported");
}
int main(void)
{
    @autoreleasepool {
        __block unsigned analysisErrors = 0, removalErrors = 0, progress = 0;
        VKCImageAnalyzerRequest *request = [[VKCImageAnalyzerRequest alloc]
            initWithCGImage:NULL orientation:6 requestType:1];
        need(request.sf_image == NULL && request.sf_orientation == 6 && request.sf_requestType == 1,
             "request stores its parameters");
        VKCImageAnalyzer *analyzer = [VKCImageAnalyzer new];
        [analyzer processRequest:request progressHandler:^{ progress++; }
            completionHandler:^(VKCImageAnalysis *result, NSError *error) {
                need(result == nil && isUnsupported(error), "analysis has no fabricated result");
                analysisErrors++;
            }];
        vk_cgImageRemoveBackgroundWithDownsizing(NULL, YES, NO, ^(CGImageRef image, NSError *error) {
            need(image == NULL && isUnsupported(error), "removal has no fabricated output");
            removalErrors++;
        });
        throwsUnsupported(^{ [analyzer processRequest:request progressHandler:nil completionHandler:nil]; });
        throwsUnsupported(^{ vk_cgImageRemoveBackgroundWithDownsizing(NULL, NO, NO, nil); });
        throwsUnsupported(^{ (void)[VKCImageAnalysis new]; });
        need(analysisErrors == 1 && removalErrors == 1 && progress == 0, "exact failure callbacks; no progress");
        [analyzer release]; [request release];
        printf("VISIONKIT analysis-errors=%u removal-errors=%u progress=%u fabricated-results=0\n",
               analysisErrors, removalErrors, progress);
    }
    return 0;
}
