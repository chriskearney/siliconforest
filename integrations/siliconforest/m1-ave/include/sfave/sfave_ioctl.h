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
/* H.264 IPPP, one stream at a time. width/height are the coded size (multiples
 * of 16); crop_* (0 = none) go in the SPS. qp 0 = 30, bitrate 0 = fixed QP. */
#define SFAVE_ENC_VERBOSE (1u<<0)
struct sfave_enc_start {
    uint32_t width, height, crop_w, crop_h;
    uint32_t fps, qp, bitrate, profile_idc;
    uint32_t level_idc, cabac, flags, reserved;
};
/* y/uv: NV12 planes in the caller, height and height/2 rows. out: Annex-B. */
struct sfave_enc_frame {
    uint64_t y, uv, out;
    uint32_t y_stride, uv_stride, out_cap, out_len;
    uint32_t idr, keyframe, n, reserved;
};
#define SFAVE_IOC_ENC_START _IOW('E',2,struct sfave_enc_start)
#define SFAVE_IOC_ENC_FRAME _IOWR('E',3,struct sfave_enc_frame)
#define SFAVE_IOC_ENC_STOP _IO('E',4)
#endif
