#include <dlfcn.h>
/*
 * Clean PDF 1.5+ XRef/ObjStm, nested-parentheses literal string, and RFC 2083 PNG predictor
 * fixes for SiliconForest Onyx2D.framework (re-exports Onyx2D.sf-base with zero lost exports).
 */
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* O2PDFObjectType values matching Onyx2D/O2PDFObject.h */
enum {
    SF_O2TypeNull = 1,
    SF_O2TypeBoolean = 2,
    SF_O2TypeInteger = 3,
    SF_O2TypeReal = 4,
    SF_O2TypeName = 5,
    SF_O2TypeString = 6,
    SF_O2TypeArray = 7,
    SF_O2TypeDictionary = 8,
    SF_O2TypeStream = 9,
    SF_O2TypeR = 10,
    SF_O2TypeIdentifier = 11,
    SF_O2TypeMarkArrayOpen = 12,
    SF_O2TypeMarkDictOpen = 13,
    SF_O2TypeMarkArrayClose = 14,
    SF_O2TypeMarkDictClose = 15,
};

/* Exact O2PDFIdentifier values matching Onyx2D/O2PDFObject_identifier.h */
enum {
    SF_IdentUnknown = 0,
    SF_IdentTrue = 1,
    SF_IdentFalse = 2,
    SF_IdentNull = 3,
    SF_IdentF = 4,
    SF_IdentN = 5,
    SF_IdentR = 6,
    SF_IdentXRef = 7,
    SF_IdentTrailer = 8,
    SF_IdentStartXRef = 9,
    SF_IdentObj = 10,
    SF_IdentEndObj = 11,
    SF_IdentStream = 12,
    SF_IdentEndStream = 13,
};

typedef int SFInt;
typedef float SFReal;

/* ---- Helpers to construct Onyx2D PDF objects ---- */
static id sf_o2_null(void) {
    return ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("O2PDFObject_const"), @selector(pdfObjectWithNull));
}
static id sf_o2_bool(BOOL v) {
    return ((id (*)(id, SEL, BOOL))objc_msgSend)((id)objc_getClass("O2PDFObject_Boolean"), @selector(pdfObjectWithBoolean:), v);
}
static id sf_o2_int(SFInt v) {
    return ((id (*)(id, SEL, SFInt))objc_msgSend)((id)objc_getClass("O2PDFObject_Integer"), @selector(pdfObjectWithInteger:), v);
}
static id sf_o2_real(SFReal v) {
    return ((id (*)(id, SEL, SFReal))objc_msgSend)((id)objc_getClass("O2PDFObject_Real"), @selector(pdfObjectWithReal:), v);
}
static id sf_o2_name(const char *bytes, unsigned len) {
    return ((id (*)(id, SEL, const char *, unsigned))objc_msgSend)((id)objc_getClass("O2PDFObject_Name"), @selector(pdfObjectWithBytes:length:), bytes, len);
}
static id sf_o2_string(const void *bytes, unsigned len) {
    return ((id (*)(id, SEL, const void *, unsigned))objc_msgSend)((id)objc_getClass("O2PDFString"), @selector(pdfObjectWithBytes:length:), bytes, len);
}
static id sf_o2_array(void) {
    return ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("O2PDFArray"), @selector(pdfArray));
}
static id sf_o2_dict(void) {
    return ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("O2PDFDictionary"), @selector(pdfDictionary));
}
static id sf_o2_ref(SFInt num, SFInt gen, id xref) {
    return ((id (*)(id, SEL, SFInt, SFInt, id))objc_msgSend)((id)objc_getClass("O2PDFObject_R"), @selector(pdfObjectWithNumber:generation:xref:), num, gen, xref);
}
static id sf_o2_ident(int ident, const char *bytes, unsigned len) {
    return ((id (*)(id, SEL, int, const char *, unsigned))objc_msgSend)((id)objc_getClass("O2PDFObject_identifier"), @selector(pdfObjectWithIdentifier:name:length:), ident, bytes, len);
}
static id sf_o2_mark(SEL sel) {
    return ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("O2PDFObject_const"), sel);
}
static int sf_o2_type_noparse(id obj) {
    if ([obj respondsToSelector:@selector(objectTypeNoParsing)]) {
        return ((int (*)(id, SEL))objc_msgSend)(obj, @selector(objectTypeNoParsing));
    }
    return ((int (*)(id, SEL))objc_msgSend)(obj, @selector(objectType));
}

/* ---- Byte buffer for scanning escaped/hex strings ---- */
typedef struct {
    uint8_t *bytes;
    size_t len;
    size_t cap;
} SFBuf;

static void sf_buf_push(SFBuf *b, uint8_t c) {
    if (b->len >= b->cap) {
        size_t nc = b->cap ? b->cap * 2 : 128;
        b->bytes = (uint8_t *)realloc(b->bytes, nc);
        b->cap = nc;
    }
    b->bytes[b->len++] = c;
}
static void sf_buf_free(SFBuf *b) {
    free(b->bytes);
    b->bytes = NULL; b->len = b->cap = 0;
}

static inline BOOL sf_is_ws(uint8_t c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\0';
}
static inline BOOL sf_is_delim(uint8_t c) {
    return c == '(' || c == ')' || c == '<' || c == '>' || c == '[' || c == ']' ||
           c == '{' || c == '}' || c == '/' || c == '%';
}
static inline int sf_hex_val(uint8_t c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int sf_classify_ident(const char *p, size_t n) {
    if (n == 4 && memcmp(p, "true", 4) == 0) return SF_IdentTrue;
    if (n == 5 && memcmp(p, "false", 5) == 0) return SF_IdentFalse;
    if (n == 4 && memcmp(p, "null", 4) == 0) return SF_IdentNull;
    if (n == 1 && p[0] == 'R') return SF_IdentR;
    if (n == 9 && memcmp(p, "startxref", 9) == 0) return SF_IdentStartXRef;
    if (n == 4 && memcmp(p, "xref", 4) == 0) return SF_IdentXRef;
    if (n == 7 && memcmp(p, "trailer", 7) == 0) return SF_IdentTrailer;
    if (n == 1 && p[0] == 'f') return SF_IdentF;
    if (n == 1 && p[0] == 'n') return SF_IdentN;
    if (n == 3 && memcmp(p, "obj", 3) == 0) return SF_IdentObj;
    if (n == 6 && memcmp(p, "endobj", 6) == 0) return SF_IdentEndObj;
    if (n == 6 && memcmp(p, "stream", 6) == 0) return SF_IdentStream;
    if (n == 9 && memcmp(p, "endstream", 9) == 0) return SF_IdentEndStream;
    return SF_IdentUnknown;
}

/* Skip whitespace and % comments */
static size_t sf_skip_ws(const uint8_t *bytes, size_t len, size_t pos) {
    while (pos < len) {
        if (sf_is_ws(bytes[pos])) { pos++; continue; }
        if (bytes[pos] == '%') {
            while (pos < len && bytes[pos] != '\n' && bytes[pos] != '\r') pos++;
            continue;
        }
        break;
    }
    return pos;
}

/* ---- ISO 32000-1 compliant PDF token scanner (handles nested balanced parens, <> hex, #xx names, octal escapes) ---- */
static BOOL sf_scan_token(const uint8_t *bytes, size_t len, size_t pos, size_t *outPos, id *outObj) {
    *outObj = nil;
    pos = sf_skip_ws(bytes, len, pos);
    if (pos >= len) {
        *outPos = pos;
        return YES;
    }
    uint8_t c = bytes[pos];
    if (c == '[') {
        *outObj = sf_o2_mark(@selector(pdfObjectArrayMark));
        *outPos = pos + 1;
        return YES;
    }
    if (c == ']') {
        *outObj = sf_o2_mark(@selector(pdfObjectArrayMarkEnd));
        *outPos = pos + 1;
        return YES;
    }
    if (c == '<') {
        if (pos + 1 < len && bytes[pos + 1] == '<') {
            *outObj = sf_o2_mark(@selector(pdfObjectDictionaryMark));
            *outPos = pos + 2;
            return YES;
        }
        /* Hex string <...> (including empty <>) */
        pos++;
        SFBuf buf = {0};
        int hi = -1;
        while (pos < len) {
            uint8_t ch = bytes[pos++];
            if (ch == '>') {
                if (hi >= 0) sf_buf_push(&buf, (uint8_t)(hi << 4));
                *outObj = sf_o2_string(buf.bytes ? (const void *)buf.bytes : (const void *)"", (unsigned)buf.len);
                sf_buf_free(&buf);
                *outPos = pos;
                return YES;
            }
            if (sf_is_ws(ch)) continue;
            int v = sf_hex_val(ch);
            if (v < 0) { sf_buf_free(&buf); return NO; }
            if (hi < 0) hi = v;
            else { sf_buf_push(&buf, (uint8_t)((hi << 4) | v)); hi = -1; }
        }
        sf_buf_free(&buf);
        return NO;
    }
    if (c == '>') {
        if (pos + 1 < len && bytes[pos + 1] == '>') {
            *outObj = sf_o2_mark(@selector(pdfObjectDictionaryMarkEnd));
            *outPos = pos + 2;
            return YES;
        }
        return NO;
    }
    if (c == '(') {
        /* Literal string with balanced nested parentheses and full backslash escape support */
        pos++;
        SFBuf buf = {0};
        int depth = 0;
        while (pos < len) {
            uint8_t ch = bytes[pos++];
            if (ch == '\\') {
                if (pos >= len) break;
                uint8_t e = bytes[pos++];
                if (e == 'n') sf_buf_push(&buf, '\n');
                else if (e == 'r') sf_buf_push(&buf, '\r');
                else if (e == 't') sf_buf_push(&buf, '\t');
                else if (e == 'b') sf_buf_push(&buf, '\b');
                else if (e == 'f') sf_buf_push(&buf, '\f');
                else if (e == '(' || e == ')' || e == '\\') sf_buf_push(&buf, e);
                else if (e == '\r') {
                    if (pos < len && bytes[pos] == '\n') pos++;
                } else if (e == '\n') {
                    /* line continuation */
                } else if (e >= '0' && e <= '7') {
                    int val = e - '0';
                    if (pos < len && bytes[pos] >= '0' && bytes[pos] <= '7') {
                        val = (val << 3) | (bytes[pos++] - '0');
                        if (pos < len && bytes[pos] >= '0' && bytes[pos] <= '7') {
                            val = (val << 3) | (bytes[pos++] - '0');
                        }
                    }
                    sf_buf_push(&buf, (uint8_t)(val & 0xFF));
                } else {
                    /* Per PDF spec, unknown \x simply emits x */
                    sf_buf_push(&buf, e);
                }
            } else if (ch == '(') {
                depth++;
                sf_buf_push(&buf, '(');
            } else if (ch == ')') {
                if (depth == 0) {
                    *outObj = sf_o2_string(buf.bytes ? (const void *)buf.bytes : (const void *)"", (unsigned)buf.len);
                    sf_buf_free(&buf);
                    *outPos = pos;
                    return YES;
                }
                depth--;
                sf_buf_push(&buf, ')');
            } else if (ch == '\r') {
                if (pos < len && bytes[pos] == '\n') pos++;
                sf_buf_push(&buf, '\n');
            } else {
                sf_buf_push(&buf, ch);
            }
        }
        sf_buf_free(&buf);
        return NO;
    }
    if (c == '/') {
        /* Name object, decoding #XX hex escapes per PDF spec */
        pos++;
        SFBuf buf = {0};
        while (pos < len && !sf_is_ws(bytes[pos]) && !sf_is_delim(bytes[pos])) {
            uint8_t ch = bytes[pos++];
            if (ch == '#' && pos + 1 < len) {
                int h1 = sf_hex_val(bytes[pos]);
                int h2 = sf_hex_val(bytes[pos + 1]);
                if (h1 >= 0 && h2 >= 0) {
                    sf_buf_push(&buf, (uint8_t)((h1 << 4) | h2));
                    pos += 2;
                    continue;
                }
            }
            sf_buf_push(&buf, ch);
        }
        *outObj = sf_o2_name(buf.bytes ? (const char *)buf.bytes : "", (unsigned)buf.len);
        sf_buf_free(&buf);
        *outPos = pos;
        return YES;
    }
    /* Number or identifier */
    if ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.') {
        size_t start = pos;
        BOOL isReal = (c == '.');
        BOOL hasDigit = (c >= '0' && c <= '9');
        pos++;
        while (pos < len && !sf_is_ws(bytes[pos]) && !sf_is_delim(bytes[pos])) {
            uint8_t ch = bytes[pos];
            if (ch >= '0' && ch <= '9') { hasDigit = YES; pos++; }
            else if (ch == '.' && !isReal) { isReal = YES; pos++; }
            else break;
        }
        /* Only treat as number if followed by ws/delim/EOF and has at least one digit */
        if (hasDigit && (pos == len || sf_is_ws(bytes[pos]) || sf_is_delim(bytes[pos]))) {
            char tmp[128];
            size_t n = pos - start;
            if (n >= sizeof(tmp)) n = sizeof(tmp) - 1;
            memcpy(tmp, bytes + start, n);
            tmp[n] = '\0';
            if (isReal) *outObj = sf_o2_real((SFReal)strtod(tmp, NULL));
            else *outObj = sf_o2_int((SFInt)strtol(tmp, NULL, 10));
            *outPos = pos;
            return YES;
        }
        pos = start;
    }
    /* Identifier / operator */
    size_t start = pos;
    while (pos < len && !sf_is_ws(bytes[pos]) && !sf_is_delim(bytes[pos])) pos++;
    if (pos == start) return NO;
    size_t n = pos - start;
    int ident = sf_classify_ident((const char *)(bytes + start), n);
    if (ident == SF_IdentTrue) *outObj = sf_o2_bool(YES);
    else if (ident == SF_IdentFalse) *outObj = sf_o2_bool(NO);
    else if (ident == SF_IdentNull) *outObj = sf_o2_null();
    else *outObj = sf_o2_ident(ident, (const char *)(bytes + start), (unsigned)n);
    *outPos = pos;
    return YES;
}

/* ---- Parse complete PDF object (scalars, arrays, dictionaries, indirect refs) ---- */
static BOOL sf_parse_object(const uint8_t *bytes, size_t len, size_t pos, size_t *outPos, id *outObj, id xref) {
    NSMutableArray *stack = nil;
    while (YES) {
        id tok = nil;
        if (!sf_scan_token(bytes, len, pos, &pos, &tok)) return NO;
        if (tok == nil) {
            *outObj = nil;
            *outPos = pos;
            return (stack == nil);
        }
        int t = sf_o2_type_noparse(tok);
        if (t == SF_O2TypeNull || t == SF_O2TypeBoolean || t == SF_O2TypeInteger ||
            t == SF_O2TypeReal || t == SF_O2TypeName || t == SF_O2TypeString) {
            if (stack) {
                [stack addObject:tok];
            } else {
                /* Lookahead for indirect ref `N G R` when at top level? No, callers handle top-level R or inside containers */
                *outObj = tok;
                *outPos = pos;
                return YES;
            }
        } else if (t == SF_O2TypeMarkArrayOpen || t == SF_O2TypeMarkDictOpen) {
            if (!stack) stack = [NSMutableArray array];
            [stack addObject:tok];
        } else if (t == SF_O2TypeMarkArrayClose) {
            if (!stack) return NO;
            NSInteger count = (NSInteger)[stack count];
            NSInteger idx = count - 1;
            while (idx >= 0 && sf_o2_type_noparse([stack objectAtIndex:(NSUInteger)idx]) != SF_O2TypeMarkArrayOpen) idx--;
            if (idx < 0) return NO;
            id arr = sf_o2_array();
            for (NSInteger j = idx + 1; j < count; j++) {
                ((void (*)(id, SEL, id))objc_msgSend)(arr, @selector(addObject:), [stack objectAtIndex:(NSUInteger)j]);
            }
            [stack removeObjectsInRange:NSMakeRange((NSUInteger)idx, (NSUInteger)(count - idx))];
            [stack addObject:arr];
            if ([stack count] == 1) {
                *outObj = arr;
                *outPos = pos;
                return YES;
            }
        } else if (t == SF_O2TypeMarkDictClose) {
            if (!stack) return NO;
            id dict = sf_o2_dict();
            BOOL closed = NO;
            while ([stack count] > 0) {
                id val = [stack lastObject];
                if (sf_o2_type_noparse(val) == SF_O2TypeMarkDictOpen) {
                    [stack removeLastObject];
                    closed = YES;
                    break;
                }
                [[val retain] autorelease];
                [stack removeLastObject];
                if ([stack count] == 0) return NO;
                id kobj = [stack lastObject];
                const char *key = NULL;
                if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)(kobj, @selector(checkForType:value:), SF_O2TypeName, &key)) {
                    return NO;
                }
                ((void (*)(id, SEL, const char *, id))objc_msgSend)(dict, @selector(setObjectForKey:value:), key, val);
                [stack removeLastObject];
            }
            if (!closed) return NO;
            [stack addObject:dict];
            if ([stack count] == 1) {
                *outObj = dict;
                *outPos = pos;
                return YES;
            }
        } else if (t == SF_O2TypeIdentifier) {
            int ident = ((int (*)(id, SEL))objc_msgSend)(tok, @selector(identifier));
            if (ident == SF_IdentR && stack && [stack count] >= 2) {
                SFInt gen = 0, num = 0;
                if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)([stack lastObject], @selector(checkForType:value:), SF_O2TypeInteger, &gen)) return NO;
                [stack removeLastObject];
                if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)([stack lastObject], @selector(checkForType:value:), SF_O2TypeInteger, &num)) return NO;
                [stack removeLastObject];
                id ref = sf_o2_ref(num, gen, xref);
                [stack addObject:ref];
            } else {
                if (stack && [stack count] > 0) return NO;
                *outObj = tok;
                *outPos = pos;
                return YES;
            }
        } else {
            return NO;
        }
    }
}

/* ---- Construct O2PDFStream from parsed dictionary + file offset ---- */
static id sf_make_stream_from_bytes(id dict, id xref, const uint8_t *bytes, size_t fileLen, size_t streamStart) {
    /* Resolve /Length (may be direct integer OR indirect reference!) */
    SFInt slen = 0;
    if (!((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(dict, @selector(getIntegerForKey:value:), "Length", &slen)) {
        slen = 0;
    }
    if (slen < 0 || streamStart + (size_t)slen > fileLen) {
        /* Fallback: scan for endstream */
        const char *es = "endstream";
        size_t found = fileLen;
        for (size_t p = streamStart; p + 9 <= fileLen; p++) {
            if (memcmp(bytes + p, es, 9) == 0) { found = p; break; }
        }
        while (found > streamStart && (bytes[found - 1] == '\n' || bytes[found - 1] == '\r')) found--;
        slen = (SFInt)(found - streamStart);
    }
    NSData *sub = [NSData dataWithBytes:(bytes + streamStart) length:(NSUInteger)slen];
    /* Use initWithDictionary:data: and attach _xref ivar so [stream xref] is valid! */
    Class streamCls = objc_getClass("O2PDFStream");
    id st = [((id (*)(id, SEL, id, id))objc_msgSend)([streamCls alloc], @selector(initWithDictionary:data:), dict, sub) autorelease];
    if (st && xref) {
        Ivar iv = class_getInstanceVariable(streamCls, "_xref");
        if (iv) object_setIvar(st, iv, [xref retain]);
    }
    return st;
}

/* ---- Parse indirect object `N G obj <val> [stream ... endstream] endobj` ---- */
static BOOL sf_parse_indirect_object(NSData *data, size_t pos, id *outObj, SFInt expectedNum, SFInt expectedGen, id xref) {
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    size_t len = (size_t)[data length];
    id tNum = nil, tGen = nil, tObj = nil;
    if (!sf_scan_token(bytes, len, pos, &pos, &tNum)) return NO;
    SFInt num = 0, gen = 0;
    if (!tNum || !((BOOL (*)(id, SEL, int, void *))objc_msgSend)(tNum, @selector(checkForType:value:), SF_O2TypeInteger, &num)) return NO;
    if (expectedNum >= 0 && num != expectedNum) return NO;
    if (!sf_scan_token(bytes, len, pos, &pos, &tGen)) return NO;
    if (!tGen || !((BOOL (*)(id, SEL, int, void *))objc_msgSend)(tGen, @selector(checkForType:value:), SF_O2TypeInteger, &gen)) return NO;
    if (expectedGen >= 0 && gen != expectedGen) return NO;
    if (!sf_scan_token(bytes, len, pos, &pos, &tObj)) return NO;
    if (!tObj || sf_o2_type_noparse(tObj) != SF_O2TypeIdentifier ||
        ((int (*)(id, SEL))objc_msgSend)(tObj, @selector(identifier)) != SF_IdentObj) return NO;

    id obj = nil;
    if (!sf_parse_object(bytes, len, pos, &pos, &obj, xref)) return NO;
    if (!obj) return NO;

    id next = nil;
    size_t afterNext = pos;
    if (!sf_scan_token(bytes, len, pos, &afterNext, &next)) return NO;
    if (next && sf_o2_type_noparse(next) == SF_O2TypeIdentifier) {
        int id2 = ((int (*)(id, SEL))objc_msgSend)(next, @selector(identifier));
        if (id2 == SF_IdentStream) {
            /* Per ISO 32000-1 §7.3.8.1: stream keyword followed by CRLF or LF (not CR alone) */
            size_t sStart = afterNext;
            if (sStart < len && bytes[sStart] == '\r') sStart++;
            if (sStart < len && bytes[sStart] == '\n') sStart++;
            *outObj = sf_make_stream_from_bytes(obj, xref, bytes, len, sStart);
            return (*outObj != nil);
        }
        if (id2 == SF_IdentEndObj) {
            *outObj = obj;
            return YES;
        }
    }
    /* Handle indirect ref at top level of indirect object: `N G obj M 0 R endobj` */
    if (next && sf_o2_type_noparse(obj) == SF_O2TypeInteger && sf_o2_type_noparse(next) == SF_O2TypeInteger) {
        id rTok = nil;
        size_t afterR = afterNext;
        if (sf_scan_token(bytes, len, afterNext, &afterR, &rTok) && rTok &&
            sf_o2_type_noparse(rTok) == SF_O2TypeIdentifier &&
            ((int (*)(id, SEL))objc_msgSend)(rTok, @selector(identifier)) == SF_IdentR) {
            SFInt rn = 0, rg = 0;
            ((BOOL (*)(id, SEL, int, void *))objc_msgSend)(obj, @selector(checkForType:value:), SF_O2TypeInteger, &rn);
            ((BOOL (*)(id, SEL, int, void *))objc_msgSend)(next, @selector(checkForType:value:), SF_O2TypeInteger, &rg);
            *outObj = sf_o2_ref(rn, rg, xref);
            return YES;
        }
    }
    *outObj = obj;
    return YES;
}

/* ---- RFC 2083 / ISO 32000-1 PNG & TIFF Predictor Unfiltering ---- */
static inline uint8_t sf_paeth(int a, int b, int c) {
    int p = a + b - c;
    int pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
    if (pa <= pb && pa <= pc) return (uint8_t)a;
    if (pb <= pc) return (uint8_t)b;
    return (uint8_t)c;
}

static NSData *sf_unpredict(NSData *raw, id params) {
    if (!raw || !params) return raw;
    SFInt predictor = 1;
    if (!((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(params, @selector(getIntegerForKey:value:), "Predictor", &predictor)) {
        return raw;
    }
    if (predictor <= 1) return raw;
    SFInt colors = 1, bpc = 8, columns = 1;
    ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(params, @selector(getIntegerForKey:value:), "Colors", &colors);
    ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(params, @selector(getIntegerForKey:value:), "BitsPerComponent", &bpc);
    ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(params, @selector(getIntegerForKey:value:), "Columns", &columns);
    if (colors <= 0) colors = 1;
    if (bpc <= 0) bpc = 8;
    if (columns <= 0) columns = 1;

    size_t bpp = (size_t)((colors * bpc + 7) / 8);
    if (bpp < 1) bpp = 1;
    size_t bytesPerRow = (size_t)(((int64_t)colors * bpc * columns + 7) / 8);
    if (bytesPerRow == 0) return raw;

    const uint8_t *src = (const uint8_t *)[raw bytes];
    size_t srcLen = (size_t)[raw length];

    if (predictor == 2) {
        /* TIFF horizontal differencing (8-bit common case) */
        NSMutableData *out = [NSMutableData dataWithLength:srcLen];
        uint8_t *dst = (uint8_t *)[out mutableBytes];
        memcpy(dst, src, srcLen);
        if (bpc == 8) {
            size_t rows = srcLen / bytesPerRow;
            for (size_t r = 0; r < rows; r++) {
                uint8_t *row = dst + r * bytesPerRow;
                for (size_t i = bpp; i < bytesPerRow; i++) {
                    row[i] = (uint8_t)((row[i] + row[i - bpp]) & 0xFF);
                }
            }
        }
        return out;
    }

    if (predictor >= 10 && predictor <= 15) {
        size_t stride = bytesPerRow + 1;
        size_t rows = srcLen / stride;
        NSMutableData *out = [NSMutableData dataWithLength:rows * bytesPerRow];
        uint8_t *dst = (uint8_t *)[out mutableBytes];
        uint8_t *prev = (uint8_t *)calloc(bytesPerRow, 1);
        if (!prev) return raw;
        for (size_t r = 0; r < rows; r++) {
            const uint8_t *inRow = src + r * stride;
            uint8_t filter = inRow[0];
            const uint8_t *inData = inRow + 1;
            uint8_t *cur = dst + r * bytesPerRow;
            for (size_t i = 0; i < bytesPerRow; i++) {
                uint8_t x = inData[i];
                uint8_t left = (i >= bpp) ? cur[i - bpp] : 0;
                uint8_t up = prev[i];
                uint8_t upLeft = (i >= bpp) ? prev[i - bpp] : 0;
                switch (filter) {
                    case 0: cur[i] = x; break;
                    case 1: cur[i] = (uint8_t)((x + left) & 0xFF); break;
                    case 2: cur[i] = (uint8_t)((x + up) & 0xFF); break;
                    case 3: cur[i] = (uint8_t)((x + (((int)left + (int)up) >> 1)) & 0xFF); break;
                    case 4: cur[i] = (uint8_t)((x + sf_paeth(left, up, upLeft)) & 0xFF); break;
                    default: cur[i] = x; break;
                }
            }
            memcpy(prev, cur, bytesPerRow);
        }
        free(prev);
        return out;
    }
    return raw;
}

static NSData *sf_ascii_hex_decode(NSData *data) {
    const uint8_t *s = (const uint8_t *)[data bytes];
    size_t n = (size_t)[data length];
    NSMutableData *out = [NSMutableData dataWithCapacity:n / 2];
    int hi = -1;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == '>') break;
        if (sf_is_ws(s[i])) continue;
        int v = sf_hex_val(s[i]);
        if (v < 0) break;
        if (hi < 0) hi = v;
        else { uint8_t b = (uint8_t)((hi << 4) | v); [out appendBytes:&b length:1]; hi = -1; }
    }
    if (hi >= 0) { uint8_t b = (uint8_t)(hi << 4); [out appendBytes:&b length:1]; }
    return out;
}

static NSData *sf_ascii85_decode(NSData *data) {
    const uint8_t *s = (const uint8_t *)[data bytes];
    size_t n = (size_t)[data length];
    NSMutableData *out = [NSMutableData dataWithCapacity:n];
    uint32_t tuple = 0;
    int count = 0;
    for (size_t i = 0; i < n; i++) {
        uint8_t c = s[i];
        if (c == '~') break;
        if (sf_is_ws(c)) continue;
        if (c == 'z' && count == 0) {
            uint8_t zeros[4] = {0, 0, 0, 0};
            [out appendBytes:zeros length:4];
            continue;
        }
        if (c < '!' || c > 'u') continue;
        tuple = tuple * 85u + (uint32_t)(c - '!');
        count++;
        if (count == 5) {
            uint8_t b[4] = { (uint8_t)(tuple >> 24), (uint8_t)(tuple >> 16), (uint8_t)(tuple >> 8), (uint8_t)tuple };
            [out appendBytes:b length:4];
            tuple = 0; count = 0;
        }
    }
    if (count > 1) {
        for (int k = count; k < 5; k++) tuple = tuple * 85u + 84u;
        uint8_t b[4] = { (uint8_t)(tuple >> 24), (uint8_t)(tuple >> 16), (uint8_t)(tuple >> 8), (uint8_t)tuple };
        [out appendBytes:b length:(NSUInteger)(count - 1)];
    }
    return out;
}

/* ---- Swizzled +[O2PDFFilter decodeWithName:data:parameters:] ---- */
static id (*g_orig_filter_decode)(id, SEL, const char *, id, id) = NULL;
static id sf_o2filter_decode(id self, SEL _cmd, const char *name, NSData *data, id params) {
    if (!name || !data) return nil;
    if (strcmp(name, "FlateDecode") == 0 || strcmp(name, "FL") == 0) {
        NSData *inflated = ((id (*)(id, SEL, id, id))objc_msgSend)(self, @selector(FlateDecode_data:parameters:), data, nil);
        if (!inflated) return nil;
        return sf_unpredict(inflated, params);
    }
    if (strcmp(name, "LZWDecode") == 0 || strcmp(name, "LZW") == 0) {
        NSData *dec = ((id (*)(id, SEL, id, id))objc_msgSend)(self, @selector(LZWDecode_data:parameters:), data, nil);
        if (!dec) return nil;
        return sf_unpredict(dec, params);
    }
    if (strcmp(name, "ASCIIHexDecode") == 0 || strcmp(name, "AHx") == 0) {
        return sf_ascii_hex_decode(data);
    }
    if (strcmp(name, "ASCII85Decode") == 0 || strcmp(name, "A85") == 0) {
        return sf_ascii85_decode(data);
    }
    return g_orig_filter_decode ? g_orig_filter_decode(self, _cmd, name, data, params) : nil;
}

/* ---- Swizzled +[O2Image imageWithPDFObject:] (fixes Cocotron 24-bpp RGB888 & 32-bpp DCTDecode stride) ---- */
static id (*g_orig_image_with_pdf)(id, SEL, id) = NULL;
static id sf_o2image_with_pdf(id self, SEL _cmd, id object) {
    if (!object || ![object respondsToSelector:@selector(dictionary)]) {
        return g_orig_image_with_pdf ? g_orig_image_with_pdf(self, _cmd, object) : nil;
    }
    id dict = ((id (*)(id, SEL))objc_msgSend)(object, @selector(dictionary));
    if (!dict) return g_orig_image_with_pdf ? g_orig_image_with_pdf(self, _cmd, object) : nil;
    SFInt width = 0, height = 0, bpc = 0;
    BOOL isMask = NO;
    ((BOOL (*)(id, SEL, const char *, BOOL *))objc_msgSend)(dict, @selector(getBooleanForKey:value:), "ImageMask", &isMask);
    id decodeArr = nil;
    BOOL hasDecode = ((BOOL (*)(id, SEL, const char *, id *))objc_msgSend)(dict, @selector(getArrayForKey:value:), "Decode", &decodeArr) && decodeArr;
    if (!isMask && !hasDecode &&
        ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(dict, @selector(getIntegerForKey:value:), "Width", &width) &&
        ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(dict, @selector(getIntegerForKey:value:), "Height", &height) &&
        ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(dict, @selector(getIntegerForKey:value:), "BitsPerComponent", &bpc) &&
        width > 0 && height > 0 && bpc == 8) {
        id csObj = nil;
        if (((BOOL (*)(id, SEL, const char *, id *))objc_msgSend)(dict, @selector(getObjectForKey:value:), "ColorSpace", &csObj) && csObj) {
            Class csCls = objc_lookUpClass("O2ColorSpace");
            id cs = csCls ? ((id (*)(id, SEL, id))objc_msgSend)((id)csCls, @selector(createColorSpaceFromPDFObject:), csObj) : nil;
            typedef size_t (*fn_cs_nc_t)(id);
            typedef id (*fn_dp_data_t)(CFDataRef);
            typedef void (*fn_rel_t)(id);
            typedef int (*fn_ri_t)(const char *);
            typedef id (*fn_img_create_t)(size_t, size_t, size_t, size_t, size_t, id, unsigned, id, const float *, BOOL, int);
            static fn_cs_nc_t f_csNC;
            static fn_dp_data_t f_dpData;
            static fn_rel_t f_dpRel, f_csRel;
            static fn_ri_t f_ri;
            static fn_img_create_t f_imgCreate;
            if (!f_csNC) {
                f_csNC = (fn_cs_nc_t)dlsym(RTLD_DEFAULT, "O2ColorSpaceGetNumberOfComponents");
                f_dpData = (fn_dp_data_t)dlsym(RTLD_DEFAULT, "O2DataProviderCreateWithCFData");
                f_dpRel = (fn_rel_t)dlsym(RTLD_DEFAULT, "O2DataProviderRelease");
                f_csRel = (fn_rel_t)dlsym(RTLD_DEFAULT, "O2ColorSpaceRelease");
                f_ri = (fn_ri_t)dlsym(RTLD_DEFAULT, "O2ImageRenderingIntentWithName");
                f_imgCreate = (fn_img_create_t)dlsym(RTLD_DEFAULT, "O2ImageCreate");
            }
            if (cs && f_csNC && f_dpData && f_dpRel && f_csRel && f_imgCreate && f_csNC(cs) == 3) {
                NSData *raw = ((id (*)(id, SEL))objc_msgSend)(object, @selector(data));
                size_t npix = (size_t)width * (size_t)height;
                NSData *rgbx = nil;
                if (raw && [raw length] == npix * 3) {
                    /* Expand 24-bpp RGB888 -> 32-bpp RGBX8888 so O2Image's 32-bpp reader never drifts */
                    NSMutableData *buf = [NSMutableData dataWithLength:npix * 4];
                    const uint8_t *s = (const uint8_t *)[raw bytes];
                    uint8_t *d = (uint8_t *)[buf mutableBytes];
                    for (size_t i = 0; i < npix; i++) {
                        d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; d[3] = 0xFF;
                        s += 3; d += 4;
                    }
                    rgbx = buf;
                } else if (raw && [raw length] == npix * 4) {
                    /* Already 32-bpp RGBA from O2DCTDecode */
                    rgbx = raw;
                }
                if (rgbx) {
                    BOOL interp = NO;
                    ((BOOL (*)(id, SEL, const char *, BOOL *))objc_msgSend)(dict, @selector(getBooleanForKey:value:), "Interpolate", &interp);
                    const char *intent = NULL;
                    ((BOOL (*)(id, SEL, const char *, const char **))objc_msgSend)(dict, @selector(getNameForKey:value:), "Intent", &intent);
                    id softMaskStream = nil;
                    id softMask = nil;
                    if (((BOOL (*)(id, SEL, const char *, id *))objc_msgSend)(dict, @selector(getStreamForKey:value:), "SMask", &softMaskStream) && softMaskStream) {
                        softMask = sf_o2image_with_pdf(self, _cmd, softMaskStream);
                    }
                    id prov = f_dpData((CFDataRef)rgbx);
                    unsigned binfo = 0x4000u | 5u; /* kO2BitmapByteOrder32Big | kO2ImageAlphaNoneSkipLast */
                    int ri = f_ri ? f_ri(intent) : 0;
                    id img = f_imgCreate((size_t)width, (size_t)height, 8, 32, (size_t)width * 4, cs, binfo, prov, NULL, interp, ri);
                    if (softMask && img) ((void (*)(id, SEL, id))objc_msgSend)(img, @selector(setMask:), softMask);
                    f_dpRel(prov);
                    f_csRel(cs);
                    return img;
                }
            }
            if (cs && f_csRel) f_csRel(cs);
        }
    }
    return g_orig_image_with_pdf ? g_orig_image_with_pdf(self, _cmd, object) : nil;
}

/* ---- Parse PDF 1.4 ASCII xref OR PDF 1.5+ binary /Type /XRef stream ---- */
static uint64_t sf_read_be(const uint8_t *p, int w) {
    uint64_t v = 0;
    for (int i = 0; i < w; i++) v = (v << 8) | p[i];
    return v;
}

static BOOL sf_parse_xref_at(NSData *data, size_t pos, id *outXref) {
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    size_t len = (size_t)[data length];
    id firstTok = nil;
    size_t afterFirst = pos;
    if (!sf_scan_token(bytes, len, pos, &afterFirst, &firstTok) || !firstTok) return NO;

    Class xrefCls = objc_getClass("O2PDFxref");
    Class entryCls = objc_getClass("O2PDFxrefEntry");
    id table = [((id (*)(id, SEL, id))objc_msgSend)([xrefCls alloc], @selector(initWithData:), data) autorelease];
    *outXref = table;

    /* Case A: Classic ASCII xref table (`xref ... trailer << ... >>`) */
    if (sf_o2_type_noparse(firstTok) == SF_O2TypeIdentifier &&
        ((int (*)(id, SEL))objc_msgSend)(firstTok, @selector(identifier)) == SF_IdentXRef) {
        size_t cur = afterFirst;
        while (YES) {
            id tok = nil;
            if (!sf_scan_token(bytes, len, cur, &cur, &tok) || !tok) return NO;
            if (sf_o2_type_noparse(tok) == SF_O2TypeIdentifier &&
                ((int (*)(id, SEL))objc_msgSend)(tok, @selector(identifier)) == SF_IdentTrailer) {
                id trailer = nil;
                if (!sf_parse_object(bytes, len, cur, &cur, &trailer, table)) return NO;
                if (!trailer || sf_o2_type_noparse(trailer) != SF_O2TypeDictionary) return NO;
                ((void (*)(id, SEL, id))objc_msgSend)(table, @selector(setTrailer:), trailer);
                /* Hybrid PDF 1.5 file: optional /XRefStm pointing to additional compressed objects */
                SFInt xrefStmPos = 0;
                if (((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(trailer, @selector(getIntegerForKey:value:), "XRefStm", &xrefStmPos) && xrefStmPos > 0) {
                    id subTable = nil;
                    if (sf_parse_xref_at(data, (size_t)xrefStmPos, &subTable) && subTable) {
                        ((void (*)(id, SEL, id))objc_msgSend)(table, @selector(setPreviousTable:), subTable);
                    }
                }
                return YES;
            }
            SFInt startNum = 0, count = 0;
            if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)(tok, @selector(checkForType:value:), SF_O2TypeInteger, &startNum)) return NO;
            id cTok = nil;
            if (!sf_scan_token(bytes, len, cur, &cur, &cTok) || !cTok) return NO;
            if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)(cTok, @selector(checkForType:value:), SF_O2TypeInteger, &count)) return NO;
            for (SFInt i = 0; i < count; i++) {
                id f1 = nil, f2 = nil, f3 = nil;
                SFInt offset = 0, gen = 0;
                if (!sf_scan_token(bytes, len, cur, &cur, &f1) || !f1) return NO;
                if (!sf_scan_token(bytes, len, cur, &cur, &f2) || !f2) return NO;
                if (!sf_scan_token(bytes, len, cur, &cur, &f3) || !f3) return NO;
                if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)(f1, @selector(checkForType:value:), SF_O2TypeInteger, &offset)) return NO;
                if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)(f2, @selector(checkForType:value:), SF_O2TypeInteger, &gen)) return NO;
                if (sf_o2_type_noparse(f3) == SF_O2TypeIdentifier &&
                    ((int (*)(id, SEL))objc_msgSend)(f3, @selector(identifier)) == SF_IdentN) {
                    id e = ((id (*)(id, SEL, SFInt, SFInt, SFInt))objc_msgSend)((id)entryCls, @selector(xrefEntryWithPosition:number:generation:), offset, startNum + i, gen);
                    ((void (*)(id, SEL, id))objc_msgSend)(table, @selector(addEntry:), e);
                }
            }
        }
    }

    /* Case B: PDF 1.5+ Cross-Reference Stream (`N G obj << /Type /XRef ... >> stream ... endstream`) */
    if (sf_o2_type_noparse(firstTok) == SF_O2TypeInteger) {
        id st = nil;
        if (!sf_parse_indirect_object(data, pos, &st, -1, -1, table) || !st) return NO;
        if (sf_o2_type_noparse(st) != SF_O2TypeStream) return NO;
        id dict = ((id (*)(id, SEL))objc_msgSend)(st, @selector(dictionary));
        if (!dict) return NO;
        const char *typeName = NULL;
        if (!((BOOL (*)(id, SEL, const char *, const char **))objc_msgSend)(dict, @selector(getNameForKey:value:), "Type", &typeName) ||
            !typeName || strcmp(typeName, "XRef") != 0) {
            return NO;
        }
        SFInt sizeVal = 0;
        ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(dict, @selector(getIntegerForKey:value:), "Size", &sizeVal);
        id wArr = nil;
        if (!((BOOL (*)(id, SEL, const char *, id *))objc_msgSend)(dict, @selector(getArrayForKey:value:), "W", &wArr) || !wArr) return NO;
        SFInt w0 = 0, w1 = 0, w2 = 0;
        ((BOOL (*)(id, SEL, unsigned, SFInt *))objc_msgSend)(wArr, @selector(getIntegerAtIndex:value:), 0, &w0);
        ((BOOL (*)(id, SEL, unsigned, SFInt *))objc_msgSend)(wArr, @selector(getIntegerAtIndex:value:), 1, &w1);
        ((BOOL (*)(id, SEL, unsigned, SFInt *))objc_msgSend)(wArr, @selector(getIntegerAtIndex:value:), 2, &w2);
        int stride = w0 + w1 + w2;
        if (stride <= 0) return NO;

        NSData *raw = ((id (*)(id, SEL))objc_msgSend)(st, @selector(data));
        if (!raw) return NO;
        const uint8_t *rb = (const uint8_t *)[raw bytes];
        size_t rlen = (size_t)[raw length];

        /* Build /Index pairs (default: [0, Size]) */
        id idxArr = nil;
        NSUInteger nPairs = 1;
        SFInt defaultPairs[2] = { 0, sizeVal };
        BOOL hasIdx = ((BOOL (*)(id, SEL, const char *, id *))objc_msgSend)(dict, @selector(getArrayForKey:value:), "Index", &idxArr) && idxArr;
        if (hasIdx) {
            unsigned cnt = ((unsigned (*)(id, SEL))objc_msgSend)(idxArr, @selector(count));
            nPairs = cnt / 2;
        }

        size_t roff = 0;
        for (NSUInteger p = 0; p < nPairs; p++) {
            SFInt firstObj = defaultPairs[0], objCount = defaultPairs[1];
            if (hasIdx) {
                ((BOOL (*)(id, SEL, unsigned, SFInt *))objc_msgSend)(idxArr, @selector(getIntegerAtIndex:value:), (unsigned)(p * 2), &firstObj);
                ((BOOL (*)(id, SEL, unsigned, SFInt *))objc_msgSend)(idxArr, @selector(getIntegerAtIndex:value:), (unsigned)(p * 2 + 1), &objCount);
            }
            for (SFInt i = 0; i < objCount; i++) {
                if (roff + (size_t)stride > rlen) break;
                uint64_t f0 = (w0 > 0) ? sf_read_be(rb + roff, w0) : 1;
                uint64_t f1 = (w1 > 0) ? sf_read_be(rb + roff + w0, w1) : 0;
                uint64_t f2 = (w2 > 0) ? sf_read_be(rb + roff + w0 + w1, w2) : 0;
                roff += (size_t)stride;
                SFInt objNum = firstObj + i;
                if (f0 == 1) {
                    id e = ((id (*)(id, SEL, SFInt, SFInt, SFInt))objc_msgSend)((id)entryCls, @selector(xrefEntryWithPosition:number:generation:), (SFInt)f1, objNum, (SFInt)f2);
                    ((void (*)(id, SEL, id))objc_msgSend)(table, @selector(addEntry:), e);
                } else if (f0 == 2) {
                    /* Type 2 compressed object: sentinel negative position = -(streamNumber + 1), generation = indexInStream */
                    SFInt sentinel = -((SFInt)f1 + 1);
                    id e = ((id (*)(id, SEL, SFInt, SFInt, SFInt))objc_msgSend)((id)entryCls, @selector(xrefEntryWithPosition:number:generation:), sentinel, objNum, (SFInt)f2);
                    ((void (*)(id, SEL, id))objc_msgSend)(table, @selector(addEntry:), e);
                }
            }
        }
        ((void (*)(id, SEL, id))objc_msgSend)(table, @selector(setTrailer:), dict);
        return YES;
    }

    return NO;
}

static BOOL sf_parse_xref(NSData *data, id *outXref) {
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    size_t len = (size_t)[data length];
    if (len < 16) return NO;
    /* Search backwards within the last 4096 bytes for "startxref" */
    size_t searchStart = (len > 4096) ? (len - 4096) : 0;
    ssize_t found = -1;
    for (ssize_t p = (ssize_t)len - 9; p >= (ssize_t)searchStart; p--) {
        if (memcmp(bytes + p, "startxref", 9) == 0) { found = p; break; }
    }
    if (found < 0) return NO;
    size_t cur = (size_t)found + 9;
    id posTok = nil;
    if (!sf_scan_token(bytes, len, cur, &cur, &posTok) || !posTok) return NO;
    SFInt xrefPos = 0;
    if (!((BOOL (*)(id, SEL, int, void *))objc_msgSend)(posTok, @selector(checkForType:value:), SF_O2TypeInteger, &xrefPos)) return NO;

    id headTable = nil, lastTable = nil;
    int depth = 0;
    while (xrefPos >= 0 && (size_t)xrefPos < len && depth++ < 64) {
        id table = nil;
        if (!sf_parse_xref_at(data, (size_t)xrefPos, &table) || !table) return NO;
        if (!headTable) headTable = table;
        else ((void (*)(id, SEL, id))objc_msgSend)(lastTable, @selector(setPreviousTable:), table);
        /* Advance to the tail of any hybrid XRefStm chain */
        lastTable = table;
        while (((id (*)(id, SEL))objc_msgSend)(lastTable, @selector(previous)) != nil) {
            lastTable = ((id (*)(id, SEL))objc_msgSend)(lastTable, @selector(previous));
        }
        id trailer = ((id (*)(id, SEL))objc_msgSend)(table, @selector(trailer));
        SFInt prevPos = -1;
        if (!trailer || !((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(trailer, @selector(getIntegerForKey:value:), "Prev", &prevPos)) {
            break;
        }
        xrefPos = prevPos;
    }
    *outXref = headTable;
    return (headTable != nil);
}

/* ---- Swizzled -[O2PDFDocument initWithData:] ---- */
static id sf_o2doc_initWithData(id self, SEL _cmd, NSData *data) {
    (void)_cmd;
    if (!data || [data length] < 8) { [self release]; return nil; }
    const char *b = (const char *)[data bytes];
    size_t len = (size_t)[data length];
    /* Scan %PDF-X.Y header within first 1024 bytes */
    size_t hdr = 0;
    BOOL foundHdr = NO;
    size_t lim = len < 1024 ? len : 1024;
    for (size_t i = 0; i + 8 <= lim; i++) {
        if (memcmp(b + i, "%PDF-", 5) == 0) { hdr = i; foundHdr = YES; break; }
    }
    if (!foundHdr) { [self release]; return nil; }
    size_t eol = hdr + 5;
    while (eol < lim && b[eol] != '\r' && b[eol] != '\n') eol++;
    id ver = sf_o2_string(b + hdr + 5, (unsigned)(eol - (hdr + 5)));
    id xref = nil;
    if (!sf_parse_xref(data, &xref) || !xref) {
        [self release];
        return nil;
    }
    Class cls = objc_getClass("O2PDFDocument");
    Ivar ivVer = class_getInstanceVariable(cls, "_version");
    Ivar ivXref = class_getInstanceVariable(cls, "_xref");
    if (ivVer) object_setIvar(self, ivVer, [ver retain]);
    if (ivXref) object_setIvar(self, ivXref, [xref retain]);
    return self;
}

/* ---- Swizzled -[O2PDFxref objectAtNumber:generation:] (handles Type 1 + Type 2 ObjStm + retains cache) ---- */
static char kSFObjCacheKey, kSFObjStmCacheKey;

static NSMutableDictionary *sf_xref_cache(id xref, const void *key) {
    NSMutableDictionary *d = objc_getAssociatedObject(xref, key);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(xref, key, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}

static id sf_o2xref_objectAtNumber(id self, SEL _cmd, SFInt number, SFInt generation) {
    (void)_cmd;
    /* Check strongly-retained per-xref cache first */
    NSMutableDictionary *cache = sf_xref_cache(self, &kSFObjCacheKey);
    NSNumber *ckey = [NSNumber numberWithLongLong:(((int64_t)number << 16) | (generation & 0xFFFF))];
    id cached = [cache objectForKey:ckey];
    if (cached) return cached;

    /* Look up entry (note: for Type 2 compressed entries, generation in PDF spec is always 0, while entry->generation holds indexInStream!) */
    id entry = ((id (*)(id, SEL, SFInt, SFInt))objc_msgSend)(self, @selector(entryWithNumber:generation:), number, generation);
    if (!entry && generation == 0) {
        /* Try walking _numberToEntries if generation != indexInStream for compressed entry */
        id cur = self;
        while (cur && !entry) {
            Ivar iv = class_getInstanceVariable(objc_getClass("O2PDFxref"), "_numberToEntries");
            if (iv) {
                ptrdiff_t off = ivar_getOffset(iv);
                NSMapTable *mt = *(NSMapTable **)((uint8_t *)cur + off);
                if (mt) {
                    id check = (id)NSMapGet(mt, (void *)(intptr_t)number);
                    if ([check isKindOfClass:[NSArray class]]) {
                        for (id e in (NSArray *)check) {
                            if (((SFInt (*)(id, SEL))objc_msgSend)(e, @selector(position)) < 0) { entry = e; break; }
                        }
                    } else if (check && ((SFInt (*)(id, SEL))objc_msgSend)(check, @selector(position)) < 0) {
                        entry = check;
                    }
                }
            }
            cur = ((id (*)(id, SEL))objc_msgSend)(cur, @selector(previous));
        }
    }
    if (!entry) return sf_o2_null();

    SFInt pos = ((SFInt (*)(id, SEL))objc_msgSend)(entry, @selector(position));
    id result = nil;
    if (pos >= 0) {
        NSData *data = ((id (*)(id, SEL))objc_msgSend)(self, @selector(data));
        if (!sf_parse_indirect_object(data, (size_t)pos, &result, number, generation, self)) {
            result = sf_o2_null();
        }
    } else {
        /* Type 2 compressed object inside ObjStm #( -pos - 1 ) at index (entry.generation) */
        SFInt stmNum = -pos - 1;
        SFInt targetIdx = ((SFInt (*)(id, SEL))objc_msgSend)(entry, @selector(generation));
        NSMutableDictionary *stmCache = sf_xref_cache(self, &kSFObjStmCacheKey);
        NSNumber *skey = [NSNumber numberWithInt:stmNum];
        NSDictionary *parsedStm = [stmCache objectForKey:skey];
        if (!parsedStm) {
            id objStm = sf_o2xref_objectAtNumber(self, _cmd, stmNum, 0);
            if (objStm && sf_o2_type_noparse(objStm) == SF_O2TypeStream) {
                id sdict = ((id (*)(id, SEL))objc_msgSend)(objStm, @selector(dictionary));
                SFInt nObjs = 0, firstOff = 0;
                ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(sdict, @selector(getIntegerForKey:value:), "N", &nObjs);
                ((BOOL (*)(id, SEL, const char *, SFInt *))objc_msgSend)(sdict, @selector(getIntegerForKey:value:), "First", &firstOff);
                NSData *sdata = ((id (*)(id, SEL))objc_msgSend)(objStm, @selector(data));
                if (sdata && nObjs > 0 && firstOff >= 0) {
                    const uint8_t *sb = (const uint8_t *)[sdata bytes];
                    size_t slen = (size_t)[sdata length];
                    NSMutableArray *offsets = [NSMutableArray arrayWithCapacity:(NSUInteger)nObjs];
                    size_t hpos = 0;
                    for (SFInt k = 0; k < nObjs; k++) {
                        id oNumT = nil, oOffT = nil;
                        SFInt on = 0, oo = 0;
                        if (!sf_scan_token(sb, slen, hpos, &hpos, &oNumT) || !oNumT) break;
                        if (!sf_scan_token(sb, slen, hpos, &hpos, &oOffT) || !oOffT) break;
                        ((BOOL (*)(id, SEL, int, void *))objc_msgSend)(oNumT, @selector(checkForType:value:), SF_O2TypeInteger, &on);
                        ((BOOL (*)(id, SEL, int, void *))objc_msgSend)(oOffT, @selector(checkForType:value:), SF_O2TypeInteger, &oo);
                        [offsets addObject:[NSNumber numberWithInt:oo]];
                    }
                    parsedStm = @{ @"data": sdata, @"first": @(firstOff), @"offsets": offsets };
                    [stmCache setObject:parsedStm forKey:skey];
                }
            }
        }
        if (parsedStm) {
            NSData *sdata = [parsedStm objectForKey:@"data"];
            SFInt firstOff = [[parsedStm objectForKey:@"first"] intValue];
            NSArray *offsets = [parsedStm objectForKey:@"offsets"];
            if (targetIdx >= 0 && (NSUInteger)targetIdx < [offsets count]) {
                SFInt relOff = [[offsets objectAtIndex:(NSUInteger)targetIdx] intValue];
                size_t absOff = (size_t)(firstOff + relOff);
                const uint8_t *sb = (const uint8_t *)[sdata bytes];
                size_t slen = (size_t)[sdata length];
                size_t endP = absOff;
                if (absOff < slen) {
                    sf_parse_object(sb, slen, absOff, &endP, &result, self);
                }
            }
        }
        if (!result) result = sf_o2_null();
    }
    if (!result) result = sf_o2_null();
    [cache setObject:result forKey:ckey];
    return result;
}

/* ---- Swizzled -[O2PDFScanner scanStream:] using our balanced-parens token scanner ---- */
static BOOL sf_o2scanner_scanStream(id self, SEL _cmd, id stream) {
    (void)_cmd;
    if (!stream) return YES;
    id xref = ((id (*)(id, SEL))objc_msgSend)(stream, @selector(xref));
    NSData *data = ((id (*)(id, SEL))objc_msgSend)(stream, @selector(data));
    if (!data) return YES;
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    size_t len = (size_t)[data length];

    Class scCls = objc_getClass("O2PDFScanner");
    Ivar ivStack = class_getInstanceVariable(scCls, "_stack");
    Ivar ivOpTab = class_getInstanceVariable(scCls, "_operatorTable");
    Ivar ivInfo = class_getInstanceVariable(scCls, "_info");
    Ivar ivPos = class_getInstanceVariable(scCls, "_position");
    NSMutableArray *stack = ivStack ? object_getIvar(self, ivStack) : nil;
    id opTab = ivOpTab ? object_getIvar(self, ivOpTab) : nil;
    void *info = ivInfo ? *(void **)((uint8_t *)self + ivar_getOffset(ivInfo)) : NULL;
    SFInt *posPtr = ivPos ? (SFInt *)((uint8_t *)self + ivar_getOffset(ivPos)) : NULL;

    size_t pos = 0;
    while (pos < len) {
        id obj = nil;
        if (!sf_parse_object(bytes, len, pos, &pos, &obj, xref)) {
            /* Skip any unexpected byte and continue scanning rather than dropping the rest of the page */
            if (pos < len) { pos++; continue; }
            break;
        }
        if (posPtr) *posPtr = (SFInt)pos;
        if (!obj) return YES;
        if (sf_o2_type_noparse(obj) != SF_O2TypeIdentifier) {
            [stack addObject:obj];
        } else {
            const char *opName = ((const char *(*)(id, SEL))objc_msgSend)(obj, @selector(name));
            if (opName && strcmp(opName, "BI") == 0) {
                /* Skip inline image cleanly until EI */
                while (pos + 2 < len) {
                    if (sf_is_ws(bytes[pos]) && bytes[pos + 1] == 'E' && bytes[pos + 2] == 'I' &&
                        (pos + 3 == len || sf_is_ws(bytes[pos + 3]))) {
                        pos += 3;
                        break;
                    }
                    pos++;
                }
                continue;
            }
            if (opName && opTab) {
                typedef void (*O2OpCb)(id, void *);
                O2OpCb cb = ((O2OpCb (*)(id, SEL, const char *))objc_msgSend)(opTab, @selector(callbackForName:), opName);
                static O2OpCb s_origTj, s_origTJ, s_origQuote;
                static int s_cbInit = 0;
                if (!s_cbInit) {
                    s_cbInit = 1;
                    s_origTj = (O2OpCb)dlsym(RTLD_DEFAULT, "O2PDF_render_Tj");
                    s_origTJ = (O2OpCb)dlsym(RTLD_DEFAULT, "O2PDF_render_TJ");
                    s_origQuote = (O2OpCb)dlsym(RTLD_DEFAULT, "O2PDF_render_quote");
                }
                if (cb && info && (cb == s_origTj || cb == s_origTJ || cb == s_origQuote)) {
                /* Properly scale PDF /Widths glyph advances and TJ kerning adjustments by fontSize * (hScale / 100)
                 * Exact Onyx2D ARM64 ABI: O2Float = float, O2AffineTransform = 6x float, O2Size = NSSize (2x double). */
                typedef struct { float a, b, c, d, tx, ty; } SF_O2AT;
                typedef struct { double width, height; } SF_O2Sz;
                typedef id (*fn_gstate_t)(id);
                typedef float (*fn_gsf_t)(id);
                typedef double (*fn_gscgf_t)(id);
                typedef id (*fn_gsobj_t)(id);
                typedef SF_O2AT (*fn_gettm_t)(id);
                typedef void (*fn_settm_t)(id, SF_O2AT);
                typedef void (*fn_enc_t)(id, uint16_t *, const uint8_t *, unsigned);
                typedef void (*fn_cw_t)(id, SF_O2Sz *, const uint8_t *, int);
                typedef void (*fn_defadv_t)(id, const uint16_t *, SF_O2Sz *, size_t);
                typedef void (*fn_showg_t)(id, const uint16_t *, const SF_O2Sz *, unsigned);
                static fn_gstate_t f_curGS;
                static fn_gsf_t f_ptSz, f_lead;
                static fn_gscgf_t f_cSp, f_wSp, f_hSc;
                static fn_gsobj_t f_enc, f_cw;
                static fn_gettm_t f_getTm, f_getTlm;
                static fn_settm_t f_setTm, f_setTlm;
                static fn_enc_t f_mapG;
                static fn_cw_t f_getCW;
                static fn_defadv_t f_defAdv;
                static fn_showg_t f_showG;
                static int r_init = 0;
                if (!r_init) {
                    r_init = 1;
                    f_curGS = (fn_gstate_t)dlsym(RTLD_DEFAULT, "O2ContextCurrentGState");
                    f_ptSz = (fn_gsf_t)dlsym(RTLD_DEFAULT, "O2GStatePointSize");
                    f_cSp = (fn_gscgf_t)dlsym(RTLD_DEFAULT, "O2GStateCharacterSpacing");
                    f_wSp = (fn_gscgf_t)dlsym(RTLD_DEFAULT, "O2GStateWordSpacing");
                    f_hSc = (fn_gscgf_t)dlsym(RTLD_DEFAULT, "O2GStateTextHorizontalScaling");
                    f_lead = (fn_gsf_t)dlsym(RTLD_DEFAULT, "O2ContextGetTextLeading");
                    f_enc = (fn_gsobj_t)dlsym(RTLD_DEFAULT, "O2GStateEncoding");
                    f_cw = (fn_gsobj_t)dlsym(RTLD_DEFAULT, "O2GStateCharWidths");
                    f_getTm = (fn_gettm_t)dlsym(RTLD_DEFAULT, "O2ContextGetTextMatrix");
                    f_setTm = (fn_settm_t)dlsym(RTLD_DEFAULT, "O2ContextSetTextMatrix");
                    f_getTlm = (fn_gettm_t)dlsym(RTLD_DEFAULT, "O2ContextGetTextLineMatrix");
                    f_setTlm = (fn_settm_t)dlsym(RTLD_DEFAULT, "O2ContextSetTextLineMatrix");
                    f_mapG = (fn_enc_t)dlsym(RTLD_DEFAULT, "O2EncodingGetGlyphsForBytes");
                    f_getCW = (fn_cw_t)dlsym(RTLD_DEFAULT, "O2PDFCharWidthsGetAdvances");
                    f_defAdv = (fn_defadv_t)dlsym(RTLD_DEFAULT, "O2ContextGetDefaultAdvances");
                    f_showG = (fn_showg_t)dlsym(RTLD_DEFAULT, "O2ContextShowGlyphsWithAdvances");
                }
                id o2ctx = (id)info;
                if (f_curGS && f_ptSz && f_enc && f_mapG && f_showG && f_getTm && f_setTm && [stack count] > 0) {
                    id gs = f_curGS(o2ctx);
                    double ptSz = gs ? (double)f_ptSz(gs) : 12.0;
                    double hSc = (gs && f_hSc) ? f_hSc(gs) : 100.0;
                    if (hSc <= 0.01) hSc = 100.0;
                    double hMul = hSc / 100.0;
                    double cSp = (gs && f_cSp) ? f_cSp(gs) : 0.0;
                    double wSp = (gs && f_wSp) ? f_wSp(gs) : 0.0;
                    id enc = gs ? f_enc(gs) : nil;
                    id cw = (gs && f_cw) ? f_cw(gs) : nil;

                    void (^emitStr)(id) = ^(id strObj) {
                        const uint8_t *sb = ((const uint8_t *(*)(id, SEL))objc_msgSend)(strObj, @selector(bytes));
                        unsigned slen = ((unsigned (*)(id, SEL))objc_msgSend)(strObj, @selector(length));
                        if (!sb || slen == 0 || !enc) return;
                        uint16_t *glyphs = (uint16_t *)calloc(slen, sizeof(uint16_t));
                        SF_O2Sz *adv = (SF_O2Sz *)calloc(slen, sizeof(SF_O2Sz));
                        f_mapG(enc, glyphs, sb, slen);
                        if (cw && f_getCW) {
                            f_getCW(cw, adv, sb, (int)slen);
                            for (unsigned k = 0; k < slen; k++) {
                                double w = adv[k].width * ptSz * hMul + cSp * hMul;
                                if (sb[k] == 0x20) w += wSp * hMul;
                                adv[k].width = w;
                                adv[k].height = 0.0;
                            }
                        } else if (f_defAdv) {
                            f_defAdv(o2ctx, glyphs, adv, slen);
                            for (unsigned k = 0; k < slen; k++) {
                                double w = adv[k].width * hMul + cSp * hMul;
                                if (sb[k] == 0x20) w += wSp * hMul;
                                adv[k].width = w;
                                adv[k].height = 0.0;
                            }
                        }
                        f_showG(o2ctx, glyphs, adv, slen);
                        free(glyphs);
                        free(adv);
                    };

                    if (cb == s_origQuote && f_getTlm && f_setTlm && f_lead) {
                        SF_O2AT tlm = f_getTlm(o2ctx);
                        float dy = -f_lead(o2ctx);
                        tlm.tx += tlm.c * dy;
                        tlm.ty += tlm.d * dy;
                        f_setTlm(o2ctx, tlm);
                        f_setTm(o2ctx, tlm);
                    }
                    id arg = [[stack lastObject] retain];
                    [stack removeLastObject];
                    if (cb == s_origTJ) {
                        if (sf_o2_type_noparse(arg) == SF_O2TypeArray) {
                            unsigned acnt = ((unsigned (*)(id, SEL))objc_msgSend)(arg, @selector(count));
                            for (unsigned ai = 0; ai < acnt; ai++) {
                                id elem = nil;
                                if (!((BOOL (*)(id, SEL, unsigned, id *))objc_msgSend)(arg, @selector(getObjectAtIndex:value:), ai, &elem) || !elem) continue;
                                int et = sf_o2_type_noparse(elem);
                                if (et == SF_O2TypeString) {
                                    emitStr(elem);
                                } else if (et == SF_O2TypeInteger || et == SF_O2TypeReal) {
                                    SFReal num = 0.0f;
                                    if (((BOOL (*)(id, SEL, int, void *))objc_msgSend)(elem, @selector(checkForType:value:), SF_O2TypeReal, &num)) {
                                        float dx = (float)(-((double)num / 1000.0) * ptSz * hMul);
                                        SF_O2AT tm = f_getTm(o2ctx);
                                        tm.tx += dx * tm.a;
                                        tm.ty += dx * tm.b;
                                        f_setTm(o2ctx, tm);
                                    }
                                }
                            }
                        }
                    } else {
                        if (sf_o2_type_noparse(arg) == SF_O2TypeString) emitStr(arg);
                    }
                    [arg release];
                    continue;
                }
                }
                if (cb) cb(self, info);
            }
        }
    }
    return YES;
}

__attribute__((constructor))
static void sf_install_onyx2d_pdf15(void) {
    Class docCls = objc_lookUpClass("O2PDFDocument");
    if (docCls) {
        Method m = class_getInstanceMethod(docCls, @selector(initWithData:));
        if (m) method_setImplementation(m, (IMP)sf_o2doc_initWithData);
    }
    Class xrefCls = objc_lookUpClass("O2PDFxref");
    if (xrefCls) {
        Method m = class_getInstanceMethod(xrefCls, @selector(objectAtNumber:generation:));
        if (m) method_setImplementation(m, (IMP)sf_o2xref_objectAtNumber);
    }
    Class fltCls = objc_lookUpClass("O2PDFFilter");
    if (fltCls) {
        Method m = class_getClassMethod(fltCls, @selector(decodeWithName:data:parameters:));
        if (m) g_orig_filter_decode = (id (*)(id, SEL, const char *, id, id))method_setImplementation(m, (IMP)sf_o2filter_decode);
    }
    Class scCls = objc_lookUpClass("O2PDFScanner");
    if (scCls) {
        Method m = class_getInstanceMethod(scCls, @selector(scanStream:));
        if (m) method_setImplementation(m, (IMP)sf_o2scanner_scanStream);
    }
    Class imgCls = objc_lookUpClass("O2Image");
    if (imgCls) {
        Method m = class_getClassMethod(imgCls, @selector(imageWithPDFObject:));
        if (m) g_orig_image_with_pdf = (id (*)(id, SEL, id))method_setImplementation(m, (IMP)sf_o2image_with_pdf);
    }
}
