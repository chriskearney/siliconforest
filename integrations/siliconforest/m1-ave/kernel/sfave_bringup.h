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
#endif
