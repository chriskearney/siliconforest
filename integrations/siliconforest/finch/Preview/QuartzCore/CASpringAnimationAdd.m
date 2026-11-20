/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * Core Animation's animation objects, timing functions and transactions.
 *
 * The objects keep what the app gives them and answer as Core Animation's
 * do (defaults, copying, the spring's settling time, the timing curves).
 * Nothing plays them yet: CALayer ends each one as it's added.
 *
 * CASpringAnimation from Finch userland/QuartzCore/CAAnimation.m. The rest of
 * that file's classes (CABasicAnimation and its parents) already come from the
 * system image this overlay reexports, so the spring stores its own parameters
 * and subclasses that system CABasicAnimation instead of replacing it.
 */
#import "QuartzCoreSubset.h"
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

@implementation CASpringAnimation {
    NSMutableDictionary *_v;
}

@dynamic mass, stiffness, damping, initialVelocity, allowsOverdamping, bounce, perceptualDuration, settlingDuration;

- (instancetype)init
{
    self = [super init];
    if (self)
        _v = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)dealloc
{
    [_v release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    CASpringAnimation *c = [[[self class] allocWithZone:zone] init];
    [c->_v setDictionary:_v];
    return c;
}

- (id)_get:(NSString *)key { return _v[key]; }

- (void)_set:(id)v key:(NSString *)key
{
    if (v)
        _v[key] = v;
    else
        [_v removeObjectForKey:key];
}

#define DOUBLE(get, set, K, def)                                    \
    -(double)get { id v = [self _get:K]; return v ? [v doubleValue] : def; } \
    -(void)set:(double)x { [self _set:@(x) key:K]; }
#define BOOLV(get, set, K, def)                                     \
    -(BOOL)get { id v = [self _get:K]; return v ? [v boolValue] : def; } \
    -(void)set:(BOOL)x { [self _set:@(x) key:K]; }

- (instancetype)initWithPerceptualDuration:(CFTimeInterval)duration bounce:(CGFloat)bounce
{
    self = [self init];
    if (self) {
        [self setMass:1];
        [self setStiffness:pow(2 * M_PI / duration, 2)];
        [self setDamping:bounce >= 0 ? 4 * M_PI * (1 - bounce) / duration : 4 * M_PI / (duration * (1 + bounce))];
        [self setDuration:[self settlingDuration]];
    }
    return self;
}

DOUBLE(mass, setMass, @"mass", 1)
DOUBLE(stiffness, setStiffness, @"stiffness", 100)
DOUBLE(damping, setDamping, @"damping", 10)
DOUBLE(initialVelocity, setInitialVelocity, @"initialVelocity", 0)
BOOLV(allowsOverdamping, setAllowsOverdamping, @"allowsOverdamping", NO)

- (CGFloat)perceptualDuration { return 2 * M_PI / sqrt([self stiffness] / [self mass]); }
- (CGFloat)bounce
{
    double d = [self perceptualDuration], damping = [self damping];
    double b = 1 - damping * d / (4 * M_PI);
    return b >= 0 ? b : 4 * M_PI / (damping * d) - 1;
}

/* Inverse of -bounce, the conversion Finch's -initWithPerceptualDuration:bounce: applies. */
- (void)setBounce:(CGFloat)bounce
{
    CGFloat duration = [self perceptualDuration];
    if (!(duration > 0))
        return;
    [self setDamping:bounce >= 0 ? 4 * M_PI * (1 - bounce) / duration : 4 * M_PI / (duration * (1 + bounce))];
}

/*
 * As Core Animation's: an underdamped spring settles when the bound on its
 * swing, (|A| + |B|) e^(-ζω t), falls to a thousandth of the distance; a
 * critically or overdamped one is taken as critical, sampled every tenth
 * of a second until it stays within that thousandth.
 */
- (CFTimeInterval)settlingDuration
{
    double m = [self mass], k = [self stiffness], c = [self damping], v0 = [self initialVelocity];
    if (m <= 0 || k <= 0)
        return 0;
    double w0 = sqrt(k / m), zw = c / (2 * m);
    if (zw < w0) {
        double wd = sqrt(w0 * w0 - zw * zw);
        double amp = 1 + fabs((zw - v0) / wd);
        return log(1000 * amp) / zw;
    }
    double last = 0;
    for (int i = 1; i <= 10000; i++) {
        double t = i * 0.1;
        if (fabs((1 + (w0 - v0) * t) * exp(-w0 * t)) >= 0.001)
            last = t;
        else if (t - last > 20 / w0)
            break;
    }
    return round((last + 0.1) * 10) / 10;
}

/* CABasicAnimation stores duration. Record it there and in our dictionary. */
- (void)setDuration:(CFTimeInterval)duration
{
    [super setDuration:duration];
    [self _set:@(duration) key:@"duration"];
}

@end
