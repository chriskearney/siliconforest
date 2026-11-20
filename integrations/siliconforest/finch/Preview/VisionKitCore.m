/* SPDX-License-Identifier: MIT */
/* Original compatibility implementation. No image-analysis backend is present. */
#import "VisionKitCore.h"

NSString *const SFVisionKitUnsupportedErrorDomain = @"org.siliconforest.VisionKitCore.Unsupported";

static NSError *unsupported(void)
{
    return [NSError errorWithDomain:SFVisionKitUnsupportedErrorDomain
                              code:SFVisionKitAnalysisUnsupported
                          userInfo:@{NSLocalizedDescriptionKey:
                              @"Image analysis and background removal are unsupported on SiliconForest."}];
}
static void rejectWithoutHandler(void)
{
    NSError *error = unsupported();
    @throw [NSException exceptionWithName:@"SFVisionKitUnsupportedOperationException"
                                  reason:[error localizedDescription]
                                userInfo:@{NSUnderlyingErrorKey:error}];
}

@implementation VKCImageAnalysis
/* Never manufacture an empty object that could be mistaken for a real result. */
- (instancetype)init
{
    [self release];
    rejectWithoutHandler();
    return nil;
}
@end

@implementation VKCImageAnalyzerRequest {
    CGImageRef _image;
    NSUInteger _orientation, _requestType;
}
- (instancetype)initWithCGImage:(CGImageRef)image orientation:(NSUInteger)orientation
                   requestType:(NSUInteger)requestType
{
    if ((self = [super init])) {
        _image = image ? CGImageRetain(image) : NULL;
        _orientation = orientation;
        _requestType = requestType;
    }
    return self;
}
- (CGImageRef)sf_image { return _image; }
- (NSUInteger)sf_orientation { return _orientation; }
- (NSUInteger)sf_requestType { return _requestType; }
- (void)dealloc
{
    if (_image)
        CGImageRelease(_image);
    [super dealloc];
}
@end

@implementation VKCImageAnalyzer
- (void)processRequest:(VKCImageAnalyzerRequest *)request progressHandler:(id)progress
    completionHandler:(void (^)(VKCImageAnalysis *, NSError *))handler
{
    if (handler)
        handler(nil, unsupported());
    else
        rejectWithoutHandler();
}
@end

void vk_cgImageRemoveBackgroundWithDownsizing(CGImageRef image, BOOL option1, BOOL option2,
    void (^handler)(CGImageRef, NSError *))
{
    if (handler)
        handler(NULL, unsupported());
    else
        rejectWithoutHandler();
}
