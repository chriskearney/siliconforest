/* SPDX-License-Identifier: MIT */
/* Resolve the preceding provider's actual export list against a private dylib.
 * CLI only: no Foundation API calls, window/session access or installation. */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: exports-probe private-library baseline-symbols\n");
        return 2;
    }
    FILE *symbols = fopen(argv[2], "r");
    if (!symbols) { perror("symbols"); return 2; }
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "dlopen: %s\n", dlerror()); fclose(symbols); return 1; }
    unsigned count = 0, missing = 0;
    char name[16384];
    while (fgets(name, sizeof(name), symbols)) {
        size_t length = strlen(name);
        if (length < 2 || name[length - 1] != '\n' || name[0] != '_') {
            fprintf(stderr, "invalid Mach-O export list\n");
            fclose(symbols); return 2;
        }
        name[length - 1] = '\0';
        /* Mach-O's C prefix is absent from the dlsym spelling. */
        (void)dlerror();
        void *address = dlsym(library, name + 1);
        const char *error = dlerror();
        if (!address || error) {
            fprintf(stderr, "missing %s: %s\n", name, error ? error : "null address");
            ++missing;
        }
        ++count;
    }
    int read_error = ferror(symbols);
    fclose(symbols);
    /* Keep Swift/Objective-C runtime metadata mapped until process exit. */
    if (read_error || !count) { fprintf(stderr, "empty/unreadable list\n"); return 2; }
    printf("Foundation exports resolved=%u missing=%u\n", count - missing, missing);
    return missing ? 1 : 0;
}
