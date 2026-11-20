/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Non-3D SceneKit subset. String values and superclasses are the M6
   measurements in runs/preview/retained/scenekit/m6-constants.log.
   Scene bytes are not parsed and nothing is drawn. */
#import "SFSceneKit.h"

NSString * const SCNExportPointOfViewAttribute = @"kExportPointOfViewAttribute";
NSString * const SCNSceneEndTimeAttributeKey = @"kSceneEndTimeAttributeKey";
NSString * const SCNSceneSourceAssetAuthorKey = @"author";
NSString * const SCNSceneSourceAssetAuthoringToolKey = @"authoring_tool";
NSString * const SCNSceneSourceAssetContributorsKey = @"contributors";
NSString * const SCNSceneSourceAssetUpAxisKey = @"up_axis";
NSString * const SCNSceneSourceSceneIndexKey = @"kSceneSourceSceneIndexKey";
NSString * const SCNSceneStartTimeAttributeKey = @"kSceneStartTimeAttributeKey";

@implementation SCNCamera
+ (instancetype)camera
{
    return [[[self alloc] init] autorelease];
}
@end

@implementation SCNRenderer
@end

@implementation SCNOffscreenRenderer
+ (instancetype)offscreenRendererWithContext:(id)context size:(CGSize)size
{
    (void)context;
    (void)size;
    return nil;
}
@end

@implementation SCNSceneSource {
    NSURL *_url;
    NSDictionary *_options;
}

+ (instancetype)sceneSourceWithURL:(NSURL *)url options:(NSDictionary *)options
{
    SCNSceneSource *source = [[self alloc] init];
    source->_url = [url copy];
    source->_options = [options copy];
    return [source autorelease];
}

- (void)dealloc
{
    [_url release];
    [_options release];
    [super dealloc];
}

- (NSURL *)url
{
    return _url;
}

- (NSDictionary *)options
{
    return _options;
}

- (id)propertyForKey:(NSString *)key
{
    (void)key;
    return nil;
}

- (id)sceneWithOptions:(NSDictionary *)options statusHandler:(SFSceneSourceStatus)statusHandler
{
    (void)options;
    if (statusHandler) {
        BOOL stop = NO;
        NSError *error = [NSError errorWithDomain:@"SFSceneKit" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Scene file load is not implemented"
        }];
        statusHandler(0.0f, error, &stop);
    }
    return nil;
}
@end

@implementation SCNTransaction
static int sf_depth;
static NSTimeInterval sf_duration;

+ (void)begin
{
    sf_depth++;
}

+ (void)commit
{
    if (sf_depth > 0)
        sf_depth--;
}

+ (void)flush
{
}

+ (void)setAnimationDuration:(NSTimeInterval)duration
{
    sf_duration = duration;
}

+ (NSTimeInterval)animationDuration
{
    return sf_duration;
}
@end

@implementation SCNView {
    id _scene;
    id _pointOfView;
    double _sceneTime;
    BOOL _allowsCameraControl;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    return self;
}

- (void)dealloc
{
    [_scene release];
    [_pointOfView release];
    [super dealloc];
}

- (id)scene
{
    return _scene;
}

- (void)setScene:(id)scene
{
    if (_scene == scene)
        return;
    [_scene release];
    _scene = [scene retain];
}

- (double)sceneTime
{
    return _sceneTime;
}

- (void)setSceneTime:(double)sceneTime
{
    _sceneTime = sceneTime;
}

- (id)pointOfView
{
    return _pointOfView;
}

- (void)setPointOfView:(id)pointOfView
{
    [self setPointOfView:pointOfView animate:NO];
}

- (void)setPointOfView:(id)pointOfView animate:(BOOL)animate
{
    (void)animate;
    if (_pointOfView == pointOfView)
        return;
    [_pointOfView release];
    _pointOfView = [pointOfView retain];
}

- (BOOL)allowsCameraControl
{
    return _allowsCameraControl;
}

- (void)setAllowsCameraControl:(BOOL)allowsCameraControl
{
    _allowsCameraControl = allowsCameraControl;
}
@end
