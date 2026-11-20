// SPDX-License-Identifier: MIT
#include <CoreText/CoreText.h>
#include <stdio.h>

struct Metrics {
    CGFloat width;
    int deallocated;
};

static CGFloat width(void *context) { return ((struct Metrics *)context)->width; }
static CGFloat ascent(void *context) { return context ? 19 : 0; }
static CGFloat descent(void *context) { return context ? 7 : 0; }
static void deallocate(void *context) { ((struct Metrics *)context)->deallocated++; }

int main(void) {
    static struct Metrics metrics = { .width = 31 };
    CTRunDelegateCallbacks callbacks = {
        kCTRunDelegateCurrentVersion, deallocate, ascent, descent, width
    };
    double first = 0, second = 0;
    CGFloat a = 0, d = 0;
    @autoreleasepool {
        CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, &metrics);
        if (!delegate || CFGetTypeID(delegate) != CTRunDelegateGetTypeID() ||
            CTRunDelegateGetRefCon(delegate) != &metrics) return 1;

        const UniChar replacement = 0xfffc;
        CFStringRef text = CFStringCreateWithCharacters(NULL, &replacement, 1);
        const void *key = kCTRunDelegateAttributeName;
        const void *value = delegate;
        CFDictionaryRef attributes = CFDictionaryCreate(NULL, &key, &value, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFAttributedStringRef attributed = CFAttributedStringCreate(NULL, text, attributes);
        CTLineRef line = CTLineCreateWithAttributedString(attributed);
        if (!line) return 2;
        first = CTLineGetTypographicBounds(line, &a, &d, NULL);
        metrics.width = 73;
        CTLineRef changed = CTLineCreateWithAttributedString(attributed);
        if (!changed) return 3;
        second = CTLineGetTypographicBounds(changed, NULL, NULL, NULL);
        CFRelease(changed);
        CFRelease(line);
        CFRelease(attributed);
        CFRelease(attributes);
        CFRelease(text);
        if (metrics.deallocated != 0) return 4;
        CFRelease(delegate);

        CFAttributedStringRef ordinary = CFAttributedStringCreate(NULL, CFSTR("cache"), NULL);
        CTLineRef cached1 = CTLineCreateWithAttributedString(ordinary);
        CTLineRef cached2 = CTLineCreateWithAttributedString(ordinary);
        if (!cached1 || cached1 != cached2) return 5;
        CFRelease(cached2);
        CFRelease(cached1);
        CFRelease(ordinary);
    }
    printf("CTRunDelegate width %.2f -> %.2f ascent %.2f descent %.2f dealloc %d\n",
           first, second, a, d, metrics.deallocated);
    if (first != 31 || second != 73 || a != 19 || d != 7 || metrics.deallocated != 1) return 6;
    puts("CTRunDelegate dynamic metrics and callback cleanup PASS");
    return 0;
}
