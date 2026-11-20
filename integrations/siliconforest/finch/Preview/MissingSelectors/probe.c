/* Arm64 probe for the AppKit, Quartz and CoreImage overlays.
   Run it on the M1 next to this tree. It does not start NSApplication. */
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fails;

static void *need(void *image, const char *name) {
    const char *plain = name[0] == '_' ? name + 1 : name;
    void *symbol = dlsym(image, plain);
    if (symbol == NULL)
        symbol = dlsym(image, name);
    if (symbol == NULL)
        symbol = dlsym(RTLD_DEFAULT, plain);
    if (symbol == NULL)
        symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol == NULL) {
        fprintf(stderr, "FAIL dlsym %s (%s)\n", name, dlerror());
        g_fails++;
    }
    return symbol;
}

typedef struct {
    double x, y;
} SFPoint;
typedef struct {
    double width, height;
} SFSize;
typedef struct {
    SFPoint origin;
    SFSize size;
} SFRect;

static id utf8(const char *text) {
    return ((id (*)(id, SEL, const char *))objc_msgSend)(
        (id)objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), text);
}

static int same_string(void *slot, const char *text) {
    if (slot == NULL)
        return 0;
    id value = *(id *)slot;
    if (value == nil)
        return 0;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(
               value, sel_registerName("isEqualToString:"), utf8(text)) == YES;
}

static id msg(id obj, const char *sel) {
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel_registerName(sel));
}

static void check_class(void *image, const char *symbol, const char *name) {
    Class cls = (Class)need(image, symbol);
    if (cls == Nil)
        return;
    const char *got = class_getName(cls);
    if (got == NULL || strcmp(got, name) != 0) {
        fprintf(stderr, "FAIL class %s name %s\n", name, got ? got : "(null)");
        g_fails++;
        return;
    }
    printf("class %s\n", name);
}

static char *framework(const char *exe, const char *name) {
    char *slash = strrchr(exe, '/');
    size_t dir = slash ? (size_t)(slash - exe) : 0;
    const char *tail = "/../framework/%s.framework/Versions/A/%s";
    size_t n = dir + strlen(tail) + strlen(name) * 2 + 1;
    char *path = malloc(n);
    if (path == NULL)
        return NULL;
    snprintf(path, n, "%.*s/../framework/%s.framework/Versions/A/%s", (int)dir, exe, name, name);
    return path;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    char exe[4096];
    uint32_t size = sizeof exe;
    if (_NSGetExecutablePath(exe, &size) != 0) {
        fprintf(stderr, "FAIL executable path\n");
        return 2;
    }
    char *appkit_path = framework(exe, "AppKit");
    char *quartz_path = framework(exe, "Quartz");
    char *ci_path = framework(exe, "CoreImage");
    /* AppKit first, so Quartz's install-name dependency is already loaded. */
    void *appkit = dlopen(appkit_path, RTLD_NOW);
    void *quartz = appkit ? dlopen(quartz_path, RTLD_NOW) : NULL;
    void *coreimage = quartz ? dlopen(ci_path, RTLD_NOW) : NULL;
    if (appkit == NULL || quartz == NULL || coreimage == NULL) {
        fprintf(stderr, "FAIL dlopen %s\n", dlerror());
        return 1;
    }
    printf("opened\n%s\n%s\n%s\n", appkit_path, quartz_path, ci_path);

    const char *swift[] = {
        "_$s6AppKit17NSApplicationMainys5Int32VAD_SpySpys4Int8VGSgGtF",
        "_$sSo10NSMenuItemC6AppKitE13sectionHeader5titleABSS_tFZ",
        "_$sSo6CGRectV6AppKitE4fill5usingySo22NSCompositingOperationV_tF",
    };
    for (size_t i = 0; i < sizeof swift / sizeof swift[0]; i++)
        if (need(appkit, swift[i]))
            printf("swift %s\n", swift[i]);

    check_class(appkit, "_OBJC_CLASS_$_NSAccessibilityCustomRotor", "NSAccessibilityCustomRotor");
    check_class(appkit, "_OBJC_METACLASS_$_NSAccessibilityCustomRotor", "NSAccessibilityCustomRotor");
    check_class(appkit, "_OBJC_CLASS_$_NSAccessibilityCustomRotorItemResult", "NSAccessibilityCustomRotorItemResult");
    check_class(appkit, "_OBJC_CLASS_$_NSAccessibilityRemoteUIElement", "NSAccessibilityRemoteUIElement");
    check_class(appkit, "_OBJC_CLASS_$_NSAdaptiveImageGlyph", "NSAdaptiveImageGlyph");
    check_class(appkit, "_OBJC_CLASS_$_NSStringDrawingContext", "NSStringDrawingContext");
    check_class(appkit, "_OBJC_CLASS_$_NSSwitch", "NSSwitch");
    check_class(appkit, "_OBJC_METACLASS_$_NSSwitch", "NSSwitch");
    check_class(appkit, "_OBJC_CLASS_$_NSTextEncapsulation", "NSTextEncapsulation");
    check_class(appkit, "_OBJC_CLASS_$_NSTextGraphicsContextProvider", "NSTextGraphicsContextProvider");
    check_class(appkit, "_OBJC_CLASS_$_NSClickGestureRecognizer", "NSClickGestureRecognizer");

    const char *strings[][2] = {
        {"_NSAccessibilityAttributedUserInputLabelsAttribute", "AXAttributedUserInputLabels"},
        {"_NSAccessibilityIdentifierAttribute", "AXIdentifier"},
        {"_NSAccessibilityIsAccessibilityElementAttribute", "AXIsElement"},
        {"_NSAccessibilityLayoutChangedNotification", "AXLayoutChanged"},
        {"_NSAccessibilityUIElementsKey", "AXUIElementsKey"},
        {"_NSAdaptiveImageGlyphAttributeName", "CTAdaptiveImageProvider"},
        {"_NSFontFeatureSettingsAttribute", "NSCTFontFeatureSettingsAttribute"},
        {"_NSTextEncapsulationAttributeName", "NSTextEncapsulation"},
        {"_NSWindowDidEndSheetNotification", "NSWindowDidEndSheetNotification"},
        {"_NSWindowWillBeginSheetNotification", "NSWindowWillBeginSheetNotification"},
    };
    for (size_t i = 0; i < sizeof strings / sizeof strings[0]; i++) {
        void *slot = need(appkit, strings[i][0]);
        if (slot && !same_string(slot, strings[i][1])) {
            fprintf(stderr, "FAIL string %s\n", strings[i][0]);
            g_fails++;
        } else if (slot) {
            printf("string %s\n", strings[i][0]);
        }
    }

    void (*begin_access)(void) = need(appkit, "_NSAccessibilityBeginInternalAccessors");
    void (*end_access)(void) = need(appkit, "_NSAccessibilityEndInternalAccessors");
    if (begin_access && end_access) {
        begin_access();
        end_access();
        printf("accessors\n");
    }
    BOOL (*has_accent)(void) = need(appkit, "_NSUserAccentHasHardwareColor");
    id (*accent_name)(void) = need(appkit, "_NSUserAccentColorGetHardwareAccentColorName");
    if (has_accent && accent_name) {
        if (has_accent() != NO || accent_name() != nil) {
            fprintf(stderr, "FAIL accent\n");
            g_fails++;
        } else {
            printf("accent\n");
        }
    }
    id (*action_names)(id, id) = need(appkit, "_NSAccessibilityEntryPointActionNames");
    id (*action_desc)(id, id) = need(appkit, "_NSAccessibilityEntryPointActionDescription");
    BOOL (*perform)(id, id) = need(appkit, "_NSAccessibilityEntryPointPerformAction");
    id (*value_for)(id, id) = need(appkit, "_NSAccessibilityEntryPointValueForAttribute");
    if (action_names && action_desc && perform && value_for)
        printf("entrypoints\n");

    Class sw = (Class)need(appkit, "_OBJC_CLASS_$_NSSwitch");
    if (sw) {
        SFRect frame = {{0, 0}, {54, 24}};
        id obj = ((id (*)(id, SEL, SFRect))objc_msgSend)(
            msg((id)sw, "alloc"), sel_registerName("initWithFrame:"), frame);
        if (obj == nil) {
            fprintf(stderr, "FAIL NSSwitch alloc\n");
            g_fails++;
        } else {
            ((void (*)(id, SEL, long))objc_msgSend)(obj, sel_registerName("setState:"), 1);
            long state = ((long (*)(id, SEL))objc_msgSend)(obj, sel_registerName("state"));
            ((void (*)(id, SEL, long))objc_msgSend)(obj, sel_registerName("setState:"), 0);
            long off = ((long (*)(id, SEL))objc_msgSend)(obj, sel_registerName("state"));
            if (state != 1 || off != 0) {
                fprintf(stderr, "FAIL NSSwitch state %ld %ld\n", state, off);
                g_fails++;
            } else {
                printf("switch\n");
            }
        }
    }

    check_class(quartz, "_OBJC_CLASS_$_IKImageEditPanel", "IKImageEditPanel");
    check_class(quartz, "_OBJC_CLASS_$_IKImageView2", "IKImageView2");
    check_class(quartz, "_OBJC_METACLASS_$_IKImageView2", "IKImageView2");
    check_class(quartz, "_OBJC_CLASS_$_IKSaveOptions", "IKSaveOptions");
    check_class(quartz, "_OBJC_CLASS_$_QuartzFilter", "QuartzFilter");
    Class view = objc_getClass("IKImageView2");
    void *ivar_symbol = need(quartz, "_OBJC_IVAR_$_IKImageView2._scrollView");
    if (view && ivar_symbol) {
        (void)msg((id)view, "self");
        Ivar ivar = class_getInstanceVariable(view, "_scrollView");
        if (ivar == NULL) {
            fprintf(stderr, "FAIL ivar _scrollView\n");
            g_fails++;
        } else {
            printf("ivar _scrollView %ld\n", (long)ivar_getOffset(ivar));
        }
    }
    const char *qstrings[][2] = {
        {"_IKImageCompletedInitialLoadingNotification", "IKImageCompletedInitialLoadingNotification"},
        {"_kC3DIOSceneSourceTriggerOptionsForRealtimeViewer", "kC3DIOSceneSourceTriggerOptionsForRealtimeViewer"},
        {"_kIKGeometryChanged", "kIKGeometryChanged"},
        {"_kIKInitialCenter", "kIKInitialCenter"},
        {"_kIKInitialZoomFactor", "kIKInitialZoomFactor"},
        {"_kIKKeepZoomToFitSticky", "kIKKeepZoomToFitSticky"},
        {"_kIKZoomToFitOnStart", "kIKZoomToFitOnStart"},
    };
    for (size_t i = 0; i < sizeof qstrings / sizeof qstrings[0]; i++) {
        void *slot = need(quartz, qstrings[i][0]);
        if (slot && !same_string(slot, qstrings[i][1])) {
            fprintf(stderr, "FAIL string %s\n", qstrings[i][0]);
            g_fails++;
        } else if (slot) {
            printf("string %s\n", qstrings[i][0]);
        }
    }
    double *quality = need(quartz, "_IKSaveOptionsDefaultCompressionQuality");
    if (quality && !(*quality > 0.79 && *quality < 0.81)) {
        fprintf(stderr, "FAIL compression quality %f\n", *quality);
        g_fails++;
    } else if (quality) {
        printf("quality %f\n", *quality);
    }
    if (need(quartz, "_SFQuartzUmbrellaVersion"))
        printf("base SFQuartzUmbrellaVersion\n");
    Class filter = (Class)need(quartz, "_OBJC_CLASS_$_QuartzFilter");
    if (filter) {
        id dict = ((id (*)(id, SEL, id, id))objc_msgSend)(
            (id)objc_getClass("NSDictionary"), sel_registerName("dictionaryWithObject:forKey:"),
            utf8("Probe"), utf8("Name"));
        id made = ((id (*)(id, SEL, id))objc_msgSend)(
            (id)filter, sel_registerName("quartzFilterWithProperties:"), dict);
        id name = made ? ((id (*)(id, SEL))objc_msgSend)(made, sel_registerName("localizedName")) : nil;
        BOOL match = name && ((BOOL (*)(id, SEL, id))objc_msgSend)(
                                  name, sel_registerName("isEqualToString:"), utf8("Probe"));
        if (!match) {
            fprintf(stderr, "FAIL QuartzFilter\n");
            g_fails++;
        } else {
            printf("quartzFilter\n");
        }
    }

    check_class(coreimage, "_OBJC_CLASS_$_CICGContext", "CICGContext");
    check_class(coreimage, "_OBJC_CLASS_$_CIColorKernel", "CIColorKernel");
    check_class(coreimage, "_OBJC_CLASS_$_CIKernel", "CIKernel");
    check_class(coreimage, "_OBJC_CLASS_$_CISampler", "CISampler");
    check_class(coreimage, "_OBJC_CLASS_$_CIRenderDestination", "CIRenderDestination");
    Class kernel = (Class)need(coreimage, "_OBJC_CLASS_$_CIKernel");
    Class sampler = (Class)need(coreimage, "_OBJC_CLASS_$_CISampler");
    Class cicg = (Class)need(coreimage, "_OBJC_CLASS_$_CICGContext");
    if (kernel && sampler && cicg) {
        id k = msg(msg((id)kernel, "alloc"), "init");
        id s = ((id (*)(id, SEL, id))objc_msgSend)((id)sampler, sel_registerName("samplerWithImage:"), nil);
        id c = msg(msg((id)cicg, "alloc"), "init");
        id none = ((id (*)(id, SEL, id))objc_msgSend)((id)kernel, sel_registerName("kernelWithString:"), nil);
        if (k == nil || s == nil || c == nil || none != nil) {
            fprintf(stderr, "FAIL coreimage instances\n");
            g_fails++;
        } else {
            printf("coreimage\n");
        }
    }

    free(appkit_path);
    free(quartz_path);
    free(ci_path);
    if (g_fails) {
        fprintf(stderr, "FAIL %d\n", g_fails);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
