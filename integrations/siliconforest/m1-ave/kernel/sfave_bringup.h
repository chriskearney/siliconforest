/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef SFAVE_BRINGUP_H
#define SFAVE_BRINGUP_H
#include <stdint.h>
/* Identity and the cold DATA snapshot are already done. This powers the
 * T8103 AVE, programs DAPF and CPUDART stream 0, and runs the 13.5 IPC
 * handshake. It does not submit an encode. *caps is set only at READY. */
struct sfave_boot_in {
	uint64_t text_phys, data_phys, data_remap;
	uint32_t text_size, data_size;
	const char *firmware, *rtkit, *iboot;
};
int sfave_bringup(const struct sfave_boot_in *in, uint32_t *handshake, uint32_t *caps);
#ifdef __cplusplus
extern "C" {
#endif
struct sfave_ipc;
struct sfave_enc_start;
struct sfave_enc_frame;
/* After READY. Bank 0 DPE, 1 ASC, 2 SVE. */
struct sfave_ipc *sfave_hw_ipc(void);
int sfave_hw_bank(unsigned which, volatile void **va, uint64_t *phys, uint64_t *len);
int sfave_hw_dart_check(void);
/* The encoder (sfave_lx.c). Positive errno. All under the driver's lock. */
int sfave_enc_start(struct sfave_enc_start *);
int sfave_enc_frame(struct sfave_enc_frame *);
int sfave_enc_stop(void);
#ifdef __cplusplus
}
#endif
#endif
