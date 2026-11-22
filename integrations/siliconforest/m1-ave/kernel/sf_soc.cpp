// SPDX-License-Identifier: GPL-2.0-only OR MIT
/*
 * Register mappings, device tree properties and PMGR power domains for Apple Silicon
 * drivers. See sf_soc.h.
 *
 * The PMGR part follows m1n1 src/pmgr.c (MIT, Copyright The Asahi Linux Contributors):
 * the "devices" and "ps-regs" tables of /arm-io/pmgr, parents before children; the
 * reset pulse and the externally clocked rule are those of Linux
 * drivers/pmdomain/apple/pmgr-pwrstate.c (GPL-2.0-only OR MIT).
 */
#include "sf_soc.h"

#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <libkern/OSAtomic.h>
#include <string.h>
#include <sys/errno.h>

#define LOG(fmt, ...) IOLog("SFSoc: " fmt "\n", ##__VA_ARGS__)

#define SOC_PAGE 0x4000ULL

bool
SFMmio::mapPhys(uint64_t p, uint64_t l)
{
	unmap();
	if (p == 0 || l == 0)
		return false;
	uint64_t start = p & ~(SOC_PAGE - 1);
	uint64_t span = ((p + l + SOC_PAGE - 1) & ~(SOC_PAGE - 1)) - start;
	IOMemoryDescriptor *md = IOMemoryDescriptor::withPhysicalAddress((IOPhysicalAddress)start,
	    (IOByteCount)span, kIODirectionOutIn);
	map = md ? md->map(kIOMapAnywhere | kIOMapInhibitCache) : NULL;
	OSSafeReleaseNULL(md);
	if (map == NULL || map->getVirtualAddress() == 0) {
		LOG("could not map 0x%llx len 0x%llx", p, l);
		unmap();
		return false;
	}
	va = (volatile uint8_t *)map->getVirtualAddress() + (p - start);
	phys = p;
	len = l;
	return true;
}

bool
SFMmio::mapNode(const char *path, unsigned regIndex)
{
	IORegistryEntry *node = IORegistryEntry::fromPath(path, gIODTPlane);
	OSArray *regs = node ? IODTResolveAddressing(node, "reg", NULL) : NULL; /* owned by the registry */
	IOMemoryDescriptor *md = regs ? OSDynamicCast(IOMemoryDescriptor, regs->getObject(regIndex)) : NULL;
	bool ok = false;

	if (md != NULL) {
		uint64_t p = md->getPhysicalSegment(0, NULL, kIOMemoryMapperNone);
		ok = mapPhys(p, md->getLength());
	} else {
		LOG("%s has no reg entry %u", path, regIndex);
	}
	OSSafeReleaseNULL(node);
	return ok;
}

void
SFMmio::unmap()
{
	OSSafeReleaseNULL(map);
	va = NULL;
	phys = len = 0;
}

static OSData *
adt_data(const char *path, const char *name)
{
	IORegistryEntry *node = IORegistryEntry::fromPath(path, gIODTPlane);
	OSData *d = node ? OSDynamicCast(OSData, node->getProperty(name)) : NULL;
	/* Device tree entries and their properties are never freed. */
	OSSafeReleaseNULL(node);
	return d;
}

bool
sf_adt_u32(const char *path, const char *name, unsigned index, uint32_t *out)
{
	OSData *d = adt_data(path, name);
	if (d == NULL || d->getLength() < (index + 1) * 4)
		return false;
	*out = OSReadLittleInt32(d->getBytesNoCopy(), index * 4);
	return true;
}

unsigned
sf_adt_cells(const char *path, const char *name)
{
	OSData *d = adt_data(path, name);
	return d ? d->getLength() / 4 : 0;
}

/* ---- PMGR ---------------------------------------------------------------------------- */

#define PMGR_RESET        (1u << 31)
#define PMGR_AUTO_ENABLE  (1u << 28)
#define PMGR_DEV_DISABLE  (1u << 10)
#define PMGR_WAS_CLKGATED (1u << 9)
#define PMGR_WAS_PWRGATED (1u << 8)
#define PMGR_PS_ACTUAL    0x000000f0u
#define PMGR_PS_TARGET    0x0000000fu
#define PMGR_PS_ACTIVE    0xf
#define PMGR_PS_CLKGATE   0x4
#define PMGR_FLAG_VIRTUAL 0x10
#define PMGR_MAX_DEPTH    32
#define PMGR_DIE_OFFSET   0x2000000000ULL
#define PMGR_DEVICE_ID    0x0000ffffu
#define PMGR_DIE_SHIFT    28

/* struct pmgr_device of m1n1, by offset */
#define DEV_SIZE        48
#define DEV_FLAGS       0
#define DEV_ID1         3
#define DEV_PARENTS     4
#define DEV_ADDR_OFFSET 10
#define DEV_PSREG_IDX   11
#define DEV_ID2         26
#define DEV_NAME        32
#define DEV_NAME_LEN    16

static struct {
	IOLock        *lock;
	bool           loaded;
	OSArray       *regs;      /* resolved "reg" of /arm-io/pmgr */
	const uint8_t *devices;
	unsigned       ndevices;
	const uint8_t *psRegs;
	unsigned       psRegsLen;
	bool           u8id;
} gPmgr;

/* The lock is made by whoever comes first; a loser of the race frees its own. */
static void
pmgr_lock_init(void)
{
	if (gPmgr.lock == NULL) {
		IOLock *lock = IOLockAlloc();
		if (!OSCompareAndSwapPtr(NULL, lock, (void *volatile *)&gPmgr.lock))
			IOLockFree(lock);
	}
}

static inline uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint32_t le32(const uint8_t *p) { return OSReadLittleInt32(p, 0); }

static int
pmgr_load(void)
{
	if (gPmgr.loaded)
		return 0;
	IORegistryEntry *pmgr = IORegistryEntry::fromPath("/arm-io/pmgr", gIODTPlane);
	OSData *ps = pmgr ? OSDynamicCast(OSData, pmgr->getProperty("ps-regs")) : NULL;
	OSData *dev = pmgr ? OSDynamicCast(OSData, pmgr->getProperty("devices")) : NULL;
	OSArray *regs = pmgr ? IODTResolveAddressing(pmgr, "reg", NULL) : NULL;
	int ret = ENXIO;

	if (ps && ps->getLength() && ps->getLength() % 12 == 0 && dev && dev->getLength() &&
	    dev->getLength() % DEV_SIZE == 0 && regs && regs->getCount()) {
		regs->retain();
		gPmgr.regs = regs;
		gPmgr.psRegs = (const uint8_t *)ps->getBytesNoCopy();
		gPmgr.psRegsLen = ps->getLength();
		gPmgr.devices = (const uint8_t *)dev->getBytesNoCopy();
		gPmgr.ndevices = dev->getLength() / DEV_SIZE;
		/* u8 or u16 ids: the first two devices differ in id1 when ids are u8 */
		if (gPmgr.ndevices >= 2)
			gPmgr.u8id = gPmgr.devices[DEV_ID1] != gPmgr.devices[DEV_SIZE + DEV_ID1];
		gPmgr.loaded = true;
		ret = 0;
	} else {
		LOG("pmgr: no usable ps-regs/devices/reg in /arm-io/pmgr");
	}
	OSSafeReleaseNULL(pmgr);
	return ret;
}

static uint16_t
dev_id(const uint8_t *dev)
{
	return gPmgr.u8id ? dev[DEV_ID1] : le16(dev + DEV_ID2);
}

static const uint8_t *
dev_find(uint16_t id)
{
	for (unsigned i = 0; i < gPmgr.ndevices; i++) {
		const uint8_t *dev = gPmgr.devices + i * DEV_SIZE;
		if (dev_id(dev) == id)
			return dev;
	}
	return NULL;
}

static const uint8_t *
dev_find_named(const char *name)
{
	size_t n = strlen(name);
	if (n > DEV_NAME_LEN)
		return NULL;
	for (unsigned i = 0; i < gPmgr.ndevices; i++) {
		const uint8_t *dev = gPmgr.devices + i * DEV_SIZE;
		if (memcmp(dev + DEV_NAME, name, n) == 0 && (n == DEV_NAME_LEN || dev[DEV_NAME + n] == 0))
			return dev;
	}
	return NULL;
}

/* Physical address of the device's power-state register. */
static uint64_t
dev_addr(uint8_t die, const uint8_t *dev)
{
	uint8_t idx = dev[DEV_PSREG_IDX];
	if (((uint32_t)idx + 1) * 12 > gPmgr.psRegsLen)
		return 0;
	uint32_t regIdx = le32(gPmgr.psRegs + 12 * idx);
	uint32_t regOffset = le32(gPmgr.psRegs + 12 * idx + 4);
	IOMemoryDescriptor *md = OSDynamicCast(IOMemoryDescriptor, gPmgr.regs->getObject(regIdx));
	uint64_t base = md ? md->getPhysicalSegment(0, NULL, kIOMemoryMapperNone) : 0;
	if (base == 0)
		return 0;
	return base + regOffset + PMGR_DIE_OFFSET * die + ((uint64_t)dev[DEV_ADDR_OFFSET] << 3);
}

static void
dev_name(const uint8_t *dev, char out[DEV_NAME_LEN + 1])
{
	memcpy(out, dev + DEV_NAME, DEV_NAME_LEN);
	out[DEV_NAME_LEN] = 0;
}

static int
pmgr_enable(uint8_t die, uint16_t id, uint32_t flags, bool log, unsigned depth)
{
	const uint8_t *dev = id ? dev_find(id) : NULL;
	if (dev == NULL || depth >= PMGR_MAX_DEPTH) {
		LOG("pmgr: device %u not usable (depth %u)", id, depth);
		return ENOENT;
	}
	for (int i = 0; i < 2; i++) {
		uint16_t parent = gPmgr.u8id ? dev[DEV_PARENTS + i] : le16(dev + DEV_PARENTS + 2 * i);
		if (parent != 0) {
			/* only the leaf may depend on an external clock */
			int ret = pmgr_enable(die, parent, 0, log, depth + 1);
			if (ret != 0)
				return ret;
		}
	}
	if (dev[DEV_FLAGS] & PMGR_FLAG_VIRTUAL)
		return 0;

	SFMmio reg;
	char name[DEV_NAME_LEN + 1];
	uint64_t addr = dev_addr(die, dev);
	dev_name(dev, name);
	if (!reg.mapPhys(addr, 4))
		return ENXIO;
	uint32_t before = reg.r32(0), now = before;
	uint32_t want = (flags & kSFPmgrExternallyClocked) ? PMGR_PS_CLKGATE : PMGR_PS_ACTIVE;
	int ret = 0;

	if (((before & PMGR_PS_ACTUAL) >> 4) != PMGR_PS_ACTIVE) {
		reg.mask32(0, PMGR_AUTO_ENABLE | PMGR_WAS_CLKGATED | PMGR_WAS_PWRGATED | PMGR_PS_TARGET, PMGR_PS_ACTIVE);
		ret = ETIMEDOUT;
		for (int i = 0; i < 10000; i++) {
			now = reg.r32(0);
			if (((now & PMGR_PS_ACTUAL) >> 4) >= want) {
				ret = 0;
				break;
			}
			IODelay(10);
		}
	}
	/* a domain that had to be turned on is always worth a line */
	if (log || ret != 0 || ((before ^ now) & PMGR_PS_ACTUAL))
		LOG("pmgr: %s (%u) at 0x%llx: 0x%08x -> 0x%08x%s", name, id, addr, before, now, ret ? " TIMEOUT" : "");
	reg.unmap();
	return ret;
}

int
sf_pmgr_enable_node(const char *path, int gateIndex, uint32_t flags, bool log)
{
	pmgr_lock_init();
	unsigned n = sf_adt_cells(path, "clock-gates");
	int result = 0;

	if (n == 0 || (gateIndex >= 0 && (unsigned)gateIndex >= n)) {
		LOG("pmgr: %s has no clock-gates entry %d", path, gateIndex);
		return ENOENT;
	}
	IOLockLock(gPmgr.lock);
	result = pmgr_load();
	for (unsigned i = 0; result == 0 && i < n; i++) {
		uint32_t entry = 0;
		if (gateIndex >= 0 && i != (unsigned)gateIndex)
			continue;
		sf_adt_u32(path, "clock-gates", i, &entry);
		int ret = pmgr_enable((uint8_t)(entry >> PMGR_DIE_SHIFT), (uint16_t)(entry & PMGR_DEVICE_ID), flags, log, 0);
		if (ret != 0)
			result = ret;
	}
	IOLockUnlock(gPmgr.lock);
	return result;
}

int
sf_pmgr_enable_named(const char *name, bool log)
{
	pmgr_lock_init();
	IOLockLock(gPmgr.lock);
	int ret = pmgr_load();
	const uint8_t *dev = ret == 0 ? dev_find_named(name) : NULL;
	if (ret == 0 && dev == NULL) {
		/* a wrong name must not cost a boot to find out: the table's names, eight to a line */
		LOG("pmgr: no domain named %s; the %u domains of the table:", name, gPmgr.ndevices);
		char line[8 * (DEV_NAME_LEN + 1) + 1];
		size_t at = 0;
		for (unsigned i = 0; i < gPmgr.ndevices; i++) {
			char one[DEV_NAME_LEN + 1];
			dev_name(gPmgr.devices + i * DEV_SIZE, one);
			at += snprintf(line + at, sizeof(line) - at, "%s ", one);
			if (i % 8 == 7 || i + 1 == gPmgr.ndevices) {
				LOG("pmgr:   %s", line);
				at = 0;
			}
		}
		ret = ENOENT;
	}
	if (ret == 0)
		ret = pmgr_enable(0, dev_id(dev), 0, log, 0);
	IOLockUnlock(gPmgr.lock);
	return ret;
}

int
sf_pmgr_reset_named(const char *name, bool log)
{
	pmgr_lock_init();
	IOLockLock(gPmgr.lock);
	int ret = pmgr_load();
	const uint8_t *dev = ret == 0 ? dev_find_named(name) : NULL;
	SFMmio reg;

	if (ret == 0 && (dev == NULL || !reg.mapPhys(dev_addr(0, dev), 4)))
		ret = ENOENT;
	if (ret == 0) {
		uint32_t before = reg.r32(0);
		if (((before & PMGR_PS_ACTUAL) >> 4) != PMGR_PS_ACTIVE) {
			LOG("pmgr: will not reset %s while it is off (0x%08x)", name, before);
			ret = EBUSY;
		} else {
			/* quiesce, pulse, release: never write the latched WAS_* flags back */
			reg.mask32(0, PMGR_WAS_CLKGATED | PMGR_WAS_PWRGATED, PMGR_DEV_DISABLE);
			reg.mask32(0, PMGR_WAS_CLKGATED | PMGR_WAS_PWRGATED, PMGR_RESET);
			IODelay(10);
			reg.mask32(0, PMGR_WAS_CLKGATED | PMGR_WAS_PWRGATED | PMGR_RESET, 0);
			reg.mask32(0, PMGR_WAS_CLKGATED | PMGR_WAS_PWRGATED | PMGR_DEV_DISABLE, 0);
			if (log)
				LOG("pmgr: reset %s at 0x%llx: 0x%08x -> 0x%08x", name, reg.phys, before, reg.r32(0));
		}
	} else {
		LOG("pmgr: no domain named %s", name);
	}
	reg.unmap();
	IOLockUnlock(gPmgr.lock);
	return ret;
}

uint32_t
sf_pmgr_state_named(const char *name)
{
	pmgr_lock_init();
	IOLockLock(gPmgr.lock);
	const uint8_t *dev = pmgr_load() == 0 ? dev_find_named(name) : NULL;
	SFMmio reg;
	uint32_t value = 0;
	if (dev != NULL && reg.mapPhys(dev_addr(0, dev), 4))
		value = reg.r32(0);
	reg.unmap();
	IOLockUnlock(gPmgr.lock);
	return value;
}

int
sf_pmgr_enable_property(const char *path, const char *property, bool log)
{
	pmgr_lock_init();
	unsigned n = sf_adt_cells(path, property);
	if (n == 0)
		return ENOENT;
	IOLockLock(gPmgr.lock);
	int result = pmgr_load();
	for (unsigned i = 0; result == 0 && i < n; i++) {
		uint32_t entry = 0;
		sf_adt_u32(path, property, i, &entry);
		int ret = pmgr_enable((uint8_t)(entry >> PMGR_DIE_SHIFT), (uint16_t)(entry & PMGR_DEVICE_ID), 0, log, 0);
		if (ret != 0)
			result = ret;
	}
	IOLockUnlock(gPmgr.lock);
	return result;
}

int
sf_pmgr_enable_named_quiet(const char *name, bool log)
{
	pmgr_lock_init();
	IOLockLock(gPmgr.lock);
	int ret = pmgr_load();
	const uint8_t *dev = ret == 0 ? dev_find_named(name) : NULL;
	if (ret == 0 && dev == NULL)
		ret = ENOENT;
	if (ret == 0)
		ret = pmgr_enable(0, dev_id(dev), 0, log, 0);
	IOLockUnlock(gPmgr.lock);
	return ret;
}
