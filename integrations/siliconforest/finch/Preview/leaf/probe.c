// SPDX-License-Identifier: MIT
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { double latitude, longitude; } Coordinate;
extern Coordinate CLLocationCoordinate2DMake(double latitude, double longitude);
extern void *_sl_dlopen(const char **paths, char **error);

int main(void) {
    Coordinate coordinate = CLLocationCoordinate2DMake(-33.867, 151.207);
    if (coordinate.latitude != -33.867 || coordinate.longitude != 151.207)
        return 2;
    const char *missing = "/private/tmp/sf-preview-test-missing.dylib";
    const char *paths[] = { missing, "/usr/lib/libSystem.B.dylib", NULL };
    char *error = NULL;
    void *handle = _sl_dlopen(paths, &error);
    if (!handle || !dlsym(handle, "malloc") || error)
        return 3;
    dlclose(handle);

    const char *absent[] = { missing, NULL };
    if (_sl_dlopen(absent, &error) || !error)
        return 4;
    free(error);
    error = NULL;
    if (_sl_dlopen(NULL, &error) || !error)
        return 5;
    free(error);
    puts("coordinate construction and soft linking fallback passed");
    return 0;
}
