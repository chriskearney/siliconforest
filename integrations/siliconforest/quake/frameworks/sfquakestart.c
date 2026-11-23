// SPDX-License-Identifier: MIT
// Starts the engine of the Mac Source Ports QuakeSpasm 0.96.3 app without changing
// its files. Upstream's Info.plist names the Launcher nib, whose objects make the
// application delegate. This build's Info.plist has no NSMainNibFile, so
// NSApplicationMain runs with no delegate and SDL_main is never called.
//
// Loaded with DYLD_INSERT_LIBRARIES, this wraps -[NSApplication run] and, when no
// delegate is set, makes the app's own SDLMain class the delegate. SDLMain then
// calls SDL_main with the real command line when the application finishes
// launching. (Interposing NSApplicationMain does not work here: this dyld applies
// the tuple to the inserted image too, so the call to the original recurses.)
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

static IMP original_run;

static void sfquake_run(id self, SEL cmd)
{
    id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    void (*sendObject)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
    if (send(self, sel_registerName("delegate")) == nil) {
        Class delegateClass = objc_getClass("SDLMain");
        if (delegateClass == Nil) {
            fprintf(stderr, "sfquakestart: no SDLMain class\n");
            exit(70);
        }
        id delegate = send(send((id)delegateClass, sel_registerName("alloc")), sel_registerName("init"));
        sendObject(self, sel_registerName("setDelegate:"), delegate);
    }
    ((void (*)(id, SEL))original_run)(self, cmd);
}

__attribute__((constructor))
static void sfquake_install(void)
{
    Class application = objc_getClass("NSApplication");
    Method run = application ? class_getInstanceMethod(application, sel_registerName("run")) : NULL;
    if (run == NULL) {
        fprintf(stderr, "sfquakestart: no -[NSApplication run]\n");
        exit(70);
    }
    original_run = method_setImplementation(run, (IMP)sfquake_run);
}
