/* SPDX-License-Identifier: GPL-2.0-only OR MIT */
/*
 * Small SoC services for Apple Silicon drivers that are not IOService clients of a
 * platform kext: register mappings by Apple device tree node, device tree properties,
 * and PMGR power domains (enable with parents, reset).
 *
 * Nothing here is specific to audio; another driver can compile sf_soc.cpp in or link
 * against the kext that carries it. All functions run in thread context.
 */
#ifndef _SF_SOC_H
#define _SF_SOC_H

#include <IOKit/IOLib.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/IORegistryEntry.h>
#include <libkern/OSByteOrder.h>
#include <stdint.h>

/* One uncached device mapping. */
struct SFMmio {
	IOMemoryMap      *map;
	volatile uint8_t *va;
	uint64_t          phys;
	uint64_t          len;

	SFMmio() : map(NULL), va(NULL), phys(0), len(0) {}

	/* [phys, phys + len), widened to 16 KiB pages. */
	bool mapPhys(uint64_t phys, uint64_t len);
	/* Entry regIndex of the node's "reg" (translated through the parents' ranges). */
	bool mapNode(const char *path, unsigned regIndex);
	void unmap();

	inline uint32_t r32(uint32_t off) const
	{
		uint32_t v = OSReadLittleInt32((volatile void *)va, off);
		OSSynchronizeIO();
		return v;
	}
	inline void w32(uint32_t off, uint32_t v) const
	{
		OSWriteLittleInt32((volatile void *)va, off, v);
		OSSynchronizeIO();
	}
	/* new = (old & ~clear) | set */
	inline void mask32(uint32_t off, uint32_t clear, uint32_t set) const { w32(off, (r32(off) & ~clear) | set); }
	/* Real 64-bit access. off must be 8-aligned and inside the mapping. */
	inline uint64_t r64(uint32_t off) const
	{
		uint64_t v = *(volatile uint64_t *)(va + off);
		OSSynchronizeIO();
		return v;
	}
	inline void w64(uint32_t off, uint64_t v) const
	{
		*(volatile uint64_t *)(va + off) = v;
		OSSynchronizeIO();
	}
};

/* Little-endian u32 number `index` of a property; false when absent or too short. */
bool sf_adt_u32(const char *path, const char *name, unsigned index, uint32_t *out);
/* Number of u32 cells in a property, 0 when absent. */
unsigned sf_adt_cells(const char *path, const char *name);

/*
 * PMGR power domains, after m1n1 src/pmgr.c (pmgr_adt_power_enable, pmgr_reset_device)
 * and Linux drivers/pmdomain/apple/pmgr-pwrstate.c.
 */
enum {
	/* a domain that needs an external clock counts as on once it is clock gated */
	kSFPmgrExternallyClocked = 1u << 0,
};

/*
 * Turns on entry gateIndex of the node's "clock-gates" (every entry for -1), parents
 * first. 0 or an errno value. With `log`, one line per domain on the way is logged;
 * without, only the domains that changed state or failed.
 */
int sf_pmgr_enable_node(const char *path, int gateIndex, uint32_t flags, bool log);
/* Turns on the domain with this name in the PMGR device table (die 0), parents first. */
int sf_pmgr_enable_named(const char *name, bool log);
/* Pulses the reset of the domain with this name in the PMGR device table (die 0). */
int sf_pmgr_reset_named(const char *name, bool log);
/* Raw power-state register of a named domain; 0 when it is not found. */
uint32_t sf_pmgr_state_named(const char *name);
/* Same as sf_pmgr_enable_node, for an arbitrary u32-id property (power-gates).
 * ENOENT when the property is absent; a miss does not dump the PMGR table. */
int sf_pmgr_enable_property(const char *path, const char *property, bool log);
/* Named enable that returns ENOENT without listing every domain. */
int sf_pmgr_enable_named_quiet(const char *name, bool log);

#endif
