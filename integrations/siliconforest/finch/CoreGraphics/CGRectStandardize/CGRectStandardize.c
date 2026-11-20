// SPDX-License-Identifier: MIT OR Apache-2.0
// CGRectStandardize for the retained CoreGraphics provider.
// Null and infinite classification stay the provider's existing exports.
// Negative extents follow the retained Finch CGGeometry.c rule: move the
// origin by the negative size, then make that size positive. An empty
// rectangle is one with a zero side and is not rewritten for that reason.
// A null rectangle becomes the provider CGRectNull. An infinite rectangle
// is returned unchanged.

typedef double CGFloat;
typedef struct {
    CGFloat x, y;
} CGPoint;
typedef struct {
    CGFloat width, height;
} CGSize;
typedef struct {
    CGPoint origin;
    CGSize size;
} CGRect;

extern _Bool CGRectIsNull(CGRect rect);
extern _Bool CGRectIsInfinite(CGRect rect);
extern const CGRect CGRectNull;

__attribute__((visibility("default")))
CGRect CGRectStandardize(CGRect rect) {
    if (CGRectIsNull(rect))
        return CGRectNull;
    if (CGRectIsInfinite(rect))
        return rect;
    if (rect.size.width < 0) {
        rect.origin.x += rect.size.width;
        rect.size.width = -rect.size.width;
    }
    if (rect.size.height < 0) {
        rect.origin.y += rect.size.height;
        rect.size.height = -rect.size.height;
    }
    return rect;
}
