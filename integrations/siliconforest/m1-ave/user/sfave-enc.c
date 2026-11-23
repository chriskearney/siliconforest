/* SPDX-License-Identifier: MIT */
/* Encodes NV12 with /dev/sfave into an Annex-B file: a synthetic moving pattern, or
 * real frames from standard input.
 *   sfave-enc out.h264 [width height frames qp [source.nv12 | -]]
 * source.nv12 receives the exact pattern frames, for a PSNR check elsewhere.
 * "-" reads tightly packed NV12 frames from stdin until EOF or <frames>.
 * SFAVE_FPS sets the stream's frame rate (default 30).
 * Exit 0 only when every frame came back with data. */
#include "sfave/sfave_ioctl.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>

static double now_ms(void) {
 struct timespec t;
 clock_gettime(CLOCK_MONOTONIC, &t);
 return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static void pattern(uint8_t *y, uint8_t *uv, unsigned w, unsigned h, unsigned n) {
 unsigned bx = (n * 7) % (w - w / 5), by = (n * 3) % (h - h / 5);
 for (unsigned r = 0; r < h; r++)
  for (unsigned c = 0; c < w; c++) {
   unsigned v = 32 + ((c + r + n * 4) * 160 / (w + h)) % 160;
   if (c >= bx && c < bx + w / 5 && r >= by && r < by + h / 5) v = 225 - ((c ^ r) & 16);
   y[r * w + c] = (uint8_t)v;
  }
 for (unsigned r = 0; r < h / 2; r++)
  for (unsigned c = 0; c < w; c += 2) {
   uv[r * w + c] = (uint8_t)(96 + (c * 64 / w) + (n % 16));
   uv[r * w + c + 1] = (uint8_t)(160 - (r * 128 / h));
  }
}

static int read_all(uint8_t *p, size_t n) {
 size_t got = fread(p, 1, n, stdin);
 return got == n ? 1 : got == 0 && feof(stdin) ? 0 : -1;
}

int main(int argc, char **argv) {
 if (argc < 2) { fprintf(stderr, "usage: %s out.h264 [w h frames qp [source.nv12 | -]]\n", argv[0]); return 2; }
 unsigned w = argc > 2 ? (unsigned)atoi(argv[2]) : 1280, h = argc > 3 ? (unsigned)atoi(argv[3]) : 720;
 unsigned frames = argc > 4 ? (unsigned)atoi(argv[4]) : 60, qp = argc > 5 ? (unsigned)atoi(argv[5]) : 26;
 if (!w || !h || (w & 15) || (h & 15) || !frames) { fputs("width and height must be multiples of 16\n", stderr); return 2; }
 size_t cap = w * h * 3 / 2 + 65536;
 uint8_t *y = malloc(w * h), *uv = malloc(w * h / 2), *out = malloc(cap);
 if (!y || !uv || !out) { fputs("out of memory\n", stderr); return 1; }
 int from_stdin = argc > 6 && !strcmp(argv[6], "-");
 FILE *f = fopen(argv[1], "wb"), *raw = argc > 6 && !from_stdin ? fopen(argv[6], "wb") : NULL;
 if (!f || (argc > 6 && !from_stdin && !raw)) { perror("output"); return 1; }
 unsigned fps = getenv("SFAVE_FPS") ? (unsigned)atoi(getenv("SFAVE_FPS")) : 30;
 if (!fps || fps > 240) { fputs("SFAVE_FPS must be 1..240\n", stderr); return 2; }
 int fd = open("/dev/sfave", O_RDWR);
 if (fd < 0) { perror("/dev/sfave"); return 1; }
 struct sfave_enc_start s = {.width = w, .height = h, .fps = fps, .qp = qp, .profile_idc = 100, .cabac = 1,
  .flags = getenv("SFAVE_VERBOSE") ? SFAVE_ENC_VERBOSE : 0};
 if (ioctl(fd, SFAVE_IOC_ENC_START, &s) < 0) { perror("SFAVE_IOC_ENC_START"); return 1; }
 unsigned long long total = 0;
 unsigned keys = 0;
 double worst = 0, t0 = now_ms();
 unsigned done = 0;
 for (unsigned n = 0; n < frames; n++) {
  if (from_stdin) {
   int a = read_all(y, w * h), b = a > 0 ? read_all(uv, w * h / 2) : a;
   if (a == 0) break;
   if (a < 0 || b <= 0) { fprintf(stderr, "frame %u: short NV12 input\n", n); ioctl(fd, SFAVE_IOC_ENC_STOP); return 1; }
  } else pattern(y, uv, w, h, n);
  if (raw && (fwrite(y, 1, w * h, raw) != w * h || fwrite(uv, 1, w * h / 2, raw) != w * h / 2)) { perror("source"); return 1; }
  struct sfave_enc_frame e = {.y = (uint64_t)(uintptr_t)y, .uv = (uint64_t)(uintptr_t)uv, .out = (uint64_t)(uintptr_t)out,
   .y_stride = w, .uv_stride = w, .out_cap = (uint32_t)cap, .idr = n % 30 == 0};
  double a = now_ms();
  if (ioctl(fd, SFAVE_IOC_ENC_FRAME, &e) < 0) { fprintf(stderr, "frame %u: %s\n", n, strerror(errno)); ioctl(fd, SFAVE_IOC_ENC_STOP); return 1; }
  double ms = now_ms() - a;
  if (ms > worst) worst = ms;
  if (!e.out_len || fwrite(out, 1, e.out_len, f) != e.out_len) { fprintf(stderr, "frame %u: no data or short write\n", n); ioctl(fd, SFAVE_IOC_ENC_STOP); return 1; }
  total += e.out_len;
  keys += e.keyframe != 0;
  if (n < 3 || n + 1 == frames) printf("frame %u: %u bytes key=%u %.2f ms\n", e.n, e.out_len, e.keyframe, ms);
  done++;
 }
 if (!done) { fputs("no input frames\n", stderr); ioctl(fd, SFAVE_IOC_ENC_STOP); return 1; }
 double all = now_ms() - t0;
 if (ioctl(fd, SFAVE_IOC_ENC_STOP) < 0) { perror("SFAVE_IOC_ENC_STOP"); return 1; }
 close(fd);
 if (fclose(f)) { perror("close"); return 1; }
 if (raw) fclose(raw);
 printf("ENCODED %u frames %ux%u QP %u: %llu bytes, %u keyframes, %.2f ms/frame (worst ioctl %.2f ms)\n",
  done, w, h, qp, total, keys, all / done, worst);
 return 0;
}
