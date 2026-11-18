/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * QuartzCore names QuickTime Player binds that SiliconForest's QuartzCore (15 November)
 * lacks. The classes are models: they hold what they are given, as the public interface
 * describes it. Where this QuartzCore's renderer does not act on a model (keyframes, text,
 * filters), the class says so once; a constraint layout manager does lay out. */
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include "absent.h"

/* Documented values. */
#ifndef SF_MOVED /* in QuartzCore: cocoa patch 0343 */
SF_EXPORT NSString *const kCATruncationMiddle = @"middle";
SF_EXPORT NSString *const kCAAlignmentCenter = @"center";
#endif
SF_EXPORT NSString *const kCAFilterDestOut = @"destOut";

@interface CAAnimation : NSObject
@end
@interface CAPropertyAnimation : CAAnimation
@end
@interface CALayer : NSObject
- (NSArray *)sublayers;
- (CGRect)bounds;
- (CGRect)frame;
- (void)setFrame:(CGRect)frame;
- (NSString *)name;
@end

#define SF_OBJECT(type, getter, setter, ivar) \
    - (type)getter { return ivar; } \
    - (void)setter:(type)value { id old = (id)ivar; ivar = (type)[(id)value retain]; [old release]; }
#define SF_SCALAR(type, getter, setter, ivar) \
    - (type)getter { return ivar; } \
    - (void)setter:(type)value { ivar = value; }

#ifndef SF_MOVED /* in QuartzCore: cocoa patch 0344 */
SF_EXPORT
@interface CAKeyframeAnimation : CAPropertyAnimation {
    NSArray *_sfValues, *_sfKeyTimes, *_sfTimingFunctions;
    NSString *_sfCalculationMode, *_sfRotationMode;
    CGPathRef _sfPath;
}
@end
@implementation CAKeyframeAnimation
- (id)init {
    SF_ABSENT("CAKeyframeAnimation keeps its keyframes; this QuartzCore does not interpolate them");
    if ((self = [super init])) _sfCalculationMode = @"linear";
    return self;
}
SF_OBJECT(NSArray *, values, setValues, _sfValues)
SF_OBJECT(NSArray *, keyTimes, setKeyTimes, _sfKeyTimes)
SF_OBJECT(NSArray *, timingFunctions, setTimingFunctions, _sfTimingFunctions)
SF_OBJECT(NSString *, calculationMode, setCalculationMode, _sfCalculationMode)
SF_OBJECT(NSString *, rotationMode, setRotationMode, _sfRotationMode)
- (CGPathRef)path { return _sfPath; }
- (void)setPath:(CGPathRef)path {
    if (path) CFRetain(path);
    if (_sfPath) CFRelease(_sfPath);
    _sfPath = path;
}
- (void)dealloc {
    [_sfValues release]; [_sfKeyTimes release]; [_sfTimingFunctions release];
    [_sfCalculationMode release]; [_sfRotationMode release];
    if (_sfPath) CFRelease(_sfPath);
    [super dealloc];
}
@end
#endif

#ifndef SF_MOVED /* in QuartzCore: cocoa patch 0343 */
SF_EXPORT
@interface CATextLayer : CALayer {
    id _sfString;
    CFTypeRef _sfFont;
    CGFloat _sfFontSize;
    CGColorRef _sfForeground;
    BOOL _sfWrapped, _sfSubpixel;
    NSString *_sfTruncation, *_sfAlignment;
}
@end
@implementation CATextLayer
- (id)init {
    SF_ABSENT("CATextLayer keeps its text and attributes; this QuartzCore does not draw them");
    if ((self = [super init])) {
        _sfFontSize = 36;
        _sfTruncation = @"none";
        _sfAlignment = @"natural";
    }
    return self;
}
SF_OBJECT(id, string, setString, _sfString)
SF_OBJECT(NSString *, truncationMode, setTruncationMode, _sfTruncation)
SF_OBJECT(NSString *, alignmentMode, setAlignmentMode, _sfAlignment)
SF_SCALAR(CGFloat, fontSize, setFontSize, _sfFontSize)
SF_SCALAR(BOOL, isWrapped, setWrapped, _sfWrapped)
SF_SCALAR(BOOL, allowsFontSubpixelQuantization, setAllowsFontSubpixelQuantization, _sfSubpixel)
- (CFTypeRef)font { return _sfFont; }
- (void)setFont:(CFTypeRef)font {
    if (font) CFRetain(font);
    if (_sfFont) CFRelease(_sfFont);
    _sfFont = font;
}
- (CGColorRef)foregroundColor { return _sfForeground; }
- (void)setForegroundColor:(CGColorRef)color {
    if (color) CFRetain(color);
    if (_sfForeground) CFRelease(_sfForeground);
    _sfForeground = color;
}
- (void)dealloc {
    [_sfString release]; [_sfTruncation release]; [_sfAlignment release];
    if (_sfFont) CFRelease(_sfFont);
    if (_sfForeground) CFRelease(_sfForeground);
    [super dealloc];
}
@end
#endif

/* A tiled layer is, here, an ordinary layer that remembers its tiling parameters: its
 * content is drawn whole. */
SF_EXPORT
@interface CATiledLayer : CALayer {
    CGSize _sfTileSize;
    size_t _sfLevels, _sfBias;
}
@end
@implementation CATiledLayer
+ (CFTimeInterval)fadeDuration { return 0.25; }
- (id)init {
    if ((self = [super init])) {
        _sfTileSize = CGSizeMake(256, 256);
        _sfLevels = 1;
    }
    return self;
}
SF_SCALAR(CGSize, tileSize, setTileSize, _sfTileSize)
SF_SCALAR(size_t, levelsOfDetail, setLevelsOfDetail, _sfLevels)
SF_SCALAR(size_t, levelsOfDetailBias, setLevelsOfDetailBias, _sfBias)
@end

#ifndef SF_MOVED /* in QuartzCore: cocoa patch 0345 */
/* Constraint attributes, in the documented order. */
enum { SFMinX, SFMidX, SFMaxX, SFWidth, SFMinY, SFMidY, SFMaxY, SFHeight };

SF_EXPORT
@interface CAConstraint : NSObject {
    int _sfAttribute, _sfSourceAttribute;
    NSString *_sfSourceName;
    CGFloat _sfScale, _sfOffset;
}
@end
@implementation CAConstraint
+ (id)constraintWithAttribute:(int)attribute relativeTo:(NSString *)source attribute:(int)sourceAttribute scale:(CGFloat)scale offset:(CGFloat)offset {
    return [[[self alloc] initWithAttribute:attribute relativeTo:source attribute:sourceAttribute scale:scale offset:offset] autorelease];
}
+ (id)constraintWithAttribute:(int)attribute relativeTo:(NSString *)source attribute:(int)sourceAttribute offset:(CGFloat)offset {
    return [self constraintWithAttribute:attribute relativeTo:source attribute:sourceAttribute scale:1 offset:offset];
}
+ (id)constraintWithAttribute:(int)attribute relativeTo:(NSString *)source attribute:(int)sourceAttribute {
    return [self constraintWithAttribute:attribute relativeTo:source attribute:sourceAttribute scale:1 offset:0];
}
- (id)initWithAttribute:(int)attribute relativeTo:(NSString *)source attribute:(int)sourceAttribute scale:(CGFloat)scale offset:(CGFloat)offset {
    if ((self = [super init])) {
        _sfAttribute = attribute;
        _sfSourceAttribute = sourceAttribute;
        _sfSourceName = [source copy];
        _sfScale = scale;
        _sfOffset = offset;
    }
    return self;
}
- (int)attribute { return _sfAttribute; }
- (int)sourceAttribute { return _sfSourceAttribute; }
- (NSString *)sourceName { return _sfSourceName; }
- (CGFloat)scale { return _sfScale; }
- (CGFloat)offset { return _sfOffset; }
- (void)dealloc {
    [_sfSourceName release];
    [super dealloc];
}
@end

static CGFloat SFAttributeOf(CGRect r, int attribute) {
    switch (attribute) {
    case SFMinX: return CGRectGetMinX(r);
    case SFMidX: return CGRectGetMidX(r);
    case SFMaxX: return CGRectGetMaxX(r);
    case SFWidth: return r.size.width;
    case SFMinY: return CGRectGetMinY(r);
    case SFMidY: return CGRectGetMidY(r);
    case SFMaxY: return CGRectGetMaxY(r);
    default: return r.size.height;
    }
}

/* One axis: of {min, mid, max, size} any two that are constrained fix the extent; one fixes
 * the position and keeps the size. */
static void SFSolveAxis(const BOOL has[4], const CGFloat v[4], CGFloat *origin, CGFloat *size) {
    if (has[3]) *size = v[3];
    if (has[0] && has[2]) { *origin = v[0]; *size = v[2] - v[0]; }
    else if (has[0] && has[1]) { *origin = v[0]; *size = 2 * (v[1] - v[0]); }
    else if (has[1] && has[2]) { *size = 2 * (v[2] - v[1]); *origin = v[2] - *size; }
    else if (has[0]) *origin = v[0];
    else if (has[1]) *origin = v[1] - *size / 2;
    else if (has[2]) *origin = v[2] - *size;
}

SF_EXPORT
@interface CAConstraintLayoutManager : NSObject
@end
@implementation CAConstraintLayoutManager
+ (id)layoutManager {
    static CAConstraintLayoutManager *shared;
    @synchronized(self) {
        if (!shared) shared = [[self alloc] init];
    }
    return shared;
}
/* Real: each sublayer's constraints are applied against its siblings (by name) or the
 * superlayer ("superlayer"), in sublayer order, one pass. A layer class without a
 * constraints property has none to apply. */
- (void)layoutSublayersOfLayer:(CALayer *)layer {
    NSArray *sublayers = [layer sublayers];
    for (CALayer *sub in sublayers) {
        if (![sub respondsToSelector:@selector(constraints)]) {
            SF_ABSENT("CAConstraintLayoutManager: this QuartzCore's layers carry no constraints; nothing is laid out");
            return;
        }
        NSArray *constraints = [(id)sub performSelector:@selector(constraints)];
        if ([constraints count] == 0) continue;
        CGRect frame = [sub frame];
        BOOL hasX[4] = {NO, NO, NO, NO}, hasY[4] = {NO, NO, NO, NO};
        CGFloat x[4] = {0, 0, 0, 0}, y[4] = {0, 0, 0, 0};
        for (CAConstraint *c in constraints) {
            CGRect source = CGRectZero;
            BOOL found = NO;
            if ([[c sourceName] isEqualToString:@"superlayer"]) {
                source = [layer bounds];
                found = YES;
            } else {
                for (CALayer *sibling in sublayers)
                    if (sibling != sub && [[sibling name] isEqualToString:[c sourceName]]) {
                        source = [sibling frame];
                        found = YES;
                        break;
                    }
            }
            if (!found) continue;
            CGFloat value = SFAttributeOf(source, [c sourceAttribute]) * [c scale] + [c offset];
            int a = [c attribute];
            if (a < 4) { hasX[a] = YES; x[a] = value; }
            else if (a < 8) { hasY[a - 4] = YES; y[a - 4] = value; }
        }
        SFSolveAxis(hasX, x, &frame.origin.x, &frame.size.width);
        SFSolveAxis(hasY, y, &frame.origin.y, &frame.size.height);
        [sub setFrame:frame];
    }
}
- (CGSize)preferredSizeOfLayer:(CALayer *)layer {
    return [layer bounds].size;
}
- (void)invalidateLayoutOfLayer:(CALayer *)layer {
    (void)layer;
}
@end
#endif

/* Private. A named filter with parameters; this compositor applies no layer filters. */
SF_EXPORT
@interface CAFilter : NSObject {
    NSString *_sfType, *_sfName;
    NSMutableDictionary *_sfValues;
    BOOL _sfEnabled;
}
@end
@implementation CAFilter
+ (id)filterWithType:(NSString *)type { return [[[self alloc] initWithType:type] autorelease]; }
+ (id)filterWithName:(NSString *)name { return [[[self alloc] initWithType:name] autorelease]; }
- (id)initWithType:(NSString *)type {
    SF_ABSENT("CAFilter keeps its type and parameters; this compositor applies no layer filters");
    if ((self = [super init])) {
        _sfType = [type copy];
        _sfValues = [[NSMutableDictionary alloc] init];
        _sfEnabled = YES;
    }
    return self;
}
- (id)initWithName:(NSString *)name { return [self initWithType:name]; }
- (NSString *)type { return _sfType; }
SF_OBJECT(NSString *, name, setName, _sfName)
SF_SCALAR(BOOL, isEnabled, setEnabled, _sfEnabled)
- (void)setValue:(id)value forKey:(NSString *)key {
    if (value) [_sfValues setObject:value forKey:key];
    else [_sfValues removeObjectForKey:key];
}
- (id)valueForKey:(NSString *)key { return [_sfValues objectForKey:key]; }
- (void)setDefaults {
}
- (void)dealloc {
    [_sfType release]; [_sfName release]; [_sfValues release];
    [super dealloc];
}
@end
