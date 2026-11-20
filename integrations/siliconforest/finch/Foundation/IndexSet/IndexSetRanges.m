// SPDX-License-Identifier: MIT
#import <Foundation/NSIndexSet.h>

@interface NSIndexSet (SFPreviewRangeAccess)
- (NSUInteger)rangeCount;
- (NSRange)rangeAtIndex:(NSUInteger)rangeIndex;
- (NSUInteger)_indexOfRangeContainingIndex:(NSUInteger)value;
@end

@implementation NSIndexSet (SFPreviewRangeAccess)
- (NSUInteger)rangeCount
{
    return _rangeCount;
}

- (NSRange)rangeAtIndex:(NSUInteger)rangeIndex
{
    return rangeIndex < _rangeCount ? _ranges[rangeIndex] : NSMakeRange(NSNotFound, 0);
}

- (NSUInteger)_indexOfRangeContainingIndex:(NSUInteger)value
{
    NSUInteger lower = 0;
    NSUInteger upper = _rangeCount;
    while (lower < upper) {
        NSUInteger middle = lower + (upper - lower) / 2;
        NSRange range = _ranges[middle];
        if (value < range.location)
            upper = middle;
        else if (value - range.location >= range.length)
            lower = middle + 1;
        else
            return middle;
    }
    return NSNotFound;
}
@end
