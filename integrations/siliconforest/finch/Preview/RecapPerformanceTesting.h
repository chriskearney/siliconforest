/* SPDX-License-Identifier: MIT OR Apache-2.0 */
#import <Foundation/Foundation.h>

/* Open compatibility declarations, not an Apple SDK header. */
extern NSString *const SFRecapUnsupportedErrorDomain;
enum { SFRecapRecordingUnsupported = 1 };

@interface RPTActivationTestParameters : NSObject
@property (copy) NSString *testName;
@property (retain) id window;
@property (copy) void (^completionHandler)(void);
- (instancetype)initWithTestName:(NSString *)name window:(id)window
              completionHandler:(void (^)(void))handler;
@end

@interface RPTTestRunner : NSObject
@property (retain) id delegate, settings, interactionOptions;
+ (BOOL)isRecapAvailable;
+ (void)runTestWithParameters:(id)parameters;
+ (void)runTestWithParameters:(id)parameters delegate:(id)delegate;
+ (void)runTestWithParameters:(id)parameters resultHandler:(void (^)(id))handler;
+ (void)playInteraction:(id)interaction completionHandler:(void (^)(id))handler;
- (instancetype)initWithInteractionOptions:(id)options;
- (BOOL)checkTestRequirementsWithError:(NSError **)error;
- (void)runTestWithParameters:(id)parameters;
- (void)runTestWithParameters:(id)parameters resultHandler:(void (^)(id))handler;
- (void)playInteraction:(id)interaction completionHandler:(void (^)(id))handler;
@end
