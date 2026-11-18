// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
// What of VLC's system-wide changes (docs/roadmap/issues/SF-AH-vlc.md, "Proposal: installing VLC's
// changes system-wide") the system in use has, one line per change: "SFVLCFEATURE <step> <name> yes|no".
// Everything is looked up at run time (dlopen, dlsym, the Objective-C runtime), so the probe runs on
// the system before, during and after the install alike; status 0 unless it cannot run at all.
// Step 3 (QuartzCore 0320, 0321, 0326) changes behaviour only: the installer's hashes stand for it.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>

#define F "/System/Library/Frameworks/"
static void say(int step, const char *name, int yes) { printf("SFVLCFEATURE %d %s %s\n", step, name, yes ? "yes" : "no"); }
// a framework this root cannot load at all (in QEMU: no graphics stack): its additions are not judged
static void unloadable(int step, const char *name) { printf("SFVLCFEATURE %d %s unloadable\n", step, name); }
static void *load(const char *path)
{
    void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (h == NULL) printf("SFVLCLOADERROR %s: %s\n", path, dlerror());
    return h;
}

@interface SFVLCPerform : NSObject { @public int ran; }
- (void)mark;
@end
@implementation SFVLCPerform
- (void)mark { ran++; }
@end

int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    // step 1: the frameworks VLC links that the system did not have
    say(1, "AddressBook", load(F "AddressBook.framework/AddressBook") != NULL);
    say(1, "ScriptingBridge", load(F "ScriptingBridge.framework/ScriptingBridge") != NULL);
    say(1, "WebKit", load(F "WebKit.framework/WebKit") != NULL);
    say(1, "MediaPlayer", load(F "MediaPlayer.framework/MediaPlayer") != NULL);
    // step 2: additions in the CoreFoundation and Foundation wrappers and in CoreServices.pd
    load(F "CoreFoundation.framework/Versions/A/CoreFoundation");
    load(F "Foundation.framework/Versions/C/Foundation");
    void *cs = load(F "CoreServices.framework/Versions/A/CoreServices");
    say(2, "CoreFoundation.NSGregorianCalendar", dlsym(RTLD_DEFAULT, "NSGregorianCalendar") != NULL);
    say(2, "Foundation.NSAppleScript", objc_getClass("NSAppleScript") != Nil);
    say(2, "CoreServices.FSGetCatalogInfo", cs && dlsym(cs, "FSGetCatalogInfo") != NULL);
    say(2, "CoreServices.FSGetVolumeParms", cs && dlsym(cs, "FSGetVolumeParms") != NULL);
    say(2, "CoreServices.LSCopyAllHandlersForURLScheme", cs && dlsym(cs, "LSCopyAllHandlersForURLScheme") != NULL);
    // step 3: QuartzCore loads (its changes are behaviour only)
    if (load(F "QuartzCore.framework/Versions/A/QuartzCore") != NULL) say(3, "QuartzCore.loads", 1);
    else unloadable(3, "QuartzCore.loads");
    // step 4: AppKit 0322 adds -[NSMenuItem parentItem] (0323-0328 change behaviour)
    if (load(F "AppKit.framework/Versions/C/AppKit") != NULL) {
        Class item = objc_getClass("NSMenuItem");
        say(4, "AppKit.NSMenuItem.parentItem", item && class_getInstanceMethod(item, sel_registerName("parentItem")) != NULL);
    } else unloadable(4, "AppKit.NSMenuItem.parentItem");
    // step 5: libFoundation queues a main-thread perform that does not wait
    SFVLCPerform *p = [[SFVLCPerform alloc] init];
    [p performSelectorOnMainThread:@selector(mark) withObject:nil waitUntilDone:NO];
    int atOnce = p->ran;
    for (int i = 0; i < 50 && p->ran == 0; i++) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    say(5, "libFoundation.main-thread-perform-queued", atOnce == 0 && p->ran == 1);
    [p release];
    // step 6: libSystem's seven exports
    static const char *const exports[] = { "sys_errlist", "sys_nerr", "exc_server", "exception_raise",
        "bootstrap_subset", "bootstrap_create_server", "bootstrap_create_service" };
    void *ls = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW);
    for (unsigned i = 0; i < sizeof exports / sizeof *exports; i++) {
        char n[64]; snprintf(n, sizeof n, "libSystem.%s", exports[i]);
        say(6, n, ls && dlsym(ls, exports[i]) != NULL);
    }
    [pool release];
    return 0;
}
