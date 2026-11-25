/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/*
 * Host unit tests of stage 1 v2's m1n1 glue, sf_ab_stage1.c, unchanged, against stand-ins for the
 * m1n1 calls it makes (hostmock/): which files it reads, which slots it asks chainload to start,
 * with which checks, what it puts on the screen, and that it stops on a fatal storage error.
 * Built by tests/test_boot_ab.py; nothing here touches a device.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "chainload.h"
#include "fb.h"
#include "sf_ab.h"
#include "utils.h"

#define UUID "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"

static int checks, failed;
#define CHECK(c)                                                                                   \
    do {                                                                                           \
        checks++;                                                                                  \
        if (!(c)) {                                                                                \
            failed++;                                                                              \
            printf("not ok %d - %s:%d %s\n", checks, __FILE__, __LINE__, #c);                     \
        }                                                                                          \
    } while (0)

/* the scripted world */
static uint8_t state_file[SF_AB_FILE_BYTES];
static size_t state_len;   /* 0: the file is absent */
static int slot_result[2]; /* chainload_load_slot's answer per slot */
static int reads, frees, passthrough, fb_on, delay_ms, ntry;
static char read_spec[128], pass_spec[128];
static struct {
    char spec[128];
    bool check;
    u32 bytes, crc;
} tries[8];

int chainload_load(const char *spec, char **vars, size_t *var_cnt, size_t cap)
{
    (void)vars, (void)var_cnt, (void)cap;
    passthrough++;
    snprintf(pass_spec, sizeof(pass_spec), "%s", spec);
    return 0;
}

int chainload_read_file(const char *spec, void **image, size_t *size)
{
    reads++;
    snprintf(read_spec, sizeof(read_spec), "%s", spec);
    if (!state_len)
        return -1;
    *image = malloc(state_len);
    memcpy(*image, state_file, state_len);
    *size = state_len;
    return 0;
}

void chainload_free_file(void *image, size_t size)
{
    (void)size;
    frees++;
    free(image);
}

int chainload_load_slot(const char *spec, char **vars, size_t *var_cnt, size_t cap, bool check,
                        u32 bytes, u32 crc32)
{
    (void)vars, (void)var_cnt, (void)cap;
    snprintf(tries[ntry].spec, sizeof(tries[ntry].spec), "%s", spec);
    tries[ntry].check = check;
    tries[ntry].bytes = bytes;
    tries[ntry].crc = crc32;
    ntry++;
    return slot_result[strstr(spec, ";sf/b/") ? 1 : 0];
}

void fb_set_active(bool active)
{
    fb_on += active;
}

void mdelay(int ms)
{
    delay_ms += ms;
}

static void reset(void)
{
    memset(state_file, 0, sizeof(state_file));
    state_len = 0;
    slot_result[0] = slot_result[1] = 0;
    reads = frees = passthrough = fb_on = delay_ms = ntry = 0;
    memset(tries, 0, sizeof(tries));
}

static void store(struct sf_ab_state *st)
{
    uint8_t rec[SF_AB_REC_BYTES];
    size_t off = sf_ab_prepare_write(state_file, sizeof(state_file), st, rec);
    memcpy(state_file + off, rec, sizeof(rec));
    state_len = sizeof(state_file);
}

static int run(const char *spec)
{
    char *vars[4] = {"a=1"};
    size_t n = 1;
    return sf_ab_stage1_chainload(spec, vars, &n, 4);
}

static void armed_b(void)
{
    struct sf_ab_state st;
    sf_ab_init(&st, 1000, 0x11111111, 1);
    store(&st);
    sf_ab_begin_stage(&st, SF_AB_SLOT_B);
    store(&st);
    sf_ab_arm(&st, SF_AB_SLOT_B, 2000, 0x22222222, 2);
    store(&st);
}

int main(void)
{
    /* other chainload targets are v1's, untouched */
    reset();
    CHECK(run(UUID ";sf/other.bin") == 0 && passthrough == 1 && reads == 0 && ntry == 0);
    CHECK(!strcmp(pass_spec, UUID ";sf/other.bin"));
    reset();
    CHECK(run("short-uuid;sf/boot.bin") == 0 && passthrough == 1 && reads == 0);
    reset();
    CHECK(run("sf/boot.bin") == 0 && passthrough == 1);

    /* no record: slot A unchecked, as v1; quiet */
    reset();
    CHECK(run(UUID ";sf/boot.bin") == 0);
    CHECK(reads == 1 && !strcmp(read_spec, UUID ";sf/bootstate.bin") && frees == 0);
    CHECK(ntry == 1 && !strcmp(tries[0].spec, UUID ";sf/boot.bin") && !tries[0].check);
    CHECK(fb_on == 0 && delay_ms == 0 && passthrough == 0);

    /* no record, A unusable: B unchecked, with the reason on screen */
    reset();
    slot_result[0] = -2;
    CHECK(run(UUID ";sf/boot.bin") == 0 && ntry == 2 && !strcmp(tries[1].spec, UUID ";sf/b/boot.bin"));
    CHECK(fb_on == 1 && delay_ms == 8000);

    /* armed B: B checked against the record, the try only logged */
    reset();
    armed_b();
    CHECK(run(UUID ";sf/boot.bin") == 0 && frees == 1);
    CHECK(ntry == 1 && !strcmp(tries[0].spec, UUID ";sf/b/boot.bin") && tries[0].check);
    CHECK(tries[0].bytes == 2000 && tries[0].crc == 0x22222222);
    CHECK(fb_on == 0 && delay_ms == 0);

    /* armed B that cannot be started: A, checked, and the reason shown */
    reset();
    armed_b();
    slot_result[1] = -2;
    CHECK(run(UUID ";sf/boot.bin") == 0 && ntry == 2);
    CHECK(!strcmp(tries[1].spec, UUID ";sf/boot.bin") && tries[1].check && tries[1].bytes == 1000 &&
          tries[1].crc == 0x11111111);
    CHECK(fb_on == 1 && delay_ms == 8000);

    /* a fatal storage error stops everything: no second slot */
    reset();
    armed_b();
    slot_result[1] = -1;
    CHECK(run(UUID ";sf/boot.bin") == -1 && ntry == 1);

    /* nothing starts: every candidate tried once, then -1 */
    reset();
    armed_b();
    slot_result[0] = slot_result[1] = -2;
    CHECK(run(UUID ";sf/boot.bin") == -1 && ntry == 3 && !tries[2].check);

    /* both copies damaged: A unchecked, the reason shown */
    reset();
    armed_b();
    state_file[5] ^= 1;
    state_file[SF_AB_COPY_STRIDE + 5] ^= 1;
    CHECK(run(UUID ";sf/boot.bin") == 0 && frees == 1 && ntry == 1);
    CHECK(!strcmp(tries[0].spec, UUID ";sf/boot.bin") && !tries[0].check && fb_on == 1);

    /* a truncated file: the copies that are whole still count (copy 0 is the armed one) */
    reset();
    armed_b();
    state_len = 100;
    CHECK(run(UUID ";sf/boot.bin") == 0 && ntry == 1 && strstr(tries[0].spec, ";sf/b/") && tries[0].check);
    /* shorter than one record: damaged */
    reset();
    armed_b();
    state_len = 40;
    CHECK(run(UUID ";sf/boot.bin") == 0 && !tries[0].check && fb_on == 1);

    printf("1..%d\n", checks);
    printf("%s: %d of %d checks failed\n", failed ? "FAILED" : "ok", failed, checks);
    return failed != 0;
}
