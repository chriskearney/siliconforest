/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/* SiliconForest A/B try-once boot state: pure logic, shared by stage 1, sf-bootslot and the tests. */
#include "sf_ab.h"

/* Record layout, little-endian (abboot/README.md):
 *   0  magic "SFBOOTAB"      8  u16 format (1)     10 u16 record bytes (64)   12 u32 seq
 *  16  u8 default slot      17  u8 trial slot     18  u8 trial state          19  u8 flags (0)
 *  20  u32 reason
 *  24  slot A: u32 boot bytes, u32 boot crc32, u32 generation, u8 good, 3 bytes 0
 *  40  slot B: the same
 *  56  u32 0                60  u32 CRC-32 of bytes 0..59
 */
#define OFF_SLOT(i) (24u + 16u * (unsigned)(i))

uint32_t sf_ab_crc32_update(uint32_t crc, const void *data, size_t len)
{
    const uint8_t *p = data;
    crc = ~crc;
    while (len--) {
        crc ^= *p++;
        for (int k = 0; k < 8; k++)
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

uint32_t sf_ab_crc32(const void *data, size_t len)
{
    return sf_ab_crc32_update(0, data, len);
}

static void put16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

static void put32(uint8_t *p, uint32_t v)
{
    for (int i = 0; i < 4; i++)
        p[i] = (uint8_t)(v >> (8 * i));
}

static uint16_t get16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t get32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

void sf_ab_encode(const struct sf_ab_state *st, uint8_t out[SF_AB_REC_BYTES])
{
    static const char magic[] = SF_AB_MAGIC;
    for (unsigned i = 0; i < SF_AB_REC_BYTES; i++)
        out[i] = 0;
    for (unsigned i = 0; i < 8; i++)
        out[i] = (uint8_t)magic[i];
    put16(out + 8, SF_AB_FORMAT);
    put16(out + 10, SF_AB_REC_BYTES);
    put32(out + 12, st->seq);
    out[16] = st->default_slot;
    out[17] = st->trial_slot;
    out[18] = st->trial_state;
    out[19] = st->flags;
    put32(out + 20, st->reason);
    for (int i = 0; i < 2; i++) {
        uint8_t *s = out + OFF_SLOT(i);
        put32(s, st->slot[i].boot_bytes);
        put32(s + 4, st->slot[i].boot_crc32);
        put32(s + 8, st->slot[i].generation);
        s[12] = st->slot[i].good;
    }
    put32(out + 60, sf_ab_crc32(out, 60));
}

static bool valid_slot(unsigned s)
{
    return s == SF_AB_SLOT_A || s == SF_AB_SLOT_B;
}

/* The rules every stored state obeys (also checked before a write) */
static bool state_ok(const struct sf_ab_state *st)
{
    if (!valid_slot(st->default_slot) || st->flags != 0 || st->trial_state > SF_AB_TRIAL_FAILED ||
        st->reason >= SF_AB_R_COUNT)
        return false;
    for (int i = 0; i < 2; i++)
        if (st->slot[i].good > 1 || (st->slot[i].boot_bytes == 0 && st->slot[i].boot_crc32 != 0))
            return false;
    if (st->trial_state == SF_AB_TRIAL_NONE)
        return st->trial_slot == SF_AB_SLOT_NONE;
    if (!valid_slot(st->trial_slot) || st->trial_slot == st->default_slot)
        return false;
    /* an armed or tried slot is always one whose stage 2 was measured when it was armed */
    if (st->trial_state != SF_AB_TRIAL_FAILED && st->slot[st->trial_slot].boot_bytes == 0)
        return false;
    return true;
}

bool sf_ab_decode(const uint8_t rec[SF_AB_REC_BYTES], struct sf_ab_state *st)
{
    static const char magic[] = SF_AB_MAGIC;
    struct sf_ab_state s;
    for (unsigned i = 0; i < 8; i++)
        if (rec[i] != (uint8_t)magic[i])
            return false;
    if (get16(rec + 8) != SF_AB_FORMAT || get16(rec + 10) != SF_AB_REC_BYTES)
        return false;
    if (get32(rec + 60) != sf_ab_crc32(rec, 60))
        return false;
    if (get32(rec + 56) != 0)
        return false;
    s.seq = get32(rec + 12);
    s.default_slot = rec[16];
    s.trial_slot = rec[17];
    s.trial_state = rec[18];
    s.flags = rec[19];
    s.reason = get32(rec + 20);
    for (int i = 0; i < 2; i++) {
        const uint8_t *p = rec + OFF_SLOT(i);
        s.slot[i].boot_bytes = get32(p);
        s.slot[i].boot_crc32 = get32(p + 4);
        s.slot[i].generation = get32(p + 8);
        s.slot[i].good = p[12];
        if (p[13] || p[14] || p[15])
            return false;
    }
    if (!state_ok(&s))
        return false;
    *st = s;
    return true;
}

/* serial-number order: a is newer than b */
static bool newer(uint32_t a, uint32_t b)
{
    return (int32_t)(a - b) > 0;
}

static int read_copies(const void *buf, size_t len, struct sf_ab_state st[2], bool ok[2])
{
    const uint8_t *p = buf;
    for (int i = 0; i < 2; i++) {
        size_t off = (size_t)i * SF_AB_COPY_STRIDE;
        ok[i] = p && len >= off + SF_AB_REC_BYTES && sf_ab_decode(p + off, &st[i]);
    }
    if (ok[0] && ok[1])
        return newer(st[1].seq, st[0].seq) ? 1 : 0;
    if (ok[0])
        return 0;
    if (ok[1])
        return 1;
    return -1;
}

int sf_ab_parse(const void *buf, size_t len, struct sf_ab_state *st, int *copy)
{
    struct sf_ab_state s[2];
    bool ok[2];
    int c;
    if (!buf || !len)
        return SF_AB_ABSENT;
    c = read_copies(buf, len, s, ok);
    if (copy)
        *copy = c;
    if (c < 0)
        return SF_AB_CORRUPT;
    *st = s[c];
    return SF_AB_OK;
}

size_t sf_ab_prepare_write(const void *file, size_t len, struct sf_ab_state *st,
                           uint8_t rec[SF_AB_REC_BYTES])
{
    struct sf_ab_state s[2];
    bool ok[2];
    int c = read_copies(file, len, s, ok);
    size_t target;
    if (c < 0) {
        target = 0;
        st->seq = 1;
    } else {
        target = (size_t)(1 - c) * SF_AB_COPY_STRIDE;
        st->seq = s[c].seq + 1;
    }
    sf_ab_encode(st, rec);
    return target;
}

static int other(int s)
{
    return s == SF_AB_SLOT_A ? SF_AB_SLOT_B : SF_AB_SLOT_A;
}

static void add(struct sf_ab_plan *p, int slot, int why, bool check, const struct sf_ab_state *st)
{
    struct sf_ab_candidate *c = &p->c[p->count++];
    c->slot = (uint8_t)slot;
    c->why = (uint8_t)why;
    c->check = check && st && st->slot[slot].boot_bytes != 0;
    c->bytes = c->check ? st->slot[slot].boot_bytes : 0;
    c->crc32 = c->check ? st->slot[slot].boot_crc32 : 0;
}

void sf_ab_decide(int load, const struct sf_ab_state *st, struct sf_ab_plan *p)
{
    int d, t;
    p->count = 0;
    p->writeback_valid = false;

    if (load == SF_AB_ABSENT) {
        /* A fresh install, or one made before this format: what stage 1 v1 does (slot A). If that
         * cannot be started, slot B, where a B exists (v1 would stop here). An unreadable record is
         * treated the same way: stage 1 cannot tell it from a missing one. */
        add(p, SF_AB_SLOT_A, SF_AB_R_NONE, false, NULL);
        add(p, SF_AB_SLOT_B, SF_AB_R_SLOT_DAMAGED, false, NULL);
    } else if (load != SF_AB_OK || !st) {
        /* Neither copy can be read, so no slot is known to be good: A first, as the installer wrote it */
        add(p, SF_AB_SLOT_A, SF_AB_R_STATE_CORRUPT, false, NULL);
        add(p, SF_AB_SLOT_B, SF_AB_R_SLOT_DAMAGED, false, NULL);
    } else {
        d = st->default_slot;
        t = st->trial_slot;
        switch (st->trial_state) {
        case SF_AB_TRIAL_ARMED:
            /* the one try: the armed slot, checked against what SAP measured when it armed it */
            add(p, t, SF_AB_R_TRYING, true, st);
            add(p, d, SF_AB_R_TRIAL_DAMAGED, true, st);
            p->writeback = *st;
            p->writeback.trial_state = SF_AB_TRIAL_TRIED;
            p->writeback.reason = SF_AB_R_TRYING;
            p->writeback_valid = true;
            break;
        case SF_AB_TRIAL_TRIED:
            /* started once, never marked good: back to the previous slot, and say why */
            add(p, d, SF_AB_R_NOT_CONFIRMED, true, st);
            add(p, t, SF_AB_R_SLOT_DAMAGED, true, st);
            break;
        default:
            /* NONE or FAILED: the default slot; the other one only if it has been good since */
            add(p, d, SF_AB_R_NONE, true, st);
            if (st->trial_state == SF_AB_TRIAL_NONE && st->slot[other(d)].good)
                add(p, other(d), SF_AB_R_SLOT_DAMAGED, true, st);
            break;
        }
        /* last resort, never worse than stage 1 v1: the default slot's files as they are */
        if (p->c[p->count - 1].slot != d || p->c[p->count - 1].check)
            add(p, d, SF_AB_R_UNVERIFIED, false, st);
    }
    p->reason = p->c[0].why;
}

int sf_ab_run(const struct sf_ab_plan *p, const struct sf_ab_ops *ops)
{
    for (int i = 0; i < p->count; i++) {
        const struct sf_ab_candidate *c = &p->c[i];
        if (c->why != SF_AB_R_NONE && ops->notice)
            ops->notice(ops->ctx, c->why, c->slot);
        if (ops->try_slot(ops->ctx, c) == 0)
            return c->slot;
    }
    return -1;
}

const char *sf_ab_boot_path(int slot)
{
    return slot == SF_AB_SLOT_B ? "sf/b/boot.bin" : "sf/boot.bin";
}

const char *sf_ab_kernel_path(int slot)
{
    return slot == SF_AB_SLOT_B ? "sf/b/kernel.bin" : "sf/kernel.bin";
}

char sf_ab_slot_name(int slot)
{
    return slot == SF_AB_SLOT_A ? 'a' : slot == SF_AB_SLOT_B ? 'b' : '-';
}

const char *sf_ab_reason_text(int reason)
{
    switch (reason) {
    case SF_AB_R_NONE:
        return "normal start";
    case SF_AB_R_TRYING:
        return "first start of the updated system";
    case SF_AB_R_NOT_CONFIRMED:
        return "the updated system started once but never reported a clean start";
    case SF_AB_R_STATE_CORRUPT:
        return "the boot state record is damaged";
    case SF_AB_R_TRIAL_DAMAGED:
        return "the updated system's stage 2 is missing or not what was installed";
    case SF_AB_R_SLOT_DAMAGED:
        return "a stage 2 is missing or not what the boot state record says";
    case SF_AB_R_UNVERIFIED:
        return "starting the previous system's files without the record's check";
    default:
        return "unknown";
    }
}

/* ---- OS-side transitions ------------------------------------------------------------------- */

static void zero_state(struct sf_ab_state *st)
{
    uint8_t *p = (uint8_t *)st;
    for (size_t i = 0; i < sizeof(*st); i++)
        p[i] = 0;
}

int sf_ab_init(struct sf_ab_state *st, uint32_t a_bytes, uint32_t a_crc, uint32_t generation)
{
    if (!a_bytes)
        return -1;
    zero_state(st);
    st->default_slot = SF_AB_SLOT_A;
    st->trial_slot = SF_AB_SLOT_NONE;
    st->trial_state = SF_AB_TRIAL_NONE;
    st->slot[SF_AB_SLOT_A].boot_bytes = a_bytes;
    st->slot[SF_AB_SLOT_A].boot_crc32 = a_crc;
    st->slot[SF_AB_SLOT_A].generation = generation;
    st->slot[SF_AB_SLOT_A].good = 1; /* the running, installed system: only init from a clean start */
    return 0;
}

/* Before SAP writes any file of slot: forget what the slot held (it is no longer a fallback) */
int sf_ab_begin_stage(struct sf_ab_state *st, int slot)
{
    if (!valid_slot((unsigned)slot) || slot == st->default_slot)
        return -1;
    if (st->trial_state == SF_AB_TRIAL_ARMED || st->trial_state == SF_AB_TRIAL_TRIED)
        return -1;
    st->slot[slot].boot_bytes = 0;
    st->slot[slot].boot_crc32 = 0;
    st->slot[slot].generation = 0;
    st->slot[slot].good = 0;
    st->trial_slot = SF_AB_SLOT_NONE;
    st->trial_state = SF_AB_TRIAL_NONE;
    st->reason = SF_AB_R_NONE;
    return 0;
}

/* After the slot's files are written, synced and read back */
int sf_ab_arm(struct sf_ab_state *st, int slot, uint32_t bytes, uint32_t crc, uint32_t generation)
{
    if (!valid_slot((unsigned)slot) || slot == st->default_slot || !bytes)
        return -1;
    if (st->trial_state != SF_AB_TRIAL_NONE || st->slot[slot].good || st->slot[slot].boot_bytes)
        return -1; /* sf_ab_begin_stage first */
    st->slot[slot].boot_bytes = bytes;
    st->slot[slot].boot_crc32 = crc;
    st->slot[slot].generation = generation;
    st->slot[slot].good = 0;
    st->trial_slot = (uint8_t)slot;
    st->trial_state = SF_AB_TRIAL_ARMED;
    st->reason = SF_AB_R_NONE;
    return 0;
}

/* SAP rolling back an interrupted update before the system restarted: an ARMED trial of slot is
 * cancelled and the slot is left unrecorded, as begin_stage left it (its files are not a fallback).
 * Only while ARMED: a TRIED trial is the running system's own decision (early / mark-good). */
int sf_ab_disarm(struct sf_ab_state *st, int slot)
{
    if (!valid_slot((unsigned)slot) || slot == st->default_slot)
        return -1;
    if (st->trial_state != SF_AB_TRIAL_ARMED || st->trial_slot != slot)
        return -1;
    st->slot[slot].boot_bytes = 0;
    st->slot[slot].boot_crc32 = 0;
    st->slot[slot].generation = 0;
    st->slot[slot].good = 0;
    st->trial_slot = SF_AB_SLOT_NONE;
    st->trial_state = SF_AB_TRIAL_NONE;
    st->reason = SF_AB_R_NONE;
    return 0;
}

/* First thing at every start of the OS (sf-bootslot early). running: the slot this system came from. */
int sf_ab_on_boot(struct sf_ab_state *st, int running, bool *changed)
{
    *changed = false;
    if (!valid_slot((unsigned)running))
        return -1;
    if (st->trial_state == SF_AB_TRIAL_ARMED && running == st->trial_slot) {
        /* stage 1 v2 cannot write: this is where the one try is used up */
        st->trial_state = SF_AB_TRIAL_TRIED;
        st->reason = SF_AB_R_TRYING;
        *changed = true;
    } else if (st->trial_state == SF_AB_TRIAL_ARMED && running == st->default_slot) {
        /* stage 1 did not start the armed slot: its stage 2 failed the check */
        st->trial_state = SF_AB_TRIAL_FAILED;
        st->reason = SF_AB_R_TRIAL_DAMAGED;
        *changed = true;
    } else if (st->trial_state == SF_AB_TRIAL_TRIED && running == st->default_slot) {
        st->trial_state = SF_AB_TRIAL_FAILED;
        st->reason = SF_AB_R_NOT_CONFIRMED;
        *changed = true;
    }
    return 0;
}

/* After a clean start (sf-bootslot mark-good) */
int sf_ab_mark_good(struct sf_ab_state *st, int running, bool *changed)
{
    *changed = false;
    if (!valid_slot((unsigned)running))
        return -1;
    if ((st->trial_state == SF_AB_TRIAL_TRIED || st->trial_state == SF_AB_TRIAL_ARMED) &&
        running == st->trial_slot) {
        st->default_slot = (uint8_t)running;
        st->slot[running].good = 1;
        st->trial_slot = SF_AB_SLOT_NONE;
        st->trial_state = SF_AB_TRIAL_NONE;
        st->reason = SF_AB_R_NONE;
        *changed = true;
        return 0;
    }
    if (running != st->default_slot)
        return -1; /* running a slot the record does not expect: change nothing */
    if (!st->slot[running].good && st->slot[running].boot_bytes) {
        st->slot[running].good = 1;
        *changed = true;
    }
    return 0;
}
