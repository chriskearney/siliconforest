/* SPDX-License-Identifier: MIT */
#ifndef SFAVE_IDENTITY_H
#define SFAVE_IDENTITY_H
#include <stddef.h>
/* Reads a caller-validated normal-RAM TEXT span. Returns one unique numeric
 * version after prefix; repeated identical tags are fine, conflicting tags fail.
 * No image data is returned, only the bounded ASCII prefix+version. */
int sfave_find_identity(const void *, size_t, const char *, char *, size_t);
/* Registry text may be padded OSData, bounded non-NUL data, or an OSString.
 * Copy printable text only; never return binary/padding beyond its first NUL. */
int sfave_copy_metadata_text(const void *,size_t,char *,size_t);
/* What the mapped TEXT actually contains. DASH is AppleAVE2FW-<version>.
 * UTF16 is that tag in UTF-16LE, copied out as ASCII. VERSION is the exact
 * cstring 6070.11.1 and only when an AppleAVE2FW/ landmark is also present;
 * the dash prefix is not invented. SOURCE is a cstring starting AppleAVE2FW/. */
enum {
    SFAVE_FW_NONE = 0,
    SFAVE_FW_DASH = 1,
    SFAVE_FW_UTF16 = 2,
    SFAVE_FW_VERSION = 3,
    SFAVE_FW_SOURCE = 4
};
struct sfave_firmware_desc {
    char text[48];
    int kind;
    unsigned path_hits;
    unsigned firmware_path;
};
int sfave_describe_firmware(const void *, size_t, struct sfave_firmware_desc *);
#endif
