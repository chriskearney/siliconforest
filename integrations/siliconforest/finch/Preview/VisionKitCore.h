/* SPDX-License-Identifier: MIT */
/* Open declarations from observed import/selector and callback type names. */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CGImage.h>

extern NSString *const SFVisionKitUnsupportedErrorDomain;
enum { SFVisionKitAnalysisUnsupported = 1 };

@interface VKCImageAnalysis : NSObject
@end

@interface VKCImageAnalyzerRequest : NSObject
@property (readonly) CGImageRef sf_image;
@property (readonly) NSUInteger sf_orientation, sf_requestType;
- (instancetype)initWithCGImage:(CGImageRef)image orientation:(NSUInteger)orientation
                   requestType:(NSUInteger)requestType;
@end

@interface VKCImageAnalyzer : NSObject
/* Progress is opaque: no progress can occur while the service is unavailable. */
- (void)processRequest:(VKCImageAnalyzerRequest *)request progressHandler:(id)progress
    completionHandler:(void (^)(VKCImageAnalysis *, NSError *))handler;
@end

void vk_cgImageRemoveBackgroundWithDownsizing(CGImageRef image, BOOL option1, BOOL option2,
    void (^handler)(CGImageRef, NSError *));
