// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
// Status 0 only with a libSystem that exports the seven symbols of
// ../../../../libsystem-default/patches/legacy-mach-and-errno-exports.patch: they are bound when the
// program is loaded, so dyld refuses to start it with a libSystem that lacks one. The guarded
// installer's proof (../../../../macos-compat/sf-lib-install.sh) that a process gets the new file.
#include <errno.h>
#include <sys/types.h>
#include <stdio.h>
#include <string.h>
#include <mach/mach.h>
extern const char *const sys_errlist[];
extern const int sys_nerr;
extern boolean_t exc_server(mach_msg_header_t *, mach_msg_header_t *);
extern kern_return_t exception_raise(mach_port_t, mach_port_t, mach_port_t, exception_type_t, exception_data_t, mach_msg_type_number_t);
extern kern_return_t bootstrap_subset(mach_port_t, mach_port_t, mach_port_t *);
extern kern_return_t bootstrap_create_server(mach_port_t, char *, uid_t, boolean_t, mach_port_t *);
extern kern_return_t bootstrap_create_service(mach_port_t, char *, mach_port_t *);
int main(void)
{
    const void *volatile fns[] = { (const void *)exc_server, (const void *)exception_raise, (const void *)bootstrap_subset,
                                   (const void *)bootstrap_create_server, (const void *)bootstrap_create_service };
    int bound = 0;
    for (unsigned i = 0; i < sizeof fns / sizeof *fns; i++) bound += fns[i] != NULL;
    int ok = sys_nerr > ENOENT && sys_errlist[ENOENT] && strcmp(sys_errlist[ENOENT], strerror(ENOENT)) == 0 && bound == 5;
    printf("sf-vlc-libsystem-probe: sys_nerr %d, sys_errlist[ENOENT] \"%s\", %d of 5 functions bound: %s\n",
           sys_nerr, sys_errlist[ENOENT] ? sys_errlist[ENOENT] : "(null)", bound, ok ? "ok" : "FAIL");
    return ok ? 0 : 1;
}
