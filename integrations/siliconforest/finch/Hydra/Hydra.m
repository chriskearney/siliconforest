// SPDX-License-Identifier: MIT
#import "SFHydra.h"
#import <dispatch/dispatch.h>

NSString * const SFHydraErrorDomain = @"org.siliconforest.Hydra";

@implementation HYDExportParams
@end

@implementation HYDStageTransformParams

- (instancetype)init {
    self = [super init];
    if (self) {
        _scale = 100;
        _metersPerUnit = 0.1;
        _upAxis = 1;
    }
    return self;
}

@end

@implementation HYDSceneNode {
    NSMutableArray<HYDSceneNode *> *_children;
}

- (instancetype)init {
    return [self init:@"" parent:nil];
}

- (instancetype)init:(NSString *)label parent:(HYDSceneNode *)parent {
    self = [super init];
    if (self) {
        _label = [label copy];
        _parent = parent;
        _children = [NSMutableArray new];
    }
    return self;
}

- (NSUInteger)numberOfChildren {
    return _children.count;
}

- (HYDSceneNode *)childAtIndex:(NSUInteger)index {
    return index < _children.count ? _children[index] : nil;
}

- (void)addChild:(HYDSceneNode *)child {
    if (child.parent == self && ![_children containsObject:child])
        [_children addObject:child];
}

- (void)removeChildAt:(NSInteger)index {
    if (index >= 0 && (NSUInteger)index < _children.count)
        [_children removeObjectAtIndex:(NSUInteger)index];
}

- (NSString *)hierarchialPath {
    HYDSceneNode *parent = self.parent;
    if (!parent)
        return @"";
    return [NSString stringWithFormat:@"%@/%@", parent.hierarchialPath, self.label];
}

- (NSString *)hierarchialName {
    return self.label;
}

@end

@implementation HYDRenderer

- (instancetype)initWithFeatures:(id)features {
    (void)features;
    return [super init];
}

- (BOOL)loadAssets:(NSArray *)assets {
    (void)assets;
    return NO;
}

- (void)loadAssetsAsync:(NSArray *)assets complete:(void (^)(void))completion {
    [self loadAssets:assets];
    if (completion)
        dispatch_async(dispatch_get_main_queue(), completion);
}

- (HYDSceneNode *)sceneHierarchy {
    return nil;
}

- (HYDStageTransformParams *)defaultStageTransformParams {
    return [HYDStageTransformParams new];
}

- (BOOL)transformStage:(HYDStageTransformParams *)params {
    (void)params;
    return NO;
}

- (BOOL)writeTo:(NSURL *)url withParams:(HYDExportParams *)params error:(NSError **)error {
    (void)params;
    if (error) {
        NSDictionary *details = url ? @{NSURLErrorKey: url} : nil;
        *error = [NSError errorWithDomain:SFHydraErrorDomain code:SFHydraRendererUnavailable userInfo:details];
    }
    return NO;
}

@end
