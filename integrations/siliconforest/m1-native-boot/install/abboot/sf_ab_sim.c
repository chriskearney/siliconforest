/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/*
 * Host emulation of stage 1 v2's decision (tests/test_boot_ab.py): the same sf_ab_decide() and
 * sf_ab_run() as sf_ab_stage1.c, with "start a slot" meaning "its boot.bin exists, is not empty,
 * and (when checked) has the recorded size and CRC-32". Never touches a device.
 *
 *   sf-ab-stage1 DIR [--stage1-writes]
 *
 * --stage1-writes emulates a stage 1 that can write (not v2): before starting an armed slot it
 * stores the plan's writeback (TRIED), which closes the gap described in abboot/README.md.
 * Prints one line per notice and a final "booted=<slot> reason=<n>" or "booted=none".
 */
#define _POSIX_C_SOURCE 200809L
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "sf_ab.h"

static const char *dir;

static int read_all(const char *rel, unsigned char **buf, size_t *len)
{
    char p[4096];
    struct stat sb;
    int fd;
    snprintf(p, sizeof(p), "%s/%s", dir, rel);
    fd = open(p, O_RDONLY);
    if (fd < 0)
        return -1;
    if (fstat(fd, &sb) || sb.st_size <= 0) {
        close(fd);
        return -1;
    }
    *len = (size_t)sb.st_size;
    *buf = malloc(*len);
    if (!*buf || read(fd, *buf, *len) != (ssize_t)*len) {
        free(*buf);
        close(fd);
        return -1;
    }
    close(fd);
    return 0;
}

static int try_slot(void *ctx, const struct sf_ab_candidate *c)
{
    unsigned char *buf;
    size_t len;
    int ok;
    (void)ctx;
    if (read_all(sf_ab_boot_path(c->slot), &buf, &len))
        return -2;
    ok = !c->check || (len == c->bytes && sf_ab_crc32(buf, len) == c->crc32);
    free(buf);
    return ok ? 0 : -2;
}

static void notice(void *ctx, int why, int slot)
{
    (void)ctx;
    printf("notice=%d slot=%c text=%s\n", why, sf_ab_slot_name(slot), sf_ab_reason_text(why));
}

int main(int argc, char **argv)
{
    unsigned char *buf = NULL;
    size_t len = 0;
    struct sf_ab_state st;
    struct sf_ab_plan plan;
    struct sf_ab_ops ops = {try_slot, notice, NULL};
    int load, slot, writes = argc == 3 && !strcmp(argv[2], "--stage1-writes");
    if (argc < 2 || (argc == 3 && !writes) || argc > 3) {
        fprintf(stderr, "usage: sf-ab-stage1 DIR [--stage1-writes]\n");
        return 2;
    }
    dir = argv[1];
    load = read_all(SF_AB_STATE_FILE, &buf, &len) ? SF_AB_ABSENT : sf_ab_parse(buf, len, &st, NULL);
    sf_ab_decide(load, load == SF_AB_OK ? &st : NULL, &plan);
    printf("load=%d\nplan=", load);
    for (int i = 0; i < plan.count; i++)
        printf("%s%c%s", i ? "," : "", sf_ab_slot_name(plan.c[i].slot), plan.c[i].check ? "" : "?");
    printf("\n");
    if (writes && plan.writeback_valid && try_slot(NULL, &plan.c[0]) == 0) {
        /* what a writing stage 1 would do before jumping to the armed slot */
        char p[4096];
        unsigned char rec[SF_AB_REC_BYTES];
        size_t off = sf_ab_prepare_write(buf, len, &plan.writeback, rec);
        int fd;
        snprintf(p, sizeof(p), "%s/%s", dir, SF_AB_STATE_FILE);
        fd = open(p, O_WRONLY);
        if (fd < 0 || pwrite(fd, rec, sizeof(rec), (off_t)off) != (ssize_t)sizeof(rec) || close(fd)) {
            perror("write");
            return 2;
        }
        printf("stage1_wrote=tried\n");
    }
    free(buf);
    slot = sf_ab_run(&plan, &ops);
    if (slot < 0) {
        printf("booted=none\n");
        return 1;
    }
    printf("booted=%c reason=%d\n", sf_ab_slot_name(slot), plan.reason);
    return 0;
}
