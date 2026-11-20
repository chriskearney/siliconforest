/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * More of Core Animation's private API that Apple's apps use (signatures read from
 * their calls).
 *
 * Contents' private properties (SwiftUI's images set them), from Finch
 * userland/QuartzCore/CAPrivate2.m: a swizzle (AAAA draws the alpha alone, as a
 * mask) and scaling (stretch or repeat; Finch stretches). Manual retain/release.
 * The multiply-colour and EDR helpers in that file need CoreGraphics and are not
 * part of the missing-symbol set.
 */
#import "QuartzCoreSubset.h"
#import <objc/runtime.h>

static const char k_swizzle, k_scaling;

@implementation CALayer (FinchContentsProperties)

- (NSString *)contentsSwizzle { return objc_getAssociatedObject(self, &k_swizzle); }

- (void)setContentsSwizzle:(NSString *)s
{
    objc_setAssociatedObject(self, &k_swizzle, s, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self setNeedsDisplay];
}

- (NSString *)contentsScaling { return objc_getAssociatedObject(self, &k_scaling) ?: @"stretch"; }

- (void)setContentsScaling:(NSString *)s
{
    objc_setAssociatedObject(self, &k_scaling, s, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end
