/* Deprecated NSString cstring entry points.
   Extracted from the overnight Foundation overlay's
   NSString (SFDeprecatedCStringCompat) category. UTF-8 first, then
   ISO Latin-1. The rest of that file is unrelated and is not here. */
#import <Foundation/Foundation.h>

@implementation NSString (SFDeprecatedCStringCompat)
- (instancetype)initWithCString:(const char *)cstr {
    if (!cstr) return [self initWithString:@""];
    id s = [self initWithCString:cstr encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithCString:cstr encoding:NSISOLatin1StringEncoding];
    return s;
}
+ (instancetype)stringWithCString:(const char *)cstr {
    if (!cstr) return @"";
    id s = [self stringWithCString:cstr encoding:NSUTF8StringEncoding];
    if (!s) s = [self stringWithCString:cstr encoding:NSISOLatin1StringEncoding];
    return s;
}
@end
