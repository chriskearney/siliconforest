// SPDX-License-Identifier: GPL-2.0-only
/* T8103/J293 coprocessor boot. Power, then one SVE idle write, then ASC
 * status. DAPF and CPUDART stream 0 follow only while the CPU is stopped.
 * TEXT is fetched from the iBoot RVBAR, not mapped in the DART. Stream 15
 * is left alone. No encode command is submitted. */
#include "sfave_bringup.h"
#include "sf_soc.h"
#include "sf_dart_table.h"
#include "sfave/sfave_ioctl.h"
extern "C" {
#include "sfave/sfave_preload.h"
#include "sfave/sfave_dapf.h"
#include "sfave_ipc.h"
}
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOLib.h>
#include <sys/errno.h>
#include <sys/fcntl.h>
#include <sys/uio.h>
#include <sys/vnode.h>

#define LOG(fmt, ...) IOLog("SFAppleAVE: " fmt "\n", ##__VA_ARGS__)

static const uint64_t kWindow = 0xf00000000ULL;
static const uint64_t kDataDva = 0xcc000ULL;
static const uint64_t kIpcDva = 0x2000000ULL;
static const uint32_t kIpcBytes = 0x700000;
static const uint64_t kHeapDva = 0x2800000ULL;
static const uint32_t kHeapBytes = 0xc0000;
static const uint64_t kDataAlias = 0xf000cc000ULL;
static const char *kDpePath = "/Library/Firmware/apple/ave-13.5-dpe-acis_8103.bin";

static const uint32_t kAscControl = 0x400044;
static const uint32_t kAscStatus = 0x400048;
static const uint32_t kAscAux400 = 0x400400;
static const uint32_t kAscAux808 = 0x400808;
static const uint32_t kAscRvbar = 0x50000;
static const uint32_t kSveIdle = 0x38;
static const uint32_t kSveScratch0 = 0x18;
static const uint32_t kBootMagic = 0x08042006u;

static int ranges_overlap(uint64_t a, uint64_t as, uint64_t b, uint64_t bs) {
	return as && bs && a < b + bs && b < a + as;
}

static int power_on(void) {
	int e = sf_pmgr_enable_node("/arm-io/ave", -1, 0, true);
	if (e)
		return e;
	e = sf_pmgr_enable_property("/arm-io/ave", "power-gates", true);
	if (e == ENOENT) {
		LOG("ave power-gates absent");
		e = 0;
	}
	if (e)
		return e;
	e = sf_pmgr_enable_node("/arm-io/dart-ave", -1, 0, true);
	if (e == ENOENT) {
		LOG("dart-ave clock-gates absent; powered with the device");
		e = 0;
	}
	if (e)
		return e;
	static const char *names[] = {"VENC_ME0", "VENC_ME1", "venc_me0", "venc_me1"};
	for (unsigned i = 0; i < 4; i++) {
		int n = sf_pmgr_enable_named_quiet(names[i], true);
		if (n == 0)
			LOG("pmgr on %s", names[i]);
		else if (n != ENOENT)
			return n;
	}
	return 0;
}

static unsigned dart_regs(uint64_t *phys, uint64_t *len, unsigned cap) {
	IORegistryEntry *node = IORegistryEntry::fromPath("/arm-io/dart-ave", gIODTPlane);
	OSArray *regs = node ? IODTResolveAddressing(node, "reg", NULL) : NULL;
	unsigned n = 0;
	if (regs != NULL) {
		unsigned count = regs->getCount();
		for (; n < cap && n < count; n++) {
			IOMemoryDescriptor *md = OSDynamicCast(IOMemoryDescriptor, regs->getObject(n));
			if (md == NULL)
				break;
			phys[n] = md->getPhysicalSegment(0, NULL, kIOMemoryMapperNone);
			len[n] = md->getLength();
			if (phys[n] == 0 || len[n] == 0)
				break;
		}
	}
	OSSafeReleaseNULL(node);
	return n;
}

static int find_dart_pair(uint64_t *cpu_phys, uint64_t *cpu_len, uint64_t *dapf_phys, uint64_t *dapf_len) {
	uint64_t phys[16], len[16];
	unsigned n = dart_regs(phys, len, 16);
	for (unsigned i = 0; i < n; i++)
		LOG("dart-ave reg%u phys=0x%llx len=0x%llx", i, phys[i], len[i]);
	for (unsigned i = 0; i < n; i++) {
		if (len[i] >= 0x8000) {
			*cpu_phys = phys[i];
			*cpu_len = len[i];
			*dapf_phys = phys[i] + 0x4000;
			*dapf_len = len[i] - 0x4000;
			return 0;
		}
		for (unsigned j = 0; j < n; j++) {
			if (phys[j] == phys[i] + 0x4000 && len[i] >= 0x100 && len[j] >= 0x400) {
				*cpu_phys = phys[i];
				*cpu_len = len[i];
				*dapf_phys = phys[j];
				*dapf_len = len[j];
				return 0;
			}
		}
	}
	LOG("dart-ave has no CPUDART/DAPF pair");
	return ENXIO;
}

struct DapfCtx {
	SFMmio *cpu;
	SFMmio *filt;
};

static SFMmio *dapf_bank(void *ctx, unsigned which) {
	DapfCtx *d = (DapfCtx *)ctx;
	return which == SFAVE_DAPF_FILTER ? d->filt : d->cpu;
}

static int dapf_span(SFMmio *m, uint32_t off, uint32_t bytes) {
	if (m == NULL || m->va == NULL || off > m->len || m->len - off < bytes)
		return EFAULT;
	return 0;
}

extern "C" int dapf_r32(void *ctx, unsigned which, uint32_t off, uint32_t *out) {
	SFMmio *m = dapf_bank(ctx, which);
	int e = dapf_span(m, off, 4);
	if (e)
		return e;
	*out = m->r32(off);
	return 0;
}

extern "C" int dapf_w32(void *ctx, unsigned which, uint32_t off, uint32_t value) {
	SFMmio *m = dapf_bank(ctx, which);
	int e = dapf_span(m, off, 4);
	if (e)
		return e;
	m->w32(off, value);
	return 0;
}

extern "C" int dapf_r64(void *ctx, unsigned which, uint32_t off, uint64_t *out) {
	SFMmio *m = dapf_bank(ctx, which);
	int e = dapf_span(m, off, 8);
	if (e)
		return e;
	*out = m->r64(off);
	return 0;
}

extern "C" int dapf_w64(void *ctx, unsigned which, uint32_t off, uint64_t value) {
	SFMmio *m = dapf_bank(ctx, which);
	int e = dapf_span(m, off, 8);
	if (e)
		return e;
	m->w64(off, value);
	return 0;
}

extern "C" int sve_rd(void *ctx, uint32_t off, uint32_t *out) {
	SFMmio *m = (SFMmio *)ctx;
	if (dapf_span(m, off, 4))
		return EFAULT;
	*out = m->r32(off);
	return 0;
}

extern "C" int sve_wr(void *ctx, uint32_t off, uint32_t value) {
	SFMmio *m = (SFMmio *)ctx;
	if (dapf_span(m, off, 4))
		return EFAULT;
	m->w32(off, value);
	return 0;
}

extern "C" void sve_delay(void *, uint32_t us) { IODelay(us); }

extern "C" void sve_barrier(void *) {
	__asm__ volatile("dsb sy" ::: "memory");
	OSSynchronizeIO();
}

static int read_dpe(void **out, size_t *size) {
	vfs_context_t ctx = vfs_context_create(NULL);
	if (ctx == NULL)
		return ENOMEM;
	vnode_t vp = NULLVP;
	int error = vnode_open(kDpePath, FREAD, 0, 0, &vp, ctx);
	uint8_t *buf = NULL;
	const size_t len = 504;
	int resid = 0;
	if (error == 0) {
		struct vnode_attr va;
		VATTR_INIT(&va);
		VATTR_WANTED(&va, va_data_size);
		error = vnode_getattr(vp, &va, ctx);
		if (error == 0 && va.va_data_size != (off_t)len)
			error = EINVAL;
	}
	if (error == 0) {
		buf = (uint8_t *)IOMalloc(len);
		if (buf == NULL)
			error = ENOMEM;
	}
	if (error == 0) {
		error = vn_rdwr(UIO_READ, vp, (caddr_t)buf, (int)len, 0, UIO_SYSSPACE, 0, vfs_context_ucred(ctx), &resid, vfs_context_proc(ctx));
		if (error == 0 && resid != 0)
			error = EIO;
	}
	if (vp != NULLVP)
		vnode_close(vp, FREAD, ctx);
	vfs_context_rele(ctx);
	if (error != 0) {
		if (buf != NULL)
			IOFree(buf, len);
		return error;
	}
	*out = buf;
	*size = len;
	return 0;
}

extern "C" int dpe_rd(void *ctx, uint32_t off, uint32_t *out) {
	SFMmio *m = (SFMmio *)ctx;
	if (dapf_span(m, off, 4))
		return EFAULT;
	*out = m->r32(off);
	return 0;
}

extern "C" int dpe_wr(void *ctx, uint32_t off, uint32_t value) {
	SFMmio *m = (SFMmio *)ctx;
	if (dapf_span(m, off, 4))
		return EFAULT;
	m->w32(off, value);
	return 0;
}

static int maybe_dpe(SFMmio *dpe) {
	void *bytes = NULL;
	size_t size = 0;
	int error = read_dpe(&bytes, &size);
	if (error == ENOENT) {
		LOG("DPE file absent; continuing without Acis");
		return 0;
	}
	if (error != 0) {
		LOG("DPE file not used (%d); continuing without Acis", error);
		return 0;
	}
	struct sfave_register_io io = {dpe, dpe_rd, dpe_wr};
	error = sfave_program_dpe(bytes, size, &io);
	IOFree(bytes, size);
	if (error)
		LOG("DPE program failed: %d", error);
	else
		LOG("DPE programmed");
	return error;
}

struct DartPage {
	IOBufferMemoryDescriptor *md;
	uint64_t *va;
	uint64_t phys;
};

struct DartState {
	DartPage pages[8];
	unsigned npages;
	struct sf_dart_tables tables;
};

extern "C" uint64_t *dart_table(void *ctx, uint64_t phys) {
	DartState *d = (DartState *)ctx;
	for (unsigned i = 0; i < d->npages; i++)
		if (d->pages[i].phys == phys)
			return d->pages[i].va;
	return NULL;
}

extern "C" uint64_t dart_alloc(void *ctx) {
	DartState *d = (DartState *)ctx;
	if (d->npages >= 8)
		return 0;
	IOBufferMemoryDescriptor *md = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
	    kIODirectionInOut | kIOMemoryPhysicallyContiguous, 0x4000, 0x0000000fffffc000ULL);
	if (md == NULL)
		return 0;
	if (md->prepare() != kIOReturnSuccess) {
		md->release();
		return 0;
	}
	uint64_t pa = md->getPhysicalSegment(0, NULL, kIOMemoryMapperNone);
	uint64_t *va = (uint64_t *)md->getBytesNoCopy();
	if (pa == 0 || va == NULL || (pa & 0x3fff)) {
		md->complete();
		md->release();
		return 0;
	}
	bzero(va, 0x4000);
	d->pages[d->npages].md = md;
	d->pages[d->npages].va = va;
	d->pages[d->npages].phys = pa;
	d->npages++;
	return pa;
}

static IOBufferMemoryDescriptor *dma_bytes(uint32_t bytes) {
	IOBufferMemoryDescriptor *md = IOBufferMemoryDescriptor::inTaskWithPhysicalMask(kernel_task,
	    kIODirectionInOut, bytes, 0x0000000fffffc000ULL);
	if (md == NULL)
		return NULL;
	if (md->prepare() != kIOReturnSuccess) {
		md->release();
		return NULL;
	}
	if (md->getBytesNoCopy() == NULL) {
		md->complete();
		md->release();
		return NULL;
	}
	bzero(md->getBytesNoCopy(), bytes);
	return md;
}

static void md_free(IOBufferMemoryDescriptor **md) {
	if (md == NULL || *md == NULL)
		return;
	(*md)->complete();
	(*md)->release();
	*md = NULL;
}

static int map_alias(struct sf_dart_tables *t, uint64_t iova, uint64_t phys, uint64_t size) {
	unsigned prot = SF_DART_PROT_READ | SF_DART_PROT_WRITE;
	int rc = sf_dart_table_map(t, iova, phys, size, prot);
	if (rc)
		return rc;
	return sf_dart_table_map(t, kWindow + iova, phys, size, prot);
}

static int map_md(struct sf_dart_tables *t, IOBufferMemoryDescriptor *md, uint64_t iova, uint32_t bytes) {
	for (uint32_t off = 0; off < bytes; off += 0x4000) {
		uint64_t pa = md->getPhysicalSegment(off, NULL, kIOMemoryMapperNone);
		if (pa == 0 || (pa & 0x3fff))
			return EFAULT;
		if (map_alias(t, iova + off, pa, 0x4000))
			return EIO;
	}
	return 0;
}

static int dart_invalidate(SFMmio &regs) {
	regs.w32(0x34, 1u);
	regs.w32(0x20, 1u << 20);
	for (int i = 0; i < 1000; i++) {
		if ((regs.r32(0x20) & 4u) == 0)
			return 0;
		IODelay(100);
	}
	LOG("DART TLB invalidate timed out");
	return ETIMEDOUT;
}

static int fill_preload(const struct sfave_boot_in *in, struct sfave_preload *pre) {
	bzero(pre, sizeof *pre);
	pre->soc = 0x8103;
	pre->preloaded = 1;
	pre->segment_count = 2;
	pre->cold_reserved = 1;
	pre->iboot = in->iboot;
	pre->firmware = in->firmware;
	pre->rtkit = in->rtkit;
	pre->segment[0].physical = in->text_phys;
	pre->segment[0].iova = 0;
	pre->segment[0].remap = in->text_phys;
	pre->segment[0].size = in->text_size;
	pre->segment[0].flags = 3;
	pre->segment[1].physical = in->data_phys;
	pre->segment[1].iova = (uint32_t)kDataDva;
	pre->segment[1].remap = in->data_remap;
	pre->segment[1].size = in->data_size;
	pre->segment[1].flags = 0;
	return sfave_preload_bootable(pre);
}

int sfave_bringup(const struct sfave_boot_in *in, uint32_t *handshake, uint32_t *caps) {
	SFMmio dpe, asc, sve, cpu, filt;
	IOBufferMemoryDescriptor *ipc_md = NULL;
	IOBufferMemoryDescriptor *heap_md = NULL;
	DartState dart;
	struct sfave_preload pre;
	DapfCtx dapf_io;
	struct sfave_dapf_io dio;
	struct sfave_ipc ipc;
	struct sfave_ipc_ops ops;
	uint64_t cpu_phys = 0, cpu_len = 0, dapf_phys = 0, dapf_len = 0, l1pa = 0, rvbar = 0;
	uint32_t sid = 0, status = 0, dart_config = 0, dapf_lock = 0, magic = 0;
	void *ipc_cpu = NULL;
	int dart_live = 0, idle = 0, err = 0;

	bzero(&dart, sizeof dart);
	if (in == NULL || handshake == NULL || caps == NULL)
		return EINVAL;
	*caps = 0;
	if (ranges_overlap(kDataDva, in->data_size, kIpcDva, kIpcBytes) ||
	    ranges_overlap(kIpcDva, kIpcBytes, kHeapDva, kHeapBytes) ||
	    ranges_overlap(kDataDva, in->data_size, kHeapDva, kHeapBytes))
		return EINVAL;
	if (in->data_remap != kDataAlias) {
		LOG("DATA remap 0x%llx is not 0x%llx; not powering", in->data_remap, kDataAlias);
		return ENOTSUP;
	}
	if ((err = fill_preload(in, &pre)))
		return err;
	if ((err = power_on()))
		return err;
	*handshake = SFAVE_HS_POWER;

	if (!dpe.mapNode("/arm-io/ave", 0) || !asc.mapNode("/arm-io/ave", 1) || !sve.mapNode("/arm-io/ave", 2)) {
		err = ENXIO;
		goto out;
	}
	LOG("ave DPE phys=0x%llx len=0x%llx ASC phys=0x%llx len=0x%llx SVE phys=0x%llx len=0x%llx",
	    dpe.phys, dpe.len, asc.phys, asc.len, sve.phys, sve.len);
	if (dpe.len < 0xdc800 || asc.len < 0x400810 || sve.len < 0x40) {
		err = ENXIO;
		goto out;
	}
	if ((err = find_dart_pair(&cpu_phys, &cpu_len, &dapf_phys, &dapf_len)))
		goto out;
	if (dapf_phys != cpu_phys + 0x4000 || !cpu.mapPhys(cpu_phys, cpu_len) || !filt.mapPhys(dapf_phys, dapf_len)) {
		err = ENXIO;
		goto out;
	}
	LOG("CPUDART phys=0x%llx len=0x%llx DAPF phys=0x%llx len=0x%llx", cpu.phys, cpu.len, filt.phys, filt.len);
	if (cpu.len < 0x100 || filt.len < 0x400) {
		err = ENXIO;
		goto out;
	}
	if (sf_adt_u32("/arm-io/dart-ave", "sids", 0, &sid) || sf_adt_u32("/arm-io/ave", "sids", 0, &sid))
		LOG("ADT sid 0x%x; programming stream 0 only", sid);

	/* First device write. Bank 2 is not read before this. */
	sve.w32(kSveIdle, 1);
	status = asc.r32(kAscStatus);
	LOG("ASC status after idle=0x%x", status);
	if ((status & 2u) == 0 || (status & 1u) != 0) {
		LOG("ASC not cold-stopped; not programming DAPF or starting");
		err = EBUSY;
		goto out;
	}
	dart_config = cpu.r32(0x60);
	dapf_lock = cpu.r32(0xf0);
	LOG("DART config=0x%x dapf_lock=0x%x params1=0x%x", dart_config, dapf_lock, cpu.r32(0x00));
	if ((dart_config & (1u << 15)) || (dapf_lock & 1u)) {
		err = EPERM;
		goto out;
	}
	if (((cpu.r32(0x00) >> 24) & 0xfu) != 14) {
		err = ENOTSUP;
		goto out;
	}
	if ((err = maybe_dpe(&dpe)))
		goto out;

	dapf_io.cpu = &cpu;
	dapf_io.filt = &filt;
	dio.context = &dapf_io;
	dio.read32 = dapf_r32;
	dio.write32 = dapf_w32;
	dio.read64 = dapf_r64;
	dio.write64 = dapf_w64;
	if ((err = sfave_program_dapf(&pre, kWindow, 0xffffffffcULL, 1, &dio)))
		goto out;
	*handshake = SFAVE_HS_DAPF;

	ipc_md = dma_bytes(kIpcBytes);
	heap_md = dma_bytes(kHeapBytes);
	ipc_cpu = ipc_md ? ipc_md->getBytesNoCopy() : NULL;
	if (ipc_md == NULL || heap_md == NULL || ipc_cpu == NULL || ((uintptr_t)ipc_cpu & 63)) {
		err = ENOMEM;
		goto out;
	}
	dart.tables.ops.ctx = &dart;
	dart.tables.ops.table = dart_table;
	dart.tables.ops.alloc_table = dart_alloc;
	if (dart_alloc(&dart) == 0) {
		err = ENOMEM;
		goto out;
	}
	dart.tables.l1 = dart.pages[0].va;
	if (map_alias(&dart.tables, kDataDva, in->data_phys, in->data_size) ||
	    map_md(&dart.tables, ipc_md, kIpcDva, kIpcBytes) ||
	    map_md(&dart.tables, heap_md, kHeapDva, kHeapBytes)) {
		LOG("DART map failed");
		err = EIO;
		goto out;
	}
	l1pa = dart.pages[0].phys;
	__asm__ volatile("dsb sy" ::: "memory");
	dart_live = 1;
	cpu.w32(0x100, 0);
	for (int i = 0; i < 4; i++)
		cpu.w32(0x200 + 4 * i, 0);
	cpu.w32(0xfc, cpu.r32(0xfc) | 1u);
	cpu.w32(0x40, cpu.r32(0x40));
	if ((err = dart_invalidate(cpu)))
		goto out;
	cpu.w32(0x200, (1u << 31) | (uint32_t)(l1pa >> 12));
	cpu.w32(0x100, 1u << 7);
	if ((err = dart_invalidate(cpu)))
		goto out;
	LOG("DART stream0 data=0x%llx/0x%x ipc=0x%llx/0x%x heap=0x%llx/0x%x ttbr=0x%x",
	    kDataDva, in->data_size, kIpcDva, kIpcBytes, kHeapDva, kHeapBytes, cpu.r32(0x200));

	ops.context = &sve;
	ops.read = sve_rd;
	ops.write = sve_wr;
	ops.delay_us = sve_delay;
	ops.barrier = sve_barrier;
	if ((err = sfave_ipc_init(&ipc, &pre, &ops, ipc_cpu, kIpcDva, kIpcBytes, kHeapDva, kHeapBytes)))
		goto out;
	if ((err = sfave_ipc_configure(&ipc)))
		goto out;
	magic = sve.r32(kSveScratch0);
	rvbar = asc.r64(kAscRvbar);
	LOG("scratch0=0x%x RVBAR=0x%llx", magic, rvbar);
	if (magic != kBootMagic) {
		err = EIO;
		goto out;
	}
	if (rvbar == 0) {
		err = ENXIO;
		goto out;
	}
	asc.w32(kAscAux808, 1);
	asc.w32(kAscControl, 0);
	asc.w32(kAscAux400, 0x10000);
	asc.w32(kAscControl, 0x10);
	idle = 0;
	for (int i = 0; i < 2000; i++) {
		status = asc.r32(kAscStatus);
		if ((status & 3u) == 0) {
			idle = 1;
			break;
		}
		IODelay(100);
	}
	LOG("ASC status after start=0x%x", status);
	if (!idle) {
		err = ETIMEDOUT;
		goto out;
	}
	*handshake = SFAVE_HS_STARTED;
	err = sfave_ipc_handshake(&ipc);
	if (err) {
		LOG("handshake failed: %d phase=%d", err, (int)ipc.phase);
		goto out;
	}
	*handshake = SFAVE_HS_READY;
	*caps = SFAVE_CAP_H264;
	LOG("handshake ready; caps=0x%x (booted, no encode session)", *caps);
	err = 0;
out:
	if (!dart_live) {
		md_free(&ipc_md);
		md_free(&heap_md);
		for (unsigned i = 0; i < dart.npages; i++)
			md_free(&dart.pages[i].md);
	}
	dpe.unmap();
	asc.unmap();
	sve.unmap();
	cpu.unmap();
	filt.unmap();
	return err;
}
