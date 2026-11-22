/* SPDX-License-Identifier: MIT
   TextEdit configures an NSLayoutManager and an NSTextView with selectors
   the dock AppKit does not have. Missing ones are unrecognized, which
   aborts the document. Add the ones it asks for. Leave any method that
   already exists alone. */
#import <Foundation/Foundation.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static BOOL sf_no(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return NO;
}

static void sf_ignore_bool(id self, SEL _cmd, BOOL value)
{
    (void)self;
    (void)_cmd;
    (void)value;
}

static void sf_ignore_obj(id self, SEL _cmd, id value)
{
    (void)self;
    (void)_cmd;
    (void)value;
}

static void sf_ignore_int(id self, SEL _cmd, long value)
{
    (void)self;
    (void)_cmd;
    (void)value;
}

static void sf_ignore_double(id self, SEL _cmd, double value)
{
    (void)self;
    (void)_cmd;
    (void)value;
}

static double sf_one(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return 1.0;
}

/* Horizontal. A table reflow asks; the dock view does not implement it,
   and the unrecognized selector aborts the document. */
static long sf_layout_orientation(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return 0;
}

static void sf_add(Class cls, const char *name, IMP imp, const char *types)
{
    if (cls)
        class_addMethod(cls, sel_registerName(name), imp, types);
}

/* objectAtIndex: on an empty text-container array traps. TextEdit asks
   for the first text view before the nib has attached one. */
/* The dock layout manager raises when the range starts at the end of the
   text. TextEdit does that while clearing spell-check marks. */
static void sf_ignore_range(id self, SEL _cmd, id name, unsigned long loc, unsigned long len)
{
    (void)self;
    (void)_cmd;
    (void)name;
    (void)loc;
    (void)len;
}

/* An empty selection array raises. TextEdit passes one while the view is
   still being built. */
static void sf_set_selected_ranges(id self, SEL _cmd, id ranges, long affinity, BOOL still)
{
    (void)self;
    (void)_cmd;
    (void)ranges;
    (void)affinity;
    (void)still;
}

typedef struct { double width, height; } SFSize;

static SFSize sf_frame_for_content(id self, SEL _cmd, double width, double height,
                                   id horizontal, id vertical, long border, long control, long style)
{
    (void)self;
    (void)_cmd;
    (void)horizontal;
    (void)vertical;
    (void)border;
    (void)control;
    (void)style;
    SFSize size;
    size.width = width;
    size.height = height;
    return size;
}

static SFSize sf_content_for_frame(id self, SEL _cmd, double width, double height,
                                   BOOL horizontal, BOOL vertical, long border)
{
    (void)self;
    (void)_cmd;
    (void)horizontal;
    (void)vertical;
    (void)border;
    SFSize size;
    size.width = width;
    size.height = height;
    return size;
}

typedef struct { double x, y, width, height; } SFRect;

static void sf_log_frame(id window)
{
    if (!getenv("SF_LOG_EXC") || !window)
        return;
    SFRect frame = ((SFRect (*)(id, SEL))objc_msgSend)(window, sel_registerName("frame"));
    fprintf(stderr, "SF_TE_FRAME %.0f %.0f %.0f %.0f\n", frame.x, frame.y, frame.width, frame.height);
    fflush(stderr);
}

static void (*g_orderFront)(id, SEL, id);

static void sf_orderFront(id self, SEL _cmd, id sender)
{
    sf_log_frame(self);
    if (g_orderFront)
        g_orderFront(self, _cmd, sender);
}

static id sf_menu_items(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    return [NSArray array];
}

/* The compositor honours a window's frame only before its first buffer, and
   only while policy window_position is on. SF_TE_PLACE=1 puts the first
   three document windows in a grid and leaves panels alone. */
static id g_place_win[3];
static int g_place_n;
static int g_place_logged[3];
static int g_place_screen_logged;

static void sf_screen(double *width, double *height)
{
    *width = 1706.0;
    *height = 1066.0;
    Class screen = objc_lookUpClass("NSScreen");
    if (!screen)
        return;
    id main = ((id (*)(id, SEL))objc_msgSend)((id)screen, sel_registerName("mainScreen"));
    if (!main)
        return;
    NSRect frame = ((NSRect (*)(id, SEL))objc_msgSend)(main, sel_registerName("frame"));
    if (frame.size.width > 400.0 && frame.size.height > 300.0) {
        *width = frame.size.width;
        *height = frame.size.height;
    }
}

static int sf_place_slot(id window)
{
    for (int i = 0; i < g_place_n; i++) {
        if (g_place_win[i] == window)
            return i;
    }
    const char *cls = object_getClassName(window);
    if (cls && (strstr(cls, "Panel") || strstr(cls, "Menu") || strstr(cls, "Popover")))
        return -1;
    if (g_place_n >= 3)
        return -1;
    g_place_win[g_place_n] = window;
    return g_place_n++;
}

static void sf_place_rect(NSRect *frame, int slot, double width, double height)
{
    /* Points. The left dock is about 83 pt; the right column is about 75. */
    double left = 108.0, right = 120.0, top = 24.0, bottom = 28.0, gap = 28.0;
    double cell_w = (width - left - right - gap) / 2.0;
    double cell_h = (height - top - bottom - gap) / 2.0;
    if (cell_w < 280.0)
        cell_w = 280.0;
    if (cell_h < 200.0)
        cell_h = 200.0;
    frame->size.width = cell_w;
    frame->size.height = cell_h;
    /* 0 top-left (01), 1 bottom-right (02), 2 bottom-left (03).
       The top-right cell is left for Terminal. */
    if (slot == 0) {
        frame->origin.x = left;
        frame->origin.y = bottom + cell_h + gap;
    } else if (slot == 1) {
        frame->origin.x = left + cell_w + gap;
        frame->origin.y = bottom;
    } else {
        frame->origin.x = left;
        frame->origin.y = bottom;
    }
}

static void sf_place_apply(id self, NSRect *frame)
{
    if (!getenv("SF_TE_PLACE"))
        return;
    int slot = sf_place_slot(self);
    if (slot < 0)
        return;
    double width, height;
    sf_screen(&width, &height);
    sf_place_rect(frame, slot, width, height);
    if (g_place_logged[slot])
        return;
    g_place_logged[slot] = 1;
    if (!g_place_screen_logged) {
        fprintf(stderr, "SF_TE_SCREEN %.0f %.0f\n", width, height);
        g_place_screen_logged = 1;
    }
    fprintf(stderr, "SF_TE_PLACE slot=%d %.0f %.0f %.0f %.0f %s\n",
            slot, frame->origin.x, frame->origin.y, frame->size.width, frame->size.height,
            object_getClassName(self));
    fflush(stderr);
}

static void (*g_setFrameAnim)(id, SEL, NSRect, BOOL, BOOL);
static void (*g_setFrameDisp)(id, SEL, NSRect, BOOL);

static void sf_set_frame_anim(id self, SEL _cmd, NSRect frame, BOOL display, BOOL animate)
{
    sf_place_apply(self, &frame);
    if (g_setFrameAnim)
        g_setFrameAnim(self, _cmd, frame, display, animate);
}

static void sf_set_frame_disp(id self, SEL _cmd, NSRect frame, BOOL display)
{
    sf_place_apply(self, &frame);
    if (g_setFrameDisp)
        g_setFrameDisp(self, _cmd, frame, display);
}

static id sf_firstTextView(id self, SEL _cmd)
{
    (void)_cmd;
    NSArray *containers = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("textContainers"));
    if (!containers || [containers count] == 0)
        return nil;
    id container = [containers objectAtIndex:0];
    return ((id (*)(id, SEL))objc_msgSend)(container, sel_registerName("textView"));
}

__attribute__((constructor))
static void sf_layout_add(void)
{
    Class layout = objc_lookUpClass("NSLayoutManager");
    if (layout) {
        class_replaceMethod(layout, sel_registerName("firstTextView"), (IMP)sf_firstTextView, "@@:");
        class_replaceMethod(layout, sel_registerName("removeTemporaryAttribute:forCharacterRange:"),
                            (IMP)sf_ignore_range, "v@:@QQ");
    }
    sf_add(layout, "setAllowsNonContiguousLayout:", (IMP)sf_ignore_bool, "v@:c");
    sf_add(layout, "allowsNonContiguousLayout", (IMP)sf_no, "c@:");
    sf_add(layout, "setUsesDefaultHyphenation:", (IMP)sf_ignore_bool, "v@:c");
    sf_add(layout, "usesDefaultHyphenation", (IMP)sf_no, "c@:");

    Class view = objc_lookUpClass("NSTextView");
    Class viewMeta = view ? object_getClass((id)view) : nil;
    sf_add(viewMeta, "_textHighlightMenuItems", (IMP)sf_menu_items, "@@:");
    sf_add(view, "layoutOrientation", (IMP)sf_layout_orientation, "q@:");
    sf_add(view, "setLayoutOrientation:", (IMP)sf_ignore_int, "v@:q");
    Class window = objc_lookUpClass("NSWindow");
    if (getenv("SF_TE_PLACE") && window) {
        Method anim = class_getInstanceMethod(window, sel_registerName("setFrame:display:animate:"));
        Method disp = class_getInstanceMethod(window, sel_registerName("setFrame:display:"));
        if (anim)
            g_setFrameAnim = (void (*)(id, SEL, NSRect, BOOL, BOOL))method_setImplementation(anim, (IMP)sf_set_frame_anim);
        if (disp)
            g_setFrameDisp = (void (*)(id, SEL, NSRect, BOOL))method_setImplementation(disp, (IMP)sf_set_frame_disp);
    }
    Method order = class_getInstanceMethod(window, sel_registerName("orderFront:"));
    if (order)
        g_orderFront = (void (*)(id, SEL, id))method_setImplementation(order, (IMP)sf_orderFront);
    /* These are registered, and several only raise "is not implemented",
       so add is not enough. */
    const char *replace_bools[] = {
        "setIncrementalSearchingEnabled:",
        "setSmartInsertDeleteEnabled:",
        "setAutomaticLinkDetectionEnabled:",
        "setAutomaticDataDetectionEnabled:",
        "setAutomaticTextReplacementEnabled:",
        "setAutomaticDashSubstitutionEnabled:",
        "setAutomaticQuoteSubstitutionEnabled:",
        "setAutomaticSpellingCorrectionEnabled:",
        "setGrammarCheckingEnabled:",
        "setContinuousSpellCheckingEnabled:",
    };
    for (unsigned i = 0; i < sizeof replace_bools / sizeof replace_bools[0]; i++)
        class_replaceMethod(view, sel_registerName(replace_bools[i]), (IMP)sf_ignore_bool, "v@:c");
    const char *bools[] = {
        "setUsesFontPanel:",
        "setUsesFindBar:",
        "setUsesInspectorBar:",
        "setAllowsDocumentBackgroundColorChange:",
        "setUsesAdaptiveColorMappingForDarkAppearance:",
    };
    const char *gets[] = {
        "usesFontPanel",
        "usesFindBar",
        "usesInspectorBar",
        "isIncrementalSearchingEnabled",
        "allowsDocumentBackgroundColorChange",
        "smartInsertDeleteEnabled",
        "isAutomaticLinkDetectionEnabled",
        "isAutomaticDataDetectionEnabled",
        "isAutomaticTextReplacementEnabled",
        "isAutomaticDashSubstitutionEnabled",
        "isAutomaticQuoteSubstitutionEnabled",
        "isGrammarCheckingEnabled",
    };
    for (unsigned i = 0; i < sizeof bools / sizeof bools[0]; i++)
        sf_add(view, bools[i], (IMP)sf_ignore_bool, "v@:c");
    for (unsigned i = 0; i < sizeof gets / sizeof gets[0]; i++)
        sf_add(view, gets[i], (IMP)sf_no, "c@:");
    /* Spell checking walks an empty word list and traps. */
    class_replaceMethod(view, sel_registerName("_continuousSpellCheckWithInvalidatedRange:"),
                        (IMP)sf_ignore_range, "v@:QQ");
    class_replaceMethod(view, sel_registerName("setSelectedRanges:affinity:stillSelecting:"),
                        (IMP)sf_set_selected_ranges, "v@:@qc");
    sf_add(view, "setIdentifier:", (IMP)sf_ignore_obj, "v@:@");
    sf_add(view, "setTypingAttributes:", (IMP)sf_ignore_obj, "v@:@");
    sf_add(view, "setLayoutOrientation:", (IMP)sf_ignore_int, "v@:q");

    /* Two CGFloats go in d0 and d1, both in and out. */
    Class scroll = objc_lookUpClass("NSScrollView");
    Class scrollMeta = scroll ? object_getClass((id)scroll) : nil;
    sf_add(scrollMeta, "frameSizeForContentSize:horizontalScrollerClass:verticalScrollerClass:borderType:controlSize:scrollerStyle:",
           (IMP)sf_frame_for_content, "{CGSize=dd}@:{CGSize=dd}##qqq");
    sf_add(scrollMeta, "contentSizeForFrameSize:hasHorizontalScroller:hasVerticalScroller:borderType:",
           (IMP)sf_content_for_frame, "{CGSize=dd}@:{CGSize=dd}ccq");
    sf_add(scroll, "setHasHorizontalRuler:", (IMP)sf_ignore_bool, "v@:c");
    sf_add(scroll, "setHasVerticalRuler:", (IMP)sf_ignore_bool, "v@:c");
    sf_add(scroll, "setRulersVisible:", (IMP)sf_ignore_bool, "v@:c");
    sf_add(scroll, "setAllowsMagnification:", (IMP)sf_ignore_bool, "v@:c");
    sf_add(scroll, "setMaxMagnification:", (IMP)sf_ignore_double, "v@:d");
    sf_add(scroll, "setMinMagnification:", (IMP)sf_ignore_double, "v@:d");
    sf_add(scroll, "setMagnification:", (IMP)sf_ignore_double, "v@:d");
    sf_add(scroll, "magnification", (IMP)sf_one, "d@:");

    Class style = objc_lookUpClass("NSMutableParagraphStyle");
    sf_add(style, "addTabStop:", (IMP)sf_ignore_obj, "v@:@");
    sf_add(style, "setDefaultTabInterval:", (IMP)sf_ignore_double, "v@:d");
    sf_add(style, "setHorizontalAlignment:", (IMP)sf_ignore_int, "v@:q");
}
