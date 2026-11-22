/* SPDX-License-Identifier: MIT
   TextEdit links NSTextContentStorage, NSTextLayoutManager, and NSTextRange.
   DocumentWindowController init uses TextKit 2 when any of these defaults
   is true, including a value inherited from the global domain. Force them
   off so it builds an NSLayoutManager instead. The classes still have to
   exist so dyld can bind them. */
#import <Foundation/Foundation.h>

__attribute__((constructor))
static void sf_textkit1(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *keys[] = {
        @"UsesTextLayoutManagerForPlainDocuments",
        @"UsesTextLayoutManagerForRichDocuments",
        @"UsesTextLayoutManagerForMultiplePageDocuments",
        @"NSUsesTextLayoutManager",
    };
    for (unsigned i = 0; i < sizeof keys / sizeof keys[0]; i++)
        [defaults setBool:NO forKey:keys[i]];
}

@interface NSTextRange : NSObject
@end
@implementation NSTextRange
@end

@interface NSTextContentStorage : NSObject
@end
@implementation NSTextContentStorage
@end

@interface NSTextLayoutManager : NSObject
@end
@implementation NSTextLayoutManager
@end
