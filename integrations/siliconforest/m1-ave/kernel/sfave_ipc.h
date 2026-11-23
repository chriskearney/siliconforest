/* SPDX-License-Identifier: GPL-2.0-only */
/* Polling T8103/13.5 transport port of upstream ave_ipc.c. See ../NOTICE.
 * Caller serializes all calls and owns mapped/coherent DMA until a real halt.
 * This module does NOT power/start the core, allocate/map DMA or reserve DATA.
 * The INFO ioctl bring-up calls it after the coprocessor is powered. */
#ifndef SFAVE_IPC_H
#define SFAVE_IPC_H
#include <stddef.h>
#include "sfave/sfave_preload.h"
#include "upstream/ave_abi_boot.h"
struct sfave_ipc_ops {
 void *context;
 int (*read)(void *,uint32_t,uint32_t *); /* offsets in SVE bank only */
 int (*write)(void *,uint32_t,uint32_t);
 void (*delay_us)(void *,uint32_t);
 void (*barrier)(void *); /* real coherent DMA + device ordering */
};
enum sfave_ipc_phase {SFAVE_IPC_IDLE,SFAVE_IPC_CONFIGURED,SFAVE_IPC_READY,SFAVE_IPC_FAILED};
struct sfave_ipc_message {uint64_t firmware;void *payload;uint32_t bytes,flags;};
struct sfave_ipc {
 struct sfave_ipc_ops ops;
 unsigned char *cpu;
 uint64_t iova,fw_base,heap_iova;
 uint32_t bytes,heap_bytes,client_bytes;
 enum sfave_ipc_phase phase;
 struct ave_ring ring[AVE_CH_MAX];
 uint32_t bound,doorbell[AVE_CH_MAX];
 struct sfave_ipc_message pending_reply;
 unsigned reply_pending;
};
/* DMA must already be exclusive, coherent, mapped and 16KiB aligned. Only
 * validated cold-reserved preload is accepted; validation cannot prove that
 * the platform's reservation assertion is true. No device I/O on init. */
int sfave_ipc_init(struct sfave_ipc *,const struct sfave_preload *,
 const struct sfave_ipc_ops *,void *,uint64_t,uint32_t,uint64_t,uint32_t);
int sfave_ipc_configure(struct sfave_ipc *);
/* Call after the platform starts the core. Timeouts/faults quarantine state;
 * nothing here frees DMA while a core might still reference it. */
int sfave_ipc_handshake(struct sfave_ipc *);
void *sfave_ipc_from_fw(struct sfave_ipc *,uint64_t,size_t);
/* Post-handshake rings. Caller copies a completion before returning its
 * credit with ack; receiving alone does not let firmware reuse its buffer. */
int sfave_ipc_send(struct sfave_ipc *,unsigned channel,uint64_t payload_iova,uint32_t bytes,uint32_t flags);
int sfave_ipc_receive(struct sfave_ipc *,unsigned channel,struct sfave_ipc_message *);
int sfave_ipc_ack(struct sfave_ipc *,unsigned channel,const struct sfave_ipc_message *);
#endif
