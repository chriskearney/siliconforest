/* SPDX-License-Identifier: MIT */
#ifndef SFAVE_IOCTL_H
#define SFAVE_IOCTL_H
#include <stdint.h>
#ifdef __APPLE__
#include <sys/ioccom.h>
#else
#include <sys/ioctl.h>
#endif
#define SFAVE_ABI_VERSION 2
#define SFAVE_INFO_PRELOADED (1u<<0)
#define SFAVE_INFO_OUTSIDE_VM (1u<<1)
#define SFAVE_INFO_TEXT_IDENTITY (1u<<2)
#define SFAVE_INFO_COLD_RESERVED (1u<<3)
#define SFAVE_INFO_ENCODER_READY (1u<<4)
#define SFAVE_INFO_HANDSHAKE (1u<<5)
#define SFAVE_CAP_H264 (1u<<0)
/* ABI 2 handshake replaces the ABI 1 reserved slot. A client must not
 * require handshake == 0. SFAVE_CAP_H264 means the 13.5 coprocessor reached
 * READY; it is not an encode ioctl. ENCODER_READY stays clear. */
enum {
    SFAVE_HS_NONE = 0,
    SFAVE_HS_COLD = 1,
    SFAVE_HS_POWER = 2,
    SFAVE_HS_DAPF = 3,
    SFAVE_HS_STARTED = 4,
    SFAVE_HS_READY = 5
};
struct sfave_info {
    uint32_t abi, size, flags, caps;
    uint32_t soc, segments, error, handshake;
    uint32_t segment_size[2], segment_flags[2];
    char firmware[48], rtkit[48], iboot[48];
    uint32_t text_crc, data_crc, cold_pages, cold_nonzero;
    uint64_t phys_base, text_phys, data_phys;
};
#define SFAVE_IOC_INFO _IOR('E',1,struct sfave_info)
#endif
