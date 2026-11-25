/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/*
 * SiliconForest A/B try-once boot state (abboot/README.md).
 *
 * One file on the SFBOOT partition, sf/bootstate.bin, 8192 bytes: two copies of a 64-byte record,
 * at offsets 0 and 4096, so a write of one copy never touches the block of the other. A reader takes
 * the valid copy with the higher sequence number; a writer overwrites the other one. Torn or lost
 * writes therefore leave the previous state readable.
 *
 * This file is pure logic: no I/O, no allocation, no libc (not even memcpy). The same source is
 * compiled into stage 1 (m1n1, freestanding; patches/stage1-v2), into the userland tool
 * sf-bootslot, and into the host tests and simulator.
 *
 * Slots. A is what the installer writes: sf/boot.bin (stage 2) + sf/kernel.bin. B is
 * sf/b/boot.bin + sf/b/kernel.bin. Each slot's stage 2 reads its own kernel file. Stage 1 only
 * chooses which stage 2 to start.
 */
#ifndef SF_AB_H
#define SF_AB_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SF_AB_STATE_FILE   "sf/bootstate.bin"
#define SF_AB_FILE_BYTES   8192u
#define SF_AB_COPY_STRIDE  4096u
#define SF_AB_REC_BYTES    64u
#define SF_AB_FORMAT       1u
#define SF_AB_MAGIC        "SFBOOTAB"

enum { SF_AB_SLOT_A = 0, SF_AB_SLOT_B = 1, SF_AB_SLOT_NONE = 0xff };

/* trial_state */
enum {
    SF_AB_TRIAL_NONE = 0,   /* no update pending: boot the default slot */
    SF_AB_TRIAL_ARMED = 1,  /* SAP staged and armed the trial slot: boot it once */
    SF_AB_TRIAL_TRIED = 2,  /* the trial slot was started once and has not been marked good */
    SF_AB_TRIAL_FAILED = 3, /* the trial slot never confirmed; the default slot is in use again */
};

/* Reasons: what stage 1 shows, and what the OS records in the state's reason field */
enum {
    SF_AB_R_NONE = 0,
    SF_AB_R_TRYING = 1,        /* first start of the updated slot */
    SF_AB_R_NOT_CONFIRMED = 2, /* the updated slot started once but never reported a clean start */
    SF_AB_R_STATE_CORRUPT = 3, /* both copies of the state record are damaged */
    SF_AB_R_TRIAL_DAMAGED = 4, /* the updated slot's stage 2 is missing or not what was armed */
    SF_AB_R_SLOT_DAMAGED = 5,  /* a slot's stage 2 is missing or not what the record says */
    SF_AB_R_UNVERIFIED = 6,    /* last resort: starting the default slot's files unchecked */
    SF_AB_R_COUNT
};

/* sf_ab_parse() results */
enum { SF_AB_ABSENT = 0, SF_AB_CORRUPT = 1, SF_AB_OK = 2 };

struct sf_ab_slot {
    uint32_t boot_bytes; /* size of this slot's boot.bin; 0 = unknown (not checked) */
    uint32_t boot_crc32; /* CRC-32 (IEEE) of it */
    uint32_t generation; /* release sequence the slot came from (informational) */
    uint8_t good;        /* 1: these exact files have been marked good once */
};

struct sf_ab_state {
    uint32_t seq;
    uint8_t default_slot;
    uint8_t trial_slot;
    uint8_t trial_state;
    uint8_t flags; /* must be 0 in format 1 */
    uint32_t reason;
    struct sf_ab_slot slot[2];
};

/* A boot plan: candidates in order. check: verify size and CRC before starting. */
struct sf_ab_candidate {
    uint8_t slot;
    uint8_t why; /* SF_AB_R_*: why this candidate is being started (NONE: say nothing) */
    bool check;
    uint32_t bytes;
    uint32_t crc32;
};

struct sf_ab_plan {
    int count;
    struct sf_ab_candidate c[3];
    int reason; /* the plan's reason: c[0].why */
    /* What a stage 1 that can write would store before starting c[0] (stage 1 v2 cannot; the
     * OS does it at its first start: sf-bootslot early). valid = there is something to write. */
    bool writeback_valid;
    struct sf_ab_state writeback;
};

uint32_t sf_ab_crc32(const void *data, size_t len);
uint32_t sf_ab_crc32_update(uint32_t crc, const void *data, size_t len);

/* Encodes one 64-byte record. */
void sf_ab_encode(const struct sf_ab_state *st, uint8_t out[SF_AB_REC_BYTES]);
/* Decodes and validates one 64-byte record. true if valid. */
bool sf_ab_decode(const uint8_t rec[SF_AB_REC_BYTES], struct sf_ab_state *st);
/*
 * Reads the state file (any length: a copy not wholly inside it counts as damaged). Returns
 * SF_AB_ABSENT when buf is NULL or len is 0, SF_AB_CORRUPT when neither copy is valid, SF_AB_OK
 * with *st the newer valid copy.
 * *copy (optional) gets the index of the copy used.
 */
int sf_ab_parse(const void *buf, size_t len, struct sf_ab_state *st, int *copy);
/*
 * Prepares a write: given the current file contents (8192 bytes), increments st->seq past the
 * newest valid copy, encodes it into rec and returns the byte offset of the copy to overwrite
 * (the older or damaged one).
 */
size_t sf_ab_prepare_write(const void *file, size_t len, struct sf_ab_state *st,
                           uint8_t rec[SF_AB_REC_BYTES]);

/* The stage-1 decision. load = result of sf_ab_parse(); st may be NULL unless load == SF_AB_OK. */
void sf_ab_decide(int load, const struct sf_ab_state *st, struct sf_ab_plan *plan);

/*
 * Runs a plan. notice(why, slot) is called before every candidate whose why is not NONE (stage 1
 * shows every reason but TRYING on the screen). try_slot starts (on the host: simulates starting)
 * one slot and returns 0 if the slot was handed over, < 0 if that slot cannot be used. Returns the
 * slot started, or -1 if none could be.
 */
struct sf_ab_ops {
    int (*try_slot)(void *ctx, const struct sf_ab_candidate *c);
    void (*notice)(void *ctx, int reason, int slot);
    void *ctx;
};
int sf_ab_run(const struct sf_ab_plan *plan, const struct sf_ab_ops *ops);

const char *sf_ab_boot_path(int slot);   /* "sf/boot.bin", "sf/b/boot.bin" */
const char *sf_ab_kernel_path(int slot); /* "sf/kernel.bin", "sf/b/kernel.bin" */
const char *sf_ab_reason_text(int reason);
char sf_ab_slot_name(int slot); /* 'a', 'b', '-' */

/* OS-side transitions (sf-bootslot, SAP). 0 on success, < 0 if not allowed; *changed set if st changed. */
int sf_ab_init(struct sf_ab_state *st, uint32_t a_bytes, uint32_t a_crc, uint32_t generation);
int sf_ab_begin_stage(struct sf_ab_state *st, int slot);
int sf_ab_arm(struct sf_ab_state *st, int slot, uint32_t bytes, uint32_t crc, uint32_t generation);
int sf_ab_on_boot(struct sf_ab_state *st, int running, bool *changed);
int sf_ab_mark_good(struct sf_ab_state *st, int running, bool *changed);

#endif
