/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Copyright (c) 2026 The Finch Project contributors
 * Derived from Finch userland/RecapPerformanceTesting/RecapPerformanceTesting.m.
 * See NOTICE for provenance and the deliberately unsupported recording contract.
 */
#import "RecapPerformanceTesting.h"

NSString *const SFRecapUnsupportedErrorDomain = @"org.siliconforest.RecapPerformanceTesting.Unsupported";

static NSError *unsupported(void)
{
    return [NSError errorWithDomain:SFRecapUnsupportedErrorDomain
                              code:SFRecapRecordingUnsupported
                          userInfo:@{NSLocalizedDescriptionKey:
                              @"Performance recording is unsupported on SiliconForest; no test was run."}];
}

/* A void completion cannot communicate failure. Never call it as success. */
static void rejectWithoutErrorChannel(void)
{
    NSError *error = unsupported();
    @throw [NSException exceptionWithName:@"SFRecapUnsupportedOperationException"
                                  reason:[error localizedDescription]
                                userInfo:@{NSUnderlyingErrorKey:error}];
}

static void rejectWithHandler(void (^handler)(id))
{
    if (handler)
        handler(unsupported());
    else
        rejectWithoutErrorChannel();
}

@implementation RPTTestRunner
@synthesize delegate = _delegate, settings = _settings, interactionOptions = _interactionOptions;
+ (BOOL)isRecapAvailable { return NO; }
+ (void)runTestWithParameters:(id)parameters { rejectWithoutErrorChannel(); }
+ (void)runTestWithParameters:(id)parameters delegate:(id)delegate { rejectWithoutErrorChannel(); }
+ (void)runTestWithParameters:(id)parameters resultHandler:(void (^)(id))handler { rejectWithHandler(handler); }
+ (void)playInteraction:(id)interaction completionHandler:(void (^)(id))handler { rejectWithHandler(handler); }
- (instancetype)initWithInteractionOptions:(id)options
{
    if ((self = [super init]))
        _interactionOptions = [options retain];
    return self;
}
- (void)dealloc
{
    [_delegate release];
    [_settings release];
    [_interactionOptions release];
    [super dealloc];
}
- (BOOL)checkTestRequirementsWithError:(NSError **)error
{
    if (error)
        *error = unsupported();
    return NO;
}
- (void)runTestWithParameters:(id)parameters { rejectWithoutErrorChannel(); }
- (void)runTestWithParameters:(id)parameters resultHandler:(void (^)(id))handler { rejectWithHandler(handler); }
- (void)playInteraction:(id)interaction completionHandler:(void (^)(id))handler { rejectWithHandler(handler); }
@end

/* Parameter storage only: constructing one never starts or completes a test. */
@implementation RPTActivationTestParameters
@synthesize testName = _testName, window = _window, completionHandler = _completionHandler;
- (instancetype)initWithTestName:(NSString *)name window:(id)window
              completionHandler:(void (^)(void))handler
{
    if ((self = [super init])) {
        _testName = [name copy];
        _window = [window retain];
        _completionHandler = [handler copy];
    }
    return self;
}
- (void)dealloc
{
    [_testName release];
    [_window release];
    [_completionHandler release];
    [super dealloc];
}
@end
