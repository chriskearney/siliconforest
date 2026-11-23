#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host test of the kern.sf_exitwait thread half: the ACTUAL bodies of sf_ew_strip, sf_ew_read,
sf_ew_owner and sf_ew_frames, cut out of the file kernel.patch adds, compiled against stubs of
ml_nofault_copy (copies only from registered ranges, as the kernel copies only mapped pages),
VM_KERNEL_UNSLIDE and the ctid table, under ASan/UBSan.

It checks what the report needs to be safe to take on a machine with a stuck process: a frame
chain that leaves the stack, loops, is misaligned or reaches an unmapped page ends the walk
(flagged truncated) instead of reading past it; the walk stops at its frame limit; a return
address outside the kernel image is reported as 0, not as a raw pointer; the owner of a kernel
mutex or rw lock is found through the ctid table, and a destroyed lock or an unreadable event
gives no owner. Exit status 0 only if every case passes.
"""
import os, re, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FILE = 'src/Kernel/xnu/osfmk/kern/sf_exitwait.c'


def added_file(patch, path):
    """the text of a file the patch creates"""
    text = patch.read_text()
    start = text.index('+++ b/' + path + '\n')
    hunk = text.index('\n@@', start) + 1
    body = text[text.index('\n', hunk) + 1:]
    out = []
    for line in body.splitlines():
        if line.startswith('diff ') or line.startswith('--- '):
            break
        assert line.startswith('+'), line
        out.append(line[1:])
    return '\n'.join(out) + '\n'


def block(src, head):
    start = src.index(head)
    lex = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m[0]), src, flags=re.S)
    brace = lex.index('{', start)
    depth = 0
    for i in range(brace, len(src)):
        depth += (lex[i] == '{') - (lex[i] == '}')
        if not depth:
            return src[start:i + 1]
    raise ValueError(head)


HARNESS = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <stdbool.h>

typedef uintptr_t vm_offset_t;
typedef uintptr_t vm_size_t;
typedef uint64_t event64_t;
typedef uint32_t ctid_t;
typedef struct thread { uint64_t thread_id; } *thread_t;
#define THREAD_NULL ((thread_t)0)
#define LCK_MTX_USE_ARCH 0
#define LCK_MTX_CTID_MASK 0x0fffffffu
typedef struct { uint32_t grp_type; uint32_t lck_rw_owner; uint32_t lck_rw; } lck_rw_t;
enum { kThreadWaitNone = 0, kThreadWaitKernelMutex = 1, kThreadWaitSemaphore = 6,
       kThreadWaitKernelRWLockRead = 7, kThreadWaitKernelRWLockWrite = 8,
       kThreadWaitKernelRWLockUpgrade = 9 };
#define SF_EW_TRUNCATED 0x10

/* xnu osfmk/kern/waitq.h, as it is */
static inline event64_t
waitq_untyped_event(event64_t event)
{
	event64_t mask = 0xffull << 48;
	return (event & ~mask) | ((event64_t)((long long)event >> 63) & mask);
}

/* the "kernel": readable ranges, an image with a slide, a ctid table */
static struct { uintptr_t lo, hi; } mapped[8];
static int nmapped;
static uintptr_t image_lo, image_hi, slide;
static struct thread table[4] = { { 0 }, { 1001 }, { 1002 }, { 1003 } };

static void map_range(const void *p, size_t n) { mapped[nmapped].lo = (uintptr_t)p; mapped[nmapped++].hi = (uintptr_t)p + n; }
static int readable(uintptr_t a) { for (int i = 0; i < nmapped; i++) if (a >= mapped[i].lo && a < mapped[i].hi) return 1; return 0; }
static vm_size_t
ml_nofault_copy(vm_offset_t src, vm_offset_t dst, vm_size_t size)
{
	vm_size_t n = 0;
	while (n < size && readable(src + n)) { ((char *)dst)[n] = ((const char *)src)[n]; n++; }
	return n;
}
#define VM_KERNEL_UNSLIDE(v) (((uintptr_t)(v) >= image_lo && (uintptr_t)(v) < image_hi) ? (uintptr_t)(v) - slide : (vm_offset_t)0)
static thread_t ctid_get_thread_unsafe(ctid_t c) { return c >= 1 && c <= 3 ? &table[c] : THREAD_NULL; }
static uint64_t thread_tid(thread_t t) { return t->thread_id; }

#include SF_EXITWAIT_SOURCE

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int
main(void)
{
	static uint64_t stack[512] __attribute__((aligned(16)));
	static uint64_t image[64];
	uint64_t out[24];
	uint32_t flags, n;
	uintptr_t lo = (uintptr_t)stack, hi = lo + sizeof(stack);

	map_range(stack, sizeof(stack));
	image_lo = (uintptr_t)image; image_hi = image_lo + sizeof(image); slide = 0x1000;
#define RA(i) ((uint64_t)(image_lo + 8 * (i)))
#define UNSLID(i) ((uint64_t)(image_lo + 8 * (i)) - slide)

	/* 1: five frames up the stack, then fp 0 */
	memset(stack, 0, sizeof(stack));
	for (int f = 0; f < 5; f++) {
		uint64_t *fr = &stack[16 + 32 * f];
		fr[0] = f < 4 ? (uint64_t)(uintptr_t)&stack[16 + 32 * (f + 1)] : 0;
		fr[1] = RA(f + 1);
	}
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(0), out, 24, &flags);
	CHECK(n == 6 && flags == 0, "chain: n %u flags 0x%x", n, flags);
	for (uint32_t i = 0; i < n && i < 6; i++) CHECK(out[i] == UNSLID(i), "chain frame %u 0x%llx", i, (unsigned long long)out[i]);

	/* 2: a frame pointer that leaves the stack */
	stack[16 + 32 * 2] = (uint64_t)hi + 64;
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(0), out, 24, &flags);
	CHECK(n == 4 && (flags & SF_EW_TRUNCATED), "leaves stack: n %u flags 0x%x", n, flags);

	/* 3: a loop (a frame that points at itself, then one that points back down) */
	stack[16 + 32 * 2] = (uint64_t)(uintptr_t)&stack[16 + 32 * 2];
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(0), out, 24, &flags);
	CHECK(n == 4 && (flags & SF_EW_TRUNCATED), "self loop: n %u flags 0x%x", n, flags);
	stack[16 + 32 * 2] = (uint64_t)(uintptr_t)&stack[16];
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(0), out, 24, &flags);
	CHECK(n == 4 && (flags & SF_EW_TRUNCATED), "back loop: n %u flags 0x%x", n, flags);

	/* 4: misaligned */
	stack[16 + 32 * 2] = (uint64_t)(uintptr_t)&stack[16 + 32 * 3] + 4;
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(0), out, 24, &flags);
	CHECK(n == 4 && (flags & SF_EW_TRUNCATED), "misaligned: n %u flags 0x%x", n, flags);

	/* 5: an unreadable stretch inside the stack bounds: no read past it */
	stack[16 + 32 * 2] = (uint64_t)(uintptr_t)&stack[16 + 32 * 3];
	nmapped = 0;
	map_range(stack, 8 * (16 + 32 * 3));     /* frames 0..2 readable, frame 3 not */
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(0), out, 24, &flags);
	CHECK(n == 4 && (flags & SF_EW_TRUNCATED), "unmapped: n %u flags 0x%x", n, flags);
	nmapped = 0;
	map_range(stack, sizeof(stack));

	/* 6: the frame limit */
	for (int f = 0; f < 15; f++) {
		uint64_t *fr = &stack[8 + 32 * f];
		fr[0] = (uint64_t)(uintptr_t)&stack[8 + 32 * (f + 1)];
		fr[1] = RA(f % 60 + 1);
	}
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[8], RA(0), out, 8, &flags);
	CHECK(n == 8, "limit: n %u", n);

	/* 7: a return address outside the image is 0, not a raw pointer */
	memset(stack, 0, sizeof(stack));
	stack[16] = 0; stack[17] = 0x4141414141414141ull;
	flags = 0;
	n = sf_ew_frames(lo, hi, (uint64_t)(uintptr_t)&stack[16], RA(3), out, 24, &flags);
	CHECK(n == 2 && out[0] == UNSLID(3) && out[1] == 0, "outside image: n %u 0x%llx", n, (unsigned long long)out[1]);

	/* 8: no frame pointer: the saved lr alone */
	flags = 0;
	n = sf_ew_frames(lo, hi, 0, RA(2), out, 24, &flags);
	CHECK(n == 1 && flags == 0, "lr only: n %u", n);

	/* owners */
	static struct { uint32_t grp, tsid, data, tail; } mtx;
	static lck_rw_t rw;
	map_range(&mtx, sizeof(mtx));
	map_range(&rw, sizeof(rw));
	mtx.data = 0x40000000u | 2;                     /* needs_wakeup, owner ctid 2 */
	CHECK(sf_ew_owner(kThreadWaitKernelMutex, (event64_t)(uintptr_t)&mtx.data) == 1002, "mutex owner");
	mtx.data = 0xf0fe2007u;                         /* LCK_MTX_TAG_DESTROYED */
	CHECK(sf_ew_owner(kThreadWaitKernelMutex, (event64_t)(uintptr_t)&mtx.data) == 0, "destroyed mutex");
	CHECK(sf_ew_owner(kThreadWaitKernelMutex, (event64_t)0x10) == 0, "unreadable mutex event");
	rw.lck_rw_owner = 3;
	/* the event of a writer's wait, lock_rw.c lck_rw_event64(): typed, +2 */
	event64_t ev = ((event64_t)(uintptr_t)&rw ^ ((uint64_t)(uint8_t)kThreadWaitKernelRWLockWrite << 48)) + 2;
	CHECK(sf_ew_owner(kThreadWaitKernelRWLockWrite, ev) == 1003, "rw owner 0x%llx", (unsigned long long)ev);
	CHECK(sf_ew_owner(kThreadWaitSemaphore, (event64_t)(uintptr_t)&mtx.data) == 0, "other hints have none");

	printf("%s: %d failure(s)\n", failures ? "FAIL" : "PASS", failures);
	return failures != 0;
}
'''


def main():
    src = added_file(HERE / 'kernel.patch', FILE)
    parts = [block(src, 'static inline uint64_t\nsf_ew_strip('),
             block(src, 'static bool\nsf_ew_read('),
             block(src, 'static uint64_t\nsf_ew_owner('),
             block(src, 'static uint32_t\nsf_ew_frames(')]
    with tempfile.TemporaryDirectory(prefix='sf-exitwait-') as tmp:
        tmp = Path(tmp)
        (tmp / 'body.h').write_text('\n'.join(parts) + '\n')
        (tmp / 't.c').write_text(HARNESS)
        exe = tmp / 't'
        cc = os.environ.get('CC', 'clang')
        subprocess.run([cc, '-std=gnu11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
                        '-fsanitize=address,undefined', '-fno-sanitize-recover=all',
                        '-DSF_EXITWAIT_SOURCE="%s"' % (tmp / 'body.h'), str(tmp / 't.c'), '-o', str(exe)], check=True)
        r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
        sys.stdout.write(r.stdout)
        if r.returncode:
            sys.stdout.write(r.stderr)
            sys.exit('sf_exitwait host test failed')
    print('SF_EXITWAIT host: frame walk and lock owners PASS (bodies from kernel.patch)')


if __name__ == '__main__':
    main()
