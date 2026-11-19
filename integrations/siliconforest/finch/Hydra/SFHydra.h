// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const SFHydraErrorDomain;
typedef NS_ENUM(NSInteger, SFHydraError) {
    SFHydraRendererUnavailable = 1,
};

typedef double SFHydraVector __attribute__((ext_vector_type(3)));

@interface HYDExportParams : NSObject
@property(nonatomic, copy) NSString *firstLayerName;
@property(nonatomic) BOOL isSiblingPath;
@property(nonatomic) NSUInteger textureCompression;
@end

@interface HYDStageTransformParams : NSObject
@property(nonatomic) double scale;
@property(nonatomic) double metersPerUnit;
@property(nonatomic) NSUInteger upAxis;
@property(nonatomic) SFHydraVector rotation;
@property(nonatomic) SFHydraVector bbox;
@end

@interface HYDSceneNode : NSObject
@property(nonatomic, readonly, copy) NSString *label;
@property(nonatomic, readonly, weak) HYDSceneNode *parent;
@property(nonatomic, readonly) NSUInteger numberOfChildren;
@property(nonatomic, readonly, copy) NSString *hierarchialPath;
@property(nonatomic, readonly, copy) NSString *hierarchialName;
- (instancetype)init:(NSString *)label parent:(HYDSceneNode *)parent;
- (void)addChild:(HYDSceneNode *)child;
- (HYDSceneNode *)childAtIndex:(NSUInteger)index;
- (void)removeChildAt:(NSInteger)index;
@end

@interface HYDRenderer : NSObject
- (instancetype)initWithFeatures:(id)features;
- (BOOL)loadAssets:(NSArray *)assets;
- (void)loadAssetsAsync:(NSArray *)assets complete:(void (^)(void))completion;
- (HYDSceneNode *)sceneHierarchy;
- (HYDStageTransformParams *)defaultStageTransformParams;
- (BOOL)transformStage:(HYDStageTransformParams *)params;
- (BOOL)writeTo:(NSURL *)url withParams:(HYDExportParams *)params error:(NSError **)error;
@end
