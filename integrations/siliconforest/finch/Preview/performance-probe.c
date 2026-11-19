/* SPDX-License-Identifier: MIT */
/* Verify the existing open QuickTime absence provider, not a recording service.
 * Its packaged Unavailable.c (SF_KIND=3) defines this two-pointer boundary. */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char **argv) {
    if (argc!=3) return 2;
    void *image=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if (strcmp(argv[2],"missing")==0) {
        if (image) { dlclose(image); return 3; }
        printf("PERFORMANCE expected missing-path rejection: %s\n",dlerror());
        return 0;
    }
    if (!image) { fprintf(stderr,"FAIL dlopen: %s\n",dlerror()); return 4; }
    uint64_t (*start)(const void *,const void *)=dlsym(image,"PAMarkOperationStart");
    void (*end)(const void *,const void *)=dlsym(image,"PAMarkOperationEnd");
    if (!start || !end) return 5;
    if (start("owned probe","unsupported recording")!=0 || start(NULL,NULL)!=0) return 6;
    end("owned probe","unsupported recording"); end(NULL,NULL);
    dlclose(image);
    puts("PERFORMANCE PASS exact two exports; recording-token=0 (unavailable), end returns; no telemetry claim");
    return 0;
}
