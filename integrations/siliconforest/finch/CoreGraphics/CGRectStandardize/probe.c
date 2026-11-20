// SPDX-License-Identifier: MIT OR Apache-2.0
// Headless CGRectStandardize probe. Does not launch an app.
// The reference is the provider's own null, infinite, and CGRectNull
// exports plus the retained negative-extent rule. Existing geometry calls
// are compared with the untouched base image.

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;

typedef CGRect (*rect_fn)(CGRect);
typedef CGRect (*rect2_fn)(CGRect, CGRect);
typedef _Bool (*bool_fn)(CGRect);
typedef _Bool (*eq_fn)(CGRect, CGRect);

void *dlopen(const char *path, int mode);
void *dlsym(void *handle, const char *symbol);
char *dlerror(void);
int snprintf(char *str, unsigned long size, const char *fmt, ...);
int write(int fd, const void *buf, unsigned long n);
char *getenv(const char *name);

static int g_fail;

static void say(const char *text) {
    unsigned long n = 0;
    while (text[n] != 0)
        n++;
    write(1, text, n);
}

static void line(const char *text) {
    say(text);
    write(1, "\n", 1);
}

static int deq(CGFloat a, CGFloat b) {
    return a == b || (a != a && b != b);
}

static int same(CGRect a, CGRect b) {
    return deq(a.origin.x, b.origin.x) && deq(a.origin.y, b.origin.y) &&
        deq(a.size.width, b.size.width) && deq(a.size.height, b.size.height);
}

static CGRect reference(CGRect rect, bool_fn is_null, bool_fn is_infinite, const CGRect *null_rect) {
    if (is_null(rect))
        return *null_rect;
    if (is_infinite(rect))
        return rect;
    if (rect.size.width < 0) {
        rect.origin.x += rect.size.width;
        rect.size.width = -rect.size.width;
    }
    if (rect.size.height < 0) {
        rect.origin.y += rect.size.height;
        rect.size.height = -rect.size.height;
    }
    return rect;
}

static CGRect R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    CGRect rect;
    rect.origin.x = x;
    rect.origin.y = y;
    rect.size.width = w;
    rect.size.height = h;
    return rect;
}

static void expect_numbers(rect_fn standardize, CGRect input, CGRect expect, const char *name) {
    CGRect got = standardize(input);
    char buf[256];
    if (same(got, expect)) {
        snprintf(buf, sizeof buf, "PASS %s", name);
        line(buf);
        return;
    }
    g_fail++;
    snprintf(buf, sizeof buf,
             "FAIL %s got %.17g,%.17g %.17g,%.17g expect %.17g,%.17g %.17g,%.17g",
             name, got.origin.x, got.origin.y, got.size.width, got.size.height,
             expect.origin.x, expect.origin.y, expect.size.width, expect.size.height);
    line(buf);
}

static void expect_ref(rect_fn standardize, bool_fn is_null, bool_fn is_infinite,
                       const CGRect *null_rect, CGRect input, const char *name) {
    expect_numbers(standardize, input, reference(input, is_null, is_infinite, null_rect), name);
}

static void *need(void *image, const char *symbol) {
    void *found = dlsym(image, symbol);
    char buf[192];
    if (found != 0) {
        snprintf(buf, sizeof buf, "PASS symbol %s", symbol);
        line(buf);
        return found;
    }
    g_fail++;
    snprintf(buf, sizeof buf, "FAIL symbol %s missing", symbol);
    line(buf);
    return 0;
}

int main(void) {
    const char *wrapper_path = getenv("CG_WRAPPER");
    const char *base_path = getenv("CG_BASE");
    void *wrapper;
    void *base;
    rect_fn standardize;
    rect2_fn inter_w, inter_b, union_w, union_b;
    bool_fn empty_w, empty_b, null_b, infinite_b;
    eq_fn equal_w, equal_b;
    const CGRect *null_rect;
    const CGRect *infinite_rect;
    const CGRect *zero_rect;
    CGRect samples[8];
    int i, j;
    char buf[256];

    if (wrapper_path == 0 || base_path == 0) {
        line("FAIL missing CG_WRAPPER or CG_BASE");
        return 1;
    }
    wrapper = dlopen(wrapper_path, 2);
    if (wrapper == 0) {
        line("FAIL dlopen wrapper");
        say(dlerror() ? dlerror() : "unknown");
        write(1, "\n", 1);
        return 1;
    }
    base = dlopen(base_path, 6);
    if (base == 0) {
        line("FAIL dlopen base");
        say(dlerror() ? dlerror() : "unknown");
        write(1, "\n", 1);
        return 1;
    }
    if (dlsym(base, "CGRectStandardize") != 0) {
        line("FAIL base already exports CGRectStandardize");
        g_fail++;
    } else {
        line("PASS base has no CGRectStandardize");
    }

    standardize = (rect_fn)need(wrapper, "CGRectStandardize");
    inter_w = (rect2_fn)need(wrapper, "CGRectIntersection");
    union_w = (rect2_fn)need(wrapper, "CGRectUnion");
    empty_w = (bool_fn)need(wrapper, "CGRectIsEmpty");
    equal_w = (eq_fn)need(wrapper, "CGRectEqualToRect");
    inter_b = (rect2_fn)need(base, "CGRectIntersection");
    union_b = (rect2_fn)need(base, "CGRectUnion");
    empty_b = (bool_fn)need(base, "CGRectIsEmpty");
    equal_b = (eq_fn)need(base, "CGRectEqualToRect");
    null_b = (bool_fn)need(base, "CGRectIsNull");
    infinite_b = (bool_fn)need(base, "CGRectIsInfinite");
    null_rect = (const CGRect *)need(base, "CGRectNull");
    infinite_rect = (const CGRect *)need(base, "CGRectInfinite");
    zero_rect = (const CGRect *)need(base, "CGRectZero");
    if (g_fail)
        goto done;

    snprintf(buf, sizeof buf,
             "INFO null %.17g,%.17g %.17g,%.17g null=%d empty=%d infinite=%d",
             null_rect->origin.x, null_rect->origin.y, null_rect->size.width, null_rect->size.height,
             (int)null_b(*null_rect), (int)empty_b(*null_rect), (int)infinite_b(*null_rect));
    line(buf);
    snprintf(buf, sizeof buf,
             "INFO infinite %.17g,%.17g %.17g,%.17g null=%d empty=%d infinite=%d",
             infinite_rect->origin.x, infinite_rect->origin.y, infinite_rect->size.width, infinite_rect->size.height,
             (int)null_b(*infinite_rect), (int)empty_b(*infinite_rect), (int)infinite_b(*infinite_rect));
    line(buf);
    snprintf(buf, sizeof buf,
             "INFO zero %.17g,%.17g %.17g,%.17g null=%d empty=%d infinite=%d",
             zero_rect->origin.x, zero_rect->origin.y, zero_rect->size.width, zero_rect->size.height,
             (int)null_b(*zero_rect), (int)empty_b(*zero_rect), (int)infinite_b(*zero_rect));
    line(buf);

    expect_numbers(standardize, R(10, 20, -5, -8), R(5, 12, 5, 8), "negative-both");
    expect_numbers(standardize, R(1, 2, 3, 4), R(1, 2, 3, 4), "positive");
    expect_numbers(standardize, R(4, 5, -2, 6), R(2, 5, 2, 6), "negative-width");
    expect_numbers(standardize, R(4, 8, 2, -3), R(4, 5, 2, 3), "negative-height");
    expect_numbers(standardize, R(1, 2, -0.5, -0.25), R(0.5, 1.75, 0.5, 0.25), "negative-fraction");
    expect_numbers(standardize, R(0, 0, 0, 5), R(0, 0, 0, 5), "empty-width");
    expect_numbers(standardize, R(2, 3, 5, 0), R(2, 3, 5, 0), "empty-height");
    expect_numbers(standardize, R(-1, -1, 0, 0), R(-1, -1, 0, 0), "empty-origin");
    expect_numbers(standardize, R(9, 3, -4, 0), R(5, 3, 4, 0), "empty-after-negative-width");
    expect_ref(standardize, null_b, infinite_b, null_rect, *null_rect, "null-constant");
    expect_ref(standardize, null_b, infinite_b, null_rect, *infinite_rect, "infinite-constant");
    expect_ref(standardize, null_b, infinite_b, null_rect, *zero_rect, "zero-constant");
    expect_ref(standardize, null_b, infinite_b, null_rect, R(1.0 / 0.0, 3, 4, 5), "null-origin-x");
    expect_ref(standardize, null_b, infinite_b, null_rect, R(1, -1.0 / 0.0, -2, 4), "null-origin-y");
    expect_ref(standardize, null_b, infinite_b, null_rect, R(0.0 / 0.0, 1, -2, 3), "nan-origin");
    expect_ref(standardize, null_b, infinite_b, null_rect, R(8, 9, 0.0 / 0.0, -3), "nan-width");

    if (!empty_w(*null_rect) || !empty_w(R(0, 0, 0, 5)) || empty_w(R(1, 2, 3, 4))) {
        line("FAIL empty classification");
        g_fail++;
    } else {
        line("PASS empty classification");
    }
    if (empty_w(standardize(R(10, 20, -5, -8))) || !empty_w(standardize(R(9, 3, -4, 0)))) {
        line("FAIL empty after standardize");
        g_fail++;
    } else {
        line("PASS empty after standardize");
    }

    samples[0] = R(1, 2, 3, 4);
    samples[1] = R(10, 20, -5, -8);
    samples[2] = R(0, 0, 0, 5);
    samples[3] = *null_rect;
    samples[4] = *infinite_rect;
    samples[5] = *zero_rect;
    samples[6] = R(4, 8, 2, -3);
    samples[7] = R(-1, -1, 0, 0);
    for (i = 0; i < 8; i++) {
        if (empty_w(samples[i]) != empty_b(samples[i])) {
            line("FAIL IsEmpty diverged from base");
            g_fail++;
            break;
        }
        for (j = 0; j < 8; j++) {
            if (!same(inter_w(samples[i], samples[j]), inter_b(samples[i], samples[j])) ||
                !same(union_w(samples[i], samples[j]), union_b(samples[i], samples[j])) ||
                equal_w(samples[i], samples[j]) != equal_b(samples[i], samples[j])) {
                snprintf(buf, sizeof buf, "FAIL retained geometry i=%d j=%d", i, j);
                line(buf);
                g_fail++;
                i = 8;
                break;
            }
        }
    }
    if (g_fail == 0)
        line("PASS retained intersection union empty equality");

done:
    if (g_fail) {
        snprintf(buf, sizeof buf, "CGRECT STANDARDIZE PROBE FAIL %d", g_fail);
        line(buf);
        return 1;
    }
    line("CGRECT STANDARDIZE PROBE PASS");
    return 0;
}
