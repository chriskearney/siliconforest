/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/*
 * sf-bootslot: the userland side of the A/B try-once boot (abboot/README.md).
 *
 *   sf-bootslot [--boot DIR] [--running a|b] COMMAND
 *
 * DIR is where the SFBOOT partition is mounted (default: $SF_BOOT_DIR). The running slot comes
 * from --running, else from sf_slot= in the kernel's boot arguments (kern.bootargs, Darwin only),
 * else it is a: slot A's kernel.bin, as the installer writes it, names no slot.
 *
 *   status              the record, and whether each slot's boot.bin agrees with it
 *   init                create sf/bootstate.bin for slot A as installed (from a clean start only)
 *   early               first thing at every start: use up an armed try, or record a fallback
 *   mark-good           after a clean start: the running trial slot becomes the default
 *   begin-stage a|b     SAP, before writing any file of that (inactive) slot
 *   arm a|b             SAP, after that slot's files are written, synced and read back
 *
 * Every write overwrites the older of the record's two copies in place (the file never changes
 * size, so the FAT is never written), is fsynced, and is read back. Exit status: 0 done or nothing
 * to do, 1 the change is not allowed in this state (nothing written), 2 any other failure.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

#include "sf_ab.h"

static const char *boot_dir;

static int fail(const char *what)
{
    fprintf(stderr, "sf-bootslot: %s: %s\n", what, errno ? strerror(errno) : "failed");
    return 2;
}

static void path(char *out, size_t n, const char *rel)
{
    snprintf(out, n, "%s/%s", boot_dir, rel);
}

static int slot_arg(const char *s)
{
    if (s && !strcmp(s, "a"))
        return SF_AB_SLOT_A;
    if (s && !strcmp(s, "b"))
        return SF_AB_SLOT_B;
    return -1;
}

static int running_slot(const char *arg)
{
    if (arg)
        return slot_arg(arg);
#ifdef __APPLE__
    {
        char args[2048];
        size_t n = sizeof(args) - 1;
        if (sysctlbyname("kern.bootargs", args, &n, NULL, 0) == 0) {
            args[n] = 0;
            for (char *t = strtok(args, " "); t; t = strtok(NULL, " "))
                if (!strncmp(t, "sf_slot=", 8))
                    return slot_arg(t + 8);
        }
    }
#endif
    return SF_AB_SLOT_A;
}

/* size and CRC-32 of a file; 0 if it cannot be read */
static int measure(const char *rel, uint32_t *bytes, uint32_t *crc)
{
    char p[4096];
    unsigned char buf[65536];
    size_t total = 0;
    ssize_t r;
    int fd;
    path(p, sizeof(p), rel);
    fd = open(p, O_RDONLY);
    if (fd < 0)
        return -1;
    *crc = 0;
    while ((r = read(fd, buf, sizeof(buf))) > 0) {
        *crc = sf_ab_crc32_update(*crc, buf, (size_t)r);
        total += (size_t)r;
    }
    close(fd);
    if (r < 0 || total == 0 || total > 0xffffffffu)
        return -1;
    *bytes = (uint32_t)total;
    return 0;
}

static int read_state(uint8_t file[SF_AB_FILE_BYTES], int *fd_out)
{
    char p[4096];
    struct stat sb;
    int fd;
    path(p, sizeof(p), SF_AB_STATE_FILE);
    fd = open(p, fd_out ? O_RDWR : O_RDONLY);
    if (fd < 0)
        return errno == ENOENT ? SF_AB_ABSENT : -1;
    if (fstat(fd, &sb) || sb.st_size != SF_AB_FILE_BYTES ||
        pread(fd, file, SF_AB_FILE_BYTES, 0) != (ssize_t)SF_AB_FILE_BYTES) {
        close(fd);
        return SF_AB_CORRUPT;
    }
    if (fd_out)
        *fd_out = fd;
    else
        close(fd);
    return SF_AB_OK;
}

static int write_state(int fd, uint8_t file[SF_AB_FILE_BYTES], struct sf_ab_state *st)
{
    uint8_t rec[SF_AB_REC_BYTES];
    struct sf_ab_state back;
    size_t off = sf_ab_prepare_write(file, SF_AB_FILE_BYTES, st, rec);
    if (pwrite(fd, rec, sizeof(rec), (off_t)off) != (ssize_t)sizeof(rec) || fsync(fd))
        return fail("write " SF_AB_STATE_FILE);
    if (pread(fd, file, SF_AB_FILE_BYTES, 0) != (ssize_t)SF_AB_FILE_BYTES ||
        sf_ab_parse(file, SF_AB_FILE_BYTES, &back, NULL) != SF_AB_OK || back.seq != st->seq) {
        fprintf(stderr, "sf-bootslot: the record did not read back\n");
        return 2;
    }
    return 0;
}

static void print_state(const struct sf_ab_state *st)
{
    static const char *const trial[] = {"none", "armed", "tried", "failed"};
    printf("seq=%u\ndefault=%c\ntrial=%c\ntrial_state=%s\nreason=%s\n", st->seq,
           sf_ab_slot_name(st->default_slot), sf_ab_slot_name(st->trial_slot), trial[st->trial_state],
           sf_ab_reason_text((int)st->reason));
    for (int i = 0; i < 2; i++) {
        uint32_t b = 0, c = 0;
        int have = measure(sf_ab_boot_path(i), &b, &c) == 0;
        const char *agree = !st->slot[i].boot_bytes ? "unrecorded"
                            : !have                  ? "missing"
                            : (b == st->slot[i].boot_bytes && c == st->slot[i].boot_crc32) ? "matches"
                                                                                           : "differs";
        printf("slot_%c=bytes:%u crc32:%08x generation:%u good:%u file:%s\n", sf_ab_slot_name(i),
               st->slot[i].boot_bytes, st->slot[i].boot_crc32, st->slot[i].generation,
               st->slot[i].good, agree);
    }
}

static int cmd_init(uint32_t generation)
{
    char p[4096];
    uint8_t file[SF_AB_FILE_BYTES], rec[SF_AB_REC_BYTES];
    struct sf_ab_state st;
    uint32_t b, c;
    int fd;
    if (measure(sf_ab_boot_path(SF_AB_SLOT_A), &b, &c))
        return fail("read sf/boot.bin");
    if (sf_ab_init(&st, b, c, generation))
        return 1;
    memset(file, 0, sizeof(file));
    sf_ab_prepare_write(file, sizeof(file), &st, rec);
    memcpy(file, rec, sizeof(rec));
    path(p, sizeof(p), SF_AB_STATE_FILE);
    fd = open(p, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0)
        return errno == EEXIST ? (fprintf(stderr, "sf-bootslot: %s exists\n", SF_AB_STATE_FILE), 1)
                               : fail("create " SF_AB_STATE_FILE);
    if (write(fd, file, sizeof(file)) != (ssize_t)sizeof(file) || fsync(fd) || close(fd))
        return fail("write " SF_AB_STATE_FILE);
    print_state(&st);
    return 0;
}

int main(int argc, char **argv)
{
    const char *running_arg = NULL, *cmd;
    uint8_t file[SF_AB_FILE_BYTES];
    struct sf_ab_state st;
    uint32_t generation = 0;
    int i = 1, fd = -1, load, rc = 0, slot = -1;
    bool changed = true;

    boot_dir = getenv("SF_BOOT_DIR");
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (!strcmp(argv[i], "--boot") && i + 1 < argc)
            boot_dir = argv[++i];
        else if (!strcmp(argv[i], "--running") && i + 1 < argc)
            running_arg = argv[++i];
        else if (!strcmp(argv[i], "--generation") && i + 1 < argc)
            generation = (uint32_t)strtoul(argv[++i], NULL, 10);
        else
            goto usage;
    }
    if (i >= argc || !boot_dir)
        goto usage;
    cmd = argv[i++];
    if (!strcmp(cmd, "begin-stage") || !strcmp(cmd, "arm")) {
        if (i >= argc || (slot = slot_arg(argv[i++])) < 0)
            goto usage;
    }
    if (i != argc)
        goto usage;
    if (running_arg && slot_arg(running_arg) < 0)
        goto usage;

    if (!strcmp(cmd, "init"))
        return cmd_init(generation);

    load = read_state(file, !strcmp(cmd, "status") ? NULL : &fd);
    if (load < 0)
        return fail("open " SF_AB_STATE_FILE);
    if (load == SF_AB_ABSENT) {
        /* an install without the record: stage 1 starts slot A, as v1 does; nothing to record */
        printf("no boot state record: slot a, as installed\n");
        return !strcmp(cmd, "begin-stage") || !strcmp(cmd, "arm") ? 1 : 0;
    }
    if (load != SF_AB_OK || sf_ab_parse(file, sizeof(file), &st, NULL) != SF_AB_OK) {
        fprintf(stderr, "sf-bootslot: the boot state record is damaged (both copies)\n");
        if (fd >= 0)
            close(fd);
        return 2;
    }

    if (!strcmp(cmd, "status")) {
        printf("running=%c\n", sf_ab_slot_name(running_slot(running_arg)));
        print_state(&st);
        return 0;
    } else if (!strcmp(cmd, "early")) {
        rc = sf_ab_on_boot(&st, running_slot(running_arg), &changed) ? 1 : 0;
    } else if (!strcmp(cmd, "mark-good")) {
        rc = sf_ab_mark_good(&st, running_slot(running_arg), &changed) ? 1 : 0;
    } else if (!strcmp(cmd, "begin-stage")) {
        if (slot == running_slot(running_arg))
            rc = 1;
        else
            rc = sf_ab_begin_stage(&st, slot) ? 1 : 0;
    } else if (!strcmp(cmd, "arm")) {
        uint32_t b, c;
        if (slot == running_slot(running_arg))
            rc = 1;
        else if (measure(sf_ab_boot_path(slot), &b, &c))
            rc = fail("read the slot's boot.bin");
        else
            rc = sf_ab_arm(&st, slot, b, c, generation) ? 1 : 0;
    } else {
        close(fd);
        goto usage;
    }
    if (rc == 1)
        fprintf(stderr, "sf-bootslot: %s is not allowed in this state; nothing was written\n", cmd);
    if (rc == 0 && changed)
        rc = write_state(fd, file, &st);
    close(fd);
    if (rc == 0)
        print_state(&st);
    return rc;

usage:
    fprintf(stderr, "usage: sf-bootslot [--boot DIR] [--running a|b] [--generation N] "
                    "status|init|early|mark-good|begin-stage SLOT|arm SLOT\n");
    return 2;
}
