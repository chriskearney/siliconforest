/* SPDX-License-Identifier: MIT */
/*
 * dispdt: Linux-style device-tree nodes for the display of the 13" M1 MacBook Pro (J293,
 * T8103), synthesised from Apple's device tree, for the pin's drivers/gpu/drm/apple
 * (omacom/linux-aurora 6a08a08e). Companion of gpudt.h: same conventions (values in FDT
 * byte order, the origin of every value recorded, no allocation, no kernel headers).
 *
 * Static values: arch/arm64/boot/dts/apple/t8103.dtsi, t8103-jxxx.dtsi, t8103-j293.dts
 * (GPL-2.0+ OR MIT). What m1n1 adds at boot (src/kboot.c, MIT, Copyright The Asahi Linux
 * Contributors): the firmware version tuples (dt_set_dcp_firmware), the reserved-memory
 * nodes of iBoot's carve-outs and the links to them (dt_carveout_reserved_regions,
 * dt_vram_reserved_region), status "okay" on dart-disp0 and dcp, and the boot framebuffer
 * node (dt_set_fb).
 */
#ifndef M1_GPU_DT_DISPDT_H
#define M1_GPU_DT_DISPDT_H

#include "gpudt.h"

#define DISPDT_MAX_PROPS 112
#define DISPDT_MAX_VALUE 128
#define DISPDT_MAX_DIAGS 24

/* phandles of the display nodes: above the GPU's (gpudt uses base + 0..6) */
#define DISPDT_DARWIN_PHANDLE_BASE (GPUDT_DARWIN_PHANDLE_BASE + 0x40u)

enum dispdt_node_id {
    DISPDT_NODE_DCP_DART = 0,     /* iommu@23130c000 */
    DISPDT_NODE_DISP0_DART,       /* iommu@231304000 */
    DISPDT_NODE_DCP_MBOX,         /* mbox@231c08000 */
    DISPDT_NODE_PMGR_DCP,         /* power-management@23b738000 */
    DISPDT_NODE_CLK_DISP0,        /* clock-disp0 */
    DISPDT_NODE_RESERVED_MEMORY,  /* reserved-memory: shared with gpudt's, see `existing` */
    DISPDT_NODE_DCP_DATA,         /* reserved-memory/dcp_data@<pa>     region-id-50 */
    DISPDT_NODE_REGION57,         /* reserved-memory/region57@<pa>     region-id-57 */
    DISPDT_NODE_REGION94,         /* reserved-memory/region94@<pa>     region-id-94 */
    DISPDT_NODE_REGION95,         /* reserved-memory/region95@<pa>     region-id-95 */
    DISPDT_NODE_VRAM,             /* reserved-memory/framebuffer@<pa>  /vram */
    DISPDT_NODE_DCP,              /* dcp@231c00000 */
    DISPDT_NODE_PIODMA,           /* dcp@231c00000/piodma */
    DISPDT_NODE_PANEL,            /* dcp@231c00000/panel */
    DISPDT_NODE_DISPLAY,          /* display-subsystem */
    DISPDT_NODE_CHOSEN,           /* chosen: existing */
    DISPDT_NODE_FRAMEBUFFER0,     /* chosen/framebuffer@<base> */
    DISPDT_NODE_COUNT
};

struct dispdt_node {
    char name[48];
    int8_t parent;  /* enum dispdt_node_id, or -1 for the device-tree root */
    bool present;
    bool existing;  /* a node the tree may already have (reserved-memory, chosen): attach below it, create only if absent */
    bool device;    /* a driver binds to it: publish as a platform device */
    uint32_t phandle;
};

struct dispdt_prop {
    uint8_t node;   /* enum dispdt_node_id */
    uint8_t type;   /* enum gpudt_type */
    uint8_t origin; /* enum gpudt_origin */
    uint8_t flags;  /* GPUDT_F_* */
    uint16_t len;
    const char *name;
    uint8_t value[DISPDT_MAX_VALUE];
};

/* One firmware mapping of a reserved region, for `iommu-addresses`. */
struct dispdt_iova {
    bool have;
    uint64_t iova;
};

struct dispdt_config {
    uint32_t chip_id; /* must be GPUDT_CHIP_T8103 */
    uint32_t phandle_base;

    /* OS firmware version as m1n1's table gives it for the ADT's iBoot string (gpudt_tree.fw_version) */
    uint32_t fw_version[4], fw_version_len;

    /* The boot framebuffer as the boot-args describe it; base 0 leaves the framebuffer node out. */
    uint64_t fb_base;
    uint32_t fb_width, fb_height, fb_stride, fb_depth;

    /*
     * Where each reserved region is mapped in the DARTs, as m1n1 finds it by searching the
     * tables (dart_get_mapping). Index: DISPDT_NODE_DCP_DATA .. DISPDT_NODE_VRAM minus
     * DISPDT_NODE_DCP_DATA. Without a value that device's `iommu-addresses` entry is left
     * out and a diagnostic recorded; the driver does not read the property (Linux's IOMMU
     * core does, and the DART backend here finds the mappings in the tables themselves).
     */
    struct dispdt_iova dcp_iova[5], disp_iova[5], piodma_iova[5];
};

enum dispdt_diag_code {
    /* 1 was "not J293": an unknown board is now refused (DISPDT_ERR_BOARD) */
    DISPDT_D_REG_ADT_MISMATCH = 2,   /* text = reg name; a = static, b = ADT */
    DISPDT_D_REG_ADT_ABSENT,     /* text = reg name */
    DISPDT_D_NO_IOVA,            /* text = region; a = 0 dcp, 1 disp, 2 piodma */
    DISPDT_D_FIRMWARE_UNKNOWN,   /* no version tuple: apple,firmware-* are 0 0 0 and the driver will refuse */
    DISPDT_D_FB_DEPTH,           /* a = depth: no Linux format for it, framebuffer node left out */
    DISPDT_D_NO_FRAMEBUFFER,
};

struct dispdt_tree {
    struct dispdt_node nodes[DISPDT_NODE_COUNT];
    struct dispdt_prop props[DISPDT_MAX_PROPS];
    uint32_t nprops;
    struct gpudt_diag diags[DISPDT_MAX_DIAGS];
    uint32_t ndiags;
    uint32_t fw_compat[3];
    uint64_t region_phys[5], region_size[5]; /* dcp_data, region57, region94, region95, vram */
};

#define DISPDT_OK              0
#define DISPDT_ERR_ARGS        (-1)
#define DISPDT_ERR_CHIP        (-2)
#define DISPDT_ERR_NO_DCP      (-3) /* /arm-io/dcp or /arm-io/disp0 missing */
#define DISPDT_ERR_CARVEOUT    (-4) /* a region-id-NN the display needs is missing or zero (m1n1 bails too) */
#define DISPDT_ERR_NO_VRAM     (-5)
#define DISPDT_ERR_OVERFLOW    (-6)
#define DISPDT_ERR_BOARD       (-7) /* root compatible names no board with known panel values */

/* Builds the tree. On a negative return it is incomplete and must not be published. */
int dispdt_build_t8103(const struct gpudt_adt_ops *adt, const struct dispdt_config *cfg,
                       struct dispdt_tree *out);

const struct dispdt_prop *dispdt_find(const struct dispdt_tree *t, enum dispdt_node_id node,
                                      const char *name);

/* As gpudt_prop_to_iodt(): the bytes for an IORegistry entry of the device-tree plane. */
uint32_t dispdt_prop_to_iodt(const struct dispdt_prop *p, uint8_t *out);

#endif
