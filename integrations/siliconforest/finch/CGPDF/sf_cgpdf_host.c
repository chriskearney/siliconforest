/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Host CoreFoundation stand-in and the open/page/text/render proof. */
#define _POSIX_C_SOURCE 200809L
#include "sf_cgpdf.h"
#include "sf_cgpdf_glue.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

typedef struct HostCF HostCF;
struct HostCF {
    int kind;
    int refs;
    char *text;
    uint8_t *data;
    size_t n;
    long number;
    struct {
        char *key;
        HostCF *val;
    } ent[32];
    int nent;
    HostCF *item[32];
    int nitem;
};

enum { H_STR, H_DATA, H_DICT, H_ARR, H_NUM };

static HostCF *hnew(int kind)
{
    HostCF *o = calloc(1, sizeof *o);
    if (o)
        o->kind = kind, o->refs = 1;
    return o;
}

static void retain(HostCF *o)
{
    if (o)
        o->refs++;
}

void sf_cf_release(void *object)
{
    HostCF *o = object;
    int i;
    if (!o)
        return;
    if (--o->refs > 0)
        return;
    if (o->kind == H_DICT) {
        for (i = 0; i < o->nent; i++) {
            free(o->ent[i].key);
            sf_cf_release(o->ent[i].val);
        }
    } else if (o->kind == H_ARR) {
        for (i = 0; i < o->nitem; i++)
            sf_cf_release(o->item[i]);
    }
    free(o->text);
    free(o->data);
    free(o);
}

void *sf_cf_empty_string(void)
{
    HostCF *o = hnew(H_STR);
    if (o)
        o->text = calloc(1, 1);
    return o;
}

void *sf_cf_string_utf8(const char *bytes, size_t n)
{
    HostCF *o = hnew(H_STR);
    if (!o)
        return NULL;
    o->text = calloc(1, n + 1);
    if (!o->text) {
        sf_cf_release(o);
        return NULL;
    }
    if (n)
        memcpy(o->text, bytes, n);
    return o;
}

void *sf_cf_data(const uint8_t *bytes, size_t n)
{
    HostCF *o = hnew(H_DATA);
    if (!o)
        return NULL;
    o->data = malloc(n ? n : 1);
    if (!o->data) {
        sf_cf_release(o);
        return NULL;
    }
    if (n)
        memcpy(o->data, bytes, n);
    o->n = n;
    return o;
}

void *sf_cf_dict(void) { return hnew(H_DICT); }
void *sf_cf_array(void) { return hnew(H_ARR); }

void *sf_cf_number_long(long value)
{
    HostCF *o = hnew(H_NUM);
    if (o)
        o->number = value;
    return o;
}

void sf_cf_dict_set(void *dict, const char *key, void *value)
{
    HostCF *d = dict;
    int i;
    if (!d || d->kind != H_DICT || !key || d->nent >= 32)
        return;
    for (i = 0; i < d->nent; i++) {
        if (strcmp(d->ent[i].key, key) == 0) {
            sf_cf_release(d->ent[i].val);
            retain(value);
            d->ent[i].val = value;
            return;
        }
    }
    d->ent[d->nent].key = strdup(key);
    retain(value);
    d->ent[d->nent].val = value;
    d->nent++;
}

void sf_cf_array_add(void *array, void *value)
{
    HostCF *a = array;
    if (!a || a->kind != H_ARR || a->nitem >= 32)
        return;
    retain(value);
    a->item[a->nitem++] = value;
}

int sf_cf_string_get_utf8(void *string, char *buf, size_t n)
{
    HostCF *s = string;
    if (!s || s->kind != H_STR || !s->text || !buf || n == 0)
        return 0;
    snprintf(buf, n, "%s", s->text);
    return 1;
}

void *sf_cf_dict_get(void *dict, const char *key)
{
    HostCF *d = dict;
    int i;
    if (!d || d->kind != H_DICT || !key)
        return NULL;
    for (i = 0; i < d->nent; i++)
        if (strcmp(d->ent[i].key, key) == 0)
            return d->ent[i].val;
    return NULL;
}

long sf_cf_number_value(void *number)
{
    HostCF *n = number;
    return n && n->kind == H_NUM ? n->number : 0;
}

size_t sf_cf_array_count(void *array)
{
    HostCF *a = array;
    return a && a->kind == H_ARR ? (size_t)a->nitem : 0;
}

void *sf_cf_array_at(void *array, size_t index)
{
    HostCF *a = array;
    if (!a || a->kind != H_ARR || index >= (size_t)a->nitem)
        return NULL;
    return a->item[index];
}

typedef struct {
    const uint8_t *p;
    size_t n;
} Prov;

int sf_copy_provider(void *provider, uint8_t **bytes, size_t *n)
{
    Prov *p = provider;
    if (!p || !p->p || !bytes || !n)
        return 0;
    *bytes = malloc(p->n ? p->n : 1);
    if (!*bytes)
        return 0;
    if (p->n)
        memcpy(*bytes, p->p, p->n);
    *n = p->n;
    return 1;
}

typedef struct {
    uint8_t *data;
    size_t w, h, stride;
    double ctm[6];
} Bmp;

int sf_bitmap(void *context, uint8_t **data, size_t *width, size_t *height, size_t *stride, double ctm[6])
{
    Bmp *b = context;
    if (!b || !b->data || !data)
        return 0;
    *data = b->data;
    *width = b->w;
    *height = b->h;
    *stride = b->stride;
    memcpy(ctm, b->ctm, sizeof b->ctm);
    return 1;
}

static int g_fails;

static void check(int cond, const char *msg)
{
    if (!cond) {
        fprintf(stderr, "FAIL %s (%s)\n", msg, sf_cgpdf_error());
        g_fails++;
    }
}

static void badd(uint8_t **b, size_t *n, size_t *c, const void *p, size_t m)
{
    if (*n + m + 1 > *c) {
        size_t nc = *c ? *c * 2 : 256;
        uint8_t *nb;
        while (nc < *n + m + 1)
            nc *= 2;
        nb = realloc(*b, nc);
        if (!nb)
            exit(1);
        *b = nb;
        *c = nc;
    }
    if (m)
        memcpy(*b + *n, p, m);
    *n += m;
    (*b)[*n] = 0;
}

static void bstr(uint8_t **b, size_t *n, size_t *c, const char *s) { badd(b, n, c, s, strlen(s)); }

static uint8_t *make_pdf(const uint8_t **objs, const size_t *lens, int count, int info, int encrypt, size_t *outn)
{
    uint8_t *b = NULL;
    size_t n = 0, c = 0, i;
    int *offs = calloc((size_t)count, sizeof(int));
    char line[128];
    bstr(&b, &n, &c, "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n");
    for (i = 0; i < (size_t)count; i++) {
        offs[i] = (int)n;
        snprintf(line, sizeof line, "%zu 0 obj\n", i + 1);
        bstr(&b, &n, &c, line);
        badd(&b, &n, &c, objs[i], lens[i]);
        bstr(&b, &n, &c, "\nendobj\n");
    }
    snprintf(line, sizeof line, "xref\n0 %d\n0000000000 65535 f \n", count + 1);
    {
        size_t xref = n;
        bstr(&b, &n, &c, line);
        for (i = 0; i < (size_t)count; i++) {
            snprintf(line, sizeof line, "%010d 00000 n \n", offs[i]);
            bstr(&b, &n, &c, line);
        }
        snprintf(line, sizeof line, "trailer\n<< /Size %d %s/Root 1 0 R /Info %d 0 R >>\nstartxref\n%zu\n%%%%EOF\n", count + 1, encrypt ? "/Encrypt 9 0 R " : "", info, xref);
        bstr(&b, &n, &c, line);
    }
    free(offs);
    *outn = n;
    return b;
}

static CGPDFDocumentRef open_mem(const uint8_t *p, size_t n)
{
    Prov prov = {p, n};
    return CGPDFDocumentCreateWithProvider((CGDataProviderRef)&prov);
}

static int text_is(CGPDFStringRef s, const char *expect)
{
    char buf[128];
    CFStringRef cf = CGPDFStringCopyTextString(s);
    int ok = sf_cf_string_get_utf8(cf, buf, sizeof buf) && strcmp(buf, expect) == 0;
    sf_cf_release(cf);
    return ok;
}

static void on_tj(CGPDFScannerRef scanner, void *info)
{
    CGPDFStringRef s = NULL;
    char buf[128];
    CFStringRef cf;
    if (!CGPDFScannerPopString(scanner, &s))
        return;
    cf = CGPDFStringCopyTextString(s);
    if (sf_cf_string_get_utf8(cf, buf, sizeof buf))
        strncat(info, buf, 200);
    sf_cf_release(cf);
}

static void on_tf(CGPDFScannerRef scanner, void *info)
{
    CGPDFReal size = 0;
    const char *name = NULL;
    double *out = info;
    if (CGPDFScannerPopNumber(scanner, &size) && CGPDFScannerPopName(scanner, &name))
        *out = size;
    (void)name;
}

static void count_colors(const uint8_t *px, size_t n, int *red, int *green, int *blue, int *dark)
{
    size_t i;
    *red = *green = *blue = *dark = 0;
    for (i = 0; i + 3 < n; i += 4) {
        if (px[i] > 200 && px[i + 1] < 30 && px[i + 2] < 30)
            (*red)++;
        else if (px[i + 1] > 200 && px[i] < 30 && px[i + 2] < 30)
            (*green)++;
        else if (px[i + 2] > 200 && px[i] < 30 && px[i + 1] < 30)
            (*blue)++;
        else if (px[i] < 40 && px[i + 1] < 40 && px[i + 2] < 40 && px[i + 3])
            (*dark)++;
    }
}

static uint8_t *stream_obj(const uint8_t *content, size_t clen, size_t *outn)
{
    char head[64];
    uint8_t *b = NULL;
    size_t n = 0, c = 0;
    snprintf(head, sizeof head, "<< /Length %zu >>\nstream\n", clen);
    bstr(&b, &n, &c, head);
    badd(&b, &n, &c, content, clen);
    bstr(&b, &n, &c, "endstream");
    *outn = n;
    return b;
}

static void test_one_page(const uint8_t *pdf, size_t n)
{
    CGPDFDocumentRef doc = open_mem(pdf, n);
    CGPDFPageRef page;
    CGPDFDictionaryRef info;
    CGPDFStringRef title = NULL;
    CGRect box, big, small;
    CGAffineTransform t;
    int major = 0, minor = 0;
    char text[256];
    double tsize = 0;
    CGPDFOperatorTableRef table;
    CGPDFContentStreamRef cs;
    CGPDFScannerRef scanner;
    CGPDFObjectRef font;
    check(doc != NULL, "open one-page fixture");
    if (!doc)
        return;
    CGPDFDocumentGetVersion(doc, &major, &minor);
    check(major == 1 && minor == 4, "version 1.4");
    check(CGPDFDocumentGetNumberOfPages(doc) == 1, "one page");
    check(!CGPDFDocumentIsEncrypted(doc), "unencrypted");
    check(CGPDFDocumentIsUnlocked(doc), "unlocked");
    check(CGPDFDocumentUnlockWithPassword(doc, "nope"), "unencrypted unlock succeeds");
    check(CGPDFDocumentGetAccessPermissions(doc) == 0xff, "unencrypted permissions");
    check(CGPDFDocumentAllowsPrinting(doc) && CGPDFDocumentAllowsCopying(doc), "print and copy");
    info = CGPDFDocumentGetInfo(doc);
    check(info && CGPDFDictionaryGetString(info, "Title", &title) && text_is(title, "Finch fixture"), "title text");
    page = CGPDFDocumentGetPage(doc, 1);
    check(page && CGPDFPageGetPageNumber(page) == 1, "page number");
    check(CGPDFDocumentGetPage(doc, 0) == NULL, "page 0 is absent");
    box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    check(box.origin.x == 0 && box.origin.y == 0 && box.size.width == 72 && box.size.height == 72, "media box 72");
    check(CGPDFPageGetRotationAngle(page) == 0, "rotation 0");
    t = CGPDFPageGetDrawingTransform(page, kCGPDFMediaBox, box, 0, true);
    check(t.a == 1 && t.d == 1 && t.tx == 0 && t.ty == 0 && t.b == 0 && t.c == 0, "identity drawing transform");
    big = box;
    big.size.width = 144;
    big.size.height = 144;
    t = CGPDFPageGetDrawingTransform(page, kCGPDFMediaBox, big, 0, true);
    check(t.a == 1 && t.d == 1 && t.tx == 36 && t.ty == 36, "never scales up");
    small = box;
    small.size.width = 36;
    small.size.height = 36;
    t = CGPDFPageGetDrawingTransform(page, kCGPDFMediaBox, small, 0, true);
    check(t.a == 0.5 && t.d == 0.5 && t.tx == 0 && t.ty == 0, "scales down to fit");
    check(CGPDFDocumentGetOutline(doc) == NULL, "no outline");
    cs = CGPDFContentStreamCreateWithPage(page);
    font = CGPDFContentStreamGetResource(cs, "Font", "F1");
    check(font != NULL, "font resource F1");
    text[0] = 0;
    table = CGPDFOperatorTableCreate();
    CGPDFOperatorTableSetCallback(table, "Tj", on_tj);
    CGPDFOperatorTableSetCallback(table, "Tf", on_tf);
    scanner = CGPDFScannerCreate(cs, table, text);
    check(CGPDFScannerScan(scanner), "scan");
    check(strcmp(text, "Finch PDF fixture") == 0, "extracted text");
    CGPDFScannerRelease(scanner);
    scanner = CGPDFScannerCreate(cs, table, &tsize);
    CGPDFOperatorTableSetCallback(table, "Tj", NULL);
    CGPDFOperatorTableSetCallback(table, "Tf", on_tf);
    check(CGPDFScannerScan(scanner), "scan font");
    check(tsize == 6, "Tf promotes integer 6 to CGPDFReal");
    CGPDFScannerRelease(scanner);
    CGPDFOperatorTableRelease(table);
    CGPDFContentStreamRelease(cs);
    CGPDFDocumentRelease(doc);
}

static void test_view(void)
{
    const char *colors[] = {"1 0 0", "0 1 0", "0 0 1"};
    const char *labels[] = {"Field notes", "Canopy survey", "River crossing"};
    uint8_t *objs_store[16];
    const uint8_t *objs[16];
    size_t lens[16];
    int i, nobj = 0;
    uint8_t *pdf;
    size_t pn = 0;
    CGPDFDocumentRef doc;
    char head[256];
    objs_store[nobj] = (uint8_t *)strdup("<< /Type /Catalog /Pages 2 0 R >>");
    lens[nobj] = strlen((char *)objs_store[nobj]);
    objs[nobj] = objs_store[nobj];
    nobj++;
    objs_store[nobj] = (uint8_t *)strdup("<< /Type /Pages /Count 3 /Kids [5 0 R 7 0 R 9 0 R] >>");
    lens[nobj] = strlen((char *)objs_store[nobj]);
    objs[nobj] = objs_store[nobj];
    nobj++;
    objs_store[nobj] = (uint8_t *)strdup("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
    lens[nobj] = strlen((char *)objs_store[nobj]);
    objs[nobj] = objs_store[nobj];
    nobj++;
    objs_store[nobj] = (uint8_t *)strdup("<< /Title (SiliconForest reading test) >>");
    lens[nobj] = strlen((char *)objs_store[nobj]);
    objs[nobj] = objs_store[nobj];
    nobj++;
    for (i = 0; i < 3; i++) {
        char content[256];
        uint8_t *st;
        size_t sl = 0;
        int stream_id = nobj + 2;
        snprintf(content, sizeof content, "%s rg 48 60 144 60 re f\n0 0 0 rg BT /F1 20 Tf 32 148 Td (%s) Tj ET\n", colors[i], labels[i]);
        snprintf(head, sizeof head, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 180] /Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>", stream_id);
        objs_store[nobj] = (uint8_t *)strdup(head);
        lens[nobj] = strlen(head);
        objs[nobj] = objs_store[nobj];
        nobj++;
        st = stream_obj((const uint8_t *)content, strlen(content), &sl);
        objs_store[nobj] = st;
        lens[nobj] = sl;
        objs[nobj] = st;
        nobj++;
    }
    pdf = make_pdf(objs, lens, nobj, 4, 0, &pn);
    doc = open_mem(pdf, pn);
    check(doc && CGPDFDocumentGetNumberOfPages(doc) == 3, "view fixture has 3 pages");
    if (doc) {
        for (i = 0; i < 3; i++) {
            CGPDFPageRef page = CGPDFDocumentGetPage(doc, (size_t)i + 1);
            Bmp bmp;
            int red = 0, green = 0, blue = 0, dark = 0;
            char extracted[128];
            CGPDFOperatorTableRef table;
            CGPDFContentStreamRef cs;
            CGPDFScannerRef scanner;
            memset(&bmp, 0, sizeof bmp);
            bmp.w = 240;
            bmp.h = 180;
            bmp.stride = 240 * 4;
            bmp.data = calloc(1, bmp.stride * bmp.h);
            bmp.ctm[0] = bmp.ctm[3] = 1;
            CGContextDrawPDFPage((CGContextRef)&bmp, page);
            count_colors(bmp.data, bmp.stride * bmp.h, &red, &green, &blue, &dark);
            if (i == 0)
                check(red > 8000 && red < 9000 && green == 0 && blue == 0, "page 1 red rectangle");
            if (i == 1)
                check(green > 8000 && green < 9000 && red == 0 && blue == 0, "page 2 green rectangle");
            if (i == 2)
                check(blue > 8000 && blue < 9000 && red == 0 && green == 0, "page 3 blue rectangle");
            check(dark > 20 && dark < 8000, "glyph ink from the page label");
            check(bmp.data[0] == 0 && bmp.data[1] == 0 && bmp.data[2] == 0, "corner stays unpainted");
            extracted[0] = 0;
            table = CGPDFOperatorTableCreate();
            CGPDFOperatorTableSetCallback(table, "Tj", on_tj);
            cs = CGPDFContentStreamCreateWithPage(page);
            scanner = CGPDFScannerCreate(cs, table, extracted);
            CGPDFScannerScan(scanner);
            check(strcmp(extracted, labels[i]) == 0, "view page text");
            CGPDFScannerRelease(scanner);
            CGPDFContentStreamRelease(cs);
            CGPDFOperatorTableRelease(table);
            free(bmp.data);
        }
        CGPDFDocumentRelease(doc);
    }
    free(pdf);
    for (i = 0; i < nobj; i++)
        free(objs_store[i]);
}

static void test_encrypted(void)
{
    const char *bodies[] = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] >>",
        "<< /Title (Secret) >>"};
    const uint8_t *objs[4];
    size_t lens[4];
    int i;
    uint8_t *pdf;
    size_t n = 0;
    CGPDFDocumentRef doc;
    CGPDFPageRef page;
    CGRect box;
    for (i = 0; i < 4; i++) {
        objs[i] = (const uint8_t *)bodies[i];
        lens[i] = strlen(bodies[i]);
    }
    pdf = make_pdf(objs, lens, 4, 4, 1, &n);
    doc = open_mem(pdf, n);
    check(doc && CGPDFDocumentIsEncrypted(doc), "encrypt flag");
    check(doc && !CGPDFDocumentIsUnlocked(doc), "stays locked");
    check(doc && !CGPDFDocumentUnlockWithPassword(doc, "secret"), "unlock fails closed");
    check(doc && CGPDFDocumentGetAccessPermissions(doc) == 0, "locked permissions are zero");
    check(doc && !CGPDFDocumentAllowsPrinting(doc) && !CGPDFDocumentAllowsCopying(doc), "locked denies print and copy");
    page = doc ? CGPDFDocumentGetPage(doc, 1) : NULL;
    check(page != NULL, "locked document still has the page");
    check(page && CGPDFPageGetPageNumber(page) == 0, "locked page number is zero");
    box = page ? CGPDFPageGetBoxRect(page, kCGPDFMediaBox) : (CGRect){0};
    check(!isfinite(box.origin.x), "locked box is null");
    CGPDFDocumentRelease(doc);
    free(pdf);
}

static void test_flate_and_text(void)
{
    const char *plain = "BT (Hi) Tj ET";
    uint8_t zbuf[128];
    uLongf zlen = sizeof zbuf;
    uint8_t *st;
    size_t sl = 0, n = 0;
    const uint8_t *objs[4];
    size_t lens[4];
    uint8_t *pdf;
    CGPDFDocumentRef doc;
    char text[32];
    CGPDFPageRef page;
    CGPDFContentStreamRef cs;
    CGPDFOperatorTableRef table;
    CGPDFScannerRef scanner;
    uint8_t title_raw[] = {'(', 0x80, ')'};
    char title_body[64];
    const uint8_t *tobjs[3];
    size_t tlens[3];
    uint8_t *tpdf;
    size_t tn = 0;
    CGPDFStringRef title = NULL;
    char utf[16];
    CFStringRef cf;
    check(compress(zbuf, &zlen, (const Bytef *)plain, (uLong)strlen(plain)) == Z_OK, "compress fixture text");
    st = stream_obj(zbuf, zlen, &sl);
    /* Filter name has to live in the stream dictionary. Rebuild with Filter. */
    free(st);
    {
        char head[96];
        uint8_t *b = NULL;
        size_t bn = 0, bc = 0;
        snprintf(head, sizeof head, "<< /Length %lu /Filter /FlateDecode >>\nstream\n", (unsigned long)zlen);
        bstr(&b, &bn, &bc, head);
        badd(&b, &bn, &bc, zbuf, zlen);
        bstr(&b, &bn, &bc, "endstream");
        st = b;
        sl = bn;
    }
    objs[0] = (const uint8_t *)"<< /Type /Catalog /Pages 2 0 R >>";
    objs[1] = (const uint8_t *)"<< /Type /Pages /Count 1 /Kids [3 0 R] >>";
    objs[2] = (const uint8_t *)"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] /Contents 4 0 R >>";
    objs[3] = st;
    lens[0] = strlen((const char *)objs[0]);
    lens[1] = strlen((const char *)objs[1]);
    lens[2] = strlen((const char *)objs[2]);
    lens[3] = sl;
    pdf = make_pdf(objs, lens, 4, 4, 0, &n);
    /* Info object 4 was replaced by the stream; drop /Info by pointing at a missing id and ignore title. */
    doc = open_mem(pdf, n);
    page = doc ? CGPDFDocumentGetPage(doc, 1) : NULL;
    text[0] = 0;
    table = CGPDFOperatorTableCreate();
    CGPDFOperatorTableSetCallback(table, "Tj", on_tj);
    cs = CGPDFContentStreamCreateWithPage(page);
    scanner = cs ? CGPDFScannerCreate(cs, table, text) : NULL;
    check(scanner && CGPDFScannerScan(scanner), "scan flate content");
    check(strcmp(text, "Hi") == 0, "flate text is Hi");
    CGPDFScannerRelease(scanner);
    CGPDFContentStreamRelease(cs);
    CGPDFOperatorTableRelease(table);
    CGPDFDocumentRelease(doc);
    free(pdf);
    free(st);

    snprintf(title_body, sizeof title_body, "<< /Title %s >>", "(");
    (void)title_raw;
    tobjs[0] = (const uint8_t *)"<< /Type /Catalog /Pages 2 0 R >>";
    tobjs[1] = (const uint8_t *)"<< /Type /Pages /Count 0 /Kids [] >>";
    {
        uint8_t body[32];
        size_t bl = 0;
        body[bl++] = '<';
        body[bl++] = '<';
        memcpy(body + bl, " /Title <FEFF0041> >>", 20);
        bl += 20;
        /* rebuilt below */
        (void)bl;
    }
    tobjs[2] = (const uint8_t *)"<< /Title <FEFF0041> >>";
    tlens[0] = strlen((const char *)tobjs[0]);
    tlens[1] = strlen((const char *)tobjs[1]);
    tlens[2] = strlen((const char *)tobjs[2]);
    tpdf = make_pdf(tobjs, tlens, 3, 3, 0, &tn);
    doc = open_mem(tpdf, tn);
    title = NULL;
    check(doc && CGPDFDictionaryGetString(CGPDFDocumentGetInfo(doc), "Title", &title), "utf16 title string");
    cf = CGPDFStringCopyTextString(title);
    check(sf_cf_string_get_utf8(cf, utf, sizeof utf) && strcmp(utf, "A") == 0, "utf16 title is A");
    sf_cf_release(cf);
    CGPDFDocumentRelease(doc);
    free(tpdf);

    tobjs[2] = (const uint8_t *)"<< /Title (\200) >>";
    tlens[2] = strlen((const char *)tobjs[2]);
    /* \200 in a C string is not byte 0x80. Build the bytes explicitly. */
    {
        uint8_t body[] = {'<', '<', ' ', '/', 'T', 'i', 't', 'l', 'e', ' ', '(', 0x80, ')', ' ', '>', '>'};
        uint8_t *owned = malloc(sizeof body);
        memcpy(owned, body, sizeof body);
        tobjs[2] = owned;
        tlens[2] = sizeof body;
        tpdf = make_pdf(tobjs, tlens, 3, 3, 0, &tn);
        doc = open_mem(tpdf, tn);
        title = NULL;
        check(doc && CGPDFDictionaryGetString(CGPDFDocumentGetInfo(doc), "Title", &title), "pdfdoc title");
        cf = CGPDFStringCopyTextString(title);
        check(sf_cf_string_get_utf8(cf, utf, sizeof utf) && strcmp(utf, "\xE2\x80\xA2") == 0, "pdfdoc 0x80 is a bullet");
        sf_cf_release(cf);
        CGPDFDocumentRelease(doc);
        free(tpdf);
        free(owned);
    }
}

static void test_outline_and_rotate(void)
{
    const char *bodies[] = {
        "<< /Type /Catalog /Pages 2 0 R /Outlines 4 0 R >>",
        "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] /Rotate 90 >>",
        "<< /Type /Outlines /First 5 0 R /Count 1 >>",
        "<< /Title (Notes) /Dest [3 0 R /Fit] /Parent 4 0 R >>",
        "<< /Title (Ignored) >>"};
    const uint8_t *objs[6];
    size_t lens[6];
    int i;
    uint8_t *pdf;
    size_t n = 0;
    CGPDFDocumentRef doc;
    CFDictionaryRef outline;
    void *kids, *item, *dest;
    char title[32];
    CGAffineTransform t;
    CGRect rect;
    for (i = 0; i < 6; i++) {
        objs[i] = (const uint8_t *)bodies[i];
        lens[i] = strlen(bodies[i]);
    }
    pdf = make_pdf(objs, lens, 6, 6, 0, &n);
    doc = open_mem(pdf, n);
    check(doc != NULL, "outline document opens");
    outline = doc ? CGPDFDocumentGetOutline(doc) : NULL;
    kids = outline ? sf_cf_dict_get(outline, "Children") : NULL;
    check(kids && sf_cf_array_count(kids) == 1, "one outline child");
    item = kids ? sf_cf_array_at(kids, 0) : NULL;
    check(item && sf_cf_string_get_utf8(sf_cf_dict_get(item, "Title"), title, sizeof title) && strcmp(title, "Notes") == 0, "outline title");
    dest = item ? sf_cf_dict_get(item, "Destination") : NULL;
    check(dest && sf_cf_number_value(dest) == 1, "outline destination page 1");
    rect = CGPDFPageGetBoxRect(CGPDFDocumentGetPage(doc, 1), kCGPDFMediaBox);
    t = CGPDFPageGetDrawingTransform(CGPDFDocumentGetPage(doc, 1), kCGPDFMediaBox, rect, 0, true);
    check(t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 && t.tx == 0 && t.ty == 72, "90 degree drawing transform");
    check(CGPDFPageGetRotationAngle(CGPDFDocumentGetPage(doc, 1)) == 90, "rotation left as written");
    CGPDFDocumentRelease(doc);
    free(pdf);
}

static void test_nulls(void)
{
    int major = 7, minor = 7;
    check(CGPDFDocumentCreateWithProvider(NULL) == NULL, "null provider");
    check(!CGPDFDocumentIsEncrypted(NULL), "null is not encrypted");
    check(CGPDFDocumentIsUnlocked(NULL), "null reports unlocked");
    check(!CGPDFDocumentUnlockWithPassword(NULL, ""), "null unlock fails");
    check(CGPDFDocumentGetAccessPermissions(NULL) == 0, "null permissions are zero");
    CGPDFDocumentGetVersion(NULL, &major, &minor);
    check(major == 0 && minor == 0, "null version is zero");
    check(sizeof(CGPDFInteger) == 8 && sizeof(CGPDFReal) == 8 && sizeof(CGRect) == 32, "host LP64 widths");
}

int main(int argc, char **argv)
{
    int i;
    test_nulls();
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        uint8_t *buf;
        long sz;
        if (!f) {
            check(0, argv[i]);
            continue;
        }
        fseek(f, 0, SEEK_END);
        sz = ftell(f);
        fseek(f, 0, SEEK_SET);
        buf = malloc((size_t)sz);
        check(buf && fread(buf, 1, (size_t)sz, f) == (size_t)sz, "read fixture");
        fclose(f);
        if (buf)
            test_one_page(buf, (size_t)sz);
        free(buf);
    }
    test_view();
    test_encrypted();
    test_flate_and_text();
    test_outline_and_rotate();
    if (g_fails) {
        fprintf(stderr, "%d checks failed\n", g_fails);
        return 1;
    }
    printf("sf-cgpdf host checks passed\n");
    return 0;
}
