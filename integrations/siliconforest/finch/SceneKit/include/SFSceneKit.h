/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* SceneKit subset Preview links. Include after AppKit. SCNRenderer is the
   measured superclass of SCNOffscreenRenderer and is not a Preview import. */
#import <AppKit/NSView.h>

typedef void (^SFSceneSourceStatus)(float progress, NSError *error, BOOL *stop);

@interface SCNCamera : NSObject
+ (instancetype)camera;
@end

@interface SCNRenderer : NSObject
@end

@interface SCNOffscreenRenderer : SCNRenderer
+ (instancetype)offscreenRendererWithContext:(id)context size:(CGSize)size;
@end

@interface SCNSceneSource : NSObject
+ (instancetype)sceneSourceWithURL:(NSURL *)url options:(NSDictionary *)options;
- (id)sceneWithOptions:(NSDictionary *)options statusHandler:(SFSceneSourceStatus)statusHandler;
- (id)propertyForKey:(NSString *)key;
- (NSURL *)url;
- (NSDictionary *)options;
@end

@interface SCNTransaction : NSObject
+ (void)begin;
+ (void)commit;
+ (void)flush;
+ (void)setAnimationDuration:(NSTimeInterval)duration;
+ (NSTimeInterval)animationDuration;
@end

@interface SCNView : NSView
- (id)initWithFrame:(NSRect)frame;
- (id)scene;
- (void)setScene:(id)scene;
- (double)sceneTime;
- (void)setSceneTime:(double)sceneTime;
- (id)pointOfView;
- (void)setPointOfView:(id)pointOfView;
- (void)setPointOfView:(id)pointOfView animate:(BOOL)animate;
- (BOOL)allowsCameraControl;
- (void)setAllowsCameraControl:(BOOL)allowsCameraControl;
@end

extern NSString * const SCNExportPointOfViewAttribute;
extern NSString * const SCNSceneEndTimeAttributeKey;
extern NSString * const SCNSceneSourceAssetAuthorKey;
extern NSString * const SCNSceneSourceAssetAuthoringToolKey;
extern NSString * const SCNSceneSourceAssetContributorsKey;
extern NSString * const SCNSceneSourceAssetUpAxisKey;
extern NSString * const SCNSceneSourceSceneIndexKey;
extern NSString * const SCNSceneStartTimeAttributeKey;
