/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/* Host unit tests of sf_ab.c, the logic stage 1 v2 runs (tests/test_boot_ab.py builds and runs this). */
#include <stdio.h>
#include <string.h>

#include "sf_ab.h"

static int failures, checks;
#define CHECK(c)                                                                                   \
    do {                                                                                           \
        checks++;                                                                                  \
        if (!(c)) {                                                                                \
            failures++;                                                                            \
            printf("not ok: %s:%d: %s\n", __FILE__, __LINE__, #c);                                 \
        }                                                                                          \
    } while (0)

static uint8_t file[SF_AB_FILE_BYTES];

static void store(struct sf_ab_state *st)
{
    uint8_t rec[SF_AB_REC_BYTES];
    size_t off = sf_ab_prepare_write(file, sizeof(file), st, rec);
    memcpy(file + off, rec, sizeof(rec));
}

static void fresh(struct sf_ab_state *st)
{
    memset(file, 0, sizeof(file));
    CHECK(sf_ab_init(st, 1000, 0x11111111, 7) == 0);
    store(st);
}

static void test_crc(void)
{
    CHECK(sf_ab_crc32("123456789", 9) == 0xcbf43926u); /* the CRC-32/ISO-HDLC check value */
    CHECK(sf_ab_crc32("", 0) == 0);
    CHECK(sf_ab_crc32_update(sf_ab_crc32("1234", 4), "56789", 5) == 0xcbf43926u);
}

static void test_record(void)
{
    struct sf_ab_state st, back;
    uint8_t rec[SF_AB_REC_BYTES];
    memset(&st, 0, sizeof(st));
    st.seq = 42;
    st.default_slot = SF_AB_SLOT_B;
    st.trial_slot = SF_AB_SLOT_A;
    st.trial_state = SF_AB_TRIAL_ARMED;
    st.slot[0].boot_bytes = 123;
    st.slot[0].boot_crc32 = 0xdeadbeef;
    st.slot[1].boot_bytes = 456;
    st.slot[1].good = 1;
    sf_ab_encode(&st, rec);
    CHECK(memcmp(rec, "SFBOOTAB", 8) == 0);
    CHECK(sf_ab_decode(rec, &back));
    CHECK(memcmp(&st, &back, sizeof(st)) == 0);
    /* every single-bit flip is caught */
    int caught = 0;
    for (unsigned i = 0; i < SF_AB_REC_BYTES * 8; i++) {
        rec[i / 8] ^= (uint8_t)(1u << (i % 8));
        caught += !sf_ab_decode(rec, &back);
        rec[i / 8] ^= (uint8_t)(1u << (i % 8));
    }
    CHECK(caught == SF_AB_REC_BYTES * 8);
    /* semantic rules, with a correct CRC */
    struct sf_ab_state bad;
#define REJECT(field, value)                                                                       \
    do {                                                                                           \
        bad = st;                                                                                  \
        bad.field = value;                                                                         \
        sf_ab_encode(&bad, rec);                                                                   \
        CHECK(!sf_ab_decode(rec, &back));                                                          \
    } while (0)
    REJECT(default_slot, 2);
    REJECT(trial_slot, SF_AB_SLOT_B); /* trial == default */
    REJECT(trial_slot, SF_AB_SLOT_NONE);
    REJECT(trial_state, 4);
    REJECT(flags, 1);
    REJECT(reason, SF_AB_R_COUNT);
    REJECT(slot[0].boot_bytes, 0); /* armed slot without a measurement (crc left nonzero too) */
    REJECT(slot[1].good, 2);
    bad = st;
    bad.trial_state = SF_AB_TRIAL_NONE; /* NONE must name no trial slot */
    sf_ab_encode(&bad, rec);
    CHECK(!sf_ab_decode(rec, &back));
    bad.trial_slot = SF_AB_SLOT_NONE;
    sf_ab_encode(&bad, rec);
    CHECK(sf_ab_decode(rec, &back));
}

static void test_copies(void)
{
    struct sf_ab_state st, got;
    int copy;
    CHECK(sf_ab_parse(NULL, 0, &got, NULL) == SF_AB_ABSENT);
    memset(file, 0, sizeof(file));
    CHECK(sf_ab_parse(file, sizeof(file), &got, NULL) == SF_AB_CORRUPT);
    fresh(&st);
    CHECK(sf_ab_parse(file, sizeof(file), &got, &copy) == SF_AB_OK && copy == 0 && got.seq == 1);
    store(&st); /* seq 2 goes to the other copy */
    CHECK(sf_ab_parse(file, sizeof(file), &got, &copy) == SF_AB_OK && copy == 1 && got.seq == 2);
    store(&st); /* seq 3 overwrites copy 0, the older one */
    CHECK(sf_ab_parse(file, sizeof(file), &got, &copy) == SF_AB_OK && copy == 0 && got.seq == 3);
    /* a torn write of the newer copy leaves the older one */
    file[5] ^= 0xff;
    CHECK(sf_ab_parse(file, sizeof(file), &got, &copy) == SF_AB_OK && copy == 1 && got.seq == 2);
    /* and the next write goes over the damaged copy, not the good one */
    store(&st);
    CHECK(sf_ab_parse(file, sizeof(file), &got, &copy) == SF_AB_OK && copy == 0 && got.seq == 3);
    /* a short file: only copy 0 can be there */
    CHECK(sf_ab_parse(file, SF_AB_REC_BYTES, &got, &copy) == SF_AB_OK && copy == 0);
    CHECK(sf_ab_parse(file, SF_AB_REC_BYTES - 1, &got, NULL) == SF_AB_CORRUPT);
    /* sequence wrap: 0 is newer than 0xffffffff */
    memset(file, 0, sizeof(file));
    st.seq = 0;
    uint8_t rec[SF_AB_REC_BYTES];
    st.seq = 0xffffffffu;
    sf_ab_encode(&st, rec);
    memcpy(file, rec, sizeof(rec));
    st.seq = 0;
    sf_ab_encode(&st, rec);
    memcpy(file + SF_AB_COPY_STRIDE, rec, sizeof(rec));
    CHECK(sf_ab_parse(file, sizeof(file), &got, &copy) == SF_AB_OK && copy == 1 && got.seq == 0);
}

static void test_decide(void)
{
    struct sf_ab_state st;
    struct sf_ab_plan p;
    bool ch;

    sf_ab_decide(SF_AB_ABSENT, NULL, &p);
    CHECK(p.count == 2 && p.c[0].slot == SF_AB_SLOT_A && !p.c[0].check && p.reason == SF_AB_R_NONE);
    CHECK(p.c[1].slot == SF_AB_SLOT_B && !p.c[1].check && p.c[1].why == SF_AB_R_SLOT_DAMAGED);
    CHECK(!p.writeback_valid);

    sf_ab_decide(SF_AB_CORRUPT, NULL, &p);
    CHECK(p.count == 2 && p.c[0].slot == SF_AB_SLOT_A && p.c[1].slot == SF_AB_SLOT_B);
    CHECK(!p.c[0].check && !p.c[1].check && p.reason == SF_AB_R_STATE_CORRUPT);

    fresh(&st);
    sf_ab_decide(SF_AB_OK, &st, &p);
    CHECK(p.count == 2 && p.c[0].slot == SF_AB_SLOT_A && p.c[0].check && p.c[0].bytes == 1000);
    CHECK(p.c[0].crc32 == 0x11111111 && p.c[1].slot == SF_AB_SLOT_A && !p.c[1].check);
    CHECK(p.c[1].why == SF_AB_R_UNVERIFIED);

    CHECK(sf_ab_begin_stage(&st, SF_AB_SLOT_A) != 0);              /* never the running slot */
    CHECK(sf_ab_begin_stage(&st, SF_AB_SLOT_B) == 0);
    CHECK(sf_ab_arm(&st, SF_AB_SLOT_B, 0, 0, 8) != 0);
    CHECK(sf_ab_arm(&st, SF_AB_SLOT_B, 2000, 0x22222222, 8) == 0);
    CHECK(sf_ab_begin_stage(&st, SF_AB_SLOT_B) != 0); /* armed: not again until it is resolved */
    sf_ab_decide(SF_AB_OK, &st, &p);
    CHECK(p.count == 3 && p.reason == SF_AB_R_TRYING);
    CHECK(p.c[0].slot == SF_AB_SLOT_B && p.c[0].check && p.c[0].bytes == 2000 && p.c[0].crc32 == 0x22222222);
    CHECK(p.c[1].slot == SF_AB_SLOT_A && p.c[1].check && p.c[1].why == SF_AB_R_TRIAL_DAMAGED);
    CHECK(p.c[2].slot == SF_AB_SLOT_A && !p.c[2].check && p.c[2].why == SF_AB_R_UNVERIFIED);
    CHECK(p.writeback_valid && p.writeback.trial_state == SF_AB_TRIAL_TRIED);

    /* the OS on B uses up the try, then marks it good */
    struct sf_ab_state tried = st;
    CHECK(sf_ab_on_boot(&tried, SF_AB_SLOT_B, &ch) == 0 && ch && tried.trial_state == SF_AB_TRIAL_TRIED);
    CHECK(sf_ab_on_boot(&tried, SF_AB_SLOT_B, &ch) == 0 && !ch);
    sf_ab_decide(SF_AB_OK, &tried, &p);
    CHECK(p.c[0].slot == SF_AB_SLOT_A && p.reason == SF_AB_R_NOT_CONFIRMED);
    CHECK(p.c[1].slot == SF_AB_SLOT_B && p.c[2].slot == SF_AB_SLOT_A && !p.c[2].check);
    struct sf_ab_state good = tried;
    CHECK(sf_ab_mark_good(&good, SF_AB_SLOT_A, &ch) == 0 && !ch); /* the default slot: nothing changes */
    CHECK(good.trial_state == SF_AB_TRIAL_TRIED);
    CHECK(sf_ab_mark_good(&good, SF_AB_SLOT_B, &ch) == 0 && ch);
    CHECK(good.default_slot == SF_AB_SLOT_B && good.trial_state == SF_AB_TRIAL_NONE && good.slot[1].good);
    sf_ab_decide(SF_AB_OK, &good, &p);
    CHECK(p.c[0].slot == SF_AB_SLOT_B && p.reason == SF_AB_R_NONE);
    CHECK(p.c[1].slot == SF_AB_SLOT_A && p.c[1].why == SF_AB_R_SLOT_DAMAGED); /* A is still good */
    CHECK(sf_ab_arm(&good, SF_AB_SLOT_A, 3000, 3, 9) != 0);                    /* begin_stage first */
    CHECK(sf_ab_mark_good(&good, SF_AB_SLOT_A, &ch) != 0); /* not the default, not the trial */

    /* B never confirmed: A runs again and records why */
    struct sf_ab_state failed = tried;
    CHECK(sf_ab_on_boot(&failed, SF_AB_SLOT_A, &ch) == 0 && ch);
    CHECK(failed.trial_state == SF_AB_TRIAL_FAILED && failed.reason == SF_AB_R_NOT_CONFIRMED);
    sf_ab_decide(SF_AB_OK, &failed, &p);
    CHECK(p.c[0].slot == SF_AB_SLOT_A && p.reason == SF_AB_R_NONE && p.count == 2); /* B never offered */

    /* armed, but stage 1 started A (B's stage 2 failed its check) */
    struct sf_ab_state damaged = st;
    CHECK(sf_ab_on_boot(&damaged, SF_AB_SLOT_A, &ch) == 0 && ch && damaged.reason == SF_AB_R_TRIAL_DAMAGED);

    /* an interrupted update rolled back before the restart: the ARMED trial is cancelled */
    struct sf_ab_state off = st;
    CHECK(sf_ab_disarm(&off, SF_AB_SLOT_A) != 0); /* the default slot */
    CHECK(sf_ab_disarm(&off, SF_AB_SLOT_B) == 0);
    CHECK(off.trial_state == SF_AB_TRIAL_NONE && off.trial_slot == SF_AB_SLOT_NONE && off.default_slot == SF_AB_SLOT_A);
    CHECK(off.slot[1].boot_bytes == 0 && !off.slot[1].good && off.slot[0].good);
    CHECK(sf_ab_disarm(&off, SF_AB_SLOT_B) != 0); /* nothing armed any more */
    sf_ab_decide(SF_AB_OK, &off, &p);
    CHECK(p.c[0].slot == SF_AB_SLOT_A && p.reason == SF_AB_R_NONE && !p.writeback_valid);
    CHECK(sf_ab_begin_stage(&off, SF_AB_SLOT_B) == 0); /* the next update can stage again */
    struct sf_ab_state t2 = tried, f2 = failed;
    CHECK(sf_ab_disarm(&t2, SF_AB_SLOT_B) != 0 && t2.trial_state == SF_AB_TRIAL_TRIED); /* not once tried */
    CHECK(sf_ab_disarm(&f2, SF_AB_SLOT_B) != 0);

    /* the next update after a failure */
    CHECK(sf_ab_begin_stage(&failed, SF_AB_SLOT_B) == 0 && failed.trial_state == SF_AB_TRIAL_NONE);
    CHECK(failed.slot[1].boot_bytes == 0);
}

struct sim {
    int bad[2]; /* candidate fails when its slot is bad */
    int tried[8], n;
    int notices[8], nn;
};

static int sim_try(void *ctx, const struct sf_ab_candidate *c)
{
    struct sim *s = ctx;
    s->tried[s->n++] = c->slot;
    return s->bad[c->slot] ? -1 : 0;
}

static void sim_notice(void *ctx, int reason, int slot)
{
    struct sim *s = ctx;
    (void)slot;
    s->notices[s->nn++] = reason;
}

static void test_run(void)
{
    struct sf_ab_state st;
    struct sf_ab_plan p;
    struct sim s;
    struct sf_ab_ops ops = {sim_try, sim_notice, &s};

    fresh(&st);
    sf_ab_begin_stage(&st, SF_AB_SLOT_B);
    sf_ab_arm(&st, SF_AB_SLOT_B, 2000, 2, 8);
    sf_ab_decide(SF_AB_OK, &st, &p);
    memset(&s, 0, sizeof(s));
    CHECK(sf_ab_run(&p, &ops) == SF_AB_SLOT_B && s.n == 1 && s.nn == 1 && s.notices[0] == SF_AB_R_TRYING);
    memset(&s, 0, sizeof(s));
    s.bad[1] = 1;
    CHECK(sf_ab_run(&p, &ops) == SF_AB_SLOT_A && s.n == 2 && s.notices[1] == SF_AB_R_TRIAL_DAMAGED);
    memset(&s, 0, sizeof(s));
    s.bad[0] = s.bad[1] = 1;
    CHECK(sf_ab_run(&p, &ops) == -1 && s.n == 3 && s.notices[2] == SF_AB_R_UNVERIFIED);
}

int main(void)
{
    test_crc();
    test_record();
    test_copies();
    test_decide();
    test_run();
    printf("1..%d\n", checks);
    printf("%s: %d of %d checks failed\n", failures ? "FAILED" : "ok", failures, checks);
    return failures ? 1 : 0;
}
