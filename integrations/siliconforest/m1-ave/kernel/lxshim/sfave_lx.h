/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * The part of the Linux kernel API that upstream ave_session.c and ave_cmd.c
 * use, on XNU. Those files stay byte-identical to the pinned upstream (see
 * ../../NOTICE). Everything runs in one thread under the driver's lock: there
 * is no interrupt handler, and a completion is waited for by polling the IPC
 * rings with a deadline.
 */
#ifndef SFAVE_LX_H
#define SFAVE_LX_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/errno.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int8_t s8;
typedef int16_t s16;
typedef int32_t s32;
typedef int64_t s64;
typedef uint16_t __le16;
typedef uint32_t __le32;
typedef uint64_t __le64;
typedef uint8_t __u8;
typedef uint16_t __u16;
typedef uint32_t __u32;
typedef uint64_t __u64;
typedef uint64_t dma_addr_t;
typedef uint64_t phys_addr_t;
typedef uint64_t resource_size_t;
typedef unsigned int gfp_t;
typedef int spinlock_t;

#undef __packed
#undef __aligned
#undef __maybe_unused
#undef __always_inline
#define __iomem
#define __force
#define __packed __attribute__((packed))
#define __aligned(x) __attribute__((aligned(x)))
#define __maybe_unused __attribute__((unused))
#define __always_inline inline __attribute__((always_inline))
#define fallthrough __attribute__((fallthrough))
#define likely(x) __builtin_expect(!!(x), 1)
#define unlikely(x) __builtin_expect(!!(x), 0)

#undef PAGE_SIZE
#define PAGE_SIZE 16384UL
#define PAGE_ALIGN(x) ALIGN((x), PAGE_SIZE)
#define HZ 1000
#define GFP_KERNEL 0u
#define SZ_4K 0x1000
#define SZ_16K 0x4000
#define SZ_32K 0x8000
#define SZ_64K 0x10000
#define SZ_256K 0x40000
#define SZ_1M 0x100000
#define SZ_16M 0x1000000
#define SZ_64M 0x4000000
#define SZ_4G 0x100000000ULL

#define BIT(n) (1UL << (n))
#define BIT_ULL(n) (1ULL << (n))
#define GENMASK(h, l) ((~0UL << (l)) & (~0UL >> (63 - (h))))
#define GENMASK_ULL(h, l) ((~0ULL << (l)) & (~0ULL >> (63 - (h))))
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define BUILD_BUG_ON(c) _Static_assert(!(c), "BUILD_BUG_ON")
#define ALIGN(x, a) (((x) + ((__typeof__(x))(a) - 1)) & ~((__typeof__(x))(a) - 1))
#define IS_ALIGNED(x, a) (((x) & ((__typeof__(x))(a) - 1)) == 0)
#define DIV_ROUND_UP(n, d) (((n) + (d) - 1) / (d))
#define DIV_ROUND_CLOSEST(n, d) (((n) + (d) / 2) / (d))
#undef min
#undef max
#define min(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a < _b ? _a : _b; })
#define max(a, b) ({ __typeof__(a) _a = (a); __typeof__(b) _b = (b); _a > _b ? _a : _b; })
#define min_t(t, a, b) ({ t _a = (t)(a); t _b = (t)(b); _a < _b ? _a : _b; })
#define max_t(t, a, b) ({ t _a = (t)(a); t _b = (t)(b); _a > _b ? _a : _b; })
#define clamp_t(t, v, lo, hi) min_t(t, max_t(t, v, lo), hi)
#define lower_32_bits(x) ((u32)(x))
#define upper_32_bits(x) ((u32)((u64)(x) >> 32))
#define READ_ONCE(x) (*(const volatile __typeof__(x) *)&(x))
#define WRITE_ONCE(x, v) (*(volatile __typeof__(x) *)&(x) = (v))
#define smp_store_release(p, v) __atomic_store_n((p), (v), __ATOMIC_RELEASE)
#define dma_wmb() __asm__ volatile("dsb oshst" ::: "memory")
#define dma_rmb() __asm__ volatile("dsb oshld" ::: "memory")
#define IS_ERR(p) ((uintptr_t)(p) >= (uintptr_t)-4095)

static inline u64 div_u64(u64 n, u32 d) { return n / d; }

/* libkern, declared here so that no BSD header's macros reach the upstream code */
void *memcpy(void *, const void *, size_t);
void *memset(void *, int, size_t);
void *memmove(void *, const void *, size_t);
int memcmp(const void *, const void *, size_t);
size_t strlen(const char *);
int strcmp(const char *, const char *);
int strncmp(const char *, const char *, size_t);
int snprintf(char *, size_t, const char *, ...);
int vsnprintf(char *, size_t, const char *, va_list);
void IOLog(const char *, ...);
void IODelay(unsigned int);
void IOSleep(unsigned int);

static inline long strscpy(char *d, const char *s, size_t n)
{
	size_t i = 0;

	if (!n)
		return -E2BIG;
	while (i + 1 < n && s[i]) {
		d[i] = s[i];
		i++;
	}
	d[i] = 0;
	return s[i] ? -E2BIG : (long)i;
}

static inline int scnprintf(char *b, size_t n, const char *f, ...)
{
	va_list a;
	int r;

	if (!n)
		return 0;
	va_start(a, f);
	r = vsnprintf(b, n, f, a);
	va_end(a);
	if (r < 0)
		return 0;
	return (size_t)r >= n ? (int)n - 1 : r;
}

/* Logging. dev_info is off unless the sfave boot argument asks for it. */
struct device { int unused; };
extern int sfave_lx_verbose;
#define dev_err(d, f, ...) IOLog("SFAppleAVE: " f, ##__VA_ARGS__)
#define dev_warn(d, f, ...) IOLog("SFAppleAVE: " f, ##__VA_ARGS__)
#define dev_info(d, f, ...) \
	do { if (sfave_lx_verbose) IOLog("SFAppleAVE: " f, ##__VA_ARGS__); } while (0)
#define dev_dbg(d, f, ...) do { } while (0)
#define dev_err_ratelimited dev_err
#define dev_warn_ratelimited dev_warn
#define KERN_INFO ""
#define DUMP_PREFIX_OFFSET 0
#define print_hex_dump(...) do { } while (0)

/* Module parameters keep their upstream defaults. */
#define module_param(n, t, p) _Static_assert(1, "")
#define MODULE_PARM_DESC(n, d) _Static_assert(1, "")

/* One thread under the driver's lock. */
struct mutex { int unused; };
#define DEFINE_MUTEX(n) struct mutex n = { 0 }
#define mutex_lock(m) do { (void)(m); } while (0)
#define mutex_unlock(m) do { (void)(m); } while (0)
#define synchronize_irq(i) do { (void)(i); } while (0)

struct completion { unsigned int done; };
static inline void init_completion(struct completion *c) { c->done = 0; }
static inline void reinit_completion(struct completion *c) { c->done = 0; }
static inline void complete(struct completion *c) { c->done++; }
#define msecs_to_jiffies(m) ((unsigned long)(m))
/* Bounded: polls the IPC rings until done or the timeout (ms). 0 on timeout. */
unsigned long wait_for_completion_timeout(struct completion *, unsigned long);

u64 ktime_get_ns(void);
#define udelay(u) IODelay(u)
#define msleep(m) IOSleep(m)

/* Allocation; sizes are remembered, since IOFree needs them. */
void *sfave_lx_alloc(size_t);
void sfave_lx_free(void *);
#define kzalloc(s, g) sfave_lx_alloc(s)
#define devm_kzalloc(d, s, g) sfave_lx_alloc(s)
#define vzalloc(s) sfave_lx_alloc(s)
#define vmalloc(s) sfave_lx_alloc(s)
#define kfree(p) sfave_lx_free(p)
#define vfree(p) sfave_lx_free(p)
void *dma_alloc_coherent(struct device *, size_t, dma_addr_t *, gfp_t);
void dma_free_coherent(struct device *, size_t, void *, dma_addr_t);
u32 crc32(u32, const void *, size_t);

static inline u16 get_unaligned_le16(const void *p) { u16 v; memcpy(&v, p, 2); return v; }
static inline u32 get_unaligned_le32(const void *p) { u32 v; memcpy(&v, p, 4); return v; }
static inline u64 get_unaligned_le64(const void *p) { u64 v; memcpy(&v, p, 8); return v; }
static inline void put_unaligned_le16(u16 v, void *p) { memcpy(p, &v, 2); }
static inline void put_unaligned_le32(u32 v, void *p) { memcpy(p, &v, 4); }
static inline void put_unaligned_le64(u64 v, void *p) { memcpy(p, &v, 8); }

static inline u32 readl_relaxed(const volatile void *p) { return *(const volatile u32 *)p; }
static inline void writel_relaxed(u32 v, volatile void *p) { *(volatile u32 *)p = v; }
static inline u64 readq_relaxed(const volatile void *p) { return *(const volatile u64 *)p; }
static inline void writeq_relaxed(u64 v, volatile void *p) { *(volatile u64 *)p = v; }
#define readl readl_relaxed
#define writel writel_relaxed
#define readl_relaxed_poll_timeout(a, v, c, delay_us, timeout_us) ({		\
	u64 _left = (timeout_us);						\
	int _r = -ETIMEDOUT;							\
	for (;;) {								\
		(v) = readl_relaxed(a);						\
		if (c) { _r = 0; break; }					\
		if (_left < (u64)(delay_us) + 1) break;				\
		IODelay((delay_us) + 1);					\
		_left -= (u64)(delay_us) + 1;					\
	}									\
	_r; })

/* Types that ave.h embeds or names; nothing here uses them. */
struct dentry;
struct gen_pool;
struct iommu_domain;
struct page;
struct reset_control;
struct dev_pm_domain_list;
struct notifier_block { int unused; };
struct work_struct { int unused; };
struct ratelimit_state { int unused; };
#define RATELIMIT_MSG_ON_RELEASE 0
#define ratelimit_state_init(r, i, b) do { (void)(r); } while (0)
#define ratelimit_set_flags(r, f) do { (void)(r); } while (0)

/* No debugfs on XNU: every call is a no-op and returns no entry. */
struct debugfs_blob_wrapper { void *data; unsigned long size; };
#ifndef _SSIZE_T
#define _SSIZE_T
typedef long ssize_t;
#endif
typedef long long loff_t;
#define __user
#define THIS_MODULE NULL
#define FMODE_WRITE 2u
#ifndef O_TRUNC
#define O_TRUNC 0x400
#endif
struct inode;
struct file { unsigned int f_mode, f_flags; };
struct file_operations {
	void *owner;
	int (*open)(struct inode *, struct file *);
	ssize_t (*read)(struct file *, char *, size_t, loff_t *);
	ssize_t (*write)(struct file *, const char *, size_t, loff_t *);
	loff_t (*llseek)(struct file *, loff_t, int);
};
#define default_llseek NULL
static inline ssize_t simple_read_from_buffer(void *t, size_t c, loff_t *p, const void *f, size_t n)
{
	(void)t; (void)c; (void)p; (void)f; (void)n;
	return -EINVAL;
}
static inline ssize_t simple_write_to_buffer(void *t, size_t n, loff_t *p, const void *f, size_t c)
{
	(void)t; (void)n; (void)p; (void)f; (void)c;
	return -EINVAL;
}

#define noinline_for_stack __attribute__((noinline))
#define ALIGN_DOWN(x, a) ((x) & ~((__typeof__(x))(a) - 1))
#define min3(a, b, c) min(min(a, b), c)
#define max3(a, b, c) max(max(a, b), c)
#define cpu_to_le16(x) ((u16)(x))
#define DECLARE_BITMAP(n, bits) unsigned long n[((bits) + 63) / 64]
static inline int test_and_set_bit(unsigned int b, unsigned long *m)
{
	unsigned long bit = 1UL << (b % 64);
	int old = (m[b / 64] & bit) != 0;

	m[b / 64] |= bit;
	return old;
}
#define debugfs_create_dir(...) ((struct dentry *)NULL)
#define debugfs_create_blob(...) ((struct dentry *)NULL)
#define debugfs_create_file(...) ((struct dentry *)NULL)
#define debugfs_remove(d) do { (void)(d); } while (0)
#define debugfs_remove_recursive(d) do { (void)(d); } while (0)

#endif
