/* SPDX-License-Identifier: MIT */
#ifndef SFAVE_PRELOAD_H
#define SFAVE_PRELOAD_H
#include <stddef.h>
#include <stdint.h>
/* Facts only. No image/table bytes or sample per-boot cookies belong here. */
struct sfave_segment {
    uint64_t physical, iova, remap;
    uint32_t size, flags;
};
struct sfave_preload {
    uint32_t soc, preloaded, segment_count, cold_reserved;
    struct sfave_segment segment[2];
    const char *iboot, *firmware, *rtkit;
};
/* Exact reviewed ABI identity and nonoverlapping, page-aligned reserved ranges.
 * cold_reserved is an adapter assertion about a REAL early boot reservation;
 * this pure check does not reserve pages or establish that assertion. */
int sfave_validate_preload(const struct sfave_preload *);
/* Geometry, iBoot and RTKit as validate_preload. Firmware may be the exact
 * dash tag, the cstring 6070.11.1, or a source path starting AppleAVE2FW/.
 * Unknown identities stay ENOTSUP. */
int sfave_preload_bootable(const struct sfave_preload *);
/* Validate the entire blob before the first register callback. Offsets passed
 * are relative to AVE's DPE bank. No bank mapping or power occurs here; programming includes DPE enable. */
struct sfave_register_io {
    void *context;
    int (*read)(void *, uint32_t, uint32_t *);
    int (*write)(void *, uint32_t, uint32_t);
};
int sfave_validate_dpe(const void *bytes, size_t size);
int sfave_program_dpe(const void *bytes, size_t size, const struct sfave_register_io *io);
#endif
