// SPDX-License-Identifier: MIT OR Apache-2.0
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* Export-trie spellings. dyld's dlsym adds one leading underscore when the
 * argument does not already have one, so the callable form drops that byte. */
static const char *const trie_names[] = {
    "_$s10Foundation21_BridgedStoredNSErrorPAAE_8userInfox4CodeQz_SDySSypGtcfC",
    "_$s10Foundation8URLErrorV4CodeV14unsupportedURLAEvgZ",
    "_$s10Foundation8URLErrorV4CodeVMa",
    "_$s10Foundation8URLErrorV8_nsErrorSo7NSErrorCvg",
    "_$s10Foundation8URLErrorVAA21_BridgedStoredNSErrorAAMc",
    "_$s10Foundation8URLErrorVMa",
};
static const char *const dlsym_names[] = {
    "$s10Foundation21_BridgedStoredNSErrorPAAE_8userInfox4CodeQz_SDySSypGtcfC",
    "$s10Foundation8URLErrorV4CodeV14unsupportedURLAEvgZ",
    "$s10Foundation8URLErrorV4CodeVMa",
    "$s10Foundation8URLErrorV8_nsErrorSo7NSErrorCvg",
    "$s10Foundation8URLErrorVAA21_BridgedStoredNSErrorAAMc",
    "$s10Foundation8URLErrorVMa",
};

static int32_t count_hits(void *handle, const char *const *names, int32_t count) {
    int32_t found = 0;
    for (int32_t i = 0; i < count; i++) {
        if (dlsym(handle, names[i]) != NULL) {
            found++;
        }
    }
    return found;
}

int32_t sf_url_error_symbols(int32_t *missing) {
    const char *image = NULL;
    uint32_t images = _dyld_image_count();
    for (uint32_t i = 0; i < images; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name != NULL && strstr(name, "libswiftFoundation.dylib") != NULL) {
            image = name;
            break;
        }
    }
    void *handle = NULL;
    if (image != NULL) {
        handle = dlopen(image, RTLD_NOLOAD | RTLD_FIRST | RTLD_LAZY);
    }
    int32_t def_trie = count_hits(RTLD_DEFAULT, trie_names, 6);
    int32_t def_dlsym = count_hits(RTLD_DEFAULT, dlsym_names, 6);
    int32_t img_trie = handle == NULL ? -1 : count_hits(handle, trie_names, 6);
    int32_t img_dlsym = handle == NULL ? -1 : count_hits(handle, dlsym_names, 6);
    void *control_plain = dlsym(RTLD_DEFAULT, "NSFileAttributeStringEncoding");
    void *control_trie = dlsym(RTLD_DEFAULT, "_NSFileAttributeStringEncoding");
    fprintf(stderr,
            "SYMBOLS image=%s def_trie=%d def_dlsym=%d img_trie=%d img_dlsym=%d control_plain=%d control_trie=%d\n",
            image == NULL ? "none" : image,
            def_trie, def_dlsym, img_trie, img_dlsym,
            control_plain != NULL, control_trie != NULL);
    int32_t found = 0;
    int32_t counts[4] = { def_trie, def_dlsym, img_trie, img_dlsym };
    for (int32_t i = 0; i < 4; i++) {
        if (counts[i] > found) {
            found = counts[i];
        }
    }
    if (missing != NULL) {
        *missing = 6 - found;
    }
    return found;
}
