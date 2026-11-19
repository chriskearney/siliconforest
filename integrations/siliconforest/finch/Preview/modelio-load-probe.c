/* SPDX-License-Identifier: MIT */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    const unsigned *count = dlsym(handle, "SFModelIOImplementedAPICount");
    const char *scope = dlsym(handle, "SFModelIOLoadContractScope");
    if (!count || *count != 0 || !scope) return 1;
    printf("MODELIO load-identity=PASS implemented-APIs=%u scope=%s\n", *count, scope);
    dlclose(handle);
    return 0;
}
