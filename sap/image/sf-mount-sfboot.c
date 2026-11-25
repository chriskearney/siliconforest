/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors */
/*
 * sf-mount-sfboot: mount the boot partition SFBOOT (FAT32, volume label SFBOOT, docs/installer)
 * read-write, for SAP and sf-bootslot (docs/sap/BOOT-INTERFACE.md, design Q3).
 *
 *   sf-mount-sfboot [--label NAME] [--dev-dir DIR] [--dry-run] MOUNTPOINT
 *
 * Reads the first sector of every /dev/rdiskNsM and takes the one FAT32 partition whose boot
 * sector carries the label (BS_VolLab). Two or none: nothing is mounted (exit 1). The mount is
 * msdosfs.kext through mount(2), as mount_msdos would make it (SiliconForest has no mount_msdos):
 * root-owned files, mode 0755/0644. Already mounted there: exit 0. --dry-run only names the device
 * (with --dev-dir, also on a non-Darwin host, for tests). Exit: 0 mounted, 1 not found, 2 failure.
 */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#define _DEFAULT_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/mount.h>
#include <sys/param.h>
#endif

/* msdosfs.kext's struct msdosfs_args (msdosfsmount.h), user side: fspec first */
struct sf_msdosfs_args {
    char *fspec;
    uid_t uid;
    gid_t gid;
    mode_t mask;
    uint32_t flags;
    uint32_t magic;
    int32_t secondsWest;
    uint8_t label[64];
};
#define SF_MSDOSFS_ARGSMAGIC 0xe4eff301u

static int is_partition_name(const char *n)
{
    /* rdiskNsM */
    const char *p = n;
    if (strncmp(p, "rdisk", 5))
        return 0;
    p += 5;
    if (*p < '0' || *p > '9')
        return 0;
    while (*p >= '0' && *p <= '9')
        p++;
    if (*p++ != 's' || *p < '0' || *p > '9')
        return 0;
    while (*p >= '0' && *p <= '9')
        p++;
    return *p == 0;
}

/* 1: a FAT32 boot sector with this volume label */
static int matches(const char *path, const char *label)
{
    uint8_t s[512];
    char want[12];
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return 0;
    ssize_t n = pread(fd, s, sizeof(s), 0);
    close(fd);
    if (n != (ssize_t)sizeof(s) || s[510] != 0x55 || s[511] != 0xaa)
        return 0;
    if (memcmp(s + 0x52, "FAT32   ", 8) || s[0x42] != 0x29) /* FAT32 type, extended boot signature */
        return 0;
    snprintf(want, sizeof(want), "%-11s", label);
    return !memcmp(s + 0x47, want, 11);
}

int main(int argc, char **argv)
{
    const char *label = "SFBOOT", *devdir = "/dev", *dir = NULL;
    int dry = 0, i, found = 0;
    char dev[512] = "", path[512];

    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--label") && i + 1 < argc)
            label = argv[++i];
        else if (!strcmp(argv[i], "--dev-dir") && i + 1 < argc)
            devdir = argv[++i];
        else if (!strcmp(argv[i], "--dry-run"))
            dry = 1;
        else if (argv[i][0] != '-' && !dir)
            dir = argv[i];
        else
            goto usage;
    }
    if (!dir || strlen(label) > 11)
        goto usage;

    DIR *d = opendir(devdir);
    if (!d) {
        perror(devdir);
        return 2;
    }
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!is_partition_name(e->d_name))
            continue;
        snprintf(path, sizeof(path), "%s/%s", devdir, e->d_name);
        if (matches(path, label)) {
            found++;
            snprintf(dev, sizeof(dev), "%s/%s", devdir, e->d_name + 1); /* the block device: diskNsM */
        }
    }
    closedir(d);
    if (found != 1) {
        fprintf(stderr, "sf-mount-sfboot: %s FAT32 partition labelled %s; nothing mounted\n", found ? "more than one" : "no", label);
        return 1;
    }
    printf("device=%s\n", dev);
    if (dry)
        return 0;
#ifdef __APPLE__
    {
        struct statfs sf;
        if (statfs(dir, &sf) == 0 && !strcmp(sf.f_fstypename, "msdos") && !strcmp(sf.f_mntfromname, dev)) {
            printf("mounted=%s (already)\n", dir);
            return 0;
        }
        if (mkdir(dir, 0755) && errno != EEXIST) {
            perror(dir);
            return 2;
        }
        struct sf_msdosfs_args a;
        memset(&a, 0, sizeof(a));
        a.fspec = dev;
        a.uid = 0;
        a.gid = 0;
        a.mask = 0755;
        a.magic = SF_MSDOSFS_ARGSMAGIC;
        if (mount("msdos", dir, MNT_NOATIME, &a)) {
            fprintf(stderr, "sf-mount-sfboot: mount %s on %s: %s\n", dev, dir, strerror(errno));
            return 2;
        }
        if (statfs(dir, &sf) || (sf.f_flags & MNT_RDONLY)) {
            fprintf(stderr, "sf-mount-sfboot: %s is not mounted read-write\n", dir);
            return 2;
        }
        printf("mounted=%s\n", dir);
        return 0;
    }
#else
    fprintf(stderr, "sf-mount-sfboot: mounting needs Darwin; use --dry-run here\n");
    return 2;
#endif
usage:
    fprintf(stderr, "usage: sf-mount-sfboot [--label NAME] [--dev-dir DIR] [--dry-run] MOUNTPOINT\n");
    return 2;
}
