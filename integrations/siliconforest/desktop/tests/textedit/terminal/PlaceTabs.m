/* SPDX-License-Identifier: MIT
   Place Apple Terminal's window in the top-right cell and open two more
   tabs in that same window. Inserted with DYLD_INSERT_LIBRARIES. It does
   not replace AppKit and it does not write into Terminal.app.

   Linked only to libSystem and libobjc. Foundation is used through the
   already-loaded AppKit, so this image does not pull libc++.

   The menu strip is not hidden here. The desk's app-menu socket
   (menubar hide on this process only) does that, so TextEdit can keep
   its menus.

   newWindowForTab: opens the extra tabs. Walking the view tree for a
   fileDescriptor does not reach the ptys (the log says wrote=0). The
   scene harness writes the pane text after the shells exist. */
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct { double x, y; } SFPoint;
typedef struct { double width, height; } SFSize;
typedef struct { SFPoint origin; SFSize size; } SFRect;

static int g_placed;
static int g_tabs_scheduled;

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
    SFRect frame = ((SFRect (*)(id, SEL))objc_msgSend)(main, sel_registerName("frame"));
    if (frame.size.width > 400.0 && frame.size.height > 300.0) {
        *width = frame.size.width;
        *height = frame.size.height;
    }
}

static void sf_top_right(SFRect *frame)
{
    double width, height;
    sf_screen(&width, &height);
    double left = 108.0, right = 120.0, top = 24.0, bottom = 28.0, gap = 28.0;
    double cell_w = (width - left - right - gap) / 2.0;
    double cell_h = (height - top - bottom - gap) / 2.0;
    if (cell_w < 280.0)
        cell_w = 280.0;
    if (cell_h < 200.0)
        cell_h = 200.0;
    frame->origin.x = left + cell_w + gap;
    frame->origin.y = bottom + cell_h + gap;
    frame->size.width = cell_w;
    frame->size.height = cell_h;
    if (!g_placed) {
        fprintf(stderr, "SF_TERM_PLACE %.0f %.0f %.0f %.0f screen %.0f %.0f\n",
                frame->origin.x, frame->origin.y, frame->size.width, frame->size.height,
                width, height);
        fflush(stderr);
        g_placed = 1;
    }
}

static int sf_write_fd(id obj, int depth, const char *text)
{
    if (!obj || depth > 5 || !text)
        return 0;
    SEL fdsel = sel_registerName("fileDescriptor");
    SEL responds = sel_registerName("respondsToSelector:");
    if (((BOOL (*)(id, SEL, SEL))objc_msgSend)(obj, responds, fdsel)) {
        int fd = ((int (*)(id, SEL))objc_msgSend)(obj, fdsel);
        if (fd > 2) {
            size_t n = strlen(text);
            if (write(fd, text, n) == (ssize_t)n)
                return 1;
        }
    }
    SEL subsel = sel_registerName("subviews");
    if (((BOOL (*)(id, SEL, SEL))objc_msgSend)(obj, responds, subsel)) {
        id subs = ((id (*)(id, SEL))objc_msgSend)(obj, subsel);
        unsigned long count = ((unsigned long (*)(id, SEL))objc_msgSend)(subs, sel_registerName("count"));
        for (unsigned long i = 0; i < count; i++) {
            id sub = ((id (*)(id, SEL, unsigned long))objc_msgSend)(subs, sel_registerName("objectAtIndex:"), i);
            if (sf_write_fd(sub, depth + 1, text))
                return 1;
        }
    }
    return 0;
}

static const char *g_tab_text[] = {
    "printf '\\033]0;forest\\007'; echo 'SiliconForest  uname:' $(uname -sm)\n",
    "printf '\\033]0;wafer\\007'; echo 'theme sf-wafer  (revert: desk_m1.sh theme sf-canopy)'\n",
    "printf '\\033]0;menu\\007'; echo 'menu strip hidden on Terminal only'\n",
};

static void sf_make_tabs(id self, SEL _cmd)
{
    (void)self;
    (void)_cmd;
    id app = ((id (*)(id, SEL))objc_msgSend)((id)objc_lookUpClass("NSApplication"),
                                            sel_registerName("sharedApplication"));
    id win = ((id (*)(id, SEL))objc_msgSend)(app, sel_registerName("keyWindow"));
    if (!win) {
        id ws = ((id (*)(id, SEL))objc_msgSend)(app, sel_registerName("windows"));
        unsigned long count = ws ? ((unsigned long (*)(id, SEL))objc_msgSend)(ws, sel_registerName("count")) : 0;
        if (count > 0)
            win = ((id (*)(id, SEL, unsigned long))objc_msgSend)(ws, sel_registerName("objectAtIndex:"), 0);
    }
    if (!win) {
        fprintf(stderr, "SF_TERM_TABS no window\n");
        fflush(stderr);
        return;
    }
    SEL tab = sel_registerName("newWindowForTab:");
    SEL responds = sel_registerName("respondsToSelector:");
    id target = win;
    if (((BOOL (*)(id, SEL, SEL))objc_msgSend)(win, responds, sel_registerName("delegate"))) {
        id del = ((id (*)(id, SEL))objc_msgSend)(win, sel_registerName("delegate"));
        if (del && ((BOOL (*)(id, SEL, SEL))objc_msgSend)(del, responds, tab))
            target = del;
    }
    if (!((BOOL (*)(id, SEL, SEL))objc_msgSend)(target, responds, tab)) {
        fprintf(stderr, "SF_TERM_TABS missing on %s\n", object_getClassName(target));
        fflush(stderr);
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(target, tab, (id)0);
    ((void (*)(id, SEL, id))objc_msgSend)(target, tab, (id)0);
    id ws = ((id (*)(id, SEL))objc_msgSend)(app, sel_registerName("windows"));
    unsigned long count = ws ? ((unsigned long (*)(id, SEL))objc_msgSend)(ws, sel_registerName("count")) : 0;
    unsigned wrote = 0;
    for (unsigned long i = 0; i < count && i < 3; i++) {
        id w = ((id (*)(id, SEL, unsigned long))objc_msgSend)(ws, sel_registerName("objectAtIndex:"), i);
        id view = ((id (*)(id, SEL))objc_msgSend)(w, sel_registerName("contentView"));
        if (sf_write_fd(view, 0, g_tab_text[i]))
            wrote++;
    }
    fprintf(stderr, "SF_TERM_TABS windows=%lu wrote=%u via %s\n",
            count, wrote, object_getClassName(target));
    fflush(stderr);
}

static void (*g_setFrameAnim)(id, SEL, SFRect, BOOL, BOOL);
static void (*g_setFrameDisp)(id, SEL, SFRect, BOOL);

static void sf_arm_tabs(id window)
{
    if (g_tabs_scheduled || !window)
        return;
    g_tabs_scheduled = 1;
    ((void (*)(id, SEL, SEL, id, double))objc_msgSend)(
        window, sel_registerName("performSelector:withObject:afterDelay:"),
        sel_registerName("sf_make_tabs"), (id)0, 1.6);
}

static void sf_set_frame_anim(id self, SEL _cmd, SFRect frame, BOOL display, BOOL animate)
{
    sf_top_right(&frame);
    sf_arm_tabs(self);
    if (g_setFrameAnim)
        g_setFrameAnim(self, _cmd, frame, display, animate);
}

static void sf_set_frame_disp(id self, SEL _cmd, SFRect frame, BOOL display)
{
    sf_top_right(&frame);
    sf_arm_tabs(self);
    if (g_setFrameDisp)
        g_setFrameDisp(self, _cmd, frame, display);
}

__attribute__((constructor))
static void sf_term_place(void)
{
    Class window = objc_lookUpClass("NSWindow");
    if (!window)
        return;
    class_addMethod(window, sel_registerName("sf_make_tabs"), (IMP)sf_make_tabs, "v@:");
    Method anim = class_getInstanceMethod(window, sel_registerName("setFrame:display:animate:"));
    Method disp = class_getInstanceMethod(window, sel_registerName("setFrame:display:"));
    if (anim)
        g_setFrameAnim = (void (*)(id, SEL, SFRect, BOOL, BOOL))method_setImplementation(anim, (IMP)sf_set_frame_anim);
    if (disp)
        g_setFrameDisp = (void (*)(id, SEL, SFRect, BOOL))method_setImplementation(disp, (IMP)sf_set_frame_disp);
}
