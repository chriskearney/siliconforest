#import <CoreGraphics/CoreGraphics.h>
#import <SFCoreGraphicsPDF.h>
#import <Foundation/Foundation.h>

/* Implemented by the installed Foundation compatibility series. The pin's
 * compile-time NSString header predates the current runtime. */
@interface NSString (SFComposedCharacters)
- (NSRange)rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index;
@end
