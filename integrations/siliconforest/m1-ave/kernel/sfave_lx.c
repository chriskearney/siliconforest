// SPDX-License-Identifier: GPL-2.0-only
/*
 * Runs upstream's encode session (upstream/ave_session.c, unchanged) on XNU.
 * The IPC channel service below is ported from upstream ave_ipc.c at the pin
 * in ../NOTICE. There is no interrupt handler: a command's completion is
 * waited for by draining the rings, with the deadline the session passes in,
 * so no wait here is unbounded. Everything runs under the driver's lock.
 */
#include "ave.h"
#include "ave_abi_boot.h"
#include "ave_dapf.h"
#include "ave_session.h"
#include "sfave_ipc.h"
#include "sfave_bringup.h"
#include "sfave/sfave_ioctl.h"

int copyin(uint64_t, void *, size_t);
int copyout(const void *, uint64_t, size_t);

int sfave_lx_verbose;
int ave_step_ms;

static struct device gDevice;
static struct ave_device gAve;
static struct sfave_ipc *gIpc;
static int gInitErr = -1;	/* -1 not tried, 0 ready, else the errno it failed with */
static bool gStream;
static u32 gW, gH, gBpl, gN, gSrcBytes, gOutCap, gFwLines;
static void *gSrc, *gOut;
static dma_addr_t gLuma;

/* The fields of upstream's ave_soc_t8103 that the session reads. */
static const struct ave_soc gSoc = {
	.name = "t8103",
	.dpe_phys = 0x267100000ULL,
	.inst = 0,
	.two_refs_hang = true,
	.dev = { [AVE_ABI_MACOS_13_5] = { .dev_id = 13, .dev_type = 10, .chip_type = 7 } },
};

/* ---- FwIPC pool: 64-byte granules, as upstream's genalloc ---- */

#define POOL_GRAN 64u
#define POOL_BITS (0x700000u / POOL_GRAN)
static u64 gPool[POOL_BITS / 64];

static inline bool pool_used(u32 i) { return (gPool[i / 64] >> (i % 64)) & 1; }
static inline void pool_mark(u32 i, u32 n, bool used)
{
	for (u32 k = i; k < i + n; k++) {
		if (used)
			gPool[k / 64] |= 1ULL << (k % 64);
		else
			gPool[k / 64] &= ~(1ULL << (k % 64));
	}
}

void *ave_ipc_alloc(struct ave_device *ave, size_t size, dma_addr_t *iova)
{
	u32 n, i = 0, run = 0;
	u8 *cpu;

	if (!size || size > ave->ipc.size)
		return NULL;
	n = (u32)DIV_ROUND_UP(size, POOL_GRAN);
	for (; i < POOL_BITS; i++) {
		run = pool_used(i) ? 0 : run + 1;
		if (run == n)
			break;
	}
	if (i == POOL_BITS)
		return NULL;
	i = i + 1 - n;
	pool_mark(i, n, true);
	cpu = (u8 *)ave->ipc.cpu + (size_t)i * POOL_GRAN;
	memset(cpu, 0, size);
	if (iova)
		*iova = ave->ipc.iova + (u64)i * POOL_GRAN;
	return cpu;
}

void ave_ipc_free(struct ave_device *ave, void *cpu, size_t size)
{
	size_t off;

	if (!cpu || !size || (u8 *)cpu < (u8 *)ave->ipc.cpu)
		return;
	off = (size_t)((u8 *)cpu - (u8 *)ave->ipc.cpu);
	if (off >= ave->ipc.size || (off & (POOL_GRAN - 1)) || size > ave->ipc.size - off)
		return;
	pool_mark((u32)(off / POOL_GRAN), (u32)DIV_ROUND_UP(size, POOL_GRAN), false);
}

u64 ave_ipc_cpu_to_fw(struct ave_device *ave, void *cpu)
{
	return (u64)((u8 *)cpu - (u8 *)ave->ipc.cpu) + ave->ipc_fw_base;
}

void *ave_ipc_fw_to_cpu(struct ave_device *ave, u64 fw, size_t len)
{
	u64 off;

	if (!ave->ipc.cpu || fw < ave->ipc_fw_base)
		return NULL;
	off = fw - ave->ipc_fw_base;
	if (off >= ave->ipc.size || len > ave->ipc.size - off)
		return NULL;
	return (u8 *)ave->ipc.cpu + off;
}

/* ---- Rings ---- */

static int chan_send_fw(u32 id, u64 fw, u32 a1, u32 a2)
{
	if (!gIpc || id >= AVE_CH_MAX || !(gIpc->bound & (1u << id)))
		return -ENODEV;
	if (ave_ring_send(&gIpc->ring[id], fw, a1, a2))
		return -EAGAIN;
	dma_wmb();
	ave_write(&gAve, AVE_BANK_SVE, AVE_SVE_DOORBELL, 1u << gIpc->doorbell[id]);
	return 0;
}

static int chan_recv_fw(u32 id, u64 *fw, u32 *a1, u32 *a2)
{
	struct ave_ring *r = &gIpc->ring[id];
	int ret = (r->type & 2) ? ave_ring_urecv(r, fw, a1, a2) : ave_ring_recv(r, fw, a1, a2);

	return ret ? -EAGAIN : 0;
}

int ave_ipc_send(struct ave_device *ave, u32 chan_id, dma_addr_t payload, u64 arg1, u64 arg2)
{
	u64 fw = 0;

	if (payload) {
		if (payload < ave->ipc.iova || payload - ave->ipc.iova >= ave->ipc.size)
			return -EINVAL;
		fw = payload - ave->ipc.iova + ave->ipc_fw_base;
		if (fw & 3)
			return -EINVAL;
	}
	return chan_send_fw(chan_id, fw, (u32)arg1, (u32)arg2);
}

static bool has_word(const char *s, const char *w)
{
	size_t n = strlen(w);

	for (; *s; s++)
		if (!strncmp(s, w, n))
			return true;
	return false;
}

static void terminal_line(u64 fw, u32 len, u32 level)
{
	char line[0x201];
	const u8 *p;
	size_t n;

	if (!fw)
		return;
	n = min_t(u32, len, 0x200);
	p = ave_ipc_fw_to_cpu(&gAve, fw, n ? n : 1);
	if (!p)
		return;
	memcpy(line, p, n);
	line[n] = 0;
	while (n && (line[n - 1] == '\n' || line[n - 1] == '\r' || !line[n - 1]))
		line[--n] = 0;
	if (sfave_lx_verbose || ((has_word(line, "ASSERT") || has_word(line, "rror") ||
				  has_word(line, "ail")) && gFwLines < 64)) {
		gFwLines++;
		IOLog("SFAppleAVE: fw[%u]| %s\n", level, line);
	}
}

static void shmalloc(u64 fw, u32 size)
{
	struct ave_device *ave = &gAve;
	unsigned int i;
	void *cpu;

	if (fw) {
		u32 sz = 0;

		cpu = ave_ipc_fw_to_cpu(ave, fw, 1);
		if (!cpu)
			return;
		for (i = 0; i < AVE_SHMALLOC_MAX; i++) {
			if (ave->shm[i].cpu == cpu) {
				sz = ave->shm[i].size;
				ave->shm[i].cpu = NULL;
				break;
			}
		}
		if (sz)
			ave_ipc_free(ave, cpu, sz);
		chan_send_fw(AVE_CH_SHAREDMALLOC, fw, 0, 0);
		return;
	}
	cpu = ave_ipc_alloc(ave, size, NULL);
	if (!cpu) {
		IOLog("SFAppleAVE: SHAREDMALLOC of %u bytes failed\n", size);
		return;
	}
	for (i = 0; i < AVE_SHMALLOC_MAX && ave->shm[i].cpu; i++)
		;
	if (i == AVE_SHMALLOC_MAX) {
		ave_ipc_free(ave, cpu, size);
		IOLog("SFAppleAVE: SHAREDMALLOC table full\n");
		return;
	}
	ave->shm[i].cpu = cpu;
	ave->shm[i].size = size;
	chan_send_fw(AVE_CH_SHAREDMALLOC, ave_ipc_cpu_to_fw(ave, cpu), size, 0);
}

static void drain(u32 id)
{
	void (*rx)(struct ave_device *, u32, void *, u32, u32);
	u32 size, flags;
	u64 fw;

	while (!chan_recv_fw(id, &fw, &size, &flags)) {
		switch (id) {
		case AVE_CH_IO:
		case AVE_CH_IO_T2H:
			if (id == AVE_CH_IO_T2H)
				chan_send_fw(id, fw, size, 0);
			rx = READ_ONCE(gAve.ipc_rx);
			if (rx)
				rx(&gAve, id, fw ? ave_ipc_fw_to_cpu(&gAve, fw, size ? size : 1) : NULL,
				   size, flags);
			break;
		case AVE_CH_SHAREDMALLOC:
			shmalloc(fw, size);
			break;
		case AVE_CH_TERMINAL:
			terminal_line(fw, size, flags);
			break;
		default:
			return;	/* one message consumed, as upstream */
		}
	}
}

static void pump(void)
{
	u32 st = ave_read(&gAve, AVE_BANK_SVE, AVE_SVE_INTR_STATUS);

	if (st)
		ave_write(&gAve, AVE_BANK_SVE, AVE_SVE_INTR_STATUS, st);
	for (u32 id = 1; id < AVE_CH_MAX; id++)
		if (gIpc->bound & (1u << id))
			drain(id);
}

unsigned long wait_for_completion_timeout(struct completion *c, unsigned long ms)
{
	const u64 deadline = ktime_get_ns() + (u64)ms * 1000000ULL;

	for (;;) {
		u64 now;

		pump();
		if (c->done) {
			c->done--;
			now = ktime_get_ns();
			return now < deadline ? (unsigned long)((deadline - now) / 1000000ULL) + 1 : 1;
		}
		now = ktime_get_ns();
		if (now >= deadline)
			return 0;
		IOSleep(1);
	}
}

u32 crc32(u32 crc, const void *buf, size_t n)
{
	const u8 *p = buf;

	while (n--) {
		crc ^= *p++;
		for (int b = 0; b < 8; b++)
			crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
	}
	return crc;
}

/* ---- What upstream's session calls in files that are not ported ---- */

void ave_pmp_stream_on(struct ave_device *ave) { (void)ave; }		/* no PMP on t8103 */
void ave_pmp_stream_off(struct ave_device *ave) { (void)ave; }
void ave_dapf_dump_on_close(struct ave_device *ave) { (void)ave; }
void ave_regdump(struct ave_device *ave, const char *tag) { (void)ave; (void)tag; }
void ave_snap_hold(struct ave_device *ave, unsigned int frame) { (void)ave; (void)frame; }
void ave_regdump_iova(struct ave_device *ave, const char *what, dma_addr_t iova)
{
	(void)ave; (void)what; (void)iova;
}

int ave_dart_datapath_check(struct ave_device *ave, const char *tag)
{
	int e = sfave_hw_dart_check();

	(void)ave;
	if (e)
		IOLog("SFAppleAVE: [%s] datapath DART does not match the CPUDART\n", tag);
	return -e;
}

/* ---- The stream ---- */

static int enc_init_once(void)
{
	const struct ave_boot_abi *a = ave_boot_abi_get(AVE_ABI_MACOS_13_5);
	u32 reserved;
	int ret;

	if (gInitErr >= 0)
		return gInitErr;
	gIpc = sfave_hw_ipc();
	if (!gIpc || !a || gIpc->bytes != 0x700000)
		return ENXIO;
	for (unsigned int i = 0; i < 3; i++) {
		volatile void *va;
		u64 phys, len;

		ret = sfave_hw_bank(i, &va, &phys, &len);
		if (ret)
			return ret;
		gAve.bank[i].base = (void *)(uintptr_t)va;
		gAve.bank[i].phys = phys;
		gAve.bank[i].size = len;
	}
	gAve.dev = &gDevice;
	gAve.soc = &gSoc;
	gAve.fw_abi = AVE_ABI_MACOS_13_5;
	gAve.boot_abi = a;
	gAve.ipc.cpu = gIpc->cpu;
	gAve.ipc.iova = gIpc->iova;
	gAve.ipc.size = gIpc->bytes;
	gAve.ipc_fw_base = gIpc->fw_base;
	gAve.client_buf_size = gIpc->client_bytes;
	gAve.running = true;
	gAve.powered = true;
	gAve.asc_started = true;
	gAve.pm_state = AVE_PM_ON;
	/* The handshake put the channel block at 0 and the info block after it. */
	reserved = ALIGN(a->msg1_chsz + AVE_BOOT_INFO_SIZE, POOL_GRAN);
	pool_mark(0, reserved / POOL_GRAN, true);
	ret = ave_enc_init(&gAve);
	/* Config is once per core start: a failure is not retried this boot. */
	gInitErr = ret < 0 ? -ret : ret;
	if (gInitErr)
		IOLog("SFAppleAVE: encoder Config failed: %d\n", gInitErr);
	return gInitErr;
}

int sfave_enc_start(struct sfave_enc_start *s)
{
	struct ave_enc_cfg cfg;
	int ret;

	if (gStream)
		return EBUSY;
	if (!s->width || !s->height || (s->width & 15) || (s->height & 15) || s->width > 4096 ||
	    s->height > 4096 || s->crop_w > s->width || s->crop_h > s->height || s->fps > 240 ||
	    s->qp > 51)
		return EINVAL;
	sfave_lx_verbose = !!(s->flags & SFAVE_ENC_VERBOSE);
	gFwLines = 0;
	ret = enc_init_once();
	if (ret)
		return ret;
	gW = s->width;
	gH = s->height;
	gBpl = ALIGN(gW, AVE_STRIDE_ALIGN);
	gSrcBytes = gBpl * gH + gBpl * (ALIGN(gH, 64) / 2);
	gOutCap = ALIGN(gW * gH * 3 / 2 + SZ_64K, SZ_4K);
	gSrc = dma_alloc_coherent(&gDevice, gSrcBytes, &gLuma, GFP_KERNEL);
	gOut = sfave_lx_alloc(gOutCap);
	if (!gSrc || !gOut) {
		ret = ENOMEM;
		goto fail;
	}
	memset(&cfg, 0, sizeof(cfg));
	cfg.codec = AVE_ENC_CODEC_H264;
	cfg.width = s->width;
	cfg.height = s->height;
	cfg.crop_w = s->crop_w;
	cfg.crop_h = s->crop_h;
	cfg.qp = s->qp ? s->qp : 30;
	cfg.bitrate = s->bitrate;
	cfg.fps_num = s->fps ? s->fps : 30;
	cfg.fps_den = 1;
	cfg.slots = 4;			/* upstream's AVE_CODED_SLOTS */
	cfg.profile_idc = s->profile_idc ? s->profile_idc : 100;
	cfg.src_bitdepth = 8;
	cfg.level_idc = s->level_idc;
	cfg.cabac = !!s->cabac;
	cfg.bframes = 0;		/* IPPP: H.264 two-reference frames hang on t8103 */
	cfg.p_refs = 1;
	ret = ave_enc_start(&gAve, &cfg);
	if (ret) {
		ret = -ret;
		IOLog("SFAppleAVE: stream start %ux%u failed: %d\n", gW, gH, ret);
		/* An open client still owns the source buffer: leave it to stop. */
		if (gAve.client_open) {
			gStream = true;
			return ret;
		}
		goto fail;
	}
	gN = 0;
	gStream = true;
	IOLog("SFAppleAVE: stream %ux%u QP %u started\n", gW, gH, cfg.qp);
	return 0;
fail:
	if (gSrc)
		dma_free_coherent(&gDevice, gSrcBytes, gSrc, gLuma);
	sfave_lx_free(gOut);
	gSrc = gOut = NULL;
	return ret;
}

static int copy_plane(u64 from, u32 from_stride, u8 *to, u32 to_stride, u32 w, u32 rows)
{
	if (from_stride < w)
		return EINVAL;
	if (from_stride == to_stride)
		return copyin(from, to, (size_t)to_stride * rows);
	for (u32 r = 0; r < rows; r++) {
		int e = copyin(from + (u64)r * from_stride, to + (size_t)r * to_stride, w);

		if (e)
			return e;
	}
	return 0;
}

int sfave_enc_frame(struct sfave_enc_frame *f)
{
	size_t len = 0;
	bool key = false;
	int ret;

	if (!gStream || !gSrc || !gOut || !gAve.client_open)
		return EINVAL;
	ret = copy_plane(f->y, f->y_stride, gSrc, gBpl, gW, gH);
	if (!ret)
		ret = copy_plane(f->uv, f->uv_stride, (u8 *)gSrc + (size_t)gBpl * gH, gBpl, gW, gH / 2);
	if (ret)
		return ret;
	__asm__ volatile("dsb sy" ::: "memory");
	ret = ave_enc_encode(&gAve, gN, !!f->idr, gLuma, gLuma + (u64)gBpl * gH, gBpl,
			     gOut, gOutCap, &len, &key);
	if (ret)
		return -ret;
	if (len > f->out_cap)
		return ENOSPC;
	ret = copyout(gOut, f->out, len);
	if (ret)
		return ret;
	f->out_len = (u32)len;
	f->keyframe = key;
	f->n = gN++;
	return 0;
}

int sfave_enc_stop(void)
{
	int ret;

	if (!gStream)
		return 0;
	ret = ave_enc_stop(&gAve);
	if (ret) {
		/* The firmware may still hold the buffers: nothing is freed. */
		IOLog("SFAppleAVE: stream stop failed: %d\n", ret);
		return -ret;
	}
	dma_free_coherent(&gDevice, gSrcBytes, gSrc, gLuma);
	sfave_lx_free(gOut);
	gSrc = gOut = NULL;
	gStream = false;
	IOLog("SFAppleAVE: stream stopped after %u frames\n", gN);
	return 0;
}
