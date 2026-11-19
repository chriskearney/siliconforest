/* SPDX-License-Identifier: MIT */
#ifndef SF_ATTRIBUTE_RUNTIME_H
#define SF_ATTRIBUTE_RUNTIME_H
#include <mach-o/dyld.h>
#include <CoreFoundation/CFRegularExpression.h>

typedef struct { CFRange range; Boolean backwards; } SFAttributeMatch;
static inline void sf_attribute_match(void *context, CFRange *ranges, CFIndex count,
    _CFRegularExpressionMatchingFlags flags, Boolean *stop) {
    (void)flags;
    SFAttributeMatch *match = (SFAttributeMatch *)context;
    if (count > 0 && ranges && ranges[0].location != kCFNotFound) {
        match->range = ranges[0];
        *stop = !match->backwards;
    }
}
/* Invalid patterns return no match, as the pinned nonthrowing range API does. */
static inline CFRange sf_attribute_regex_range(CFStringRef value, CFStringRef pattern,
                                               CFOptionFlags options) {
    SFAttributeMatch match = {{kCFNotFound, 0}, (options & 4) != 0};
    CFErrorRef error = NULL;
    _CFRegularExpressionRef regex = _CFRegularExpressionCreate(kCFAllocatorDefault,
        pattern, (options & 1) ? _kCFRegularExpressionCaseInsensitive : 0, &error);
    if (error) CFRelease(error);
    if (!regex) return match.range;
    _CFRegularExpressionEnumerateMatchesInString(regex, value,
        (options & 8) ? _kCFRegularExpressionMatchingAnchored : 0,
        CFRangeMake(0, CFStringGetLength(value)), &match, sf_attribute_match);
    CFRelease(regex);
    return match.range;
}
#endif
