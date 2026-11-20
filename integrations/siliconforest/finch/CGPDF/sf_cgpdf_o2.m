/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * Public CGPDF read and scanner calls on retained Onyx2D objects.
 *
 * CGPDFDocumentRef and CGPDFPageRef stay the O2PDFDocument and O2PDFPage
 * pointers that CoreGraphics already returns. This file does not export
 * CGPDFDocumentCreateWithProvider or CGContextDrawPDFPage, so drawing stays
 * in O2ContextDrawPDFPage and uses Onyx fonts and path operators.
 *
 * O2PDFInteger is int and O2PDFReal is float. Public values are long and
 * double. Each read uses a narrow local, then widens. Onyx2D is MIT,
 * Copyright 2007 Christopher J. W. Lloyd. The PDFDocEncoding table is ISO
 * 32000-1 Annex D. This is not Apple code.
 */
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFObject.h>
#import <Onyx2D/O2PDFOperatorTable.h>
#import <Onyx2D/O2PDFPage.h>
#import <Onyx2D/O2PDFScanner.h>
#import <Onyx2D/O2PDFStream.h>
#import <Onyx2D/O2PDFString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMapTable.h>
#import <objc/runtime.h>
#import <stdbool.h>
#import <stdlib.h>
#import <string.h>

typedef long CGPDFInteger;
typedef double CGPDFReal;
typedef unsigned char CGPDFBoolean;
typedef uint32_t CGPDFAccessPermissions;
typedef O2PDFObject *CGPDFObjectRef;
typedef O2PDFArray *CGPDFArrayRef;
typedef O2PDFDictionary *CGPDFDictionaryRef;
typedef O2PDFStream *CGPDFStreamRef;
typedef O2PDFString *CGPDFStringRef;
typedef O2PDFContentStream *CGPDFContentStreamRef;
typedef O2PDFScanner *CGPDFScannerRef;
typedef O2PDFOperatorTable *CGPDFOperatorTableRef;
typedef void (*CGPDFDictionaryApplierFunction)(const char *key, CGPDFObjectRef value, void *info);
typedef void (*CGPDFOperatorCallback)(CGPDFScannerRef scanner, void *info);

enum {
    kCGPDFAllowsLowQualityPrinting = 1 << 0,
    kCGPDFAllowsContentCopying = 1 << 4
};

_Static_assert(sizeof(CGPDFInteger) == 8, "public CGPDFInteger is signed long");
_Static_assert(sizeof(O2PDFInteger) == 4, "O2PDFInteger stays int");
_Static_assert(sizeof(CGPDFReal) == 8, "public CGPDFReal is double");
_Static_assert(sizeof(O2PDFReal) == 4, "O2PDFReal stays float");
_Static_assert(sizeof(CGRect) == 32, "CGRect is four doubles");
_Static_assert(sizeof(O2Rect) == sizeof(CGRect), "O2Rect is NSRect, which is CGRect");

const CFStringRef kCGPDFOutlineTitle = CFSTR("Title");
const CFStringRef kCGPDFOutlineChildren = CFSTR("Children");
const CFStringRef kCGPDFOutlineDestination = CFSTR("Destination");
const CFStringRef kCGPDFContextMediaBox = CFSTR("kCGPDFContextMediaBox");
const CFStringRef kCGPDFContextAuthor = CFSTR("kCGPDFContextAuthor");
const CFStringRef kCGPDFContextSubject = CFSTR("kCGPDFContextSubject");
const CFStringRef kCGPDFContextKeywords = CFSTR("kCGPDFContextKeywords");

static char g_outline_key;

static id ivar_value(id object, Class cls, const char *name)
{
    Ivar iv;
    if (!object)
        return nil;
    iv = class_getInstanceVariable(cls, name);
    if (!iv)
        return nil;
    return *(id *)((char *)object + ivar_getOffset(iv));
}

static int parse_version_bytes(const unsigned char *bytes, size_t n, int *major, int *minor)
{
    if (!bytes || n < 3 || bytes[0] < '0' || bytes[0] > '9' || bytes[1] != '.')
        return 0;
    *major = bytes[0] - '0';
    *minor = atoi((const char *)bytes + 2);
    return 1;
}

void CGPDFDocumentGetVersion(CGPDFDocumentRef doc, int *major, int *minor)
{
    O2PDFString *version;
    O2PDFDictionary *catalog;
    const char *name = NULL;
    int ma = 0, mi = 0, ca = 0, ci = 0;
    if (major)
        *major = 0;
    if (minor)
        *minor = 0;
    if (!doc)
        return;
    version = (O2PDFString *)ivar_value((id)doc, [O2PDFDocument class], "_version");
    if (version)
        parse_version_bytes(O2PDFStringGetBytePtr(version), O2PDFStringGetLength(version), &ma, &mi);
    catalog = [(O2PDFDocument *)doc catalog];
    if (catalog && [catalog getNameForKey:"Version" value:&name] && name)
        parse_version_bytes((const unsigned char *)name, strlen(name), &ca, &ci);
    if (ca > ma || (ca == ma && ci > mi)) {
        ma = ca;
        mi = ci;
    }
    if (major)
        *major = ma;
    if (minor)
        *minor = mi;
}

bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef doc)
{
    return doc && [(O2PDFDocument *)doc encryptDictionary] != nil;
}

bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef doc)
{
    /* NULL matches the Finch reader. An encrypt dictionary has no password handler. */
    if (!doc)
        return true;
    return [(O2PDFDocument *)doc encryptDictionary] == nil;
}

bool CGPDFDocumentUnlockWithPassword(CGPDFDocumentRef doc, const char *password)
{
    (void)password;
    if (!doc)
        return false;
    return [(O2PDFDocument *)doc encryptDictionary] == nil;
}

CGPDFAccessPermissions CGPDFDocumentGetAccessPermissions(CGPDFDocumentRef doc)
{
    /* /P is not decoded. Encrypted documents stay at zero. Unencrypted files
       use the same 0xff mask as PDFKit/Numeric.h. */
    if (!doc || [(O2PDFDocument *)doc encryptDictionary])
        return 0;
    return 0xff;
}

bool CGPDFDocumentAllowsPrinting(CGPDFDocumentRef doc)
{
    return doc && (CGPDFDocumentGetAccessPermissions(doc) & kCGPDFAllowsLowQualityPrinting);
}

bool CGPDFDocumentAllowsCopying(CGPDFDocumentRef doc)
{
    return doc && (CGPDFDocumentGetAccessPermissions(doc) & kCGPDFAllowsContentCopying);
}

CGPDFDictionaryRef CGPDFDocumentGetInfo(CGPDFDocumentRef doc)
{
    return doc ? (CGPDFDictionaryRef)[(O2PDFDocument *)doc infoDictionary] : NULL;
}

static int utf8_add(char **buf, size_t *n, size_t *cap, unsigned cp)
{
    unsigned char tmp[4];
    int k = 0;
    char *grown;
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
        cp = 0xFFFD;
    if (cp < 0x80)
        tmp[k++] = (unsigned char)cp;
    else if (cp < 0x800) {
        tmp[k++] = (unsigned char)(0xC0 | (cp >> 6));
        tmp[k++] = (unsigned char)(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
        tmp[k++] = (unsigned char)(0xE0 | (cp >> 12));
        tmp[k++] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
        tmp[k++] = (unsigned char)(0x80 | (cp & 0x3F));
    } else {
        tmp[k++] = (unsigned char)(0xF0 | (cp >> 18));
        tmp[k++] = (unsigned char)(0x80 | ((cp >> 12) & 0x3F));
        tmp[k++] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
        tmp[k++] = (unsigned char)(0x80 | (cp & 0x3F));
    }
    if (*n + (size_t)k + 1 > *cap) {
        size_t c = *cap ? *cap * 2 : 32;
        while (c < *n + (size_t)k + 1)
            c *= 2;
        grown = realloc(*buf, c);
        if (!grown)
            return 0;
        *buf = grown;
        *cap = c;
    }
    memcpy(*buf + *n, tmp, (size_t)k);
    *n += (size_t)k;
    (*buf)[*n] = 0;
    return 1;
}

static char *text_utf8(const unsigned char *b, size_t n)
{
    static const unsigned pdfdoc_18[8] = {0x02D8, 0x02C7, 0x02C6, 0x02D9, 0x02DD, 0x02DB, 0x02DA, 0x02DC};
    static const unsigned pdfdoc_80[33] = {
        0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013, 0x0192, 0x2044, 0x2039, 0x203A, 0x2212,
        0x2030, 0x201E, 0x201C, 0x201D, 0x2018, 0x2019, 0x201A, 0x2122, 0xFB01, 0xFB02, 0x0141,
        0x0152, 0x0160, 0x0178, 0x017D, 0x0131, 0x0142, 0x0153, 0x0161, 0x017E, 0xFFFD, 0x20AC};
    char *out = NULL;
    size_t len = 0, cap = 0, i;
    if (!b)
        n = 0;
    if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
        for (i = 2; i + 1 < n; i += 2)
            if (!utf8_add(&out, &len, &cap, ((unsigned)b[i] << 8) | b[i + 1]))
                goto fail;
    } else if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
        for (i = 2; i + 1 < n; i += 2)
            if (!utf8_add(&out, &len, &cap, ((unsigned)b[i + 1] << 8) | b[i]))
                goto fail;
    } else if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
        for (i = 3; i < n; i++)
            if (!utf8_add(&out, &len, &cap, b[i]))
                goto fail;
    } else {
        for (i = 0; i < n; i++) {
            unsigned c = b[i];
            if (c >= 0x18 && c <= 0x1F)
                c = pdfdoc_18[c - 0x18];
            else if (c >= 0x80 && c <= 0xA0)
                c = pdfdoc_80[c - 0x80];
            if (!utf8_add(&out, &len, &cap, c))
                goto fail;
        }
    }
    if (!out)
        out = calloc(1, 1);
    return out;
fail:
    free(out);
    return NULL;
}

static CFStringRef cf_text(O2PDFString *string)
{
    char *utf;
    CFStringRef result;
    if (!string)
        return CFStringCreateWithCString(NULL, "", kCFStringEncodingUTF8);
    utf = text_utf8(O2PDFStringGetBytePtr(string), O2PDFStringGetLength(string));
    if (!utf)
        return NULL;
    result = CFStringCreateWithBytes(NULL, (const UInt8 *)utf, (CFIndex)strlen(utf), kCFStringEncodingUTF8, false);
    free(utf);
    return result;
}

static long page_index(O2PDFDocument *doc, O2PDFDictionary *page)
{
    int count, i;
    if (!doc || !page)
        return 0;
    count = [doc pageCount];
    for (i = 1; i <= count; i++) {
        O2PDFPage *got = [doc pageAtNumber:i];
        if ([got dictionary] == page)
            return i;
    }
    return 0;
}

static long dest_page(O2PDFDocument *doc, O2PDFObject *dest)
{
    O2PDFObject *first = nil;
    /* A name destination is not resolved. Only an explicit array is. */
    dest = [dest realObject];
    if (!dest || [dest objectType] != kO2PDFObjectTypeArray)
        return 0;
    if (![(O2PDFArray *)dest getObjectAtIndex:0 value:&first])
        return 0;
    first = [first realObject];
    if (!first || [first objectType] != kO2PDFObjectTypeDictionary)
        return 0;
    return page_index(doc, (O2PDFDictionary *)first);
}

static CFArrayRef outline_items(O2PDFDocument *doc, O2PDFDictionary *item, int depth, id *seen, int *nseen)
{
    CFMutableArrayRef kids = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (!kids)
        return NULL;
    while (item && depth < 32) {
        CFMutableDictionaryRef entry;
        O2PDFString *title = nil;
        O2PDFObject *dest = nil;
        O2PDFDictionary *action = nil;
        O2PDFDictionary *child = nil;
        O2PDFDictionary *next = nil;
        CFStringRef title_cf;
        CFArrayRef nested;
        long page;
        const char *kind = NULL;
        int s, stop = 0;
        for (s = 0; s < *nseen; s++) {
            if (seen[s] == (id)item)
                stop = 1;
        }
        if (stop)
            break;
        if (*nseen < 64)
            seen[(*nseen)++] = (id)item;
        entry = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        [item getStringForKey:"Title" value:&title];
        title_cf = cf_text(title);
        if (entry && title_cf)
            CFDictionarySetValue(entry, kCGPDFOutlineTitle, title_cf);
        if (title_cf)
            CFRelease(title_cf);
        if (![item getObjectForKey:"Dest" value:&dest])
            dest = nil;
        if (!dest && [item getDictionaryForKey:"A" value:&action] && [action getNameForKey:"S" value:&kind] && kind && strcmp(kind, "GoTo") == 0)
            [action getObjectForKey:"D" value:&dest];
        page = dest ? dest_page(doc, dest) : 0;
        if (page && entry) {
            CFNumberRef number = CFNumberCreate(NULL, kCFNumberLongType, &page);
            if (number) {
                CFDictionarySetValue(entry, kCGPDFOutlineDestination, number);
                CFRelease(number);
            }
        }
        if ([item getDictionaryForKey:"First" value:&child]) {
            nested = outline_items(doc, child, depth + 1, seen, nseen);
            if (nested && CFArrayGetCount(nested) && entry)
                CFDictionarySetValue(entry, kCGPDFOutlineChildren, nested);
            if (nested)
                CFRelease(nested);
        }
        if (entry && (page || (CFDictionaryGetValue(entry, kCGPDFOutlineChildren) != NULL)))
            CFArrayAppendValue(kids, entry);
        if (entry)
            CFRelease(entry);
        if (![item getDictionaryForKey:"Next" value:&next])
            break;
        item = next;
    }
    return kids;
}

CFDictionaryRef CGPDFDocumentGetOutline(CGPDFDocumentRef doc)
{
    id cached;
    O2PDFDictionary *outlines = nil;
    O2PDFDictionary *first = nil;
    CFMutableDictionaryRef root;
    CFArrayRef kids;
    id seen[64];
    int nseen = 0;
    if (!doc)
        return NULL;
    cached = objc_getAssociatedObject((id)doc, &g_outline_key);
    if (cached)
        return (CFDictionaryRef)cached;
    if (![[(O2PDFDocument *)doc catalog] getDictionaryForKey:"Outlines" value:&outlines])
        return NULL;
    [outlines getDictionaryForKey:"First" value:&first];
    kids = first ? outline_items((O2PDFDocument *)doc, first, 0, seen, &nseen) : CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    root = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!root) {
        if (kids)
            CFRelease(kids);
        return NULL;
    }
    if (kids) {
        CFDictionarySetValue(root, kCGPDFOutlineChildren, kids);
        CFRelease(kids);
    }
    objc_setAssociatedObject((id)doc, &g_outline_key, (id)root, OBJC_ASSOCIATION_RETAIN);
    CFRelease(root);
    return root;
}

CGPDFDictionaryRef CGPDFPageGetDictionary(CGPDFPageRef page)
{
    return page ? (CGPDFDictionaryRef)[(O2PDFPage *)page dictionary] : NULL;
}

int CGPDFPageGetRotationAngle(CGPDFPageRef page)
{
    O2PDFObject *rotate;
    O2PDFInteger value = 0;
    /* -[O2PDFPage rotationAngle] returns 0. The parsed dictionary still has /Rotate. */
    if (!page)
        return 0;
    rotate = [[(O2PDFPage *)page dictionary] inheritedForCStringKey:"Rotate" typecheck:kO2PDFObjectTypeInteger];
    if (!rotate || ![rotate checkForType:kO2PDFObjectTypeInteger value:&value])
        return 0;
    return (int)value;
}

size_t CGPDFPageGetPageNumber(CGPDFPageRef page)
{
    /* pageAtNumber: stores the zero-based kid offset it searched for. */
    if (!page)
        return 0;
    return (size_t)[(O2PDFPage *)page pageNumber] + 1;
}

void CGPDFContextBeginPage(CGContextRef context, CFDictionaryRef pageInfo)
{
    CFDataRef box;
    CGRect rect;
    if (!context || ![(id)context isKindOfClass:[O2PDFContext class]])
        return;
    box = pageInfo ? (CFDataRef)CFDictionaryGetValue(pageInfo, kCGPDFContextMediaBox) : NULL;
    if (!box || CFGetTypeID(box) != CFDataGetTypeID() || CFDataGetLength(box) != (CFIndex)sizeof(CGRect))
        return;
    memcpy(&rect, CFDataGetBytePtr(box), sizeof rect);
    [(O2PDFContext *)context beginPage:(const O2Rect *)&rect];
}

void CGPDFContextEndPage(CGContextRef context)
{
    if (context && [(id)context isKindOfClass:[O2PDFContext class]])
        [(O2PDFContext *)context endPage];
}

CGPDFContentStreamRef CGPDFContentStreamCreateWithPage(CGPDFPageRef page)
{
    if (!page)
        return NULL;
    return (CGPDFContentStreamRef)[[O2PDFContentStream alloc] initWithPage:(O2PDFPage *)page];
}

CGPDFObjectRef CGPDFContentStreamGetResource(CGPDFContentStreamRef stream, const char *category, const char *name)
{
    if (!stream || !category || !name)
        return NULL;
    return (CGPDFObjectRef)[(O2PDFContentStream *)stream resourceForCategory:category name:name];
}

void CGPDFContentStreamRelease(CGPDFContentStreamRef stream)
{
    [(id)stream release];
}

CGPDFOperatorTableRef CGPDFOperatorTableCreate(void)
{
    return (CGPDFOperatorTableRef)[[O2PDFOperatorTable alloc] init];
}

void CGPDFOperatorTableRelease(CGPDFOperatorTableRef table)
{
    [(id)table release];
}

void CGPDFOperatorTableSetCallback(CGPDFOperatorTableRef table, const char *name, CGPDFOperatorCallback callback)
{
    if (!table || !name)
        return;
    [(O2PDFOperatorTable *)table setCallback:(O2PDFOperatorCallback)callback forName:name];
}

CGPDFScannerRef CGPDFScannerCreate(CGPDFContentStreamRef stream, CGPDFOperatorTableRef table, void *info)
{
    if (!stream)
        return NULL;
    return (CGPDFScannerRef)[[O2PDFScanner alloc] initWithContentStream:(O2PDFContentStream *)stream
                                                           operatorTable:(O2PDFOperatorTable *)table
                                                                    info:info];
}

static int sf_regular(unsigned char c)
{
    return c > 32 && c < 127 && c != '(' && c != ')' && c != '<' && c != '>' && c != '[' && c != ']' &&
           c != '{' && c != '}' && c != '/' && c != '%';
}

static int sf_operator_name(const char *name, size_t n)
{
    size_t i;
    int word = 0;
    if (!name || n == 0 || n > 16)
        return 0;
    for (i = 0; i < n; i++) {
        unsigned char c = (unsigned char)name[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '*' || c == '\'' || c == '"')
            word = 1;
        else if (c < '0' || c > '9')
            return 0;
    }
    return word;
}

/* Onyx raises on an operator that has no callback. CGPDFScanner skips that
   operator and drops the operands it pushed. */
static void sf_ignore_operator(O2PDFScanner *scanner, void *info)
{
    O2PDFObject *value = nil;
    (void)info;
    while (O2PDFScannerPopObject(scanner, &value))
        ;
}

static void sf_note_operators(O2PDFOperatorTable *table, const unsigned char *bytes, size_t n)
{
    size_t i = 0;
    if (!table || !bytes)
        return;
    while (i < n) {
        unsigned char c = bytes[i];
        if (c == '%') {
            while (i < n && bytes[i] != '\n' && bytes[i] != '\r')
                i++;
            continue;
        }
        if (c == '(') {
            int depth = 1;
            i++;
            while (i < n && depth) {
                if (bytes[i] == '\\' && i + 1 < n) {
                    i += 2;
                    continue;
                }
                if (bytes[i] == '(')
                    depth++;
                else if (bytes[i] == ')')
                    depth--;
                i++;
            }
            continue;
        }
        if (c == '<') {
            i++;
            if (i < n && bytes[i] == '<') {
                i++;
                continue;
            }
            while (i < n && bytes[i] != '>')
                i++;
            if (i < n)
                i++;
            continue;
        }
        if (c == '/') {
            i++;
            while (i < n && sf_regular(bytes[i]))
                i++;
            continue;
        }
        if (sf_regular(c)) {
            size_t start = i;
            char name[17];
            while (i < n && sf_regular(bytes[i]))
                i++;
            if (sf_operator_name((const char *)bytes + start, i - start)) {
                memcpy(name, bytes + start, i - start);
                name[i - start] = 0;
                if ([table callbackForName:name] == NULL)
                    [table setCallback:sf_ignore_operator forName:name];
            }
            continue;
        }
        i++;
    }
}

static void sf_arm_unknown_operators(O2PDFScanner *scanner)
{
    O2PDFOperatorTable *table;
    NSArray *streams;
    NSUInteger i, count;
    table = (O2PDFOperatorTable *)ivar_value((id)scanner, [O2PDFScanner class], "_operatorTable");
    streams = [[scanner contentStream] streams];
    count = streams ? [streams count] : 0;
    for (i = 0; i < count; i++) {
        id item = [streams objectAtIndex:i];
        O2PDFStream *stream = nil;
        NSData *data;
        if (![item checkForType:kO2PDFObjectTypeStream value:&stream] || !stream)
            continue;
        data = [stream data];
        if (data)
            sf_note_operators(table, [data bytes], (size_t)[data length]);
    }
}

bool CGPDFScannerScan(CGPDFScannerRef scanner)
{
    BOOL result = NO;
    NSAutoreleasePool *pool;
    if (!scanner)
        return false;
    pool = [[NSAutoreleasePool alloc] init];
    sf_arm_unknown_operators((O2PDFScanner *)scanner);
    @try {
        result = [(O2PDFScanner *)scanner scan];
    } @catch (id exception) {
        (void)exception;
        result = NO;
    }
    [pool release];
    return result ? true : false;
}

CGPDFContentStreamRef CGPDFScannerGetContentStream(CGPDFScannerRef scanner)
{
    return scanner ? (CGPDFContentStreamRef)[(O2PDFScanner *)scanner contentStream] : NULL;
}

void CGPDFScannerRelease(CGPDFScannerRef scanner)
{
    [(id)scanner release];
}

bool CGPDFScannerPopNumber(CGPDFScannerRef scanner, CGPDFReal *value)
{
    O2PDFReal narrow;
    if (!scanner || !value)
        return false;
    if (!O2PDFScannerPopNumber((O2PDFScanner *)scanner, &narrow))
        return false;
    *value = (CGPDFReal)narrow;
    return true;
}

bool CGPDFScannerPopInteger(CGPDFScannerRef scanner, CGPDFInteger *value)
{
    O2PDFInteger narrow;
    if (!scanner || !value)
        return false;
    if (!O2PDFScannerPopInteger((O2PDFScanner *)scanner, &narrow))
        return false;
    *value = (CGPDFInteger)narrow;
    return true;
}

bool CGPDFScannerPopName(CGPDFScannerRef scanner, const char **value)
{
    return scanner && value && O2PDFScannerPopName((O2PDFScanner *)scanner, value);
}

bool CGPDFScannerPopString(CGPDFScannerRef scanner, CGPDFStringRef *value)
{
    O2PDFString *narrow = nil;
    if (!scanner || !value)
        return false;
    if (!O2PDFScannerPopString((O2PDFScanner *)scanner, &narrow))
        return false;
    *value = (CGPDFStringRef)narrow;
    return true;
}

bool CGPDFScannerPopArray(CGPDFScannerRef scanner, CGPDFArrayRef *value)
{
    O2PDFArray *narrow = nil;
    if (!scanner || !value)
        return false;
    if (!O2PDFScannerPopArray((O2PDFScanner *)scanner, &narrow))
        return false;
    *value = (CGPDFArrayRef)narrow;
    return true;
}

bool CGPDFObjectGetValue(CGPDFObjectRef object, int type, void *value)
{
    O2PDFInteger integer;
    O2PDFReal real;
    O2PDFBoolean boolean;
    if (!object || !value)
        return false;
    if (type == kO2PDFObjectTypeInteger) {
        if (![(O2PDFObject *)object checkForType:kO2PDFObjectTypeInteger value:&integer])
            return false;
        *(CGPDFInteger *)value = integer;
        return true;
    }
    if (type == kO2PDFObjectTypeReal) {
        if (![(O2PDFObject *)object checkForType:kO2PDFObjectTypeReal value:&real])
            return false;
        *(CGPDFReal *)value = real;
        return true;
    }
    if (type == kO2PDFObjectTypeBoolean) {
        if (![(O2PDFObject *)object checkForType:kO2PDFObjectTypeBoolean value:&boolean])
            return false;
        *(CGPDFBoolean *)value = boolean ? 1 : 0;
        return true;
    }
    return [(O2PDFObject *)object checkForType:(O2PDFObjectType)type value:value];
}

size_t CGPDFArrayGetCount(CGPDFArrayRef array)
{
    return array ? [(O2PDFArray *)array count] : 0;
}

bool CGPDFArrayGetNumber(CGPDFArrayRef array, size_t index, CGPDFReal *value)
{
    O2PDFReal narrow;
    if (!array || !value || index > 0xffffffffu)
        return false;
    if (![(O2PDFArray *)array getNumberAtIndex:(unsigned)index value:&narrow])
        return false;
    *value = (CGPDFReal)narrow;
    return true;
}

bool CGPDFArrayGetString(CGPDFArrayRef array, size_t index, CGPDFStringRef *value)
{
    O2PDFString *narrow = nil;
    if (!array || !value || index > 0xffffffffu)
        return false;
    if (![(O2PDFArray *)array getStringAtIndex:(unsigned)index value:&narrow])
        return false;
    *value = (CGPDFStringRef)narrow;
    return true;
}

bool CGPDFArrayGetDictionary(CGPDFArrayRef array, size_t index, CGPDFDictionaryRef *value)
{
    O2PDFDictionary *narrow = nil;
    if (!array || !value || index > 0xffffffffu)
        return false;
    if (![(O2PDFArray *)array getDictionaryAtIndex:(unsigned)index value:&narrow])
        return false;
    *value = (CGPDFDictionaryRef)narrow;
    return true;
}

bool CGPDFDictionaryGetInteger(CGPDFDictionaryRef dict, const char *key, CGPDFInteger *value)
{
    O2PDFInteger narrow;
    if (!dict || !key || !value)
        return false;
    if (![(O2PDFDictionary *)dict getIntegerForKey:key value:&narrow])
        return false;
    *value = (CGPDFInteger)narrow;
    return true;
}

bool CGPDFDictionaryGetNumber(CGPDFDictionaryRef dict, const char *key, CGPDFReal *value)
{
    O2PDFReal narrow;
    if (!dict || !key || !value)
        return false;
    if (![(O2PDFDictionary *)dict getNumberForKey:key value:&narrow])
        return false;
    *value = (CGPDFReal)narrow;
    return true;
}

bool CGPDFDictionaryGetName(CGPDFDictionaryRef dict, const char *key, const char **value)
{
    return dict && key && value && [(O2PDFDictionary *)dict getNameForKey:key value:value];
}

bool CGPDFDictionaryGetString(CGPDFDictionaryRef dict, const char *key, CGPDFStringRef *value)
{
    O2PDFString *narrow = nil;
    if (!dict || !key || !value)
        return false;
    if (![(O2PDFDictionary *)dict getStringForKey:key value:&narrow])
        return false;
    *value = (CGPDFStringRef)narrow;
    return true;
}

bool CGPDFDictionaryGetArray(CGPDFDictionaryRef dict, const char *key, CGPDFArrayRef *value)
{
    O2PDFArray *narrow = nil;
    if (!dict || !key || !value)
        return false;
    if (![(O2PDFDictionary *)dict getArrayForKey:key value:&narrow])
        return false;
    *value = (CGPDFArrayRef)narrow;
    return true;
}

bool CGPDFDictionaryGetDictionary(CGPDFDictionaryRef dict, const char *key, CGPDFDictionaryRef *value)
{
    O2PDFDictionary *narrow = nil;
    if (!dict || !key || !value)
        return false;
    if (![(O2PDFDictionary *)dict getDictionaryForKey:key value:&narrow])
        return false;
    *value = (CGPDFDictionaryRef)narrow;
    return true;
}

bool CGPDFDictionaryGetStream(CGPDFDictionaryRef dict, const char *key, CGPDFStreamRef *value)
{
    O2PDFStream *narrow = nil;
    if (!dict || !key || !value)
        return false;
    if (![(O2PDFDictionary *)dict getStreamForKey:key value:&narrow])
        return false;
    *value = (CGPDFStreamRef)narrow;
    return true;
}

void CGPDFDictionaryApplyFunction(CGPDFDictionaryRef dict, CGPDFDictionaryApplierFunction function, void *info)
{
    NSMapTable *table;
    NSMapEnumerator state;
    void *keyp = NULL;
    void *valuep = NULL;
    if (!dict || !function)
        return;
    table = (NSMapTable *)ivar_value((id)dict, [O2PDFDictionary class], "_table");
    if (!table)
        return;
    state = NSEnumerateMapTable(table);
    while (NSNextMapEnumeratorPair(&state, &keyp, &valuep)) {
        id value = (id)valuep;
        O2PDFObject *real = [value realObject];
        function((const char *)keyp, (CGPDFObjectRef)real, info);
    }
    NSEndMapTableEnumeration(&state);
}

size_t CGPDFStringGetLength(CGPDFStringRef string)
{
    return string ? O2PDFStringGetLength((O2PDFString *)string) : 0;
}

const unsigned char *CGPDFStringGetBytePtr(CGPDFStringRef string)
{
    return string ? O2PDFStringGetBytePtr((O2PDFString *)string) : NULL;
}

CFStringRef CGPDFStringCopyTextString(CGPDFStringRef string)
{
    return cf_text((O2PDFString *)string);
}

CFDataRef CGPDFStreamCopyData(CGPDFStreamRef stream, int *format)
{
    NSData *data;
    if (format)
        *format = 0;
    if (!stream)
        return NULL;
    data = [(O2PDFStream *)stream data];
    if (!data)
        return NULL;
    return CFDataCreate(NULL, [data bytes], (CFIndex)[data length]);
}
