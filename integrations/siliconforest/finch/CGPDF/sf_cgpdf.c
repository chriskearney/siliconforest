/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * Width-correct CGPDF reader for the Finch PDFKit port.
 *
 * The box, rotation, drawing-transform, PDFDocEncoding, and unencrypted
 * permission behavior follows Finch's CGPDF reader (MIT OR Apache-2.0) and
 * ISO 32000. This file is original C. It is not Apple code and it does not
 * alias O2PDFInteger (int) or O2PDFReal (float).
 *
 * Classic xref only. An xref stream fails closed. Encrypted documents stay
 * locked. FlateDecode is inflated; other filters fail the data copy.
 */
#include "sf_cgpdf.h"
#include "sf_cgpdf_glue.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

_Static_assert(sizeof(CGPDFInteger) == 8, "arm64 CGPDFInteger is signed long");
_Static_assert(sizeof(CGPDFReal) == 8, "arm64 CGPDFReal is double");
_Static_assert(sizeof(CGRect) == 32, "CGRect is four doubles");
_Static_assert(sizeof(CGAffineTransform) == 48, "CGAffineTransform is six doubles");

enum { TY_REF = 100 };

typedef struct Obj Obj;
typedef struct Doc Doc;

struct Obj {
    int type;
    Doc *doc;
    union {
        unsigned char boolean;
        long i;
        double r;
        char *name;
        struct {
            uint8_t *b;
            size_t n;
        } str;
        struct {
            Obj **items;
            size_t count, cap;
        } arr;
        struct {
            char **keys;
            Obj **vals;
            size_t count, cap;
        } dict;
        struct {
            Obj *dict;
            const uint8_t *raw;
            size_t raw_n;
            uint8_t *decoded;
            size_t decoded_n;
            int decode_state;
        } stream;
        struct {
            int num, gen;
        } ref;
    } u;
};

typedef struct Page {
    int refs;
    int held_doc;
    Doc *doc;
    Obj *dict;
    int number;
} Page;

struct Doc {
    int refs;
    uint8_t *bytes;
    size_t len;
    void **pool;
    size_t npool, cappool;
    int *off;
    unsigned char *used;
    Obj **objs;
    int capobj;
    Obj **page_dicts;
    Page **slots;
    int npages;
    Obj *trailer;
    Obj *catalog;
    int major, minor;
    int encrypted;
    int unlocked;
    int outline_ready;
    void *outline;
};

typedef struct Rd {
    const uint8_t *b;
    size_t n, i;
} Rd;

struct SfPdfCs {
    int refs;
    Doc *doc;
    Obj *resources;
    uint8_t *bytes;
    size_t len;
};

struct SfPdfOps {
    int refs;
    struct {
        char name[16];
        CGPDFOperatorCallback cb;
    } items[48];
    int n;
};

struct SfPdfScan {
    int refs;
    struct SfPdfCs *cs;
    struct SfPdfOps *table;
    void *info;
    Obj *stack[256];
    int sp;
};

static char g_error[160];
static Obj g_loading;

const char *sf_cgpdf_error(void) { return g_error; }

static void set_error(const char *msg)
{
    snprintf(g_error, sizeof g_error, "%s", msg ? msg : "pdf error");
}

static void *pool_alloc(Doc *d, size_t n)
{
    void *p = calloc(1, n ? n : 1);
    if (!p)
        return NULL;
    if (d->npool == d->cappool) {
        size_t c = d->cappool ? d->cappool * 2 : 64;
        void **np = realloc(d->pool, c * sizeof(void *));
        if (!np) {
            free(p);
            return NULL;
        }
        d->pool = np;
        d->cappool = c;
    }
    d->pool[d->npool++] = p;
    return p;
}

static char *pool_copy(Doc *d, const void *s, size_t n)
{
    char *p = pool_alloc(d, n + 1);
    if (!p)
        return NULL;
    if (n)
        memcpy(p, s, n);
    p[n] = 0;
    return p;
}

static Obj *new_obj(Doc *d, int type)
{
    Obj *o = pool_alloc(d, sizeof *o);
    if (!o)
        return NULL;
    o->type = type;
    o->doc = d;
    return o;
}

static int is_ws(int c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static int is_delim_at(const Rd *r, size_t i)
{
    if (i >= r->n)
        return 1;
    unsigned char c = r->b[i];
    return is_ws(c) || c == '(' || c == ')' || c == '<' || c == '>' || c == '[' || c == ']' || c == '{' || c == '}' || c == '/' || c == '%';
}

static void skip(Rd *r)
{
    for (;;) {
        while (r->i < r->n && is_ws(r->b[r->i]))
            r->i++;
        if (r->i < r->n && r->b[r->i] == '%') {
            while (r->i < r->n && r->b[r->i] != '\n' && r->b[r->i] != '\r')
                r->i++;
            continue;
        }
        break;
    }
}

static int kw(Rd *r, const char *k)
{
    size_t n = strlen(k);
    if (r->i + n > r->n || memcmp(r->b + r->i, k, n) != 0)
        return 0;
    if (!is_delim_at(r, r->i + n))
        return 0;
    r->i += n;
    return 1;
}

static int hex_nibble(int c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

static Obj *parse_value(Doc *d, Rd *r, int depth);

static int dict_put(Doc *d, Obj *dict, const char *key, Obj *val)
{
    if (!dict || !key || !val)
        return 0;
    if (dict->u.dict.count == dict->u.dict.cap) {
        size_t c = dict->u.dict.cap ? dict->u.dict.cap * 2 : 8;
        char **keys = pool_alloc(d, c * sizeof(char *));
        Obj **vals = pool_alloc(d, c * sizeof(Obj *));
        if (!keys || !vals)
            return 0;
        if (dict->u.dict.count) {
            memcpy(keys, dict->u.dict.keys, dict->u.dict.count * sizeof(char *));
            memcpy(vals, dict->u.dict.vals, dict->u.dict.count * sizeof(Obj *));
        }
        dict->u.dict.keys = keys;
        dict->u.dict.vals = vals;
        dict->u.dict.cap = c;
    }
    dict->u.dict.keys[dict->u.dict.count] = (char *)key;
    dict->u.dict.vals[dict->u.dict.count] = val;
    dict->u.dict.count++;
    return 1;
}

static int arr_add(Doc *d, Obj *arr, Obj *val)
{
    if (arr->u.arr.count == arr->u.arr.cap) {
        size_t c = arr->u.arr.cap ? arr->u.arr.cap * 2 : 8;
        Obj **items = pool_alloc(d, c * sizeof(Obj *));
        if (!items)
            return 0;
        if (arr->u.arr.count)
            memcpy(items, arr->u.arr.items, arr->u.arr.count * sizeof(Obj *));
        arr->u.arr.items = items;
        arr->u.arr.cap = c;
    }
    arr->u.arr.items[arr->u.arr.count++] = val;
    return 1;
}

static Obj *parse_literal(Doc *d, Rd *r)
{
    size_t cap = 64, n = 0;
    uint8_t *buf = pool_alloc(d, cap);
    if (!buf || r->i >= r->n || r->b[r->i] != '(')
        return NULL;
    r->i++;
    int nest = 1;
    while (r->i < r->n && nest) {
        unsigned char c = r->b[r->i++];
        if (c == '\\') {
            if (r->i >= r->n)
                break;
            unsigned char e = r->b[r->i++];
            if (e == 'n')
                c = '\n';
            else if (e == 'r')
                c = '\r';
            else if (e == 't')
                c = '\t';
            else if (e == 'b')
                c = '\b';
            else if (e == 'f')
                c = '\f';
            else if (e == '(' || e == ')' || e == '\\')
                c = e;
            else if (e == '\n')
                continue;
            else if (e == '\r') {
                if (r->i < r->n && r->b[r->i] == '\n')
                    r->i++;
                continue;
            } else if (e >= '0' && e <= '7') {
                int v = e - '0', k;
                for (k = 0; k < 2 && r->i < r->n && r->b[r->i] >= '0' && r->b[r->i] <= '7'; k++)
                    v = (v << 3) + (r->b[r->i++] - '0');
                c = (unsigned char)v;
            } else
                c = e;
        } else if (c == '(') {
            nest++;
        } else if (c == ')') {
            nest--;
            if (!nest)
                break;
        }
        if (n + 1 >= cap) {
            uint8_t *nb = pool_alloc(d, cap * 2);
            if (!nb)
                return NULL;
            memcpy(nb, buf, n);
            buf = nb;
            cap *= 2;
        }
        buf[n++] = c;
    }
    if (nest)
        return NULL;
    Obj *o = new_obj(d, kCGPDFObjectTypeString);
    if (!o)
        return NULL;
    o->u.str.b = buf;
    o->u.str.n = n;
    buf[n] = 0;
    return o;
}

static Obj *parse_hex_string(Doc *d, Rd *r)
{
    if (r->i >= r->n || r->b[r->i] != '<')
        return NULL;
    r->i++;
    size_t cap = 32, n = 0;
    uint8_t *buf = pool_alloc(d, cap);
    int hi = -1;
    if (!buf)
        return NULL;
    while (r->i < r->n && r->b[r->i] != '>') {
        int c = r->b[r->i++];
        if (is_ws(c))
            continue;
        int v = hex_nibble(c);
        if (v < 0)
            return NULL;
        if (hi < 0)
            hi = v;
        else {
            if (n + 1 >= cap) {
                uint8_t *nb = pool_alloc(d, cap * 2);
                if (!nb)
                    return NULL;
                memcpy(nb, buf, n);
                buf = nb;
                cap *= 2;
            }
            buf[n++] = (uint8_t)((hi << 4) | v);
            hi = -1;
        }
    }
    if (r->i >= r->n || r->b[r->i] != '>')
        return NULL;
    r->i++;
    if (hi >= 0) {
        if (n + 1 >= cap) {
            uint8_t *nb = pool_alloc(d, cap + 2);
            if (!nb)
                return NULL;
            memcpy(nb, buf, n);
            buf = nb;
        }
        buf[n++] = (uint8_t)(hi << 4);
    }
    Obj *o = new_obj(d, kCGPDFObjectTypeString);
    if (!o)
        return NULL;
    o->u.str.b = buf;
    o->u.str.n = n;
    buf[n] = 0;
    return o;
}

static Obj *parse_name(Doc *d, Rd *r)
{
    if (r->i >= r->n || r->b[r->i] != '/')
        return NULL;
    r->i++;
    size_t s = r->i;
    char tmp[256];
    size_t n = 0;
    while (!is_delim_at(r, r->i)) {
        unsigned char c = r->b[r->i++];
        if (c == '#' && r->i + 1 < r->n) {
            int h = hex_nibble(r->b[r->i]), l = hex_nibble(r->b[r->i + 1]);
            if (h >= 0 && l >= 0) {
                c = (unsigned char)((h << 4) | l);
                r->i += 2;
            }
        }
        if (n + 1 >= sizeof tmp)
            return NULL;
        tmp[n++] = (char)c;
    }
    (void)s;
    Obj *o = new_obj(d, kCGPDFObjectTypeName);
    if (!o)
        return NULL;
    o->u.name = pool_copy(d, tmp, n);
    return o->u.name ? o : NULL;
}

static int scan_number(Rd *r, int *is_real, long *iv, double *rv)
{
    size_t s = r->i, i = s;
    if (i < r->n && (r->b[i] == '+' || r->b[i] == '-'))
        i++;
    size_t digits = i;
    int saw = 0, real = 0;
    while (i < r->n && isdigit(r->b[i])) {
        saw = 1;
        i++;
    }
    if (i < r->n && r->b[i] == '.') {
        real = 1;
        i++;
        while (i < r->n && isdigit(r->b[i])) {
            saw = 1;
            i++;
        }
    }
    if (i < r->n && (r->b[i] == 'e' || r->b[i] == 'E')) {
        size_t e = i + 1;
        if (e < r->n && (r->b[e] == '+' || r->b[e] == '-'))
            e++;
        size_t ed = e;
        while (e < r->n && isdigit(r->b[e]))
            e++;
        if (e > ed) {
            real = 1;
            i = e;
        }
    }
    /* digits marks the first digit byte. A sign or a bare dot is not a number. */
    if (!saw || digits == i)
        return 0;
    char tok[128];
    size_t n = i - s;
    if (n >= sizeof tok)
        return 0;
    memcpy(tok, r->b + s, n);
    tok[n] = 0;
    r->i = i;
    *is_real = real;
    if (real)
        *rv = strtod(tok, NULL);
    else
        *iv = strtol(tok, NULL, 10);
    return 1;
}

static Obj *parse_value(Doc *d, Rd *r, int depth)
{
    skip(r);
    if (depth > 64 || r->i >= r->n) {
        set_error("pdf value nested too deep or truncated");
        return NULL;
    }
    unsigned char c = r->b[r->i];
    if (c == '(')
        return parse_literal(d, r);
    if (c == '<') {
        if (r->i + 1 < r->n && r->b[r->i + 1] == '<') {
            Obj *dict = new_obj(d, kCGPDFObjectTypeDictionary);
            if (!dict)
                return NULL;
            r->i += 2;
            for (;;) {
                skip(r);
                if (r->i + 1 < r->n && r->b[r->i] == '>' && r->b[r->i + 1] == '>') {
                    r->i += 2;
                    break;
                }
                Obj *key = parse_name(d, r);
                Obj *val = key ? parse_value(d, r, depth + 1) : NULL;
                if (!key || !val || !dict_put(d, dict, key->u.name, val)) {
                    set_error("pdf dictionary is truncated");
                    return NULL;
                }
            }
            return dict;
        }
        return parse_hex_string(d, r);
    }
    if (c == '[') {
        Obj *arr = new_obj(d, kCGPDFObjectTypeArray);
        if (!arr)
            return NULL;
        r->i++;
        for (;;) {
            skip(r);
            if (r->i < r->n && r->b[r->i] == ']') {
                r->i++;
                break;
            }
            Obj *val = parse_value(d, r, depth + 1);
            if (!val || !arr_add(d, arr, val)) {
                set_error("pdf array is truncated");
                return NULL;
            }
        }
        return arr;
    }
    if (c == '/' )
        return parse_name(d, r);
    if (c == '+' || c == '-' || c == '.' || isdigit(c)) {
        int real = 0;
        long iv = 0;
        double rv = 0;
        if (!scan_number(r, &real, &iv, &rv))
            return NULL;
        if (!real) {
            size_t save = r->i;
            skip(r);
            int real2 = 0;
            long gen = 0;
            double ignore = 0;
            size_t before = r->i;
            if (r->i < r->n && isdigit(r->b[r->i]) && scan_number(r, &real2, &gen, &ignore) && !real2) {
                skip(r);
                if (kw(r, "R")) {
                    Obj *o = new_obj(d, TY_REF);
                    if (!o)
                        return NULL;
                    o->u.ref.num = (int)iv;
                    o->u.ref.gen = (int)gen;
                    return o;
                }
            }
            r->i = save;
            (void)before;
        }
        Obj *o = new_obj(d, real ? kCGPDFObjectTypeReal : kCGPDFObjectTypeInteger);
        if (!o)
            return NULL;
        if (real)
            o->u.r = rv;
        else
            o->u.i = iv;
        return o;
    }
    if (kw(r, "true") || kw(r, "false")) {
        Obj *o = new_obj(d, kCGPDFObjectTypeBoolean);
        size_t at;
        if (!o)
            return NULL;
        at = r->i;
        o->u.boolean = (unsigned char)(at >= 4 && r->b[at - 4] == 't' && (at < 5 || r->b[at - 5] != 'f'));
        return o;
    }
    if (kw(r, "null"))
        return new_obj(d, kCGPDFObjectTypeNull);
    set_error("pdf value is not a recognized token");
    return NULL;
}

static Obj *dict_raw(Obj *dict, const char *key)
{
    size_t i;
    if (!dict || dict->type != kCGPDFObjectTypeDictionary || !key)
        return NULL;
    for (i = 0; i < dict->u.dict.count; i++)
        if (dict->u.dict.keys[i] && strcmp(dict->u.dict.keys[i], key) == 0)
            return dict->u.dict.vals[i];
    return NULL;
}

static int reserve_obj(Doc *d, int num)
{
    int c;
    int *off;
    unsigned char *used;
    Obj **objs;
    if (num < 0 || num > 1000000)
        return 0;
    if (num < d->capobj)
        return 1;
    c = d->capobj ? d->capobj : 16;
    while (c <= num) {
        if (c > 1000000)
            return 0;
        c *= 2;
    }
    off = calloc((size_t)c, sizeof(int));
    used = calloc((size_t)c, 1);
    objs = calloc((size_t)c, sizeof(Obj *));
    if (!off || !used || !objs) {
        free(off);
        free(used);
        free(objs);
        return 0;
    }
    if (d->capobj) {
        memcpy(off, d->off, (size_t)d->capobj * sizeof(int));
        memcpy(used, d->used, (size_t)d->capobj);
        memcpy(objs, d->objs, (size_t)d->capobj * sizeof(Obj *));
        free(d->off);
        free(d->used);
        free(d->objs);
    }
    d->off = off;
    d->used = used;
    d->objs = objs;
    d->capobj = c;
    return 1;
}

static Obj *load_obj(Doc *d, int num);

static Obj *resolve(Obj *o)
{
    int hops = 0;
    while (o && o->type == TY_REF && hops++ < 32) {
        if (!o->doc)
            return NULL;
        o = load_obj(o->doc, o->u.ref.num);
    }
    return o && o->type != TY_REF ? o : NULL;
}

static int attach_stream(Doc *d, Rd *r, Obj *dict, Obj **out)
{
    Obj *leno, *o;
    long length;
    skip(r);
    if (!kw(r, "stream"))
        return 0;
    if (r->i < r->n && r->b[r->i] == '\r')
        r->i++;
    if (r->i < r->n && r->b[r->i] == '\n')
        r->i++;
    leno = resolve(dict_raw(dict, "Length"));
    if (!leno || (leno->type != kCGPDFObjectTypeInteger && leno->type != kCGPDFObjectTypeReal)) {
        set_error("pdf stream is missing Length");
        return -1;
    }
    length = leno->type == kCGPDFObjectTypeInteger ? leno->u.i : (long)leno->u.r;
    if (length < 0 || r->i + (size_t)length > r->n) {
        set_error("pdf stream Length runs past the file");
        return -1;
    }
    o = new_obj(d, kCGPDFObjectTypeStream);
    if (!o)
        return -1;
    o->u.stream.dict = dict;
    o->u.stream.raw = r->b + r->i;
    o->u.stream.raw_n = (size_t)length;
    r->i += (size_t)length;
    skip(r);
    kw(r, "endstream");
    *out = o;
    return 1;
}

static Obj *parse_indirect(Doc *d, size_t at)
{
    Rd r = {d->bytes, d->len, at};
    int real = 0;
    long num = 0, gen = 0;
    double rv = 0;
    Obj *value;
    skip(&r);
    if (!scan_number(&r, &real, &num, &rv) || real)
        return NULL;
    skip(&r);
    if (!scan_number(&r, &real, &gen, &rv) || real)
        return NULL;
    skip(&r);
    if (!kw(&r, "obj"))
        return NULL;
    value = parse_value(d, &r, 0);
    if (!value)
        return NULL;
    if (value->type == kCGPDFObjectTypeDictionary) {
        Obj *stream = NULL;
        int rc = attach_stream(d, &r, value, &stream);
        if (rc < 0)
            return NULL;
        if (rc > 0)
            value = stream;
    }
    (void)num;
    (void)gen;
    return value;
}

static Obj *load_obj(Doc *d, int num)
{
    Obj *o;
    if (!d || num <= 0 || num >= d->capobj || !d->used[num])
        return NULL;
    if (d->objs[num] == &g_loading)
        return NULL;
    if (d->objs[num])
        return d->objs[num];
    d->objs[num] = &g_loading;
    o = parse_indirect(d, (size_t)d->off[num]);
    d->objs[num] = o;
    return o;
}

static int parse_xref(Doc *d, size_t at)
{
    Rd r = {d->bytes, d->len, at};
    skip(&r);
    if (!kw(&r, "xref")) {
        set_error("pdf xref stream is not supported");
        return 0;
    }
    for (;;) {
        int real = 0;
        long start = 0, count = 0, i;
        double rv = 0;
        skip(&r);
        if (kw(&r, "trailer"))
            break;
        if (!scan_number(&r, &real, &start, &rv) || real)
            return 0;
        skip(&r);
        if (!scan_number(&r, &real, &count, &rv) || real || count < 0 || start < 0)
            return 0;
        if (!reserve_obj(d, (int)(start + count)))
            return 0;
        for (i = 0; i < count; i++) {
            unsigned off = 0, gen = 0;
            char use = 0;
            int nread = 0;
            skip(&r);
            if (r.i >= r.n || sscanf((const char *)r.b + r.i, "%u %u %c%n", &off, &gen, &use, &nread) < 3)
                return 0;
            r.i += (size_t)nread;
            if (use == 'n' && start + i > 0) {
                d->off[start + i] = (int)off;
                d->used[start + i] = 1;
            }
        }
    }
    d->trailer = parse_value(d, &r, 0);
    if (!d->trailer || d->trailer->type != kCGPDFObjectTypeDictionary) {
        set_error("pdf trailer is missing");
        return 0;
    }
    return 1;
}

static const char *dict_name(Obj *dict, const char *key)
{
    Obj *o = resolve(dict_raw(dict, key));
    if (!o || o->type != kCGPDFObjectTypeName)
        return NULL;
    return o->u.name;
}

static void walk_pages(Doc *d, Obj *node, int depth)
{
    Obj *kids;
    const char *type;
    size_t i;
    node = resolve(node);
    if (!node || node->type != kCGPDFObjectTypeDictionary || depth > 32)
        return;
    kids = resolve(dict_raw(node, "Kids"));
    type = dict_name(node, "Type");
    if (kids && kids->type == kCGPDFObjectTypeArray && !(type && strcmp(type, "Page") == 0)) {
        for (i = 0; i < kids->u.arr.count; i++)
            walk_pages(d, kids->u.arr.items[i], depth + 1);
        return;
    }
    if (d->npages >= d->capobj)
        return;
    d->page_dicts[d->npages++] = node;
}

static int read_header(Doc *d)
{
    size_t i = 0;
    while (i < d->len && is_ws(d->bytes[i]))
        i++;
    if (i + 8 > d->len || memcmp(d->bytes + i, "%PDF-", 5) != 0)
        return 0;
    if (!isdigit(d->bytes[i + 5]) || d->bytes[i + 6] != '.' || !isdigit(d->bytes[i + 7]))
        return 0;
    d->major = d->bytes[i + 5] - '0';
    d->minor = d->bytes[i + 7] - '0';
    return 1;
}

static size_t find_startxref(const uint8_t *b, size_t n)
{
    size_t i = n, limit = n > 65536 ? n - 65536 : 0;
    while (i > limit + 9) {
        i--;
        if (memcmp(b + i - 9, "startxref", 9) == 0)
            return i;
    }
    return 0;
}

static void free_doc(Doc *d)
{
    size_t i;
    if (!d)
        return;
    if (d->outline)
        sf_cf_release(d->outline);
    for (i = 0; i < d->npool; i++)
        free(d->pool[i]);
    free(d->pool);
    free(d->off);
    free(d->used);
    free(d->objs);
    free(d->page_dicts);
    free(d->slots);
    free(d->bytes);
    free(d);
}

static Doc *open_bytes(const uint8_t *bytes, size_t n)
{
    Doc *d;
    size_t sx;
    long at;
    Obj *root, *ver, *pages;
    const char *vs;
    if (!bytes || n < 8) {
        set_error("pdf bytes are empty");
        return NULL;
    }
    d = calloc(1, sizeof *d);
    if (!d)
        return NULL;
    d->refs = 1;
    d->bytes = malloc(n + 1);
    if (!d->bytes) {
        free(d);
        return NULL;
    }
    memcpy(d->bytes, bytes, n);
    d->bytes[n] = 0;
    d->len = n;
    g_error[0] = 0;
    if (!read_header(d)) {
        set_error("pdf header is not %PDF-");
        free_doc(d);
        return NULL;
    }
    sx = find_startxref(d->bytes, d->len);
    if (!sx) {
        set_error("pdf startxref is missing");
        free_doc(d);
        return NULL;
    }
    at = strtol((char *)d->bytes + sx, NULL, 10);
    if (at <= 0 || (size_t)at >= d->len || !parse_xref(d, (size_t)at)) {
        if (!g_error[0])
            set_error("pdf xref did not parse");
        free_doc(d);
        return NULL;
    }
    if (dict_raw(d->trailer, "Encrypt"))
        d->encrypted = 1;
    root = resolve(dict_raw(d->trailer, "Root"));
    if (!root || root->type != kCGPDFObjectTypeDictionary) {
        set_error("pdf catalog is missing");
        free_doc(d);
        return NULL;
    }
    d->catalog = root;
    ver = resolve(dict_raw(root, "Version"));
    if (ver && ver->type == kCGPDFObjectTypeName && (vs = ver->u.name) && vs[0] >= '0' && vs[0] <= '9' && vs[1] == '.') {
        int ma = vs[0] - '0', mi = atoi(vs + 2);
        if (ma > d->major || (ma == d->major && mi > d->minor)) {
            d->major = ma;
            d->minor = mi;
        }
    }
    pages = resolve(dict_raw(root, "Pages"));
    d->page_dicts = calloc(d->capobj > 0 ? (size_t)d->capobj : 1, sizeof(Obj *));
    d->slots = calloc(d->capobj > 0 ? (size_t)d->capobj : 1, sizeof(Page *));
    if (!d->page_dicts || !d->slots) {
        free_doc(d);
        return NULL;
    }
    if (pages)
        walk_pages(d, pages, 0);
    g_error[0] = 0;
    return d;
}

static Obj *inherited(Obj *dict, const char *key)
{
    Obj *seen[32];
    int hop;
    for (hop = 0; dict && hop < 32; hop++) {
        int s;
        Obj *raw, *val, *parent;
        for (s = 0; s < hop; s++)
            if (seen[s] == dict)
                return NULL;
        seen[hop] = dict;
        if (dict->type != kCGPDFObjectTypeDictionary)
            return NULL;
        raw = dict_raw(dict, key);
        val = raw ? resolve(raw) : NULL;
        if (val)
            return val;
        parent = dict_raw(dict, "Parent");
        dict = parent ? resolve(parent) : NULL;
    }
    return NULL;
}

static CGRect rect_make(double x, double y, double w, double h)
{
    CGRect r;
    r.origin.x = x;
    r.origin.y = y;
    r.size.width = w;
    r.size.height = h;
    return r;
}

static CGRect rect_null(void) { return rect_make(INFINITY, INFINITY, 0, 0); }

static CGRect rect_std(CGRect r)
{
    if (r.size.width < 0) {
        r.origin.x += r.size.width;
        r.size.width = -r.size.width;
    }
    if (r.size.height < 0) {
        r.origin.y += r.size.height;
        r.size.height = -r.size.height;
    }
    return r;
}

static int rect_missing(CGRect r) { return !isfinite(r.origin.x) || !isfinite(r.origin.y); }

static CGRect rect_isect(CGRect a, CGRect b)
{
    double x0, y0, x1, y1;
    if (rect_missing(a) || rect_missing(b))
        return rect_null();
    x0 = a.origin.x > b.origin.x ? a.origin.x : b.origin.x;
    y0 = a.origin.y > b.origin.y ? a.origin.y : b.origin.y;
    x1 = a.origin.x + a.size.width < b.origin.x + b.size.width ? a.origin.x + a.size.width : b.origin.x + b.size.width;
    y1 = a.origin.y + a.size.height < b.origin.y + b.size.height ? a.origin.y + a.size.height : b.origin.y + b.size.height;
    if (x1 <= x0 || y1 <= y0)
        return rect_null();
    return rect_make(x0, y0, x1 - x0, y1 - y0);
}

static int read_box(Obj *dict, const char *key, CGRect *out)
{
    Obj *a = inherited(dict, key);
    double v[4];
    int i;
    if (!a || a->type != kCGPDFObjectTypeArray || a->u.arr.count < 4)
        return 0;
    for (i = 0; i < 4; i++) {
        Obj *it = resolve(a->u.arr.items[i]);
        if (!it)
            return 0;
        if (it->type == kCGPDFObjectTypeInteger)
            v[i] = (double)it->u.i;
        else if (it->type == kCGPDFObjectTypeReal)
            v[i] = it->u.r;
        else
            return 0;
    }
    *out = rect_std(rect_make(v[0], v[1], v[2] - v[0], v[3] - v[1]));
    return 1;
}

static int page_locked(Page *p)
{
    return p && p->doc && p->doc->encrypted && !p->doc->unlocked;
}

static int is_flate(const char *name)
{
    return name && (strcmp(name, "FlateDecode") == 0 || strcmp(name, "Fl") == 0);
}

static int inflate_all(const uint8_t *src, size_t n, uint8_t **out, size_t *outn)
{
    z_stream z;
    uint8_t *buf;
    size_t cap = n * 4 + 64;
    int rc;
    memset(&z, 0, sizeof z);
    if (cap < 64)
        cap = 64;
    if (inflateInit(&z) != Z_OK)
        return 0;
    buf = malloc(cap);
    if (!buf) {
        inflateEnd(&z);
        return 0;
    }
    z.next_in = (Bytef *)src;
    z.avail_in = (uInt)n;
    for (;;) {
        if (z.total_out + 1 >= cap) {
            size_t nc = cap * 2;
            uint8_t *nb = realloc(buf, nc);
            if (!nb) {
                free(buf);
                inflateEnd(&z);
                return 0;
            }
            buf = nb;
            cap = nc;
        }
        z.next_out = buf + z.total_out;
        z.avail_out = (uInt)(cap - z.total_out);
        rc = inflate(&z, Z_NO_FLUSH);
        if (rc == Z_STREAM_END)
            break;
        if (rc != Z_OK) {
            free(buf);
            inflateEnd(&z);
            return 0;
        }
    }
    inflateEnd(&z);
    *out = buf;
    *outn = z.total_out;
    return 1;
}

static int stream_bytes(Obj *stream, const uint8_t **data, size_t *n)
{
    Obj *dict, *filter, *parms, *pred;
    const char *fname = NULL;
    if (!stream || stream->type != kCGPDFObjectTypeStream)
        return 0;
    if (stream->u.stream.decode_state < 0)
        return 0;
    if (stream->u.stream.decode_state > 0) {
        *data = stream->u.stream.decoded ? stream->u.stream.decoded : stream->u.stream.raw;
        *n = stream->u.stream.decoded ? stream->u.stream.decoded_n : stream->u.stream.raw_n;
        return 1;
    }
    dict = stream->u.stream.dict;
    filter = dict ? resolve(dict_raw(dict, "Filter")) : NULL;
    parms = dict ? resolve(dict_raw(dict, "DecodeParms")) : NULL;
    if (!parms)
        parms = dict ? resolve(dict_raw(dict, "DP")) : NULL;
    pred = parms && parms->type == kCGPDFObjectTypeDictionary ? resolve(dict_raw(parms, "Predictor")) : NULL;
    if (pred && pred->type == kCGPDFObjectTypeInteger && pred->u.i > 1) {
        stream->u.stream.decode_state = -1;
        return 0;
    }
    if (filter && filter->type == kCGPDFObjectTypeArray) {
        if (filter->u.arr.count != 1) {
            stream->u.stream.decode_state = -1;
            return 0;
        }
        filter = resolve(filter->u.arr.items[0]);
    }
    if (filter && filter->type == kCGPDFObjectTypeName)
        fname = filter->u.name;
    if (!fname) {
        stream->u.stream.decode_state = 1;
        *data = stream->u.stream.raw;
        *n = stream->u.stream.raw_n;
        return 1;
    }
    if (!is_flate(fname)) {
        stream->u.stream.decode_state = -1;
        return 0;
    }
    if (!inflate_all(stream->u.stream.raw, stream->u.stream.raw_n, &stream->u.stream.decoded, &stream->u.stream.decoded_n)) {
        stream->u.stream.decode_state = -1;
        return 0;
    }
    if (stream->doc) {
        if (stream->doc->npool == stream->doc->cappool) {
            void **np = realloc(stream->doc->pool, (stream->doc->cappool ? stream->doc->cappool * 2 : 64) * sizeof(void *));
            if (!np) {
                free(stream->u.stream.decoded);
                stream->u.stream.decoded = NULL;
                stream->u.stream.decode_state = -1;
                return 0;
            }
            stream->doc->pool = np;
            if (!stream->doc->cappool)
                stream->doc->cappool = 64;
            else
                stream->doc->cappool *= 2;
        }
        stream->doc->pool[stream->doc->npool++] = stream->u.stream.decoded;
    }
    stream->u.stream.decode_state = 1;
    *data = stream->u.stream.decoded;
    *n = stream->u.stream.decoded_n;
    return 1;
}

static int utf8_add(char **buf, size_t *n, size_t *cap, unsigned cp)
{
    unsigned char tmp[4];
    int k = 0;
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
        char *nb;
        while (c < *n + (size_t)k + 1)
            c *= 2;
        nb = realloc(*buf, c);
        if (!nb)
            return 0;
        *buf = nb;
        *cap = c;
    }
    memcpy(*buf + *n, tmp, (size_t)k);
    *n += (size_t)k;
    (*buf)[*n] = 0;
    return 1;
}

static char *text_utf8(const uint8_t *b, size_t n, size_t *outn)
{
    /* ISO 32000-1 Annex D bytes that differ from Latin-1. */
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
    if (!out) {
        out = calloc(1, 1);
        if (!out)
            return NULL;
    }
    if (outn)
        *outn = len;
    return out;
fail:
    free(out);
    return NULL;
}

static int is_operator(const char *op)
{
    static const char *ops[] = {
        "b", "B", "b*", "B*", "BDC", "BMC", "BT", "c", "cm", "CS", "cs", "d", "d0", "d1", "Do", "DP", "EI",
        "EMC", "ET", "f", "F", "f*", "G", "g", "gs", "h", "i", "j", "J", "K", "k", "l", "m", "M", "MP", "n",
        "q", "Q", "re", "RG", "rg", "ri", "s", "S", "SC", "sc", "SCN", "scn", "sh", "T*", "Tc", "Td", "TD",
        "Tf", "Tj", "TJ", "TL", "Tm", "Tr", "Ts", "Tw", "Tz", "v", "w", "W", "W*", "y", "'", "\""};
    size_t i;
    for (i = 0; i < sizeof ops / sizeof ops[0]; i++)
        if (strcmp(ops[i], op) == 0)
            return 1;
    return 0;
}

static void skip_inline(Rd *r)
{
    while (r->i + 1 < r->n) {
        if (r->b[r->i] == 'E' && r->b[r->i + 1] == 'I') {
            int before = r->i == 0 || is_ws(r->b[r->i - 1]);
            int after = r->i + 2 >= r->n || is_ws(r->b[r->i + 2]);
            if (before && after) {
                r->i += 2;
                return;
            }
        }
        r->i++;
    }
    r->i = r->n;
}

static int content_word(Rd *r, char *op, size_t cap)
{
    size_t n = 0;
    while (!is_delim_at(r, r->i)) {
        if (n + 1 >= cap)
            return 0;
        op[n++] = (char)r->b[r->i++];
    }
    op[n] = 0;
    return n > 0;
}

/* Returns 1 and an operand, 2 and an operator, 0 at end, -1 on a bad token. */
static int content_next(Doc *d, Rd *r, Obj **operand, char *op, size_t opcap)
{
    skip(r);
    *operand = NULL;
    op[0] = 0;
    if (r->i >= r->n)
        return 0;
    if (r->b[r->i] == '(' || r->b[r->i] == '<' || r->b[r->i] == '[' || r->b[r->i] == '/' ||
        r->b[r->i] == '+' || r->b[r->i] == '-' || r->b[r->i] == '.' || isdigit(r->b[r->i])) {
        *operand = parse_value(d, r, 0);
        return *operand ? 1 : -1;
    }
    if (!content_word(r, op, opcap))
        return -1;
    if (strcmp(op, "BI") == 0) {
        skip_inline(r);
        snprintf(op, opcap, "EI");
    }
    return 2;
}

static int ensure_cs_bytes(struct SfPdfCs *cs, const uint8_t *add, size_t n)
{
    uint8_t *nb = realloc(cs->bytes, cs->len + n + 2);
    if (!nb)
        return 0;
    cs->bytes = nb;
    if (n)
        memcpy(cs->bytes + cs->len, add, n);
    cs->len += n;
    cs->bytes[cs->len] = 0;
    return 1;
}

static int append_stream(struct SfPdfCs *cs, Obj *obj)
{
    const uint8_t *data = NULL;
    size_t n = 0;
    obj = resolve(obj);
    if (!obj)
        return 0;
    if (obj->type == kCGPDFObjectTypeArray) {
        size_t i;
        for (i = 0; i < obj->u.arr.count; i++) {
            if (!append_stream(cs, obj->u.arr.items[i]))
                return 0;
            if (!ensure_cs_bytes(cs, (const uint8_t *)"\n", 1))
                return 0;
        }
        return 1;
    }
    if (obj->type != kCGPDFObjectTypeStream || !stream_bytes(obj, &data, &n))
        return 0;
    return ensure_cs_bytes(cs, data, n);
}

static uint8_t glyph_row(unsigned char ch, int row)
{
    unsigned c;
    uint8_t bits;
    if (ch == ' ' || row < 0 || row > 6)
        return 0;
    c = ch;
    bits = 0x01;
    if (row == 0 || row == 6)
        bits |= 0x15;
    if ((c >> (row % 5)) & 1)
        bits |= 0x04;
    if ((c >> ((row + 3) % 5)) & 1)
        bits |= 0x10;
    if (row == 3)
        bits |= (uint8_t)((c * 3) & 0x1E);
    return (uint8_t)(bits & 0x1F);
}

static void plot(uint8_t *px, size_t w, size_t h, size_t stride, const double ctm[6], double x, double y, uint8_t r, uint8_t g, uint8_t b)
{
    double dx = ctm[0] * x + ctm[2] * y + ctm[4];
    double dy = ctm[1] * x + ctm[3] * y + ctm[5];
    int ix = (int)floor(dx);
    int iy = (int)floor((double)h - dy);
    uint8_t *p;
    if (ix < 0 || iy < 0 || (size_t)ix >= w || (size_t)iy >= h)
        return;
    if (stride < w * 4)
        return;
    p = px + (size_t)iy * stride + (size_t)ix * 4;
    p[0] = r;
    p[1] = g;
    p[2] = b;
    p[3] = 255;
}

static void fill_user(uint8_t *px, size_t w, size_t h, size_t stride, const double ctm[6], double x, double y, double rw, double rh, uint8_t r, uint8_t g, uint8_t b)
{
    int ix, iy, nw, nh;
    if (rw < 0) {
        x += rw;
        rw = -rw;
    }
    if (rh < 0) {
        y += rh;
        rh = -rh;
    }
    nw = (int)ceil(rw);
    nh = (int)ceil(rh);
    for (iy = 0; iy < nh; iy++)
        for (ix = 0; ix < nw; ix++)
            plot(px, w, h, stride, ctm, x + ix + 0.5, y + iy + 0.5, r, g, b);
}

static void draw_bytes(Doc *d, const uint8_t *bytes, size_t len, uint8_t *px, size_t w, size_t h, size_t stride, const double ctm[6])
{
    Rd r = {bytes, len, 0};
    Obj *stack[128];
    int sp = 0, in_text = 0;
    double tx = 0, ty = 0, size = 12, cr = 0, cg = 0, cb = 0;
    struct {
        double x, y, w, h;
    } rects[32];
    int nr = 0;
    while (r.i < r.n) {
        Obj *operand = NULL;
        char op[16];
        int kind = content_next(d, &r, &operand, op, sizeof op);
        if (kind == 0)
            break;
        if (kind < 0)
            break;
        if (kind == 1) {
            if (sp < 128)
                stack[sp++] = operand;
            continue;
        }
        if (!is_operator(op))
            continue;
        if (strcmp(op, "rg") == 0 && sp >= 3) {
            Obj *b = stack[sp - 1], *g = stack[sp - 2], *rr = stack[sp - 3];
            if (b->type == kCGPDFObjectTypeInteger || b->type == kCGPDFObjectTypeReal)
                cb = b->type == kCGPDFObjectTypeInteger ? (double)b->u.i : b->u.r;
            if (g->type == kCGPDFObjectTypeInteger || g->type == kCGPDFObjectTypeReal)
                cg = g->type == kCGPDFObjectTypeInteger ? (double)g->u.i : g->u.r;
            if (rr->type == kCGPDFObjectTypeInteger || rr->type == kCGPDFObjectTypeReal)
                cr = rr->type == kCGPDFObjectTypeInteger ? (double)rr->u.i : rr->u.r;
        } else if (strcmp(op, "re") == 0 && sp >= 4 && nr < 32) {
            Obj *rh = stack[sp - 1], *rw = stack[sp - 2], *y = stack[sp - 3], *x = stack[sp - 4];
            if ((x->type == kCGPDFObjectTypeInteger || x->type == kCGPDFObjectTypeReal) &&
                (y->type == kCGPDFObjectTypeInteger || y->type == kCGPDFObjectTypeReal) &&
                (rw->type == kCGPDFObjectTypeInteger || rw->type == kCGPDFObjectTypeReal) &&
                (rh->type == kCGPDFObjectTypeInteger || rh->type == kCGPDFObjectTypeReal)) {
                rects[nr].x = x->type == kCGPDFObjectTypeInteger ? (double)x->u.i : x->u.r;
                rects[nr].y = y->type == kCGPDFObjectTypeInteger ? (double)y->u.i : y->u.r;
                rects[nr].w = rw->type == kCGPDFObjectTypeInteger ? (double)rw->u.i : rw->u.r;
                rects[nr].h = rh->type == kCGPDFObjectTypeInteger ? (double)rh->u.i : rh->u.r;
                nr++;
            }
        } else if ((strcmp(op, "f") == 0 || strcmp(op, "F") == 0 || strcmp(op, "f*") == 0)) {
            int i;
            uint8_t R = (uint8_t)(cr < 0 ? 0 : cr > 1 ? 255 : cr * 255);
            uint8_t G = (uint8_t)(cg < 0 ? 0 : cg > 1 ? 255 : cg * 255);
            uint8_t B = (uint8_t)(cb < 0 ? 0 : cb > 1 ? 255 : cb * 255);
            for (i = 0; i < nr; i++)
                fill_user(px, w, h, stride, ctm, rects[i].x, rects[i].y, rects[i].w, rects[i].h, R, G, B);
            nr = 0;
        } else if (strcmp(op, "n") == 0 || strcmp(op, "S") == 0 || strcmp(op, "s") == 0) {
            nr = 0;
        } else if (strcmp(op, "BT") == 0) {
            in_text = 1;
            tx = ty = 0;
        } else if (strcmp(op, "ET") == 0) {
            in_text = 0;
        } else if (strcmp(op, "Tf") == 0 && sp >= 1) {
            Obj *sz = stack[sp - 1];
            if (sz->type == kCGPDFObjectTypeInteger || sz->type == kCGPDFObjectTypeReal)
                size = sz->type == kCGPDFObjectTypeInteger ? (double)sz->u.i : sz->u.r;
        } else if ((strcmp(op, "Td") == 0 || strcmp(op, "TD") == 0) && sp >= 2) {
            Obj *oy = stack[sp - 1], *ox = stack[sp - 2];
            double mx = ox->type == kCGPDFObjectTypeInteger ? (double)ox->u.i : ox->type == kCGPDFObjectTypeReal ? ox->u.r : 0;
            double my = oy->type == kCGPDFObjectTypeInteger ? (double)oy->u.i : oy->type == kCGPDFObjectTypeReal ? oy->u.r : 0;
            tx += mx;
            ty += my;
        } else if (strcmp(op, "Tm") == 0 && sp >= 6) {
            Obj *e = stack[sp - 2], *f = stack[sp - 1];
            tx = e->type == kCGPDFObjectTypeInteger ? (double)e->u.i : e->type == kCGPDFObjectTypeReal ? e->u.r : tx;
            ty = f->type == kCGPDFObjectTypeInteger ? (double)f->u.i : f->type == kCGPDFObjectTypeReal ? f->u.r : ty;
        } else if (strcmp(op, "Tj") == 0 || strcmp(op, "'") == 0 || strcmp(op, "\"") == 0) {
            Obj *s = NULL;
            int i;
            if (strcmp(op, "'") == 0)
                ty -= size;
            if (strcmp(op, "\"") == 0 && sp >= 1)
                s = stack[sp - 1];
            else if (sp >= 1)
                s = stack[sp - 1];
            if (strcmp(op, "\"") == 0)
                ty -= size;
            if (s && s->type == kCGPDFObjectTypeString && in_text) {
                double scale = size / 7.0;
                uint8_t R = (uint8_t)(cr < 0 ? 0 : cr > 1 ? 255 : cr * 255);
                uint8_t G = (uint8_t)(cg < 0 ? 0 : cg > 1 ? 255 : cg * 255);
                uint8_t B = (uint8_t)(cb < 0 ? 0 : cb > 1 ? 255 : cb * 255);
                if (scale < 1)
                    scale = 1;
                for (i = 0; i < (int)s->u.str.n; i++) {
                    int row, col;
                    for (row = 0; row < 7; row++) {
                        uint8_t bits = glyph_row(s->u.str.b[i], row);
                        for (col = 0; col < 5; col++)
                            if (bits & (1u << (4 - col)))
                                fill_user(px, w, h, stride, ctm, tx + col * scale, ty + (6 - row) * scale, scale, scale, R, G, B);
                    }
                    tx += 6 * scale;
                }
            }
        }
        sp = 0;
    }
}

static long dest_page(Doc *d, Obj *dest)
{
    Obj *first;
    int i;
    dest = resolve(dest);
    if (!dest || dest->type != kCGPDFObjectTypeArray || dest->u.arr.count < 1)
        return 0;
    first = resolve(dest->u.arr.items[0]);
    if (!first)
        return 0;
    if (first->type == kCGPDFObjectTypeInteger && first->u.i >= 0)
        return first->u.i + 1;
    if (first->type == kCGPDFObjectTypeDictionary) {
        for (i = 0; i < d->npages; i++)
            if (d->page_dicts[i] == first)
                return i + 1;
    }
    return 0;
}

static void *outline_cf(Doc *d, Obj *item, int depth, Obj **seen, int *nseen)
{
    void *kids, *entry, *title_cf = NULL;
    Obj *title, *dest, *action, *child, *next;
    char *utf = NULL;
    size_t un = 0;
    long page = 0;
    int s;
    if (!item || depth > 32)
        return sf_cf_array();
    item = resolve(item);
    kids = sf_cf_array();
    if (!kids)
        return NULL;
    while (item && item->type == kCGPDFObjectTypeDictionary && depth < 32) {
        for (s = 0; s < *nseen; s++)
            if (seen[s] == item)
                goto done;
        if (*nseen < 64)
            seen[(*nseen)++] = item;
        entry = sf_cf_dict();
        title = resolve(dict_raw(item, "Title"));
        if (title && title->type == kCGPDFObjectTypeString)
            utf = text_utf8(title->u.str.b, title->u.str.n, &un);
        title_cf = utf ? sf_cf_string_utf8(utf, un) : sf_cf_empty_string();
        free(utf);
        utf = NULL;
        if (entry && title_cf)
            sf_cf_dict_set(entry, "Title", title_cf);
        if (title_cf)
            sf_cf_release(title_cf);
        dest = dict_raw(item, "Dest");
        if (!dest && (action = resolve(dict_raw(item, "A"))) && action->type == kCGPDFObjectTypeDictionary) {
            const char *kind = dict_name(action, "S");
            if (kind && strcmp(kind, "GoTo") == 0)
                dest = dict_raw(action, "D");
        }
        page = dest ? dest_page(d, dest) : 0;
        if (page && entry) {
            void *num = sf_cf_number_long(page);
            if (num) {
                sf_cf_dict_set(entry, "Destination", num);
                sf_cf_release(num);
            }
        }
        child = resolve(dict_raw(item, "First"));
        if (child) {
            void *ck = outline_cf(d, child, depth + 1, seen, nseen);
            if (ck && sf_cf_array_count(ck) && entry)
                sf_cf_dict_set(entry, "Children", ck);
            if (ck)
                sf_cf_release(ck);
        }
        if (entry && (page || sf_cf_dict_get(entry, "Children")))
            sf_cf_array_add(kids, entry);
        if (entry)
            sf_cf_release(entry);
        next = resolve(dict_raw(item, "Next"));
        item = next;
    }
done:
    return kids;
}

/* ---- public document / page ---- */

CGPDFDocumentRef CGPDFDocumentCreateWithProvider(CGDataProviderRef provider)
{
    uint8_t *bytes = NULL;
    size_t n = 0;
    Doc *d;
    if (!provider || !sf_copy_provider(provider, &bytes, &n)) {
        set_error("pdf provider has no bytes");
        return NULL;
    }
    d = open_bytes(bytes, n);
    free(bytes);
    return (CGPDFDocumentRef)d;
}

CGPDFDocumentRef CGPDFDocumentRetain(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    if (!d)
        return NULL;
    d->refs++;
    return doc;
}

void CGPDFDocumentRelease(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    if (!d)
        return;
    if (--d->refs > 0)
        return;
    free_doc(d);
}

size_t CGPDFDocumentGetNumberOfPages(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    return d ? (size_t)d->npages : 0;
}

CGPDFPageRef CGPDFDocumentGetPage(CGPDFDocumentRef doc, size_t number)
{
    Doc *d = (Doc *)doc;
    Page *p;
    if (!d || number == 0 || number > (size_t)d->npages)
        return NULL;
    p = d->slots[number - 1];
    if (!p) {
        p = pool_alloc(d, sizeof *p);
        if (!p)
            return NULL;
        p->doc = d;
        p->dict = d->page_dicts[number - 1];
        p->number = (int)number;
        d->slots[number - 1] = p;
    }
    return (CGPDFPageRef)p;
}

void CGPDFDocumentGetVersion(CGPDFDocumentRef doc, int *major, int *minor)
{
    Doc *d = (Doc *)doc;
    if (major)
        *major = d ? d->major : 0;
    if (minor)
        *minor = d ? d->minor : 0;
}

bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    return d && d->encrypted;
}

bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    return !d || !d->encrypted || d->unlocked;
}

bool CGPDFDocumentUnlockWithPassword(CGPDFDocumentRef doc, const char *password)
{
    Doc *d = (Doc *)doc;
    (void)password;
    if (!d)
        return false;
    if (!d->encrypted)
        return true;
    return false;
}

CGPDFAccessPermissions CGPDFDocumentGetAccessPermissions(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    if (!d)
        return 0;
    if (!d->encrypted)
        return 0xff;
    if (!d->unlocked)
        return 0;
    return 0;
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
    Doc *d = (Doc *)doc;
    Obj *info = d && d->trailer ? resolve(dict_raw(d->trailer, "Info")) : NULL;
    if (!info || info->type != kCGPDFObjectTypeDictionary)
        return NULL;
    return (CGPDFDictionaryRef)info;
}

CFDictionaryRef CGPDFDocumentGetOutline(CGPDFDocumentRef doc)
{
    Doc *d = (Doc *)doc;
    Obj *outlines, *first, *seen[64];
    int nseen = 0;
    void *kids, *root;
    if (!d)
        return NULL;
    if (d->outline_ready)
        return d->outline;
    d->outline_ready = 1;
    outlines = d->catalog ? resolve(dict_raw(d->catalog, "Outlines")) : NULL;
    if (!outlines || outlines->type != kCGPDFObjectTypeDictionary)
        return NULL;
    first = resolve(dict_raw(outlines, "First"));
    kids = first ? outline_cf(d, first, 0, seen, &nseen) : sf_cf_array();
    root = sf_cf_dict();
    if (!root) {
        if (kids)
            sf_cf_release(kids);
        return NULL;
    }
    if (kids) {
        sf_cf_dict_set(root, "Children", kids);
        sf_cf_release(kids);
    }
    d->outline = root;
    return root;
}

CGPDFPageRef CGPDFPageRetain(CGPDFPageRef page)
{
    Page *p = (Page *)page;
    if (!p)
        return NULL;
    if (p->refs++ == 0 && p->doc) {
        p->doc->refs++;
        p->held_doc = 1;
    }
    return page;
}

void CGPDFPageRelease(CGPDFPageRef page)
{
    Page *p = (Page *)page;
    Doc *doc;
    if (!p || p->refs <= 0)
        return;
    p->refs--;
    if (p->refs == 0 && p->held_doc) {
        p->held_doc = 0;
        doc = p->doc;
        CGPDFDocumentRelease((CGPDFDocumentRef)doc);
    }
}

CGRect CGPDFPageGetBoxRect(CGPDFPageRef page, int box)
{
    Page *p = (Page *)page;
    CGRect media, crop, r;
    static const char *keys[] = {NULL, NULL, "BleedBox", "TrimBox", "ArtBox"};
    if (!p || box < kCGPDFMediaBox || box > kCGPDFArtBox || page_locked(p))
        return rect_null();
    if (!read_box(p->dict, "MediaBox", &media))
        media = rect_make(0, 0, 612, 792);
    if (box == kCGPDFMediaBox)
        return media;
    crop = media;
    if (read_box(p->dict, "CropBox", &r)) {
        r = rect_isect(r, media);
        if (!rect_missing(r))
            crop = r;
    }
    if (box == kCGPDFCropBox)
        return crop;
    if (read_box(p->dict, keys[box], &r))
        return r;
    return crop;
}

int CGPDFPageGetRotationAngle(CGPDFPageRef page)
{
    Page *p = (Page *)page;
    Obj *o;
    if (!p)
        return 0;
    o = inherited(p->dict, "Rotate");
    if (o && o->type == kCGPDFObjectTypeInteger)
        return (int)o->u.i;
    if (o && o->type == kCGPDFObjectTypeReal)
        return (int)o->u.r;
    return 0;
}

CGAffineTransform CGPDFPageGetDrawingTransform(CGPDFPageRef page, int box, CGRect rect, int clockwiseDegrees, bool preserveAspectRatio)
{
    Page *p = (Page *)page;
    CGRect b;
    int angle, quarter;
    double bw, bh, sx, sy, cosv, sinv, ex, ey, mx, my;
    CGAffineTransform t;
    static const int cs[4][2] = {{1, 0}, {0, -1}, {-1, 0}, {0, 1}};
    if (!p)
        return (CGAffineTransform){1, 0, 0, 1, 0, 0};
    b = CGPDFPageGetBoxRect(page, box);
    angle = (CGPDFPageGetRotationAngle(page) + clockwiseDegrees) % 360;
    if (angle < 0)
        angle += 360;
    if (angle % 90)
        angle = 0;
    rect = rect_std(rect);
    quarter = angle == 90 || angle == 270;
    bw = quarter ? b.size.height : b.size.width;
    bh = quarter ? b.size.width : b.size.height;
    sx = 1;
    sy = 1;
    if (bw > 0 && bh > 0) {
        sx = rect.size.width / bw;
        sy = rect.size.height / bh;
        if (preserveAspectRatio) {
            double m = sx < sy ? sx : sy;
            sx = sy = m;
        }
        if (sx > 1)
            sx = 1;
        if (sy > 1)
            sy = 1;
    }
    cosv = cs[angle / 90][0];
    sinv = cs[angle / 90][1];
    ex = quarter ? sy : sx;
    ey = quarter ? sx : sy;
    t.a = cosv * ex;
    t.b = sinv * ex;
    t.c = -sinv * ey;
    t.d = cosv * ey;
    mx = b.origin.x + b.size.width * 0.5;
    my = b.origin.y + b.size.height * 0.5;
    t.tx = rect.origin.x + rect.size.width * 0.5 - (t.a * mx + t.c * my);
    t.ty = rect.origin.y + rect.size.height * 0.5 - (t.b * mx + t.d * my);
    return t;
}

CGPDFDictionaryRef CGPDFPageGetDictionary(CGPDFPageRef page)
{
    Page *p = (Page *)page;
    return p ? (CGPDFDictionaryRef)p->dict : NULL;
}

size_t CGPDFPageGetPageNumber(CGPDFPageRef page)
{
    Page *p = (Page *)page;
    return p && !page_locked(p) ? (size_t)p->number : 0;
}

void CGContextDrawPDFPage(CGContextRef context, CGPDFPageRef page)
{
    Page *p = (Page *)page;
    struct SfPdfCs *cs;
    uint8_t *px = NULL;
    size_t w = 0, h = 0, stride = 0;
    double ctm[6] = {1, 0, 0, 1, 0, 0};
    if (!p || page_locked(p) || !context)
        return;
    if (!sf_bitmap(context, &px, &w, &h, &stride, ctm) || !px || !w || !h)
        return;
    cs = (struct SfPdfCs *)CGPDFContentStreamCreateWithPage(page);
    if (!cs)
        return;
    draw_bytes(p->doc, cs->bytes, cs->len, px, w, h, stride, ctm);
    CGPDFContentStreamRelease((CGPDFContentStreamRef)cs);
}

CGPDFContentStreamRef CGPDFContentStreamCreateWithPage(CGPDFPageRef page)
{
    Page *p = (Page *)page;
    struct SfPdfCs *cs;
    Obj *contents, *resources;
    if (!p)
        return NULL;
    contents = inherited(p->dict, "Contents");
    if (!contents)
        return NULL;
    cs = calloc(1, sizeof *cs);
    if (!cs)
        return NULL;
    cs->refs = 1;
    cs->doc = p->doc;
    resources = inherited(p->dict, "Resources");
    cs->resources = resources && resources->type == kCGPDFObjectTypeDictionary ? resources : NULL;
    if (!append_stream(cs, contents)) {
        free(cs->bytes);
        free(cs);
        return NULL;
    }
    return (CGPDFContentStreamRef)cs;
}

CGPDFObjectRef CGPDFContentStreamGetResource(CGPDFContentStreamRef stream, const char *category, const char *name)
{
    struct SfPdfCs *cs = (struct SfPdfCs *)stream;
    Obj *cat, *item;
    if (!cs || !category || !name || !cs->resources)
        return NULL;
    cat = resolve(dict_raw(cs->resources, category));
    if (!cat || cat->type != kCGPDFObjectTypeDictionary)
        return NULL;
    item = resolve(dict_raw(cat, name));
    return (CGPDFObjectRef)item;
}

void CGPDFContentStreamRelease(CGPDFContentStreamRef stream)
{
    struct SfPdfCs *cs = (struct SfPdfCs *)stream;
    if (!cs)
        return;
    if (--cs->refs > 0)
        return;
    free(cs->bytes);
    free(cs);
}

CGPDFOperatorTableRef CGPDFOperatorTableCreate(void)
{
    struct SfPdfOps *t = calloc(1, sizeof *t);
    if (!t)
        return NULL;
    t->refs = 1;
    return (CGPDFOperatorTableRef)t;
}

void CGPDFOperatorTableRelease(CGPDFOperatorTableRef table)
{
    struct SfPdfOps *t = (struct SfPdfOps *)table;
    if (!t)
        return;
    if (--t->refs > 0)
        return;
    free(t);
}

void CGPDFOperatorTableSetCallback(CGPDFOperatorTableRef table, const char *name, CGPDFOperatorCallback callback)
{
    struct SfPdfOps *t = (struct SfPdfOps *)table;
    int i;
    if (!t || !name)
        return;
    for (i = 0; i < t->n; i++) {
        if (strcmp(t->items[i].name, name) == 0) {
            t->items[i].cb = callback;
            return;
        }
    }
    if (t->n >= 48 || strlen(name) >= sizeof t->items[0].name)
        return;
    snprintf(t->items[t->n].name, sizeof t->items[0].name, "%s", name);
    t->items[t->n].cb = callback;
    t->n++;
}

CGPDFScannerRef CGPDFScannerCreate(CGPDFContentStreamRef stream, CGPDFOperatorTableRef table, void *info)
{
    struct SfPdfScan *s;
    struct SfPdfCs *cs = (struct SfPdfCs *)stream;
    struct SfPdfOps *ops = (struct SfPdfOps *)table;
    if (!cs)
        return NULL;
    s = calloc(1, sizeof *s);
    if (!s)
        return NULL;
    s->refs = 1;
    s->cs = cs;
    cs->refs++;
    s->table = ops;
    if (ops)
        ops->refs++;
    s->info = info;
    return (CGPDFScannerRef)s;
}

bool CGPDFScannerScan(CGPDFScannerRef scanner)
{
    struct SfPdfScan *s = (struct SfPdfScan *)scanner;
    Rd r;
    if (!s || !s->cs)
        return false;
    r.b = s->cs->bytes;
    r.n = s->cs->len;
    r.i = 0;
    s->sp = 0;
    while (r.i < r.n) {
        Obj *operand = NULL;
        char op[16];
        int kind = content_next(s->cs->doc, &r, &operand, op, sizeof op);
        int i;
        CGPDFOperatorCallback cb = NULL;
        if (kind == 0)
            break;
        if (kind < 0)
            return false;
        if (kind == 1) {
            if (s->sp < 256)
                s->stack[s->sp++] = operand;
            continue;
        }
        if (!is_operator(op))
            continue;
        if (s->table) {
            for (i = 0; i < s->table->n; i++)
                if (strcmp(s->table->items[i].name, op) == 0)
                    cb = s->table->items[i].cb;
        }
        if (cb)
            cb((CGPDFScannerRef)s, s->info);
        s->sp = 0;
    }
    return true;
}

CGPDFContentStreamRef CGPDFScannerGetContentStream(CGPDFScannerRef scanner)
{
    struct SfPdfScan *s = (struct SfPdfScan *)scanner;
    return s ? (CGPDFContentStreamRef)s->cs : NULL;
}

void CGPDFScannerRelease(CGPDFScannerRef scanner)
{
    struct SfPdfScan *s = (struct SfPdfScan *)scanner;
    if (!s)
        return;
    if (--s->refs > 0)
        return;
    CGPDFContentStreamRelease((CGPDFContentStreamRef)s->cs);
    CGPDFOperatorTableRelease((CGPDFOperatorTableRef)s->table);
    free(s);
}

static Obj *pop_obj(struct SfPdfScan *s)
{
    if (!s || s->sp <= 0)
        return NULL;
    return s->stack[--s->sp];
}

bool CGPDFScannerPopNumber(CGPDFScannerRef scanner, CGPDFReal *value)
{
    Obj *o = pop_obj((struct SfPdfScan *)scanner);
    return CGPDFObjectGetValue((CGPDFObjectRef)o, kCGPDFObjectTypeReal, value);
}

bool CGPDFScannerPopInteger(CGPDFScannerRef scanner, CGPDFInteger *value)
{
    Obj *o = pop_obj((struct SfPdfScan *)scanner);
    return CGPDFObjectGetValue((CGPDFObjectRef)o, kCGPDFObjectTypeInteger, value);
}

bool CGPDFScannerPopName(CGPDFScannerRef scanner, const char **value)
{
    Obj *o = pop_obj((struct SfPdfScan *)scanner);
    return CGPDFObjectGetValue((CGPDFObjectRef)o, kCGPDFObjectTypeName, value);
}

bool CGPDFScannerPopString(CGPDFScannerRef scanner, CGPDFStringRef *value)
{
    Obj *o = pop_obj((struct SfPdfScan *)scanner);
    return CGPDFObjectGetValue((CGPDFObjectRef)o, kCGPDFObjectTypeString, value);
}

bool CGPDFScannerPopArray(CGPDFScannerRef scanner, CGPDFArrayRef *value)
{
    Obj *o = pop_obj((struct SfPdfScan *)scanner);
    return CGPDFObjectGetValue((CGPDFObjectRef)o, kCGPDFObjectTypeArray, value);
}

bool CGPDFObjectGetValue(CGPDFObjectRef object, int type, void *value)
{
    Obj *o = (Obj *)object;
    if (!o)
        return false;
    if (o->type != type) {
        if (o->type == kCGPDFObjectTypeInteger && type == kCGPDFObjectTypeReal) {
            if (value)
                *(CGPDFReal *)value = (CGPDFReal)o->u.i;
            return true;
        }
        return false;
    }
    if (!value)
        return true;
    switch (type) {
    case kCGPDFObjectTypeBoolean:
        *(CGPDFBoolean *)value = o->u.boolean;
        break;
    case kCGPDFObjectTypeInteger:
        *(CGPDFInteger *)value = o->u.i;
        break;
    case kCGPDFObjectTypeReal:
        *(CGPDFReal *)value = o->u.r;
        break;
    case kCGPDFObjectTypeName:
        *(const char **)value = o->u.name;
        break;
    case kCGPDFObjectTypeString:
        *(CGPDFStringRef *)value = object;
        break;
    case kCGPDFObjectTypeArray:
        *(CGPDFArrayRef *)value = object;
        break;
    case kCGPDFObjectTypeDictionary:
        *(CGPDFDictionaryRef *)value = object;
        break;
    case kCGPDFObjectTypeStream:
        *(CGPDFStreamRef *)value = object;
        break;
    default:
        break;
    }
    return true;
}

static Obj *array_at(CGPDFArrayRef array, size_t index)
{
    Obj *a = (Obj *)array;
    if (!a || a->type != kCGPDFObjectTypeArray || index >= a->u.arr.count)
        return NULL;
    return resolve(a->u.arr.items[index]);
}

size_t CGPDFArrayGetCount(CGPDFArrayRef array)
{
    Obj *a = (Obj *)array;
    return a && a->type == kCGPDFObjectTypeArray ? a->u.arr.count : 0;
}

bool CGPDFArrayGetNumber(CGPDFArrayRef array, size_t index, CGPDFReal *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)array_at(array, index), kCGPDFObjectTypeReal, value);
}

bool CGPDFArrayGetString(CGPDFArrayRef array, size_t index, CGPDFStringRef *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)array_at(array, index), kCGPDFObjectTypeString, value);
}

bool CGPDFArrayGetDictionary(CGPDFArrayRef array, size_t index, CGPDFDictionaryRef *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)array_at(array, index), kCGPDFObjectTypeDictionary, value);
}

static Obj *dict_resolved(CGPDFDictionaryRef dict, const char *key)
{
    Obj *d = (Obj *)dict;
    if (!d || !key)
        return NULL;
    if (d->type == kCGPDFObjectTypeStream)
        d = d->u.stream.dict;
    return resolve(dict_raw(d, key));
}

bool CGPDFDictionaryGetInteger(CGPDFDictionaryRef dict, const char *key, CGPDFInteger *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeInteger, value);
}

bool CGPDFDictionaryGetNumber(CGPDFDictionaryRef dict, const char *key, CGPDFReal *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeReal, value);
}

bool CGPDFDictionaryGetName(CGPDFDictionaryRef dict, const char *key, const char **value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeName, value);
}

bool CGPDFDictionaryGetString(CGPDFDictionaryRef dict, const char *key, CGPDFStringRef *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeString, value);
}

bool CGPDFDictionaryGetArray(CGPDFDictionaryRef dict, const char *key, CGPDFArrayRef *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeArray, value);
}

bool CGPDFDictionaryGetDictionary(CGPDFDictionaryRef dict, const char *key, CGPDFDictionaryRef *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeDictionary, value);
}

bool CGPDFDictionaryGetStream(CGPDFDictionaryRef dict, const char *key, CGPDFStreamRef *value)
{
    return CGPDFObjectGetValue((CGPDFObjectRef)dict_resolved(dict, key), kCGPDFObjectTypeStream, value);
}

void CGPDFDictionaryApplyFunction(CGPDFDictionaryRef dict, CGPDFDictionaryApplierFunction function, void *info)
{
    Obj *d = (Obj *)dict;
    size_t i;
    if (!d || !function)
        return;
    if (d->type == kCGPDFObjectTypeStream)
        d = d->u.stream.dict;
    if (!d || d->type != kCGPDFObjectTypeDictionary)
        return;
    for (i = 0; i < d->u.dict.count; i++) {
        Obj *val = resolve(d->u.dict.vals[i]);
        if (val)
            function(d->u.dict.keys[i], (CGPDFObjectRef)val, info);
    }
}

size_t CGPDFStringGetLength(CGPDFStringRef string)
{
    Obj *s = (Obj *)string;
    return s && s->type == kCGPDFObjectTypeString ? s->u.str.n : 0;
}

const unsigned char *CGPDFStringGetBytePtr(CGPDFStringRef string)
{
    Obj *s = (Obj *)string;
    return s && s->type == kCGPDFObjectTypeString ? s->u.str.b : NULL;
}

CFStringRef CGPDFStringCopyTextString(CGPDFStringRef string)
{
    Obj *s = (Obj *)string;
    char *utf;
    size_t n = 0;
    void *cf;
    if (!s || s->type != kCGPDFObjectTypeString)
        return sf_cf_empty_string();
    utf = text_utf8(s->u.str.b, s->u.str.n, &n);
    if (!utf)
        return sf_cf_empty_string();
    cf = sf_cf_string_utf8(utf, n);
    free(utf);
    return cf ? cf : sf_cf_empty_string();
}

CFDataRef CGPDFStreamCopyData(CGPDFStreamRef stream, int *format)
{
    const uint8_t *data = NULL;
    size_t n = 0;
    if (format)
        *format = 0;
    if (!stream_bytes((Obj *)stream, &data, &n) || !data)
        return NULL;
    return sf_cf_data(data, n);
}
