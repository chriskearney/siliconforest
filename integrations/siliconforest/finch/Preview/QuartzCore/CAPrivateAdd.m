/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * Core Animation classes beyond QuartzCore's headers that SwiftUI's renderer uses,
 * with Finch's behaviour:
 *   - CABackdropLayer: a layer with its backdrop settings (drawn as an ordinary layer).
 *   - CAChameleonLayer: the layer AppKit tints from what is behind it, for
 *     vibrant content (drawn as an ordinary layer).
 *   - CAPresentationModifier and its group: values for a key path, applied on flush.
 *   - CATransactionCompletionItem: a token that holds a transaction's completion open.
 *   - CALayerGetSuperlayer.
 *
 * From Finch userland/QuartzCore/CAPrivate.m. CAFilter and CADisplayLink are omitted:
 * the private chain already exports them. The modifier group keeps non-retaining
 * membership through Foundation's NSHashTable C API (NSNonRetainedObjectHashCallBacks).
 * This Foundation has that API and does not implement +weakObjectsHashTable.
 */
#import "QuartzCoreSubset.h"

CALayer *
CALayerGetSuperlayer(CALayer *layer)
{
    return layer.superlayer;
}

#pragma mark - CABackdropLayer

@implementation CABackdropLayer

- (instancetype)init
{
    if ((self = [super init])) {
        _scale = 1;
        _enabled = YES;
    }
    return self;
}

- (void)dealloc
{
    [_groupName release];
    [super dealloc];
}

@end

#pragma mark - CAChameleonLayer

@implementation CAChameleonLayer
@end

#pragma mark - CAPresentationModifier

@interface CAPresentationModifierGroup ()
- (void)_finchAdd:(CAPresentationModifier *)m;
@end

@implementation CAPresentationModifierGroup {
    NSUInteger _capacity;
    NSHashTable *_modifiers;
}

+ (instancetype)groupWithCapacity:(NSUInteger)capacity
{
    CAPresentationModifierGroup *g = [[[self alloc] init] autorelease];
    g->_capacity = capacity;
    return g;
}

- (instancetype)init
{
    if ((self = [super init]))
        _modifiers = NSCreateHashTable(NSNonRetainedObjectHashCallBacks, 0);
    return self;
}

- (void)dealloc
{
    if (_modifiers)
        NSFreeHashTable(_modifiers);
    [super dealloc];
}

- (NSUInteger)capacity { return _capacity; }
- (NSUInteger)count { return _modifiers ? NSCountHashTable(_modifiers) : 0; }
- (void)_finchAdd:(CAPresentationModifier *)m
{
    if (_modifiers && m)
        NSHashInsert(_modifiers, m);
}

- (void)flush {}
- (void)flushWithTargetTime:(double)t { (void)t; }
- (void)flushLocally {}
- (void)flushLocallyWithTargetTime:(double)t { (void)t; }
- (void)flushWithTransaction {}
- (void)flushWithTransactionAndTargetTime:(double)t { (void)t; }

@end

@implementation CAPresentationModifier

- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value initialVelocity:(id)velocity additive:(BOOL)additive
   preferredFrameRateRangeMaximum:(NSInteger)maximum group:(CAPresentationModifierGroup *)group
{
    (void)velocity;
    (void)maximum;
    if ((self = [super init])) {
        _keyPath = [keyPath copy];
        _value = [value retain];
        _additive = additive;
        _enabled = YES;
        _group = [group retain];
        [group _finchAdd:self];
    }
    return self;
}

- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value additive:(BOOL)additive group:(CAPresentationModifierGroup *)group
{
    return [self initWithKeyPath:keyPath initialValue:value initialVelocity:nil additive:additive preferredFrameRateRangeMaximum:0 group:group];
}

- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value additive:(BOOL)additive
{
    return [self initWithKeyPath:keyPath initialValue:value additive:additive group:nil];
}

- (void)dealloc
{
    [_keyPath release];
    [_value release];
    [_group release];
    [super dealloc];
}

- (void)setValue:(id)value velocity:(id)velocity
{
    (void)velocity;
    self.value = value;
}

@end

#pragma mark - CATransactionCompletionItem

@implementation CATransactionCompletionItem
+ (instancetype)completionItem { return [[[self alloc] init] autorelease]; }
- (void)invalidate {}
@end

#import <objc/runtime.h>

static char kSFContentsFormatKey, kSFCornerCurveKey, kSFDrawsAsyncKey, kSFAllowsGroupOpacityKey;
static char kSFAllowsEdgeAAKey, kSFShouldRasterizeKey, kSFRasterScaleKey, kSFWantsEDRKey;
static char kSFFiltersKey, kSFCompositingFilterKey;

@implementation CALayer (SFSwiftUILayerProps)
- (NSString *)contentsFormat {
    NSString *s = objc_getAssociatedObject(self, &kSFContentsFormatKey);
    return s ? s : @"Automatic";
}
- (void)setContentsFormat:(NSString *)format {
    objc_setAssociatedObject(self, &kSFContentsFormatKey, format, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
- (NSString *)cornerCurve {
    NSString *s = objc_getAssociatedObject(self, &kSFCornerCurveKey);
    return s ? s : @"circular";
}
- (void)setCornerCurve:(NSString *)curve {
    objc_setAssociatedObject(self, &kSFCornerCurveKey, curve, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
- (BOOL)drawsAsynchronously {
    return [objc_getAssociatedObject(self, &kSFDrawsAsyncKey) boolValue];
}
- (void)setDrawsAsynchronously:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFDrawsAsyncKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)allowsGroupOpacity {
    NSNumber *n = objc_getAssociatedObject(self, &kSFAllowsGroupOpacityKey);
    return n ? [n boolValue] : YES;
}
- (void)setAllowsGroupOpacity:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFAllowsGroupOpacityKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)allowsEdgeAntialiasing {
    NSNumber *n = objc_getAssociatedObject(self, &kSFAllowsEdgeAAKey);
    return n ? [n boolValue] : YES;
}
- (void)setAllowsEdgeAntialiasing:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFAllowsEdgeAAKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)shouldRasterize {
    return [objc_getAssociatedObject(self, &kSFShouldRasterizeKey) boolValue];
}
- (void)setShouldRasterize:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFShouldRasterizeKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (double)rasterizationScale {
    NSNumber *n = objc_getAssociatedObject(self, &kSFRasterScaleKey);
    return n ? [n doubleValue] : 1.0;
}
- (void)setRasterizationScale:(double)scale {
    objc_setAssociatedObject(self, &kSFRasterScaleKey, @(scale), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)wantsExtendedDynamicRangeContent {
    return [objc_getAssociatedObject(self, &kSFWantsEDRKey) boolValue];
}
- (void)setWantsExtendedDynamicRangeContent:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFWantsEDRKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSArray *)filters {
    return objc_getAssociatedObject(self, &kSFFiltersKey);
}
- (void)setFilters:(NSArray *)filters {
    objc_setAssociatedObject(self, &kSFFiltersKey, filters, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
- (id)compositingFilter {
    return objc_getAssociatedObject(self, &kSFCompositingFilterKey);
}
- (void)setCompositingFilter:(id)filter {
    objc_setAssociatedObject(self, &kSFCompositingFilterKey, filter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char kSFKVCStorageKey;

@implementation CALayer (SFArbitraryKVC)
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    if (!key) return;
    NSMutableDictionary *d = objc_getAssociatedObject(self, &kSFKVCStorageKey);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &kSFKVCStorageKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (value) [d setObject:value forKey:key];
    else [d removeObjectForKey:key];
}
- (id)valueForUndefinedKey:(NSString *)key {
    if (!key) return nil;
    NSMutableDictionary *d = objc_getAssociatedObject(self, &kSFKVCStorageKey);
    return d ? [d objectForKey:key] : nil;
}
@end

static char kSFActionsKey, kSFStyleKey, kSFNameKey, kSFMaskedCornersKey, kSFEdgeAAMaskKey;
static char kSFMinFilterKey, kSFMagFilterKey, kSFMinBiasKey, kSFZPosKey, kSFDoubleSidedKey;
static char kSFGeomFlippedKey, kSFAutoMaskKey, kSFLayoutMgrKey;

@implementation CALayer (SFMoreLayerProps)
- (NSDictionary *)actions { return objc_getAssociatedObject(self, &kSFActionsKey); }
- (void)setActions:(NSDictionary *)a { objc_setAssociatedObject(self, &kSFActionsKey, a, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSDictionary *)style { return objc_getAssociatedObject(self, &kSFStyleKey); }
- (void)setStyle:(NSDictionary *)s { objc_setAssociatedObject(self, &kSFStyleKey, s, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)name { return objc_getAssociatedObject(self, &kSFNameKey); }
- (void)setName:(NSString *)n { objc_setAssociatedObject(self, &kSFNameKey, n, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSUInteger)maskedCorners {
    NSNumber *n = objc_getAssociatedObject(self, &kSFMaskedCornersKey);
    return n ? [n unsignedIntegerValue] : 15;
}
- (void)setMaskedCorners:(NSUInteger)m { objc_setAssociatedObject(self, &kSFMaskedCornersKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (unsigned int)edgeAntialiasingMask {
    NSNumber *n = objc_getAssociatedObject(self, &kSFEdgeAAMaskKey);
    return n ? [n unsignedIntValue] : 15;
}
- (void)setEdgeAntialiasingMask:(unsigned int)m { objc_setAssociatedObject(self, &kSFEdgeAAMaskKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSString *)minificationFilter {
    NSString *s = objc_getAssociatedObject(self, &kSFMinFilterKey);
    return s ? s : @"linear";
}
- (void)setMinificationFilter:(NSString *)f { objc_setAssociatedObject(self, &kSFMinFilterKey, f, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSString *)magnificationFilter {
    NSString *s = objc_getAssociatedObject(self, &kSFMagFilterKey);
    return s ? s : @"linear";
}
- (void)setMagnificationFilter:(NSString *)f { objc_setAssociatedObject(self, &kSFMagFilterKey, f, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (float)minificationFilterBias { return [objc_getAssociatedObject(self, &kSFMinBiasKey) floatValue]; }
- (void)setMinificationFilterBias:(float)b { objc_setAssociatedObject(self, &kSFMinBiasKey, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (double)zPosition { return [objc_getAssociatedObject(self, &kSFZPosKey) doubleValue]; }
- (void)setZPosition:(double)z { objc_setAssociatedObject(self, &kSFZPosKey, @(z), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isDoubleSided {
    NSNumber *n = objc_getAssociatedObject(self, &kSFDoubleSidedKey);
    return n ? [n boolValue] : YES;
}
- (void)setDoubleSided:(BOOL)f { objc_setAssociatedObject(self, &kSFDoubleSidedKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isGeometryFlipped { return [objc_getAssociatedObject(self, &kSFGeomFlippedKey) boolValue]; }
- (void)setGeometryFlipped:(BOOL)f { objc_setAssociatedObject(self, &kSFGeomFlippedKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (unsigned int)autoresizingMask { return [objc_getAssociatedObject(self, &kSFAutoMaskKey) unsignedIntValue]; }
- (void)setAutoresizingMask:(unsigned int)m { objc_setAssociatedObject(self, &kSFAutoMaskKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)layoutManager { return objc_getAssociatedObject(self, &kSFLayoutMgrKey); }
- (void)setLayoutManager:(id)lm { objc_setAssociatedObject(self, &kSFLayoutMgrKey, lm, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

static char kSFContMultColKey, kSFContScalingKey, kSFContCenterKey, kSFContEdrKey, kSFContMaxEdrKey;
static char kSFAllowsGroupBlendKey, kSFAllowsHitTestKey, kSFAllowsDisplayCompKey, kSFPreloadsKey;
static char kSFCornerMasksKey, kSFMaskedCornersKey, kSFDrawsAsOverlayKey, kSFPrefDynRangeKey;
static char kSFShadowPathIsBoundsKey, kSFInvertsShadowKey, kSFSortModeKey, kSFContHintsKey;

@implementation CALayer (SFSwiftUIRenderProps)
- (id)contentsMultiplyColor { return objc_getAssociatedObject(self, &kSFContMultColKey); }
- (void)setContentsMultiplyColor:(id)c { objc_setAssociatedObject(self, &kSFContMultColKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGRect)contentsCenter {
    NSValue *v = objc_getAssociatedObject(self, &kSFContCenterKey);
    return v ? [v rectValue] : NSMakeRect(0, 0, 1, 1);
}
- (void)setContentsCenter:(CGRect)r { objc_setAssociatedObject(self, &kSFContCenterKey, [NSValue valueWithRect:r], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSDictionary *)contentsHints { return objc_getAssociatedObject(self, &kSFContHintsKey); }
- (void)setContentsHints:(NSDictionary *)h { objc_setAssociatedObject(self, &kSFContHintsKey, h, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (BOOL)allowsGroupBlending { return [objc_getAssociatedObject(self, &kSFAllowsGroupBlendKey) boolValue]; }
- (void)setAllowsGroupBlending:(BOOL)f { objc_setAssociatedObject(self, &kSFAllowsGroupBlendKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)allowsHitTesting { id v = objc_getAssociatedObject(self, &kSFAllowsHitTestKey); return v ? [v boolValue] : YES; }
- (void)setAllowsHitTesting:(BOOL)f { objc_setAssociatedObject(self, &kSFAllowsHitTestKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)allowsDisplayCompositing { id v = objc_getAssociatedObject(self, &kSFAllowsDisplayCompKey); return v ? [v boolValue] : YES; }
- (void)setAllowsDisplayCompositing:(BOOL)f { objc_setAssociatedObject(self, &kSFAllowsDisplayCompKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)preloadsCache { return [objc_getAssociatedObject(self, &kSFPreloadsKey) boolValue]; }
- (void)setPreloadsCache:(BOOL)f { objc_setAssociatedObject(self, &kSFPreloadsKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)shadowPathIsBounds { return [objc_getAssociatedObject(self, &kSFShadowPathIsBoundsKey) boolValue]; }
- (void)setShadowPathIsBounds:(BOOL)f { objc_setAssociatedObject(self, &kSFShadowPathIsBoundsKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)invertsShadow { return [objc_getAssociatedObject(self, &kSFInvertsShadowKey) boolValue]; }
- (void)setInvertsShadow:(BOOL)f { objc_setAssociatedObject(self, &kSFInvertsShadowKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)contentsEDRStrength { return [objc_getAssociatedObject(self, &kSFContEdrKey) doubleValue]; }
- (void)setContentsEDRStrength:(CGFloat)v { objc_setAssociatedObject(self, &kSFContEdrKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)contentsMaximumDesiredEDR { return [objc_getAssociatedObject(self, &kSFContMaxEdrKey) doubleValue]; }
- (void)setContentsMaximumDesiredEDR:(CGFloat)v { objc_setAssociatedObject(self, &kSFContMaxEdrKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSInteger)preferredDynamicRange { return [objc_getAssociatedObject(self, &kSFPrefDynRangeKey) integerValue]; }
- (void)setPreferredDynamicRange:(NSInteger)v { objc_setAssociatedObject(self, &kSFPrefDynRangeKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)toneMapToStandardDynamicRange { return NO; }
- (void)setToneMapToStandardDynamicRange:(BOOL)f { (void)f; }
- (void)setSecurityMode:(NSString *)m { (void)m; }
- (NSString *)securityMode { return nil; }
- (void)setFlattensSublayerTransform:(BOOL)f { (void)f; }
- (BOOL)flattensSublayerTransform { return NO; }
- (void)setCreatesCompositingGroup:(BOOL)f { (void)f; }
- (BOOL)createsCompositingGroup { return NO; }
@end

static char kSFNeedsLayoutGeomKey;
@implementation CALayer (SFNeedsLayoutGeom)
- (BOOL)needsLayoutOnGeometryChange { return [objc_getAssociatedObject(self, &kSFNeedsLayoutGeomKey) boolValue]; }
- (void)setNeedsLayoutOnGeometryChange:(BOOL)f { objc_setAssociatedObject(self, &kSFNeedsLayoutGeomKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
