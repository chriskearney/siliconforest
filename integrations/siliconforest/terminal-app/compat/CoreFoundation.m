// SPDX-License-Identifier: MIT
// CoreFoundation.framework as macOS applications link it: this file plus re-exports of
// /usr/lib/libCoreFoundation.dylib and /usr/lib/libFoundation.dylib (upstream's
// framework-compat layout). What is added here is what Terminal.app imports from
// CoreFoundation and neither library has.
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

// ICU's break iterator (libicucore), declared here: the SDK this is built with has no ICU headers
typedef struct UBreakIterator UBreakIterator;
typedef int UErrorCode;
typedef UniChar UChar;
enum { U_ZERO_ERROR = 0, UBRK_DONE = -1, UBRK_WORD = 1, UBRK_LINE = 2, UBRK_SENTENCE = 3 };
#define U_FAILURE(x) ((x) > U_ZERO_ERROR)
extern UBreakIterator *ubrk_open(int type, const char *locale, const UChar *text, int32_t length, UErrorCode *status);
extern void ubrk_close(UBreakIterator *bi);
extern int32_t ubrk_following(UBreakIterator *bi, int32_t offset);
extern int32_t ubrk_preceding(UBreakIterator *bi, int32_t offset);

// ---- NSURL resource keys (strings whose value is their name, as CoreFoundation's own keys)
NSString *const NSURLLocalizedNameKey = @"NSURLLocalizedNameKey";
NSString *const NSURLPathKey = @"_NSURLPathKey";
NSString *const NSURLTypeIdentifierKey = @"NSURLTypeIdentifierKey";

// ---- CFStringTokenizer: word and other boundaries of a string, from ICU's break iterators
typedef struct __SFStringTokenizer {
    CFStringRef string;
    UniChar *text;
    CFIndex length;
    CFRange range;
    CFOptionFlags options;
    UBreakIterator *iterator;
    CFRange current;
} *SFStringTokenizerRef;

enum { kSFTokenizerUnitMask = 0xf, kSFTokenNone = 0, kSFTokenNormal = 1 };

static void SFTokenizerLoad(SFStringTokenizerRef t, CFStringRef string, CFRange range)
{
    if (t->iterator) { ubrk_close(t->iterator); t->iterator = NULL; }
    if (t->string) CFRelease(t->string);
    free(t->text);
    t->string = string ? CFRetain(string) : NULL;
    t->length = string ? CFStringGetLength(string) : 0;
    if (range.location < 0) range.location = 0;
    if (range.location > t->length) range.location = t->length;
    if (range.length < 0 || range.location + range.length > t->length) range.length = t->length - range.location;
    t->range = range;
    t->text = malloc(sizeof(UniChar) * (size_t)(t->length + 1));
    if (string && t->length) CFStringGetCharacters(string, CFRangeMake(0, t->length), t->text);
    t->current = CFRangeMake(kCFNotFound, 0);
    UErrorCode status = U_ZERO_ERROR;
    int type;
    switch (t->options & kSFTokenizerUnitMask) {
    case 1: type = UBRK_SENTENCE; break;       // kCFStringTokenizerUnitSentence
    case 3: type = UBRK_LINE; break;           // kCFStringTokenizerUnitLineBreak
    default: type = UBRK_WORD; break;          // word, paragraph (approximated by words), word boundary
    }
    t->iterator = ubrk_open(type, NULL, (const UChar *)t->text + t->range.location, (int32_t)t->range.length, &status);
    if (U_FAILURE(status)) t->iterator = NULL;
}

CFTypeRef CFStringTokenizerCreate(CFAllocatorRef alloc, CFStringRef string, CFRange range, CFOptionFlags options, CFLocaleRef locale)
{
    SFStringTokenizerRef t = calloc(1, sizeof(*t));
    if (t == NULL) return NULL;
    t->options = options;
    SFTokenizerLoad(t, string, range);
    // The object is handed out as a CFData that owns nothing but carries the pointer: callers
    // only CFRetain/CFRelease it and pass it back to the calls below.
    CFMutableDataRef box = CFDataCreateMutable(alloc, sizeof(t));
    CFDataAppendBytes(box, (const UInt8 *)&t, sizeof(t));
    return box;
}

static SFStringTokenizerRef SFTokenizer(CFTypeRef box)
{
    SFStringTokenizerRef t = NULL;
    if (box && CFGetTypeID(box) == CFDataGetTypeID() && CFDataGetLength(box) == sizeof(t))
        memcpy(&t, CFDataGetBytePtr(box), sizeof(t));
    return t;
}

void CFStringTokenizerSetString(CFTypeRef tokenizer, CFStringRef string, CFRange range)
{
    SFStringTokenizerRef t = SFTokenizer(tokenizer);
    if (t) SFTokenizerLoad(t, string, range);
}

CFOptionFlags CFStringTokenizerGoToTokenAtIndex(CFTypeRef tokenizer, CFIndex index)
{
    SFStringTokenizerRef t = SFTokenizer(tokenizer);
    if (t == NULL || t->iterator == NULL || index < t->range.location || index >= t->range.location + t->range.length) {
        if (t) t->current = CFRangeMake(kCFNotFound, 0);
        return kSFTokenNone;
    }
    int32_t offset = (int32_t)(index - t->range.location);
    int32_t end = ubrk_following(t->iterator, offset);
    if (end == UBRK_DONE) end = (int32_t)t->range.length;
    int32_t start = ubrk_preceding(t->iterator, offset + 1);
    if (start == UBRK_DONE) start = 0;
    t->current = CFRangeMake(t->range.location + start, end - start);
    return kSFTokenNormal;
}

CFRange CFStringTokenizerGetCurrentTokenRange(CFTypeRef tokenizer)
{
    SFStringTokenizerRef t = SFTokenizer(tokenizer);
    return t ? t->current : CFRangeMake(kCFNotFound, 0);
}

// ---- Web services providers (private; Terminal asks for the default search engine's name for
// "Search With ..."). This system has no provider registry: there is no provider.
CFStringRef const kCFWebServicesTypeWebSearch = CFSTR("WebSearch");
CFStringRef const kCFWebServicesProviderDefaultDisplayNameKey = CFSTR("DefaultDisplayName");
CFDictionaryRef _CFWebServicesCopyProviderInfo(CFStringRef serviceType, Boolean *outIsUserSelection)
{
    if (outIsUserSelection) *outIsUserSelection = false;
    return NULL;
}

// ---- The calendar identifier of before macOS 10.10 (VLC media player 3.0 and the Growl framework
// it carries import it from CoreFoundation, where macOS keeps it; docs/roadmap/issues/SF-AH-vlc.md).
// The value is the identifier itself: +[NSCalendar calendarWithIdentifier:] takes it as it takes
// NSCalendarIdentifierGregorian.
CFStringRef const NSGregorianCalendar = CFSTR("gregorian");
