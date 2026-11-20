/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * qtp-exitwatch: why a program ends, or where it waits. Inserted with DYLD_INSERT_LIBRARIES into a
 * program we test (our own runs of QuickTime Player on SiliconForest); it changes nothing the program does.
 * It writes to stderr and, when QTP_EXITWATCH is set, also appends to that file:
 *   QTPEXIT exit <status> / _exit <status> / abort   with the calling thread's backtrace
 *   QTPEXIT signal <n>                               a fatal signal, with a backtrace, then the default action
 *   QTPEXIT uncaught <class> <reason>                an Objective-C exception nothing caught
 *   QTPEXIT stack (SIGUSR2)                          the backtrace of the thread the signal interrupted
 * Each frame is "image+offset symbol" (dladdr), so frames of a stripped program can be mapped later. */
#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <objc/runtime.h>
#include <objc/message.h>

/* objc/objc-exception.h declares this for Objective-C only */
typedef void (*sfUncaughtHandler)(id exception);
extern sfUncaughtHandler objc_setUncaughtExceptionHandler(sfUncaughtHandler handler);

static int sfFile = -1;

static void sfWrite(const char *text)
{
    size_t n = strlen(text);
    write(2, text, n);
    if (sfFile >= 0)
        write(sfFile, text, n);
}

static void sfBacktrace(const char *what)
{
    void *frames[64];
    char line[640];
    int n = backtrace(frames, 64);
    snprintf(line, sizeof line, "QTPEXIT %s pid %d frames %d\n", what, (int)getpid(), n);
    sfWrite(line);
    for (int i = 0; i < n; i++) {
        Dl_info info;
        const char *image = "?", *name = "?";
        unsigned long offset = 0, symbolOffset = 0;
        if (dladdr(frames[i], &info)) {
            if (info.dli_fname) {
                image = strrchr(info.dli_fname, '/') ? strrchr(info.dli_fname, '/') + 1 : info.dli_fname;
                offset = (unsigned long)((char *)frames[i] - (char *)info.dli_fbase);
            }
            if (info.dli_sname) {
                name = info.dli_sname;
                symbolOffset = (unsigned long)((char *)frames[i] - (char *)info.dli_saddr);
            }
        }
        snprintf(line, sizeof line, "QTPEXIT   #%-2d %s+0x%lx %s+%lu\n", i, image, offset, name, symbolOffset);
        sfWrite(line);
    }
}

/* ---- exits ---------------------------------------------------------------------------------------- */
static void sfExit(int status)
{
    char line[64];
    snprintf(line, sizeof line, "exit %d", status);
    sfBacktrace(line);
    exit(status);
}

static void sfUnderscoreExit(int status)
{
    char line[64];
    snprintf(line, sizeof line, "_exit %d", status);
    sfBacktrace(line);
    _exit(status);
}

static void sfAbort(void)
{
    sfBacktrace("abort");
    abort();
}

struct sfInterpose { const void *replacement, *replacee; };
__attribute__((used, section("__DATA,__interpose"))) static const struct sfInterpose sfInterposers[] = {
    { (const void *)sfExit, (const void *)exit },
    { (const void *)sfUnderscoreExit, (const void *)_exit },
    { (const void *)sfAbort, (const void *)abort },
};

/* ---- signals ---------------------------------------------------------------------------------------- */
static void sfFatal(int sig)
{
    char line[48];
    snprintf(line, sizeof line, "signal %d", sig);
    sfBacktrace(line);
    signal(sig, SIG_DFL);
    raise(sig);
}

static void sfStack(int sig)
{
    (void)sig;
    sfBacktrace("stack (SIGUSR2)");
}

/* ---- uncaught Objective-C exceptions ------------------------------------------------------------------- */
static const char *sfString(id object, const char *selector)
{
    if (object == nil)
        return "(nil)";
    id value = ((id (*)(id, SEL))objc_msgSend)(object, sel_registerName(selector));
    if (value == nil)
        return "(nil)";
    const char *text = ((const char *(*)(id, SEL))objc_msgSend)(value, sel_registerName("UTF8String"));
    return text ? text : "(no text)";
}

static void sfUncaught(id exception)
{
    char line[1024];
    snprintf(line, sizeof line, "QTPEXIT uncaught %s: %s\n", sfString(exception, "name"), sfString(exception, "reason"));
    sfWrite(line);
    sfBacktrace("uncaught exception");
}

__attribute__((constructor)) static void sfStart(void)
{
    const char *path = getenv("QTP_EXITWATCH");
    if (path && *path)
        sfFile = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    int fatal[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP, SIGSYS };
    for (size_t i = 0; i < sizeof fatal / sizeof fatal[0]; i++)
        signal(fatal[i], sfFatal);
    signal(SIGUSR2, sfStack);
    objc_setUncaughtExceptionHandler(sfUncaught);
    char line[64];
    snprintf(line, sizeof line, "QTPEXIT watching pid %d\n", (int)getpid());
    sfWrite(line);
}
