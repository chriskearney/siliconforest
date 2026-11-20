/* SPDX-License-Identifier: MIT OR Apache-2.0 */
#import "RecapPerformanceTesting.h"
#include <stdio.h>
#include <stdlib.h>

static void need(BOOL condition, const char *message)
{
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static BOOL isUnsupported(id value)
{
    return [value isKindOfClass:[NSError class]] &&
        [[value domain] isEqualToString:SFRecapUnsupportedErrorDomain] &&
        [value code] == SFRecapRecordingUnsupported;
}
static void throwsUnsupported(void (^operation)(void))
{
    BOOL caught = NO;
    @try { operation(); }
    @catch (NSException *exception) {
        caught = [[exception name] isEqualToString:@"SFRecapUnsupportedOperationException"] &&
            isUnsupported([[exception userInfo] objectForKey:NSUnderlyingErrorKey]);
    }
    need(caught, "void operation throws explicit unsupported error");
}
int main(void)
{
    @autoreleasepool {
        need(![RPTTestRunner isRecapAvailable], "recording is unavailable");
        id window = [NSObject new];
        __block unsigned success = 0, failures = 0;
        NSMutableString *name = [NSMutableString stringWithString:@"own activation fixture"];
        RPTActivationTestParameters *p = [[RPTActivationTestParameters alloc]
            initWithTestName:name window:window completionHandler:^{ success++; }];
        [name appendString:@" changed"];
        need([[p testName] isEqualToString:@"own activation fixture"] && [p window] == window,
             "parameters copy name and retain window");
        RPTTestRunner *runner = [[RPTTestRunner alloc] initWithInteractionOptions:@{}];
        NSError *error = nil;
        need(![runner checkTestRequirementsWithError:&error] && isUnsupported(error), "readiness fails with error");
        need(![runner checkTestRequirementsWithError:NULL], "readiness also fails without error slot");
        void (^failed)(id) = ^(id result) { need(isUnsupported(result), "callback receives NSError"); failures++; };
        [RPTTestRunner runTestWithParameters:p resultHandler:failed];
        [runner runTestWithParameters:p resultHandler:failed];
        [RPTTestRunner playInteraction:nil completionHandler:failed];
        [runner playInteraction:nil completionHandler:failed];
        throwsUnsupported(^{ [RPTTestRunner runTestWithParameters:p]; });
        throwsUnsupported(^{ [RPTTestRunner runTestWithParameters:p delegate:nil]; });
        throwsUnsupported(^{ [runner runTestWithParameters:p]; });
        throwsUnsupported(^{ [runner runTestWithParameters:p resultHandler:nil]; });
        throwsUnsupported(^{ [runner playInteraction:nil completionHandler:nil]; });
        need(failures == 4 && success == 0, "each error callback once; no success completion");
        [p release]; [runner release]; [window release];
        printf("RECAP unavailable=YES readiness=failed error-callbacks=%u success-completions=%u\n", failures, success);
    }
    return 0;
}
