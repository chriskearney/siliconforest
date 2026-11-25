/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * sapg-durable DIR N     what SAP's journal relies on (design 9, Q2), in a loop:
 *   write DIR/state.tmp (sequence i and 256 KiB derived from i), fsync it, rename it over
 *   DIR/state, fsync DIR, then print "ACK i". The host cuts the power at some ACK k
 *   (sap_guest.py run --kill-on). Afterwards DIR/state must be a whole record with i >= k:
 *   rename is atomic (never a mix, never empty) and fsync is durable (nothing acknowledged is lost).
 * sapg-durable --check DIR K   checks that, prints "DURABLE_OK i" or "DURABLE_BAD reason", exit 0/1.
 * Builds for Linux (the loopback comparison) and aarch64-apple-darwin (the guest).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define BODY (256 * 1024)

static void fill(uint8_t *b, uint32_t seq)
{
    uint32_t x = seq * 2654435761u + 1;
    for (size_t i = 0; i < BODY; i++) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        b[i] = (uint8_t)x;
    }
}

static int check(const char *dir, long want)
{
    char p[1024];
    static uint8_t got[8 + BODY + 1], exp[BODY];
    snprintf(p, sizeof(p), "%s/state", dir);
    int fd = open(p, O_RDONLY);
    if (fd < 0) { printf("DURABLE_BAD no state (%s)\n", strerror(errno)); return 1; }
    ssize_t n = 0, r;
    while ((r = read(fd, got + n, sizeof(got) - (size_t)n)) > 0) n += r;
    close(fd);
    if (n != 8 + BODY) { printf("DURABLE_BAD state is %zd bytes, not %d\n", n, 8 + BODY); return 1; }
    uint32_t seq, inv;
    memcpy(&seq, got, 4); memcpy(&inv, got + 4, 4);
    if (inv != ~seq) { printf("DURABLE_BAD header torn\n"); return 1; }
    fill(exp, seq);
    if (memcmp(exp, got + 8, BODY)) { printf("DURABLE_BAD body of %u is not its own\n", seq); return 1; }
    if ((long)seq < want) { printf("DURABLE_BAD state is %u, %ld was acknowledged\n", seq, want); return 1; }
    printf("DURABLE_OK %u (acknowledged %ld)\n", seq, want);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 4 && !strcmp(argv[1], "--check"))
        return check(argv[2], atol(argv[3]));
    if (argc != 3) { fprintf(stderr, "usage: sapg-durable DIR N | --check DIR K\n"); return 2; }
    const char *dir = argv[1];
    long n = atol(argv[2]);
    char tmp[1024], fin[1024];
    static uint8_t buf[8 + BODY];
    snprintf(tmp, sizeof(tmp), "%s/state.tmp", dir);
    snprintf(fin, sizeof(fin), "%s/state", dir);
    int dfd = open(dir, O_RDONLY);
    if (dfd < 0) { perror(dir); return 2; }
    for (uint32_t i = 1; i <= (uint32_t)n; i++) {
        uint32_t inv = ~i;
        memcpy(buf, &i, 4); memcpy(buf + 4, &inv, 4);
        fill(buf + 8, i);
        int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0 || write(fd, buf, sizeof(buf)) != (ssize_t)sizeof(buf) || fsync(fd) || close(fd)) { perror("write"); return 2; }
        if (rename(tmp, fin) || fsync(dfd)) { perror("rename"); return 2; }
        printf("ACK %u\n", i);
        fflush(stdout);
    }
    printf("DURABLE_DONE\n");
    return 0;
}
