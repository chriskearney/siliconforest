/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Our own check of the QuickTime prefix on SiliconForest, run before the application ever
 * meets it. No window, no input, no device. Run with the prefix's DYLD_* environment:
 *
 *   additions-probe SYMBOLS.txt      (lines: "<library path> <symbol>")
 *
 * Part 1: every listed symbol is found by the real dyld in the library at that path.
 * Part 2: the additions that claim behaviour show it; the absences fail the way they say.
 * One line per check, "PROBE ok|FAIL <what>", and "PROBE_RESULT failed=<n>" last.
 * Exit status 0 only when nothing failed. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <sys/ucontext.h>
#include <mach/mach.h>
#include <mach-o/dyld_images.h>

static int failed, checks;
static void check(int ok, const char *what) {
    checks++;
    if (!ok) failed++;
    printf("PROBE %s %s\n", ok ? "ok" : "FAIL", what);
}
typedef struct { int64_t value; int32_t timescale; uint32_t flags; int64_t epoch; } SFTime;
typedef struct { double x, y, w, h; } SFRect;

@interface SFProbeLayer : NSObject {
@public
    SFRect frame;
    NSString *name;
    NSArray *constraints, *sublayers;
}
@end
@implementation SFProbeLayer
- (SFRect)frame { return frame; }
- (void)setFrame:(SFRect)f { frame = f; }
- (SFRect)bounds { SFRect b = {0, 0, frame.w, frame.h}; return b; }
- (NSString *)name { return name; }
- (NSArray *)constraints { return constraints; }
- (NSArray *)sublayers { return sublayers; }
@end

/* A fault is reported by the probe itself (no crash report is written for it on this system):
 * where it happened, how deep the stack was, and the return addresses that recur most often in
 * the frame chain, each named by dladdr. Diagnostic only: not async-signal-safe, then _exit. */
static void sfName(const char *label, uintptr_t address) {
    Dl_info info;
    if (address && dladdr((void *)address, &info) && info.dli_fname)
        printf("PROBE fault %s 0x%lx %s+0x%lx (%s)\n", label, (unsigned long)address, info.dli_sname ? info.dli_sname : "?",
               (unsigned long)(address - (uintptr_t)(info.dli_sname ? info.dli_saddr : info.dli_fbase)), info.dli_fname);
    else
        printf("PROBE fault %s 0x%lx (no image)\n", label, (unsigned long)address);
}
static void sfFault(int sig, siginfo_t *si, void *context) {
    ucontext_t *uc = context;
    uintptr_t pc = (uintptr_t)uc->uc_mcontext->__ss.__pc, sp = (uintptr_t)uc->uc_mcontext->__ss.__sp;
    uintptr_t lr = (uintptr_t)uc->uc_mcontext->__ss.__lr, fp = (uintptr_t)uc->uc_mcontext->__ss.__fp;
    pthread_t self = pthread_self();
    uintptr_t top = (uintptr_t)pthread_get_stackaddr_np(self), size = pthread_get_stacksize_np(self);
    printf("PROBE fault signal %d address 0x%lx sp 0x%lx stack [0x%lx..0x%lx) %ld bytes from its end\n", sig, (unsigned long)si->si_addr,
           (unsigned long)sp, (unsigned long)(top - size), (unsigned long)top, (long)(sp - (top - size)));
    sfName("pc", pc & 0x0000ffffffffffffUL);
    sfName("lr", lr & 0x0000ffffffffffffUL);
    enum { kinds = 8 };
    uintptr_t seen[kinds] = {0};
    unsigned long count[kinds] = {0}, frames = 0;
    while (fp > sp && fp < top && (fp & 7) == 0 && frames < 2000000) {
        uintptr_t ret = ((uintptr_t *)fp)[1] & 0x0000ffffffffffffUL, next = ((uintptr_t *)fp)[0];
        frames++;
        for (int i = 0; i < kinds; i++) {
            if (seen[i] == ret) { count[i]++; break; }
            if (!seen[i]) { seen[i] = ret; count[i] = 1; break; }
        }
        if (next <= fp) break;
        fp = next;
    }
    printf("PROBE fault frames %lu\n", frames);
    struct task_dyld_info dyldInfo;
    mach_msg_type_number_t n = TASK_DYLD_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyldInfo, &n) == KERN_SUCCESS) {
        const struct dyld_all_image_infos *all = (const void *)(uintptr_t)dyldInfo.all_image_info_addr;
        printf("PROBE fault dyld loaded at 0x%lx (addresses below minus this are offsets into /usr/lib/dyld)\n", (unsigned long)(uintptr_t)all->dyldImageLoadAddress);
    }
    for (int i = 0; i < kinds && seen[i]; i++) {
        char label[32];
        snprintf(label, sizeof label, "return x%lu", count[i]);
        sfName(label, seen[i]);
    }
    fflush(stdout);
    _exit(128 + sig);
}
static void sfCatchFaults(void) {
    static char alternate[256 * 1024];
    stack_t ss = {.ss_sp = alternate, .ss_size = sizeof alternate, .ss_flags = 0};
    sigaltstack(&ss, NULL);
    struct sigaction sa = {0};
    sa.sa_sigaction = sfFault;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
}

#define SEND(type, ...) ((type (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    /* Line-buffered, so that every check printed before a crash survives in a file or pipe. */
    setvbuf(stdout, NULL, _IOLBF, 0);
    sfCatchFaults();
    if (argc != 2) {
        fprintf(stderr, "usage: additions-probe SYMBOLS.txt\n");
        return 2;
    }
    FILE *list = fopen(argv[1], "r");
    if (!list) {
        perror(argv[1]);
        return 2;
    }
    char path[512], symbol[256], what[900];
    while (fscanf(list, "%511s %255s", path, symbol) == 2) {
        printf("PROBE try %s %s\n", path, symbol);
        void *image = dlopen(path, RTLD_NOW);
        if (!image) printf("PROBE dlerror %s\n", dlerror());
        void *address = image ? dlsym(image, symbol[0] == '_' ? symbol + 1 : symbol) : NULL;
        snprintf(what, sizeof what, "bind %s from %s%s", symbol, strrchr(path, '/') + 1, image ? "" : " (library did not load)");
        check(address != NULL, what);
    }
    fclose(list);

    @try {
    /* Foundation */
    NSString *(*fullName)(id, SEL) = dlsym(RTLD_DEFAULT, "_NSFullMethodName");
    check(fullName && [fullName(@"x", @selector(length)) hasSuffix:@" length]"] && [fullName(@"x", @selector(length)) hasPrefix:@"-["], "_NSFullMethodName names an instance method");
    Class coordinator = objc_getClass("NSFileCoordinator");
    __block int ran = 0;
    id c = SEND(id, id)([coordinator alloc], sel_registerName("initWithFilePresenter:"), nil);
    NSURL *url = [NSURL fileURLWithPath:@"/private/var/tmp"];
    NSError *error = (id)1;
    SEND(void, NSURL *, NSUInteger, NSError **, void (^)(NSURL *))(c, sel_registerName("coordinateReadingItemAtURL:options:error:byAccessor:"), url, 0, &error, ^(NSURL *u) { ran += (u == url); });
    check(ran == 1 && error == nil, "NSFileCoordinator runs the reader once with the same URL and no error");
    NSDictionary *scriptError = nil;
    id script = SEND(id, NSString *)([objc_getClass("NSAppleScript") alloc], sel_registerName("initWithSource:"), @"beep");
    check(script && SEND(id, NSDictionary **)(script, sel_registerName("executeAndReturnError:"), &scriptError) == nil && scriptError != nil, "NSAppleScript refuses to run and gives an error dictionary");
    NSError *wrapperError = nil;
    Class wrapper = objc_getClass("NSFileWrapper");
    printf("PROBE info NSFileWrapper comes from %s\n", wrapper ? class_getImageName(wrapper) : "(no such class)");
    check(wrapper != Nil, "NSFileWrapper exists (one class: this system's, from AppKit)");
    if (wrapper && ![wrapper instancesRespondToSelector:sel_registerName("initWithURL:options:error:")])
        printf("PROBE info gap: this system's NSFileWrapper does not answer initWithURL:options:error: (not a claim of the prefix)\n");
    Class application = objc_getClass("NSApplication");
    NSBundle *appKit = application ? [NSBundle bundleForClass:application] : nil;
    NSArray *resources = appKit ? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[appKit resourcePath] error:NULL] : nil;
    printf("PROBE info AppKit bundle %s, %lu entries in its resources\n", appKit ? [[appKit bundlePath] UTF8String] : "(none)", (unsigned long)[resources count]);
    check(!application || [resources count] > 0, "a framework found through the prefix still has its resources (AppKit)");

    /* AVFoundation */
    id formatter = [[objc_getClass("AVTimeFormatter") alloc] init];
    SFTime t = {7325 * 600, 600, 1, 0};
    check([SEND(NSString *, SFTime)(formatter, sel_registerName("stringFromCMTime:"), t) isEqualToString:@"2:02:05"], "AVTimeFormatter formats 7325 s as 2:02:05");
    SFTime shortTime = {65, 1, 1, 0};
    check([SEND(NSString *, SFTime)(formatter, sel_registerName("stringFromCMTime:"), shortTime) isEqualToString:@"01:05"], "AVTimeFormatter formats 65 s as 01:05");
    id session = SEND(id, id, NSString *)([objc_getClass("AVAssetExportSession") alloc], sel_registerName("initWithAsset:presetName:"), nil, @"x");
    __block int exported = 0;
    SEND(void, void (^)(void))(session, sel_registerName("exportAsynchronouslyWithCompletionHandler:"), ^{ exported = 1; });
    for (int i = 0; i < 50 && !exported; i++) usleep(20000);
    check(exported && SEND(NSInteger)(session, sel_registerName("status")) == 4 && SEND(id)(session, sel_registerName("error")) != nil, "AVAssetExportSession calls back with status failed and an error");
    check([[objc_getClass("AVCaptureMovieFileOutput") alloc] init] == nil, "AVCaptureMovieFileOutput cannot be created");
    id composition = SEND(id)((id)objc_getClass("AVMutableComposition"), sel_registerName("composition"));
    check(composition && SEND(id, NSString *, int32_t)(composition, sel_registerName("addMutableTrackWithMediaType:preferredTrackID:"), @"vide", 0) == nil, "AVMutableComposition exists and adds no track");

    /* AVFAudio */
    __block int arbitrated = 0;
    id arbiter = SEND(id)((id)objc_getClass("AVAudioRoutingArbiter"), sel_registerName("sharedRoutingArbiter"));
    SEND(void, NSInteger, void (^)(BOOL, NSError *))(arbiter, sel_registerName("beginArbitrationWithCategory:completionHandler:"), 0, ^(BOOL changed, NSError *e) { arbitrated = (!changed && e == nil); });
    check(arbitrated, "AVAudioRoutingArbiter completes at once: device unchanged, no error");

    /* QuartzCore: MinX of b = MaxX of a + 10; Width of b = Width of superlayer * 0.5 */
    Class constraint = objc_getClass("CAConstraint");
    SEL make = sel_registerName("constraintWithAttribute:relativeTo:attribute:scale:offset:");
    SFProbeLayer *parent = [[SFProbeLayer alloc] init], *a = [[SFProbeLayer alloc] init], *b = [[SFProbeLayer alloc] init];
    parent->frame = (SFRect){0, 0, 400, 100};
    a->frame = (SFRect){20, 0, 80, 30};
    a->name = @"a";
    b->frame = (SFRect){0, 5, 10, 30};
    b->constraints = [NSArray arrayWithObjects:SEND(id, int, NSString *, int, double, double)((id)constraint, make, 0, @"a", 2, 1.0, 10.0),
                                               SEND(id, int, NSString *, int, double, double)((id)constraint, make, 3, @"superlayer", 3, 0.5, 0.0), nil];
    parent->sublayers = [NSArray arrayWithObjects:a, b, nil];
    id manager = SEND(id)((id)objc_getClass("CAConstraintLayoutManager"), sel_registerName("layoutManager"));
    SEND(void, id)(manager, sel_registerName("layoutSublayersOfLayer:"), parent);
    check(b->frame.x == 110 && b->frame.w == 200 && b->frame.y == 5 && b->frame.h == 30, "CAConstraintLayoutManager places a sublayer by two constraints");

    /* AVKit */
    id resolver = [[objc_getClass("AVPlayerControllerTimeResolver") alloc] init];
    check(resolver && SEND(double)(resolver, sel_registerName("interval")) == 1 && SEND(double)(resolver, sel_registerName("currentTime")) == 0, "time resolver starts with interval 1 and time 0");
    SEND(void, double)(resolver, sel_registerName("setCurrentTimeWithinEndTimes:"), 2.5);
    check(SEND(double)(resolver, sel_registerName("currentTime")) == 2.5, "time resolver without a controller: the time properties are one value");
    Class slider = objc_getClass("AVVolumeControlSlider"), controls = objc_getClass("AVPlayerControlsViewController");
    check(slider && class_getSuperclass(slider) == objc_getClass("AVVolumeControlView") && class_getSuperclass(class_getSuperclass(slider)) == objc_getClass("NSView"), "AVVolumeControlSlider is a view through AVVolumeControlView");
    check(controls && class_getSuperclass(controls) == objc_getClass("AVControlsViewController") && class_getSuperclass(class_getSuperclass(controls)) == objc_getClass("NSViewController"), "AVPlayerControlsViewController is a view controller through AVControlsViewController");
    check(objc_getClass("AVAudioView") && class_getSuperclass(objc_getClass("AVAudioView")) == objc_getClass("NSView"), "AVAudioView exists and is a view");
    check(objc_getClass("AVPlayerView") != Nil && objc_getClass("AVCaptureView") != Nil, "AVPlayerView and AVCaptureView exist for the application to subclass");

    /* C absences and real functions */
    int32_t (*displays)(SFRect, uint32_t, uint32_t *, uint32_t *) = dlsym(RTLD_DEFAULT, "CGGetDisplaysWithRect");
    uint32_t count = 99;
    SFRect everything = {-100000, -100000, 200000, 200000};
    int32_t status = displays ? displays(everything, 0, NULL, &count) : -1;
    printf("PROBE info CGGetDisplaysWithRect status %d, %u display(s) intersect a very large rectangle\n", status, count);
    check(displays && (status == 0 || status == 1006) && count != 99, "CGGetDisplaysWithRect answers or says it cannot");
    void *(*spaces)(int, int) = dlsym(RTLD_DEFAULT, "CGSCopySpaces");
    check(spaces && spaces(0, 7) == NULL, "CGSCopySpaces reports no Spaces");
    _Bool (*airdrop)(void) = dlsym(RTLD_DEFAULT, "_CSDeviceSupportsAirDrop");
    check(airdrop && !airdrop(), "_CSDeviceSupportsAirDrop is false");
    _Bool (*alpha)(const void *) = dlsym(RTLD_DEFAULT, "FigVideoFormatDescriptionContainsAlphaChannel");
    check(alpha && !alpha(NULL), "FigVideoFormatDescriptionContainsAlphaChannel(NULL) is false");
    _Bool (*stereo)(void) = dlsym(RTLD_DEFAULT, "VTIsStereoMVHEVCDecodeSupported");
    check(stereo && !stereo(), "VTIsStereoMVHEVCDecodeSupported is false");
    ptrdiff_t *copyright = dlsym(RTLD_DEFAULT, "OBJC_IVAR_$_NSSystemInfoPanel.copyrightView");
    printf("PROBE info About panel copyrightView offset %ld (0 means the class has neither copyrightView nor legalTextField)\n", copyright ? (long)*copyright : -1L);

    } @catch (id exception) {
        char what[300];
        snprintf(what, sizeof what, "behaviour checks stopped by an exception: %s", [[exception description] UTF8String]);
        check(0, what);
    }
    printf("PROBE_RESULT checks=%d failed=%d\n", checks, failed);
    [pool release];
    return failed ? 1 : 0;
}
