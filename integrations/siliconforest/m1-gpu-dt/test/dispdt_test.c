/* SPDX-License-Identifier: MIT */
/* Host test of src/dispdt.c against the saved device tree (build/adt_fixture.c). */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "dispdt.h"
#include "fixture.h"

static const void *getprop(void *ctx, const char *path, const char *name, uint32_t *len)
{
    (void)ctx;
    for (unsigned i = 0; i < fixture_nprops; i++) {
        if (!strcmp(fixture_props[i].path, path) && !strcmp(fixture_props[i].name, name)) {
            *len = fixture_props[i].len;
            return fixture_props[i].value;
        }
    }
    return NULL;
}

static const void *getprop_nothing(void *ctx, const char *path, const char *name, uint32_t *len)
{
    (void)ctx, (void)path, (void)name, (void)len;
    return NULL;
}

static uint32_t cell(const struct dispdt_prop *p, unsigned i)
{
    const uint8_t *v = p->value + 4 * i;

    assert(p && 4 * i + 4 <= p->len);
    return (uint32_t)v[0] << 24 | (uint32_t)v[1] << 16 | (uint32_t)v[2] << 8 | v[3];
}

static uint64_t cell64(const struct dispdt_prop *p, unsigned i)
{
    return (uint64_t)cell(p, i) << 32 | cell(p, i + 1);
}

static struct dispdt_tree t; /* large: not on the stack */

int main(void)
{
    struct gpudt_adt_ops adt = {NULL, getprop}, none = {NULL, getprop_nothing};
    struct dispdt_config cfg = {.chip_id = GPUDT_CHIP_T8103, .phandle_base = DISPDT_DARWIN_PHANDLE_BASE,
                                .fw_version = {13, 6, 1}, .fw_version_len = 3,
                                .fb_base = 0xbd5d5c000ull, .fb_width = 2560, .fb_height = 1600,
                                .fb_stride = 10240, .fb_depth = 30};
    const struct dispdt_prop *p;
    uint32_t ph = cfg.phandle_base;

    /* refusals */
    assert(dispdt_build_t8103(&none, &cfg, &t) == DISPDT_ERR_NO_DCP);
    cfg.chip_id = 0x8112;
    assert(dispdt_build_t8103(&adt, &cfg, &t) == DISPDT_ERR_CHIP);
    cfg.chip_id = GPUDT_CHIP_T8103;

    assert(dispdt_build_t8103(&adt, &cfg, &t) == DISPDT_OK);

    /* static register windows agree with this machine's device tree: no mismatch diagnostics */
    for (uint32_t i = 0; i < t.ndiags; i++)
        assert(t.diags[i].code != DISPDT_D_REG_ADT_MISMATCH && t.diags[i].code != DISPDT_D_REG_ADT_ABSENT);

    /* dcp: what the pin's driver reads (dcp.c) */
    p = dispdt_find(&t, DISPDT_NODE_DCP, "compatible");
    assert(p && p->len == sizeof("apple,t8103-dcp") + sizeof("apple,dcp") && !strcmp((const char *)p->value, "apple,t8103-dcp"));
    p = dispdt_find(&t, DISPDT_NODE_DCP, "reg");
    assert(p && p->len == 96 && cell64(p, 0) == 0x231c00000ull && cell64(p, 2) == 0x4000 && cell64(p, 4) == 0x230000000ull);
    p = dispdt_find(&t, DISPDT_NODE_DCP, "reg-names");
    assert(p && !memcmp(p->value, "coproc\0disp-0\0", 14));
    p = dispdt_find(&t, DISPDT_NODE_DCP, "iommus");
    assert(p && p->len == 24 && cell(p, 0) == t.nodes[DISPDT_NODE_DCP_DART].phandle && cell(p, 1) == 0 && cell(p, 5) == 0xfc000000u);
    p = dispdt_find(&t, DISPDT_NODE_PIODMA, "iommus");
    assert(p && cell(p, 0) == t.nodes[DISPDT_NODE_DISP0_DART].phandle && cell(p, 1) == 4);
    p = dispdt_find(&t, DISPDT_NODE_DISPLAY, "iommus");
    assert(p && cell(p, 0) == t.nodes[DISPDT_NODE_DISP0_DART].phandle && cell(p, 1) == 0);
    p = dispdt_find(&t, DISPDT_NODE_DCP, "apple,bw-scratch");
    assert(p && p->len == 16 && cell(p, 0) == t.nodes[DISPDT_NODE_PMGR_DCP].phandle && cell(p, 2) == 5 && cell(p, 3) == 0x14);
    p = dispdt_find(&t, DISPDT_NODE_DCP, "apple,firmware-version");
    assert(p && cell(p, 0) == 13 && cell(p, 1) == 6 && cell(p, 2) == 1);
    p = dispdt_find(&t, DISPDT_NODE_DCP, "apple,firmware-compat");
    assert(p && cell(p, 0) == 13 && cell(p, 1) == 5 && cell(p, 2) == 0);
    p = dispdt_find(&t, DISPDT_NODE_DCP, "memory-region-names");
    assert(p && !memcmp(p->value, "dcp_data\0region57\0region94\0region95\0framebuffer", 47));
    p = dispdt_find(&t, DISPDT_NODE_DISPLAY, "memory-region-names");
    assert(p && !memcmp(p->value, "region94\0framebuffer", 21));
    p = dispdt_find(&t, DISPDT_NODE_PANEL, "apple,max-brightness");
    assert(p && cell(p, 0) == 525);

    /* reserved memory: each region is exactly one iBoot carve-out; names carry the address */
    for (int i = 0; i < 5; i++) {
        const struct dispdt_node *n = &t.nodes[DISPDT_NODE_DCP_DATA + i];
        char want[48];

        p = dispdt_find(&t, (enum dispdt_node_id)(DISPDT_NODE_DCP_DATA + i), "reg");
        assert(p && cell64(p, 0) == t.region_phys[i] && cell64(p, 2) == t.region_size[i] && t.region_phys[i]);
        snprintf(want, sizeof(want), "%llx", (unsigned long long)t.region_phys[i]);
        assert(n->present && strstr(n->name, want) && n->parent == DISPDT_NODE_RESERVED_MEMORY);
        assert(dispdt_find(&t, (enum dispdt_node_id)(DISPDT_NODE_DCP_DATA + i), "no-map"));
        /* no table search was supplied: no iommu-addresses, and a diagnostic says so */
        assert(!dispdt_find(&t, (enum dispdt_node_id)(DISPDT_NODE_DCP_DATA + i), "iommu-addresses"));
    }
    assert(t.nodes[DISPDT_NODE_RESERVED_MEMORY].existing && t.nodes[DISPDT_NODE_CHOSEN].existing);
    /* the framebuffer the boot-args name lies inside the /vram carve-out */
    assert(cfg.fb_base >= t.region_phys[4] && cfg.fb_base + (uint64_t)cfg.fb_stride * cfg.fb_height <= t.region_phys[4] + t.region_size[4]);
    p = dispdt_find(&t, DISPDT_NODE_FRAMEBUFFER0, "format");
    assert(p && !strcmp((const char *)p->value, "x2r10g10b10"));

    /* with the mappings supplied, iommu-addresses is <owner iova size> per mapping device */
    cfg.dcp_iova[2] = (struct dispdt_iova){true, 0x1318000};
    cfg.disp_iova[2] = (struct dispdt_iova){true, 0x4000};
    assert(dispdt_build_t8103(&adt, &cfg, &t) == DISPDT_OK);
    p = dispdt_find(&t, DISPDT_NODE_REGION94, "iommu-addresses");
    assert(p && p->len == 40 && cell(p, 0) == t.nodes[DISPDT_NODE_DCP].phandle && cell64(p, 1) == 0x1318000 &&
           cell64(p, 3) == t.region_size[2] && cell(p, 5) == t.nodes[DISPDT_NODE_DISPLAY].phandle && cell64(p, 6) == 0x4000);

    /* every phandle is unique and above the GPU's */
    for (int i = 0; i < DISPDT_NODE_COUNT; i++)
        for (int j = i + 1; j < DISPDT_NODE_COUNT; j++)
            assert(!t.nodes[i].phandle || t.nodes[i].phandle != t.nodes[j].phandle);
    assert(ph > GPUDT_DARWIN_PHANDLE_BASE + 6);

    /* IODT form: cells little-endian, reg fields as u64 */
    uint8_t out[DISPDT_MAX_VALUE];
    p = dispdt_find(&t, DISPDT_NODE_DCP, "reg");
    dispdt_prop_to_iodt(p, out);
    assert(out[0] == 0x00 && out[3] == 0x31 && out[4] == 0x02 && out[8] == 0x00 && out[9] == 0x40);

    printf("dispdt: all checks passed (%u properties, %u diagnostics; carve-outs", t.nprops, t.ndiags);
    for (int i = 0; i < 5; i++)
        printf(" 0x%llx+0x%llx", (unsigned long long)t.region_phys[i], (unsigned long long)t.region_size[i]);
    printf(")\n");
    return 0;
}
