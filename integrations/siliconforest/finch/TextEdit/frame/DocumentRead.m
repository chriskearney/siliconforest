/* SPDX-License-Identifier: MIT
   TextEdit reads a file with readFromURL:options:documentAttributes:error:,
   which the dock AppKit does not implement. initWithURL: on
   NSAttributedString only raises. NSRichTextReader's
   attributedStringWithData: is the reader that parses RTF. The menu nib
   also binds NSMenuItem.objectValue, and that key is missing. */
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern NSString * const NSDocumentTypeDocumentAttribute;
extern NSString * const NSRTFTextDocumentType;

@interface NSMutableAttributedString (SFTextEditRead)
- (void)setAttributedString:(NSAttributedString *)attrString;
@end

static void sf_read_log(const char *msg)
{
    if (!getenv("SF_LOG_EXC"))
        return;
    fprintf(stderr, "SF_TE_READ %s\n", msg);
    fflush(stderr);
}

/* This NSRichTextReader has no table destination: \trowd, \cellx and \intbl
   are dropped and the cell text runs together. The file stays a real RTF
   table. Before the reader sees it, each row becomes one paragraph and the
   cells are joined by \u9 (a real tab). The same column stops are applied
   to that paragraph and stroked as a grid after the text view draws. */
static const double SF_TABLE_RIGHT = 620.0;

/* Interior tab positions for `tabs` separators. The right edge is the
   border, not a place text lands. Two- and three-column notes are the
   ones these documents use; a wider row shares the width evenly. */
static int sf_stops_for_tabs(int tabs, double *stops)
{
    if (tabs == 1) {
        stops[0] = 196.0;
        return 1;
    }
    if (tabs == 2) {
        stops[0] = 158.0;
        stops[1] = 328.0;
        return 2;
    }
    if (tabs < 1 || tabs > 6)
        return 0;
    double col = SF_TABLE_RIGHT / (double)(tabs + 1);
    for (int i = 0; i < tabs; i++)
        stops[i] = col * (double)(i + 1);
    return tabs;
}
static int sf_word(const unsigned char *bytes, NSUInteger n, NSUInteger i, const char *word)
{
    size_t len = strlen(word);
    if (i + len > n || memcmp(bytes + i, word, len) != 0)
        return 0;
    if (i + len < n && ((bytes[i + len] >= 'a' && bytes[i + len] <= 'z') || (bytes[i + len] >= 'A' && bytes[i + len] <= 'Z')))
        return 0;
    return 1;
}

static NSData *sf_expand_tables(NSData *data)
{
    const unsigned char *bytes = [data bytes];
    NSUInteger n = [data length];
    NSMutableData *out = [NSMutableData dataWithCapacity:n + 64];
    NSUInteger i = 0;
    while (i < n) {
        if (!sf_word(bytes, n, i, "\\trowd")) {
            [out appendBytes:bytes + i length:1];
            i++;
            continue;
        }
        NSUInteger row = i + 6;
        NSUInteger end = row;
        while (end < n && !sf_word(bytes, n, end, "\\row"))
            end++;
        if (end >= n)
            break;
        /* The paragraph before the row already ended. A leading \par here
           would insert a blank line between every row of the grid. */
        NSMutableString *line = [NSMutableString string];
        NSUInteger cursor = row;
        int cells = 0;
        while (cursor < end && cells < 8) {
            NSUInteger at = cursor;
            int found = 0;
            while (at < end) {
                if (sf_word(bytes, n, at, "\\intbl")) {
                    found = 1;
                    break;
                }
                at++;
            }
            if (!found)
                break;
            at += 6;
            NSUInteger cell = at;
            while (cell < end && !sf_word(bytes, n, cell, "\\cell"))
                cell++;
            if (cell >= end)
                break;
            if (cells)
                [line appendString:@"\\u9?  "];
            NSString *body = [[NSString alloc] initWithBytes:bytes + at length:cell - at encoding:NSUTF8StringEncoding];
            if (body)
                [line appendString:body];
            [body release];
            cells++;
            cursor = cell + 5;
        }
        [line appendString:@"\\par\n"];
        [out appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        i = end + 4;
    }
    if (i < n)
        [out appendBytes:bytes + i length:n - i];
    return out;
}

static id sf_paragraph_style_name(void)
{
    static id name;
    static int looked;
    if (!looked) {
        looked = 1;
        void *sym = dlsym(RTLD_DEFAULT, "NSParagraphStyleAttributeName");
        if (sym)
            name = *(id *)sym;
    }
    return name;
}

static int sf_tab_count(NSString *slice)
{
    int tabs = 0;
    NSUInteger n = [slice length];
    for (NSUInteger i = 0; i < n; i++) {
        if ([slice characterAtIndex:i] == (unichar)'\t')
            tabs++;
    }
    return tabs;
}

static id sf_style_for_tabs(int tabs)
{
    static id cache[8];
    if (tabs < 1 || tabs > 6)
        return nil;
    if (cache[tabs])
        return cache[tabs];
    Class tabClass = objc_lookUpClass("NSTextTab");
    Class styleClass = objc_lookUpClass("NSMutableParagraphStyle");
    if (!tabClass || !styleClass)
        return nil;
    double where[8];
    int n = sf_stops_for_tabs(tabs, where);
    if (n <= 0)
        return nil;
    id style = [[styleClass alloc] init];
    NSMutableArray *stops = [NSMutableArray array];
    for (int s = 0; s < n; s++) {
        id tab = ((id (*)(id, SEL, long, double))objc_msgSend)(
            [tabClass alloc], sel_registerName("initWithType:location:"), (long)0, where[s]);
        if (tab)
            [stops addObject:tab];
        [tab release];
    }
    /* One stop past the last column so a default interval cannot open
       another column inside the border. */
    id edge = ((id (*)(id, SEL, long, double))objc_msgSend)(
        [tabClass alloc], sel_registerName("initWithType:location:"), (long)0, SF_TABLE_RIGHT);
    if (edge)
        [stops addObject:edge];
    [edge release];
    ((void (*)(id, SEL, id))objc_msgSend)(style, sel_registerName("setTabStops:"), stops);
    /* Eight points of air inside the left border. The next column's text
       starts at the tab, so the vertical gridline sits on that stop. */
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setHeadIndent:"), 8.0);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setFirstLineHeadIndent:"), 8.0);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setMinimumLineHeight:"), 16.0);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setMaximumLineHeight:"), 16.0);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setParagraphSpacing:"), 0.0);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setParagraphSpacingBefore:"), 0.0);
    ((void (*)(id, SEL, long))objc_msgSend)(style, sel_registerName("setLineBreakMode:"), (long)2);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setDefaultTabInterval:"), 1200.0);
    cache[tabs] = style;
    return style;
}

static id sf_font_name(void)
{
    static id name;
    static int looked;
    if (!looked) {
        looked = 1;
        void *sym = dlsym(RTLD_DEFAULT, "NSFontAttributeName");
        if (sym)
            name = *(id *)sym;
    }
    return name;
}

/* The reader drops \sa, \sb, \pard, \li and \fi. Line height and the gap
   around a heading are applied here so the grid cursor and the glyphs
   share one set of numbers. kind: 0 title, 1 section, 2 body, 3 code. */
static id sf_metric_style(int kind)
{
    static id cache[4];
    if (kind < 0 || kind > 3)
        kind = 2;
    if (cache[kind])
        return cache[kind];
    Class styleClass = objc_lookUpClass("NSMutableParagraphStyle");
    if (!styleClass)
        return nil;
    double line = 15.0, before = 0.0, after = 1.0;
    if (kind == 0) {
        line = 22.0;
        after = 2.0;
    } else if (kind == 1) {
        line = 16.0;
        before = 6.0;
        after = 1.0;
    } else if (kind == 3) {
        line = 14.0;
        before = 1.0;
        after = 1.0;
    }
    id style = [[styleClass alloc] init];
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setMinimumLineHeight:"), line);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setMaximumLineHeight:"), line);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setParagraphSpacing:"), after);
    ((void (*)(id, SEL, double))objc_msgSend)(style, sel_registerName("setParagraphSpacingBefore:"), before);
    ((void (*)(id, SEL, long))objc_msgSend)(style, sel_registerName("setLineBreakMode:"), (long)0);
    cache[kind] = style;
    return style;
}

static int sf_kind_for_point(double point)
{
    if (point >= 16.0)
        return 0;
    if (point >= 12.5)
        return 1;
    if (point > 0.0 && point <= 9.5)
        return 3;
    return 2;
}

static double sf_point_size(id storage, NSUInteger index, NSUInteger length)
{
    id name = sf_font_name();
    if (!name || index >= length)
        return 11.0;
    id font = ((id (*)(id, SEL, id, NSUInteger, NSRange *))objc_msgSend)(
        storage, sel_registerName("attribute:atIndex:effectiveRange:"),
        name, index, (NSRange *)0);
    if (!font)
        return 11.0;
    double pt = ((double (*)(id, SEL))objc_msgSend)(font, sel_registerName("pointSize"));
    if (pt < 6.0 || pt > 48.0)
        return 11.0;
    return pt;
}

static void sf_apply_table_tabs(id loaded)
{
    id styleName = sf_paragraph_style_name();
    NSString *text = ((id (*)(id, SEL))objc_msgSend)(loaded, sel_registerName("string"));
    if (!text || !styleName)
        return;
    NSUInteger length = [text length];
    NSUInteger index = 0;
    int rows = 0;
    int tabs = 0;
    while (index < length) {
        NSRange para = [text paragraphRangeForRange:NSMakeRange(index, 1)];
        if (para.length == 0)
            break;
        NSString *slice = [text substringWithRange:para];
        int count = sf_tab_count(slice);
        id style = nil;
        if (count > 0)
            style = sf_style_for_tabs(count);
        else
            style = sf_metric_style(sf_kind_for_point(sf_point_size(loaded, para.location, length)));
        if (style) {
            ((void (*)(id, SEL, id, id, NSRange))objc_msgSend)(
                loaded, sel_registerName("addAttribute:value:range:"),
                styleName, style, para);
            if (count > 0) {
                rows++;
                tabs += count;
            }
        }
        if (NSMaxRange(para) <= index)
            break;
        index = NSMaxRange(para);
    }
    if (getenv("SF_LOG_EXC")) {
        fprintf(stderr, "SF_TE_TABLE rows=%d tabs=%d\n", rows, tabs);
        fflush(stderr);
    }
}

static int g_in_grid;
static int g_draw_depth;
static int g_glyph_depth;
static int g_glyphs_stroked;

typedef struct {
    Class cls;
    IMP previous;
} SFHook;

#define SF_HOOKS 24
static SFHook g_draw_hooks[SF_HOOKS];
static int g_draw_n;
static SFHook g_glyph_hooks[SF_HOOKS];
static int g_glyph_n;

static IMP sf_hook_previous(SFHook *hooks, int n, id obj)
{
    Class cls = object_getClass(obj);
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        for (int i = 0; i < n; i++) {
            if (hooks[i].cls == c)
                return hooks[i].previous;
        }
    }
    return NULL;
}

static void sf_log_grid(const char *where, const char *reason, int rows, double h, double x, double y)
{
    if (!getenv("SF_LOG_EXC"))
        return;
    static int misses;
    static int hits;
    if (rows > 0) {
        if (hits > 12)
            return;
        hits++;
    } else if (misses > 24) {
        return;
    } else {
        misses++;
    }
    fprintf(stderr, "SF_TE_GRID where=%s rows=%d reason=%s h=%.1f origin=%.1f %.1f\n",
            where, rows, reason ? reason : "", h, x, y);
    fflush(stderr);
}

static void sf_grid_line(id path, double x0, double y0, double x1, double y1)
{
    NSPoint a, b;
    a.x = x0;
    a.y = y0;
    b.x = x1;
    b.y = y1;
    ((void (*)(id, SEL, NSPoint))objc_msgSend)(path, sel_registerName("moveToPoint:"), a);
    ((void (*)(id, SEL, NSPoint))objc_msgSend)(path, sel_registerName("lineToPoint:"), b);
}

static void sf_path_rect(id path, double x, double y, double w, double h)
{
    NSRect r;
    r.origin.x = x;
    r.origin.y = y;
    r.size.width = w;
    r.size.height = h;
    ((void (*)(id, SEL, NSRect))objc_msgSend)(path, sel_registerName("appendBezierPathWithRect:"), r);
}

/* The glyph index is a 32-bit argument. A zero rect means the fragment
   store is empty, and the caller uses the paragraph line height instead. */
static double sf_fragment(id layout, NSUInteger glyph, double *y, double *x)
{
    NSRange used = NSMakeRange(0, 0);
    NSRect frag = ((NSRect (*)(id, SEL, unsigned int, NSRange *))objc_msgSend)(
        layout, sel_registerName("lineFragmentRectForGlyphAtIndex:effectiveRange:"),
        (unsigned int)glyph, &used);
    *y = frag.origin.y;
    *x = frag.origin.x;
    return frag.size.height;
}

static double sf_style_double(id style, const char *sel)
{
    if (!style)
        return 0.0;
    return ((double (*)(id, SEL))objc_msgSend)(style, sel_registerName(sel));
}

/* `at` is the container origin in the current view. Do not add
   textContainerOrigin on top of it. Fill runs before the glyphs.
   Stroke runs after them. A zero-height fragment still takes a row. */
static void sf_paint_grid(id layout, NSPoint at, int do_fill, int do_stroke, const char *where)
{
    if (g_in_grid) {
        sf_log_grid(where, "reenter", 0, 0, at.x, at.y);
        return;
    }
    if (!layout) {
        sf_log_grid(where, "nil-layout", 0, 0, at.x, at.y);
        return;
    }
    g_in_grid = 1;
    id storage = ((id (*)(id, SEL))objc_msgSend)(layout, sel_registerName("textStorage"));
    NSString *text = storage ? ((id (*)(id, SEL))objc_msgSend)(storage, sel_registerName("string")) : nil;
    Class pathClass = objc_lookUpClass("NSBezierPath");
    Class colorClass = objc_lookUpClass("NSColor");
    if (!text || !pathClass || !colorClass) {
        sf_log_grid(where, !text ? "nil-text" : "nil-path", 0, 0, at.x, at.y);
        g_in_grid = 0;
        return;
    }
    id strokePath = ((id (*)(id, SEL))objc_msgSend)((id)pathClass, sel_registerName("bezierPath"));
    id fillPath = do_fill ? ((id (*)(id, SEL))objc_msgSend)((id)pathClass, sel_registerName("bezierPath")) : nil;
    if (!strokePath || (do_fill && !fillPath)) {
        sf_log_grid(where, "nil-bezier", 0, 0, at.x, at.y);
        g_in_grid = 0;
        return;
    }
    id styleName = sf_paragraph_style_name();
    NSUInteger length = [text length];
    NSUInteger index = 0;
    double cursor = 0.0;
    int rows = 0;
    int fallbacks = 0;
    int real_n = 0;
    double sample_h = 0.0;
    int prev_tabs = 0;
    while (index < length && rows < 40) {
        NSRange para = [text paragraphRangeForRange:NSMakeRange(index, 1)];
        if (para.length == 0)
            break;
        NSString *slice = [text substringWithRange:para];
        int tabs = sf_tab_count(slice);
        id style = nil;
        if (styleName && para.location < length) {
            style = ((id (*)(id, SEL, id, NSUInteger, NSRange *))objc_msgSend)(
                storage, sel_registerName("attribute:atIndex:effectiveRange:"),
                styleName, para.location, (NSRange *)0);
        }
        double line = sf_style_double(style, "minimumLineHeight");
        double before = sf_style_double(style, "paragraphSpacingBefore");
        double after = sf_style_double(style, "paragraphSpacing");
        if (line < 0.5 || line > 80.0)
            line = 16.0;
        if (before < 0.0 || before > 40.0)
            before = 0.0;
        if (after < 0.0 || after > 40.0)
            after = 0.0;
        double gy = 0.0, gx = 0.0;
        double gh = sf_fragment(layout, para.location, &gy, &gx);
        int real = (gh > 0.5 && gh < 400.0);
        double y, h;
        if (real) {
            y = gy;
            h = gh;
            if (gy + gh > cursor)
                cursor = gy + gh;
            real_n++;
        } else {
            int lines = 1;
            if (tabs == 0) {
                NSUInteger chars = para.length > 0 ? para.length - 1 : 0;
                if (chars * 5.6 > 600.0) {
                    lines = (int)((chars * 5.6) / 600.0) + 1;
                    if (lines > 4)
                        lines = 4;
                }
            }
            cursor += before;
            y = cursor;
            h = line * (double)lines;
            cursor += h + after;
            fallbacks++;
        }
        double stops[8];
        int nstops = sf_stops_for_tabs(tabs, stops);
        if (nstops > 0) {
            double left = at.x + (real ? gx : 0.0);
            double right = left + SF_TABLE_RIGHT;
            double top = at.y + y;
            double bot = top + h;
            if (do_fill && prev_tabs == 0 && fillPath)
                sf_path_rect(fillPath, left, top, right - left, bot - top);
            if (do_stroke) {
                sf_grid_line(strokePath, left, top, right, top);
                sf_grid_line(strokePath, left, bot, right, bot);
                sf_grid_line(strokePath, left, top, left, bot);
                sf_grid_line(strokePath, right, top, right, bot);
                for (int s = 0; s < nstops; s++)
                    sf_grid_line(strokePath, left + stops[s], top, left + stops[s], bot);
            }
            rows++;
            sample_h = h;
        }
        prev_tabs = tabs;
        if (NSMaxRange(para) <= index)
            break;
        index = NSMaxRange(para);
    }
    if (do_fill && rows > 0 && fillPath) {
        id fill = ((id (*)(id, SEL, double, double, double, double))objc_msgSend)(
            (id)colorClass, sel_registerName("colorWithCalibratedRed:green:blue:alpha:"),
            236.0 / 255.0, 240.0 / 255.0, 246.0 / 255.0, 1.0);
        if (fill)
            ((void (*)(id, SEL))objc_msgSend)(fill, sel_registerName("setFill"));
        ((void (*)(id, SEL))objc_msgSend)(fillPath, sel_registerName("fill"));
    }
    if (do_stroke && rows > 0) {
        ((void (*)(id, SEL, double))objc_msgSend)(strokePath, sel_registerName("setLineWidth:"), 1.5);
        id color = ((id (*)(id, SEL, double, double, double, double))objc_msgSend)(
            (id)colorClass, sel_registerName("colorWithCalibratedRed:green:blue:alpha:"),
            18.0 / 255.0, 38.0 / 255.0, 64.0 / 255.0, 1.0);
        if (color)
            ((void (*)(id, SEL))objc_msgSend)(color, sel_registerName("setStroke"));
        ((void (*)(id, SEL))objc_msgSend)(strokePath, sel_registerName("stroke"));
    }
    char reason[80];
    snprintf(reason, sizeof reason, "%s fb=%d real=%d",
             rows ? "paint" : "no-rows", fallbacks, real_n);
    sf_log_grid(where, reason, rows, sample_h, at.x, at.y);
    g_in_grid = 0;
}

static void sf_paint_view(id view, int do_fill, int do_stroke, const char *where)
{
    if (!view) {
        sf_log_grid(where, "nil-view", 0, 0, 0, 0);
        return;
    }
    id layout = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("layoutManager"));
    NSPoint origin = ((NSPoint (*)(id, SEL))objc_msgSend)(view, sel_registerName("textContainerOrigin"));
    sf_paint_grid(layout, origin, do_fill, do_stroke, where);
}

typedef void (*SFDrawRect)(id, SEL, NSRect);
typedef void (*SFDrawGlyphs)(id, SEL, NSRange, NSPoint);

static void sf_draw_glyphs(id self, SEL _cmd, NSRange glyphs, NSPoint at)
{
    (void)glyphs;
    if (g_glyph_depth > 2) {
        SFDrawGlyphs prev = (SFDrawGlyphs)sf_hook_previous(g_glyph_hooks, g_glyph_n, self);
        if (prev)
            prev(self, _cmd, glyphs, at);
        sf_log_grid("glyphs", "depth", 0, 0, at.x, at.y);
        return;
    }
    g_glyph_depth++;
    SFDrawGlyphs prev = (SFDrawGlyphs)sf_hook_previous(g_glyph_hooks, g_glyph_n, self);
    if (prev)
        prev(self, _cmd, glyphs, at);
    sf_paint_grid(self, at, 0, 1, "glyphs");
    g_glyphs_stroked = 1;
    g_glyph_depth--;
}

static void sf_text_draw_rect(id self, SEL _cmd, NSRect dirty)
{
    if (g_draw_depth > 2) {
        SFDrawRect prev = (SFDrawRect)sf_hook_previous(g_draw_hooks, g_draw_n, self);
        if (prev)
            prev(self, _cmd, dirty);
        sf_log_grid("drawRect", "depth", 0, 0, dirty.origin.x, dirty.origin.y);
        return;
    }
    g_draw_depth++;
    g_glyphs_stroked = 0;
    sf_paint_view(self, 1, 0, "drawRect-fill");
    SFDrawRect prev = (SFDrawRect)sf_hook_previous(g_draw_hooks, g_draw_n, self);
    if (prev)
        prev(self, _cmd, dirty);
    if (!g_glyphs_stroked)
        sf_paint_view(self, 0, 1, "drawRect");
    else {
        static int noted;
        if (noted < 3) {
            noted++;
            fprintf(stderr, "SF_TE_GRID where=drawRect rows=0 reason=glyphs-already h=0 origin=%.1f %.1f\n",
                    dirty.origin.x, dirty.origin.y);
            fflush(stderr);
        }
    }
    g_draw_depth--;
}

static int sf_named(Class cls, const char *name)
{
    for (Class c = cls; c; c = class_getSuperclass(c)) {
        const char *cn = class_getName(c);
        if (cn && strcmp(cn, name) == 0)
            return 1;
    }
    return 0;
}

static void sf_hook_own(Class cls, SEL sel, IMP neu, SFHook *hooks, int *count)
{
    if (*count >= SF_HOOKS || !cls)
        return;
    unsigned int nmethods = 0;
    Method *list = class_copyMethodList(cls, &nmethods);
    if (!list)
        return;
    for (unsigned int i = 0; i < nmethods; i++) {
        if (method_getName(list[i]) != sel)
            continue;
        IMP old = method_setImplementation(list[i], neu);
        if (old != neu && *count < SF_HOOKS) {
            hooks[*count].cls = cls;
            hooks[*count].previous = old;
            (*count)++;
            if (getenv("SF_LOG_EXC")) {
                fprintf(stderr, "SF_TE_GRID hook %s %s\n", class_getName(cls), sel_getName(sel));
                fflush(stderr);
            }
        }
        break;
    }
    free(list);
}

static void sf_install_draw_hooks(void)
{
    int ncls = objc_getClassList(NULL, 0);
    Class *classes = ncls > 0 ? (Class *)malloc((size_t)ncls * sizeof(Class)) : NULL;
    int got = (classes && ncls > 0) ? objc_getClassList(classes, ncls) : 0;
    SEL drawSel = sel_registerName("drawRect:");
    SEL glyphSel = sel_registerName("drawGlyphsForGlyphRange:atPoint:");
    for (int i = 0; i < got; i++) {
        Class cls = classes[i];
        if (!cls)
            continue;
        if (sf_named(cls, "NSTextView"))
            sf_hook_own(cls, drawSel, (IMP)sf_text_draw_rect, g_draw_hooks, &g_draw_n);
        if (sf_named(cls, "NSLayoutManager"))
            sf_hook_own(cls, glyphSel, (IMP)sf_draw_glyphs, g_glyph_hooks, &g_glyph_n);
    }
    free(classes);
    if (getenv("SF_LOG_EXC")) {
        fprintf(stderr, "SF_TE_GRID install draw=%d glyphs=%d classes=%d\n", g_draw_n, g_glyph_n, got);
        fflush(stderr);
    }
}

static BOOL sf_readFromURL(id self, SEL _cmd, NSURL *url, NSDictionary *options, NSDictionary **attrs, NSError **error)
{
    (void)_cmd;
    (void)options;
    NSError *local = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error ? error : &local];
    if (data)
        data = sf_expand_tables(data);
    if (!data) {
        NSError *shown = error && *error ? *error : local;
        char buf[300];
        snprintf(buf, sizeof buf, "fail %s", shown ? [[shown description] UTF8String] : "nil");
        sf_read_log(buf);
        return NO;
    }
    Class reader = objc_lookUpClass("NSRichTextReader");
    id loaded = nil;
    BOOL owned = NO;
    if (reader) {
        loaded = ((id (*)(id, SEL, id))objc_msgSend)((id)reader,
            sel_registerName("attributedStringWithData:"), data);
    }
    if (!loaded) {
        NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!plain)
            plain = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!plain) {
            sf_read_log("fail undecoded");
            return NO;
        }
        loaded = [[NSAttributedString alloc] initWithString:plain];
        [plain release];
        owned = YES;
        sf_read_log("plain");
    } else {
        NSUInteger n = ((NSUInteger (*)(id, SEL))objc_msgSend)(loaded, sel_registerName("length"));
        char buf[64];
        snprintf(buf, sizeof buf, "rtf len=%lu", (unsigned long)n);
        sf_read_log(buf);
        id styled = [loaded mutableCopy];
        if (styled) {
            sf_apply_table_tabs(styled);
            if (owned)
                [loaded release];
            loaded = styled;
            owned = YES;
        }
    }
    [(NSMutableAttributedString *)self setAttributedString:loaded];
    if (owned)
        [loaded release];
    if (attrs) {
        static NSDictionary *doc;
        if (!doc)
            doc = [[NSDictionary alloc] initWithObjectsAndKeys:
                   NSRTFTextDocumentType, NSDocumentTypeDocumentAttribute, nil];
        *attrs = doc;
    }
    return YES;
}

static char sf_object_value_key;

static id sf_objectValue(id self, SEL _cmd)
{
    (void)_cmd;
    return objc_getAssociatedObject(self, &sf_object_value_key);
}

static void sf_setObjectValue(id self, SEL _cmd, id value)
{
    (void)_cmd;
    objc_setAssociatedObject(self, &sf_object_value_key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

__attribute__((constructor))
static void sf_document_read_install(void)
{
    Class storage = objc_lookUpClass("NSTextStorage");
    if (storage)
        class_replaceMethod(storage, sel_registerName("readFromURL:options:documentAttributes:error:"),
                            (IMP)sf_readFromURL, "c@:@@@@");
    Class item = objc_lookUpClass("NSMenuItem");
    if (item) {
        class_addMethod(item, sel_registerName("objectValue"), (IMP)sf_objectValue, "@@:");
        class_addMethod(item, sel_registerName("setObjectValue:"), (IMP)sf_setObjectValue, "v@:@");
    }
    sf_install_draw_hooks();
}
