/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Minimal declarations for the QuartzCore classes this overlay adds or subclasses.
 * The implementations live in the system image (CALayer, CABasicAnimation) or in
 * the Finch sources compiled beside this header. */
#import <Foundation/Foundation.h>
#import "CAConstantsAdd.h"

__attribute__((visibility("default")))
@interface CALayer : NSObject
+ (instancetype)layer;
@property (readonly, nonatomic) CALayer *superlayer;
- (void)addSublayer:(CALayer *)layer;
- (void)setNeedsDisplay;
@end

__attribute__((visibility("default")))
CALayer *CALayerGetSuperlayer(CALayer *layer);

__attribute__((visibility("default")))
@interface CABackdropLayer : CALayer
@property (nonatomic) CGFloat scale;
@property (nonatomic) BOOL allowsInPlaceFiltering;
@property (nonatomic, copy) NSString *groupName;
@property (nonatomic) BOOL enabled;
@end

__attribute__((visibility("default")))
@interface CAChameleonLayer : CALayer
@end

@class CAPresentationModifier;

__attribute__((visibility("default")))
@interface CAPresentationModifierGroup : NSObject
@property (nonatomic) BOOL updatesAsynchronously;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, readonly) NSUInteger capacity;
+ (instancetype)groupWithCapacity:(NSUInteger)capacity;
- (void)flush;
- (void)flushWithTargetTime:(double)targetTime;
- (void)flushLocally;
- (void)flushLocallyWithTargetTime:(double)targetTime;
- (void)flushWithTransaction;
- (void)flushWithTransactionAndTargetTime:(double)targetTime;
@end

__attribute__((visibility("default")))
@interface CAPresentationModifier : NSObject
@property (nonatomic, copy, readonly) NSString *keyPath;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) BOOL additive;
@property (nonatomic, readonly) CAPresentationModifierGroup *group;
@property (nonatomic, strong) id value;
- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value initialVelocity:(id)velocity
    additive:(BOOL)additive preferredFrameRateRangeMaximum:(NSInteger)maximum group:(CAPresentationModifierGroup *)group;
- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value additive:(BOOL)additive
                          group:(CAPresentationModifierGroup *)group;
- (instancetype)initWithKeyPath:(NSString *)keyPath initialValue:(id)value additive:(BOOL)additive;
- (void)setValue:(id)value velocity:(id)velocity;
@end

__attribute__((visibility("default")))
@interface CATransactionCompletionItem : NSObject
+ (instancetype)completionItem;
- (void)invalidate;
@end

__attribute__((visibility("default")))
@interface CABasicAnimation : NSObject
+ (instancetype)animationWithKeyPath:(NSString *)path;
- (void)setDuration:(CFTimeInterval)duration;
- (CFTimeInterval)duration;
@end

__attribute__((visibility("default")))
@interface CASpringAnimation : CABasicAnimation
- (instancetype)initWithPerceptualDuration:(CFTimeInterval)duration bounce:(CGFloat)bounce;
@property (nonatomic) CGFloat mass;
@property (nonatomic) CGFloat stiffness;
@property (nonatomic) CGFloat damping;
@property (nonatomic) CGFloat initialVelocity;
@property (nonatomic) BOOL allowsOverdamping;
@property (nonatomic) CGFloat bounce;
@property (nonatomic, readonly) CFTimeInterval perceptualDuration;
@property (nonatomic, readonly) CFTimeInterval settlingDuration;
@end

/* Finch CAPrivate2.m: SwiftUI sets these on CALayer. */
@interface CALayer (FinchContentsProperties)
@property (nonatomic, copy) NSString *contentsSwizzle;
@property (nonatomic, copy) NSString *contentsScaling;
@end
