/* SPDX-License-Identifier: MIT
   When SF_LOG_EXC is set, print NSException reasons TextEdit does not
   catch. The Preview hook covers two NSException entry points; this also
   covers +raise:format:, which is what an unrecognized selector uses. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdarg.h>

static void sf_log(id exc, const char *how)
{
    if (!getenv("SF_LOG_EXC") || !exc)
        return;
    NSString *name = [exc respondsToSelector:@selector(name)] ? [exc name] : @"?";
    NSString *reason = [exc respondsToSelector:@selector(reason)] ? [exc reason] : @"?";
    fprintf(stderr, "SF_TE_EXC %s name=%s reason=%s\n", how,
            name ? [name UTF8String] : "?",
            reason ? [reason UTF8String] : "?");
    fflush(stderr);
}

static void (*g_raise)(id, SEL);
static void sf_raise(id self, SEL _cmd)
{
    sf_log(self, "raise");
    g_raise(self, _cmd);
}

/* +raise:format: is variadic, so the replacement builds the exception and
   raises that. The arguments are consumed here. */
static void sf_raise_format(id self, SEL _cmd, NSString *name, NSString *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    NSString *reason = fmt ? [[NSString alloc] initWithFormat:fmt arguments:ap] : nil;
    va_end(ap);
    NSException *exc = [NSException exceptionWithName:name reason:reason userInfo:nil];
    sf_log(exc, "raise:format:");
    [exc raise];
}

__attribute__((constructor))
static void sf_te_install_exception_log(void)
{
    if (!getenv("SF_LOG_EXC"))
        return;
    Class cls = [NSException class];
    Method m = class_getInstanceMethod(cls, @selector(raise));
    if (m)
        g_raise = (void (*)(id, SEL))method_setImplementation(m, (IMP)sf_raise);
    Method c = class_getClassMethod(cls, @selector(raise:format:));
    if (c)
        method_setImplementation(c, (IMP)sf_raise_format);
}
