/* SPDX-License-Identifier: MIT */
/*
 * The display tree is per board: J293 and J313 differ only in the panel node, and a board
 * without known panel values is refused. A small synthetic device tree, no saved capture.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "dispdt.h"

#define IO(a) ((a) - 0x200000000ull)

static const uint64_t reg_dcp[] = {IO(0x231c00000ull), 0x4000};
static const uint64_t reg_disp0[] = {
    IO(0x230000000ull), 0x3e8000, IO(0x231320000ull), 0x4000, IO(0x231344000ull), 0x4000,
    IO(0x231800000ull), 0x800000, IO(0x23b3d0000ull), 0x4000, IO(0x23b738000ull), 0x1000,
    IO(0x23bc3c000ull), 0x1000,
};
static const uint64_t reg_dart_dcp[] = {IO(0x23130c000ull), 0x4000};
static const uint64_t reg_dart_disp0[] = {IO(0x231304000ull), 0x4000};
static const uint64_t region[4][2] = {
    {0x9e0000000ull, 0x4000}, {0x9e0100000ull, 0x8000}, {0x9e0200000ull, 0xc000}, {0x9e0300000ull, 0x10000},
};
static const uint64_t vram[] = {0x9f0000000ull, 0x2000000};

static const void *compatible;
static uint32_t compatible_len;

static const void *getprop(void *ctx, const char *path, const char *name, uint32_t *len)
{
    static const struct {
        const char *path, *name;
        const void *value;
        uint32_t len;
    } table[] = {
        {"/arm-io/dcp", "reg", reg_dcp, sizeof(reg_dcp)},
        {"/arm-io/disp0", "reg", reg_disp0, sizeof(reg_disp0)},
        {"/arm-io/dart-dcp", "reg", reg_dart_dcp, sizeof(reg_dart_dcp)},
        {"/arm-io/dart-disp0", "reg", reg_dart_disp0, sizeof(reg_dart_disp0)},
        {"/chosen/carveout-memory-map", "region-id-50", region[0], 16},
        {"/chosen/carveout-memory-map", "region-id-57", region[1], 16},
        {"/chosen/carveout-memory-map", "region-id-94", region[2], 16},
        {"/chosen/carveout-memory-map", "region-id-95", region[3], 16},
        {"/vram", "reg", vram, sizeof(vram)},
    };

    (void)ctx;
    if (!strcmp(path, "/") && !strcmp(name, "compatible")) {
        if (compatible)
            *len = compatible_len;
        return compatible;
    }
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (!strcmp(table[i].path, path) && !strcmp(table[i].name, name)) {
            *len = table[i].len;
            return table[i].value;
        }
    }
    return NULL;
}

static uint32_t cell(const struct dispdt_prop *p)
{
    assert(p && p->len == 4);
    return (uint32_t)p->value[0] << 24 | (uint32_t)p->value[1] << 16 | (uint32_t)p->value[2] << 8 | p->value[3];
}

static struct dispdt_tree a, b, c;
static const struct gpudt_adt_ops adt = {NULL, getprop};
static const struct dispdt_config cfg = {
    .chip_id = GPUDT_CHIP_T8103, .phandle_base = DISPDT_DARWIN_PHANDLE_BASE,
    .fw_version = {13, 5, 0}, .fw_version_len = 3,
    .fb_base = 0x9f0000000ull, .fb_width = 2560, .fb_height = 1600, .fb_stride = 10240, .fb_depth = 30,
};

#define BOARD(s) (compatible = (s), compatible_len = sizeof(s), dispdt_build_t8103(&adt, &cfg, &c))
#define BYTES(s) (compatible = (s), compatible_len = sizeof(s) - 1, dispdt_build_t8103(&adt, &cfg, &c))

static void panel(const struct dispdt_tree *t, const char *name, uint32_t brightness)
{
    const struct dispdt_prop *p = dispdt_find(t, DISPDT_NODE_PANEL, "compatible");

    assert(p && !strcmp((const char *)p->value, name));
    assert(!strcmp((const char *)p->value + strlen(name) + 1, "apple,panel"));
    assert(cell(dispdt_find(t, DISPDT_NODE_PANEL, "width-mm")) == 286);
    assert(cell(dispdt_find(t, DISPDT_NODE_PANEL, "height-mm")) == 179);
    assert(cell(dispdt_find(t, DISPDT_NODE_PANEL, "apple,max-brightness")) == brightness);
}

int main(void)
{
    unsigned differing = 0;

    compatible = "J293AP\0MacBookPro17,1\0AppleARM";
    compatible_len = sizeof("J293AP\0MacBookPro17,1\0AppleARM");
    assert(dispdt_build_t8103(&adt, &cfg, &a) == DISPDT_OK);
    panel(&a, "apple,panel-j293", 525);

    compatible = "J313AP\0MacBookAir10,1\0AppleARM";
    compatible_len = sizeof("J313AP\0MacBookAir10,1\0AppleARM");
    assert(dispdt_build_t8103(&adt, &cfg, &b) == DISPDT_OK);
    panel(&b, "apple,panel-j313", 420);

    /* the only properties that differ between the boards are the panel's two */
    assert(a.nprops == b.nprops && a.ndiags == b.ndiags);
    for (uint32_t i = 0; i < a.nprops; i++) {
        const struct dispdt_prop *x = &a.props[i], *y = &b.props[i];

        assert(x->node == y->node && !strcmp(x->name, y->name) && x->type == y->type);
        if (x->len == y->len && !memcmp(x->value, y->value, x->len))
            continue;
        assert(x->node == DISPDT_NODE_PANEL);
        assert(!strcmp(x->name, "compatible") || !strcmp(x->name, "apple,max-brightness"));
        differing++;
    }
    assert(differing == 2);

    /* everything else is refused, and no panel node is left behind */
    assert(BOARD("J314AP\0MacBookPro18,3\0AppleARM") == DISPDT_ERR_BOARD);
    assert(!c.nodes[DISPDT_NODE_PANEL].present && c.nprops == 0);
    assert(BOARD("J293APX\0MacBookPro17,1") == DISPDT_ERR_BOARD);
    assert(BOARD("J293") == DISPDT_ERR_BOARD);
    assert(BOARD("") == DISPDT_ERR_BOARD);
    assert(BYTES("J293AP") == DISPDT_ERR_BOARD); /* not terminated inside the property */
    assert(BYTES("J313AP") == DISPDT_ERR_BOARD);
    compatible = NULL;
    assert(dispdt_build_t8103(&adt, &cfg, &c) == DISPDT_ERR_BOARD);

    puts("dispdt per-board checks passed");
    return 0;
}
