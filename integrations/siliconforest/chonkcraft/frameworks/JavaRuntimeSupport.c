// SPDX-License-Identifier: MIT
// SiliconForest JavaRuntimeSupport: the C entry points the JetBrains
// Runtime's AWT libraries import (libawt_lwawt: font rendering helpers;
// libosxui: the Aqua look-and-feel control painter). Written from the
// call sites in OpenJDK, not from Apple's binary. Fonts go straight to
// CoreText/CoreGraphics, found at run time so this image links only
// libSystem. The Aqua painter draws nothing; use a cross-platform look
// and feel (Metal, Nimbus) for Swing.
#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

typedef const void *CFTypeRef;
typedef long CFIndex;
typedef struct { double x, y; } CGPoint;
typedef struct { double w, h; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { double a, b, c, d, tx, ty; } CGAffineTransform;
typedef uint16_t CGGlyph;
typedef uint16_t UTF16Char;
typedef uint32_t JRSFontRenderingStyle;

static void *sym(const char *name) { return dlsym(RTLD_DEFAULT, name); }

static CFTypeRef retain(CFTypeRef ref) {
    CFTypeRef (*f)(CFTypeRef) = (CFTypeRef (*)(CFTypeRef))sym("CFRetain");
    return (f && ref) ? f(ref) : ref;
}

// Hint bits are kept as given: bit 0 anti-alias, bit 1 fractional metrics.
JRSFontRenderingStyle JRSFontGetRenderingStyleForHints(int fmHint, int aaHint) {
    // sun.awt.SunHints: text AA ON == 2, fractional metrics ON == 2.
    return (aaHint == 2 ? 1u : 0u) | (fmHint == 2 ? 2u : 0u);
}

bool JRSFontStyleUsesFractionalMetrics(JRSFontRenderingStyle style) {
    return (style & 2u) != 0;
}

JRSFontRenderingStyle JRSFontAlignStyleForFractionalMeasurement(JRSFontRenderingStyle style) {
    return style | 2u;
}

void JRSFontSetRenderingStyleOnContext(void *context, JRSFontRenderingStyle style) {
    void (*aa)(void *, bool) = (void (*)(void *, bool))sym("CGContextSetShouldAntialias");
    void (*smooth)(void *, bool) = (void (*)(void *, bool))sym("CGContextSetShouldSmoothFonts");
    if (context && aa) aa(context, (style & 1u) != 0);
    if (context && smooth) smooth(context, false);
}

static CGRect apply(CGRect r, const CGAffineTransform *t) {
    if (!t) return r;
    double xs[4] = { r.origin.x, r.origin.x + r.size.w, r.origin.x, r.origin.x + r.size.w };
    double ys[4] = { r.origin.y, r.origin.y, r.origin.y + r.size.h, r.origin.y + r.size.h };
    double minx = 0, maxx = 0, miny = 0, maxy = 0;
    for (int i = 0; i < 4; i++) {
        double x = t->a * xs[i] + t->c * ys[i] + t->tx;
        double y = t->b * xs[i] + t->d * ys[i] + t->ty;
        if (i == 0 || x < minx) minx = x;
        if (i == 0 || x > maxx) maxx = x;
        if (i == 0 || y < miny) miny = y;
        if (i == 0 || y > maxy) maxy = y;
    }
    CGRect out = { { minx, miny }, { maxx - minx, maxy - miny } };
    return out;
}

void JRSFontGetBoundingBoxesForGlyphsAndStyle(CFTypeRef font, const CGAffineTransform *tx,
        JRSFontRenderingStyle style, const CGGlyph glyphs[], size_t count, CGRect bboxes[]) {
    (void)style;
    CGRect (*rects)(CFTypeRef, int, const CGGlyph *, CGRect *, CFIndex) =
        (CGRect (*)(CFTypeRef, int, const CGGlyph *, CGRect *, CFIndex))sym("CTFontGetBoundingRectsForGlyphs");
    for (size_t i = 0; i < count; i++) {
        CGRect zero = { { 0, 0 }, { 0, 0 } };
        bboxes[i] = zero;
    }
    if (!font || !rects) return;
    rects(font, 0, glyphs, bboxes, (CFIndex)count);
    for (size_t i = 0; i < count; i++) bboxes[i] = apply(bboxes[i], tx);
}

// No cascade list yet: the requested font answers for every character.
CFTypeRef JRSFontCreateFallbackFontForCharacters(CFTypeRef font, const UTF16Char *chars, CFIndex length) {
    (void)chars; (void)length;
    return retain(font);
}

// Aqua control painter (libosxui). Swing's Aqua look and feel calls these;
// they keep state nowhere and paint nothing.
typedef struct { int unused; } JRSUIObject;
void *JRSUIRendererCreate(void) { return calloc(1, sizeof(JRSUIObject)); }
void *JRSUIControlCreate(bool flipped) { (void)flipped; return calloc(1, sizeof(JRSUIObject)); }
void JRSUIControlRelease(void *control) { free(control); }
void JRSUIControlDraw(void) {}
long JRSUIGetKey(CFTypeRef name) { (void)name; return 0; }
int JRSUIControlGetHitPart(void) { return 0; }
double JRSUIControlGetScrollBarOffsetFor(void) { return 0; }
void JRSUIControlGetScrollBarPartBounds(void) {}
bool JRSUIControlShouldScrollToClick(void) { return false; }
void JRSUIControlSetAlignmentHorizontal(void) {}
void JRSUIControlSetAlignmentVertical(void) {}
void JRSUIControlSetAnimating(void) {}
void JRSUIControlSetDirection(void) {}
void JRSUIControlSetOrientation(void) {}
void JRSUIControlSetScrollBarPart(void) {}
void JRSUIControlSetSegmentPosition(void) {}
void JRSUIControlSetShowArrows(void) {}
void JRSUIControlSetSize(void) {}
void JRSUIControlSetState(void) {}
void JRSUIControlSetValueByKey(void) {}
void JRSUIControlSetVariant(void) {}
void JRSUIControlSetWidget(void) {}
void JRSUIControlSetWindowType(void) {}

// JRSAppKitAWT. NSApplicationAWT asks for +registerAWTAppWithOptions: and,
// without it, falls back to a block that calls -[NSApp run] from inside
// the running loop. That nested loop never returns on SiliconForest and
// starves every later perform-on-main-thread, so AWT start-up hangs. The
// class is made at load time through the Objective-C runtime (no ObjC
// compiler or Foundation headers needed). Registration does nothing: the
// desk compositor already treats every NSApplication as a foreground app.
typedef void *id;
typedef void *SEL;
static id (*objc_msg)(id, SEL, ...);
static SEL (*objc_sel)(const char *);

static id jrs_register(id self, SEL cmd, id options) {
    (void)self; (void)cmd; (void)options;
    return 0;
}

// Headless start: report that the process was marked a daemon.
static signed char jrs_mark_daemon(id self, SEL cmd) {
    (void)self; (void)cmd;
    return 1;
}

__attribute__((constructor)) static void jrs_make_classes(void) {
    dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY);
    void *objc = dlopen("/usr/lib/libobjc.A.dylib", RTLD_LAZY);
    if (!objc) return;
    id (*get)(const char *) = (id (*)(const char *))dlsym(objc, "objc_getClass");
    id (*alloc)(id, const char *, size_t) = (id (*)(id, const char *, size_t))dlsym(objc, "objc_allocateClassPair");
    void (*reg)(id) = (void (*)(id))dlsym(objc, "objc_registerClassPair");
    id (*meta)(id) = (id (*)(id))dlsym(objc, "object_getClass");
    signed char (*add)(id, SEL, void *, const char *) =
        (signed char (*)(id, SEL, void *, const char *))dlsym(objc, "class_addMethod");
    objc_msg = (id (*)(id, SEL, ...))dlsym(objc, "objc_msgSend");
    objc_sel = (SEL (*)(const char *))dlsym(objc, "sel_registerName");
    if (!get || !alloc || !reg || !meta || !add || !objc_sel) return;
    if (get("JRSAppKitAWT")) return;
    id base = get("NSObject");
    if (!base) return;
    id cls = alloc(base, "JRSAppKitAWT", 0);
    if (!cls) return;
    reg(cls);
    id m = meta(cls);
    add(m, objc_sel("registerAWTAppWithOptions:"), (void *)jrs_register, "@@:@");
    add(m, objc_sel("markAppIsDaemon"), (void *)jrs_mark_daemon, "c@:");
}
