// SPDX-License-Identifier: MIT
/*
 * dispdt: Linux-style device-tree nodes for the J293 and J313 displays, from Apple's device tree.
 * See dispdt.h. Static values are those of arch/arm64/boot/dts/apple/t8103.dtsi,
 * t8103-jxxx.dtsi, t8103-j293.dts and t8103-j313.dts at omacom/linux-aurora 6a08a08e; the boot-time parts
 * follow m1n1 src/kboot.c (dt_set_fb, dt_set_dcp_firmware, dt_carveout_reserved_regions,
 * dt_vram_reserved_region, dt_add_reserved_regions), MIT, Copyright The Asahi Linux
 * Contributors.
 */
#include "dispdt.h"

#include <string.h>

/* t8103.dtsi */
#define DCP_DART_BASE   0x23130c000ull /* :635 */
#define DISP0_DART_BASE 0x231304000ull /* :625 */
#define DCP_MBOX_BASE   0x231c08000ull /* :644 */
#define PMGR_DCP_BASE   0x23b738000ull /* :1114 */
#define PMGR_DCP_BASE2  0x23bc3c000ull
#define DCP_BASE        0x231c00000ull /* :659 */
#define DART_WINDOW     0xfc000000u    /* iommus = <&dart sid 0x0 0x0 0x0 0xfc000000> */
#define CLK_DISP0_HZ    533333328u     /* :430 */
#define ARM_IO_BASE     0x200000000ull

static const struct {
    const char *name;
    uint64_t addr, size;
} dcp_regs[6] = {
    /* t8103.dtsi:665-672; the last five are /arm-io/disp0's first five reg entries */
    {"coproc", 0x231c00000ull, 0x4000},   {"disp-0", 0x230000000ull, 0x3e8000},
    {"disp-1", 0x231320000ull, 0x4000},   {"disp-2", 0x231344000ull, 0x4000},
    {"disp-3", 0x231800000ull, 0x800000}, {"disp-4", 0x23b3d0000ull, 0x4000},
};

/* m1n1 kboot.c:2869-2875 disp_reserved_regions_t8103, and :2518-2521 for /vram */
static const struct {
    const char *adt, *fdt, *compat;
    bool map_dcp, map_disp, map_piodma;
} regions[5] = {
    {"region-id-50", "dcp_data", "apple,asc-mem", true, false, false},
    {"region-id-57", "region57", "apple,asc-mem", true, false, false},
    {"region-id-94", "region94", "apple,asc-mem", true, true, false},
    {"region-id-95", "region95", "apple,asc-mem", true, false, true},
    {NULL, "framebuffer", "framebuffer", true, true, false},
};

/* The panel node of each board (&dcp in t8103-j293.dts:43-50 and t8103-j313.dts:38-45). */
static const struct dispdt_panel {
    const char *board, *compatible;
    uint32_t width_mm, height_mm, max_brightness;
} panels[] = {
    {"J293AP", "apple,panel-j293", 286, 179, 525},
    {"J313AP", "apple,panel-j313", 286, 179, 420},
};

/* By the first string of the root compatible, which must be terminated inside the property. */
static const struct dispdt_panel *find_panel(const uint8_t *compatible, uint32_t len)
{
    if (!compatible)
        return NULL;
    for (size_t i = 0; i < sizeof(panels) / sizeof(panels[0]); i++) {
        size_t n = strlen(panels[i].board) + 1;

        if (len >= n && !memcmp(compatible, panels[i].board, n))
            return &panels[i];
    }
    return NULL;
}

static uint32_t rd32le(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint64_t rd64le(const uint8_t *p)
{
    return (uint64_t)rd32le(p) | (uint64_t)rd32le(p + 4) << 32;
}

static uint32_t rd32be(const uint8_t *p)
{
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | (uint32_t)p[3];
}

static void wr32be(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static void wr32le(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static void diag(struct dispdt_tree *t, uint16_t code, const char *text, uint64_t a, uint64_t b)
{
    if (t->ndiags < DISPDT_MAX_DIAGS)
        t->diags[t->ndiags++] = (struct gpudt_diag){code, text, a, b};
}

/* A property under construction; `full` is set when the table or a value overflowed. */
struct builder {
    struct dispdt_tree *t;
    bool full;
};

static struct dispdt_prop *add(struct builder *b, int node, const char *name, uint8_t type, uint8_t origin,
                               uint8_t flags)
{
    static struct dispdt_prop scratch;
    struct dispdt_prop *p;

    if (b->t->nprops >= DISPDT_MAX_PROPS) {
        b->full = true;
        memset(&scratch, 0, sizeof(scratch));
        return &scratch;
    }
    p = &b->t->props[b->t->nprops++];
    memset(p, 0, sizeof(*p));
    p->node = (uint8_t)node;
    p->name = name;
    p->type = type;
    p->origin = origin;
    p->flags = flags;
    return p;
}

static void put_cell(struct builder *b, struct dispdt_prop *p, uint32_t v)
{
    if (p->len + 4u > DISPDT_MAX_VALUE) {
        b->full = true;
        return;
    }
    wr32be(p->value + p->len, v);
    p->len += 4;
}

static void put_u64(struct builder *b, struct dispdt_prop *p, uint64_t v)
{
    put_cell(b, p, (uint32_t)(v >> 32));
    put_cell(b, p, (uint32_t)v);
}

static void put_str(struct builder *b, struct dispdt_prop *p, const char *s)
{
    size_t n = strlen(s) + 1;

    if (p->len + n > DISPDT_MAX_VALUE) {
        b->full = true;
        return;
    }
    memcpy(p->value + p->len, s, n);
    p->len += (uint16_t)n;
}

static void prop_u32(struct builder *b, int node, const char *name, uint8_t origin, uint8_t flags, uint32_t v)
{
    put_cell(b, add(b, node, name, GPUDT_T_CELLS, origin, flags), v);
}

static void prop_str(struct builder *b, int node, const char *name, uint8_t origin, uint8_t flags, const char *s)
{
    put_str(b, add(b, node, name, GPUDT_T_STRINGS, origin, flags), s);
}

static void prop_reg1(struct builder *b, int node, uint8_t origin, uint64_t addr, uint64_t size)
{
    struct dispdt_prop *p = add(b, node, "reg", GPUDT_T_REG, origin, GPUDT_F_DRIVER_READS);

    put_u64(b, p, addr);
    put_u64(b, p, size);
}

/* <&dart sid 0x0 0x0 0x0 0xfc000000>: #iommu-cells = 5 */
static void put_iommu(struct builder *b, struct dispdt_prop *p, uint32_t dart_phandle, uint32_t sid)
{
    put_cell(b, p, dart_phandle);
    put_cell(b, p, sid);
    put_cell(b, p, 0);
    put_cell(b, p, 0);
    put_cell(b, p, 0);
    put_cell(b, p, DART_WINDOW);
}

static void node_set(struct dispdt_tree *t, int id, const char *name, int parent, uint32_t phandle)
{
    struct dispdt_node *n = &t->nodes[id];

    size_t len = strlen(name);

    if (len >= sizeof(n->name))
        len = sizeof(n->name) - 1;
    memcpy(n->name, name, len);
    n->name[len] = 0;
    n->parent = (int8_t)parent;
    n->present = true;
    n->phandle = phandle;
}

static void hex_name(char *out, size_t len, const char *base, uint64_t addr)
{
    static const char digits[] = "0123456789abcdef";
    char tmp[17];
    size_t n = strlen(base), i = 0;

    if (n + 18 >= len)
        n = len - 19;
    memcpy(out, base, n);
    out[n++] = '@';
    do {
        tmp[i++] = digits[addr & 0xf];
        addr >>= 4;
    } while (addr);
    while (i)
        out[n++] = tmp[--i];
    out[n] = 0;
}

/* The i-th (address, size) pair of an /arm-io child's reg, CPU physical. */
static bool adt_reg(const struct gpudt_adt_ops *adt, const char *path, uint32_t i, uint64_t *addr, uint64_t *size)
{
    uint32_t len = 0;
    const uint8_t *v = adt->getprop(adt->ctx, path, "reg", &len);

    if (!v || len < 16 * (i + 1))
        return false;
    *addr = rd64le(v + 16 * i) + ARM_IO_BASE;
    *size = rd64le(v + 16 * i + 8);
    return true;
}

static void check_reg(struct builder *b, const struct gpudt_adt_ops *adt, const char *path, uint32_t i,
                      const char *what, uint64_t want)
{
    uint64_t addr, size;

    if (!adt_reg(adt, path, i, &addr, &size))
        diag(b->t, DISPDT_D_REG_ADT_ABSENT, what, 0, 0);
    else if (addr != want)
        diag(b->t, DISPDT_D_REG_ADT_MISMATCH, what, want, addr);
}

int dispdt_build_t8103(const struct gpudt_adt_ops *adt, const struct dispdt_config *cfg, struct dispdt_tree *t)
{
    struct builder b = {t, false};
    struct dispdt_prop *p;
    uint32_t ph, len;
    const uint8_t *v;
    uint64_t a, s;
    char name[48];
    int i;
    const struct dispdt_panel *panel;

    if (!adt || !adt->getprop || !cfg || !t)
        return DISPDT_ERR_ARGS;
    memset(t, 0, sizeof(*t));
    if (cfg->chip_id != GPUDT_CHIP_T8103)
        return DISPDT_ERR_CHIP;
    ph = cfg->phandle_base;

    if (!adt_reg(adt, "/arm-io/dcp", 0, &a, &s) || !adt_reg(adt, "/arm-io/disp0", 0, &a, &s))
        return DISPDT_ERR_NO_DCP;
    len = 0;
    v = adt->getprop(adt->ctx, "/", "compatible", &len);
    panel = find_panel(v, len);
    if (!panel)
        return DISPDT_ERR_BOARD;

    /* iBoot's carve-outs: m1n1 reads them all before it changes anything, and gives up if one is missing */
    for (i = 0; i < 4; i++) {
        v = adt->getprop(adt->ctx, "/chosen/carveout-memory-map", regions[i].adt, &len);
        if (!v || len != 16 || !rd64le(v) || !rd64le(v + 8))
            return DISPDT_ERR_CARVEOUT;
        t->region_phys[i] = rd64le(v);
        t->region_size[i] = rd64le(v + 8);
    }
    v = adt->getprop(adt->ctx, "/vram", "reg", &len);
    if (!v || len < 16 || !rd64le(v) || !rd64le(v + 8))
        return DISPDT_ERR_NO_VRAM;
    t->region_phys[4] = rd64le(v);
    t->region_size[4] = rd64le(v + 8);

    enum {
        PH_DCP_DART,
        PH_DISP0_DART,
        PH_DCP_MBOX,
        PH_PMGR_DCP,
        PH_CLK,
        PH_DCP,
        PH_PIODMA,
        PH_PANEL,
        PH_DISPLAY,
        PH_REGION0 /* + 0..4 */
    };

    /* ---- the two DARTs (t8103.dtsi:625-642; dart-disp0 enabled as m1n1 does, kboot.c:2440-2452) ---- */
    hex_name(name, sizeof(name), "iommu", DCP_DART_BASE);
    node_set(t, DISPDT_NODE_DCP_DART, name, -1, ph + PH_DCP_DART);
    hex_name(name, sizeof(name), "iommu", DISP0_DART_BASE);
    node_set(t, DISPDT_NODE_DISP0_DART, name, -1, ph + PH_DISP0_DART);
    for (i = 0; i < 2; i++) {
        int n = i ? DISPDT_NODE_DISP0_DART : DISPDT_NODE_DCP_DART;

        prop_str(&b, n, "compatible", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, "apple,t8103-dart");
        prop_reg1(&b, n, GPUDT_O_STATIC, i ? DISP0_DART_BASE : DCP_DART_BASE, 0x4000);
        prop_u32(&b, n, "#iommu-cells", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, 5);
        prop_u32(&b, n, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, t->nodes[n].phandle);
        check_reg(&b, adt, i ? "/arm-io/dart-disp0" : "/arm-io/dart-dcp", 0, i ? "dart-disp0" : "dart-dcp",
                  i ? DISP0_DART_BASE : DCP_DART_BASE);
    }
    prop_str(&b, DISPDT_NODE_DISP0_DART, "status", GPUDT_O_ADT, GPUDT_F_FRAMEWORK, "okay");

    /* ---- mailbox (t8103.dtsi:644-657). The RTKit port finds /arm-io/dcp itself; kept for comparison ---- */
    hex_name(name, sizeof(name), "mbox", DCP_MBOX_BASE);
    node_set(t, DISPDT_NODE_DCP_MBOX, name, -1, ph + PH_DCP_MBOX);
    p = add(&b, DISPDT_NODE_DCP_MBOX, "compatible", GPUDT_T_STRINGS, GPUDT_O_STATIC, GPUDT_F_FRAMEWORK);
    put_str(&b, p, "apple,t8103-asc-mailbox");
    put_str(&b, p, "apple,asc-mailbox-v4");
    prop_reg1(&b, DISPDT_NODE_DCP_MBOX, GPUDT_O_STATIC, DCP_MBOX_BASE, 0x4000);
    prop_u32(&b, DISPDT_NODE_DCP_MBOX, "#mbox-cells", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, 0);
    prop_u32(&b, DISPDT_NODE_DCP_MBOX, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_DCP_MBOX);

    /* ---- PMGR bandwidth scratch and doorbell (t8103.dtsi:1114-1120) ---- */
    hex_name(name, sizeof(name), "power-management", PMGR_DCP_BASE);
    node_set(t, DISPDT_NODE_PMGR_DCP, name, -1, ph + PH_PMGR_DCP);
    p = add(&b, DISPDT_NODE_PMGR_DCP, "reg", GPUDT_T_REG, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    put_u64(&b, p, PMGR_DCP_BASE);
    put_u64(&b, p, 0x1000);
    put_u64(&b, p, PMGR_DCP_BASE2);
    put_u64(&b, p, 0x1000);
    p = add(&b, DISPDT_NODE_PMGR_DCP, "reg-names", GPUDT_T_STRINGS, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    put_str(&b, p, "dcp-bw-scratch");
    put_str(&b, p, "dcp-bw-doorbell");
    prop_u32(&b, DISPDT_NODE_PMGR_DCP, "#apple,bw-scratch-cells", GPUDT_O_STATIC, GPUDT_F_DRIVER_READS, 3);
    prop_u32(&b, DISPDT_NODE_PMGR_DCP, "#apple,bw-doorbell-cells", GPUDT_O_STATIC, GPUDT_F_DRIVER_READS, 2);
    prop_u32(&b, DISPDT_NODE_PMGR_DCP, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_PMGR_DCP);
    /* the two windows are /arm-io/disp0's sixth and seventh reg entries */
    check_reg(&b, adt, "/arm-io/disp0", 5, "dcp-bw-scratch", PMGR_DCP_BASE);
    check_reg(&b, adt, "/arm-io/disp0", 6, "dcp-bw-doorbell", PMGR_DCP_BASE2);

    /* ---- clock (t8103.dtsi:427-432) ---- */
    node_set(t, DISPDT_NODE_CLK_DISP0, "clock-disp0", -1, ph + PH_CLK);
    prop_str(&b, DISPDT_NODE_CLK_DISP0, "compatible", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, "fixed-clock");
    prop_u32(&b, DISPDT_NODE_CLK_DISP0, "#clock-cells", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, 0);
    prop_u32(&b, DISPDT_NODE_CLK_DISP0, "clock-frequency", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, CLK_DISP0_HZ);
    prop_str(&b, DISPDT_NODE_CLK_DISP0, "clock-output-names", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, "clk_disp0");
    prop_u32(&b, DISPDT_NODE_CLK_DISP0, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_CLK);

    /* ---- reserved memory (m1n1 dt_get_or_add_reserved_mem, dt_device_set_reserved_mem) ---- */
    node_set(t, DISPDT_NODE_RESERVED_MEMORY, "reserved-memory", -1, 0);
    t->nodes[DISPDT_NODE_RESERVED_MEMORY].existing = true;
    for (i = 0; i < 5; i++) {
        int n = DISPDT_NODE_DCP_DATA + i;
        const struct dispdt_iova *io[3] = {&cfg->dcp_iova[i], &cfg->disp_iova[i], &cfg->piodma_iova[i]};
        const bool maps[3] = {regions[i].map_dcp, regions[i].map_disp, regions[i].map_piodma};
        const uint32_t owner[3] = {ph + PH_DCP, ph + PH_DISPLAY, ph + PH_PIODMA};
        struct dispdt_prop *ia = NULL;
        int k;

        hex_name(name, sizeof(name), regions[i].fdt, t->region_phys[i]);
        node_set(t, n, name, DISPDT_NODE_RESERVED_MEMORY, ph + PH_REGION0 + (uint32_t)i);
        prop_str(&b, n, "compatible", GPUDT_O_SYNTH, GPUDT_F_DRIVER_READS, regions[i].compat);
        prop_reg1(&b, n, GPUDT_O_ADT, t->region_phys[i], t->region_size[i]);
        add(&b, n, "no-map", GPUDT_T_EMPTY, GPUDT_O_SYNTH, GPUDT_F_FRAMEWORK);
        prop_u32(&b, n, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, t->nodes[n].phandle);
        for (k = 0; k < 3; k++) {
            if (!maps[k])
                continue;
            if (!io[k]->have) {
                diag(t, DISPDT_D_NO_IOVA, regions[i].fdt, (uint64_t)k, 0);
                continue;
            }
            if (!ia)
                ia = add(&b, n, "iommu-addresses", GPUDT_T_CELLS, GPUDT_O_ADT_HW, GPUDT_F_PHANDLE | GPUDT_F_FRAMEWORK);
            put_cell(&b, ia, owner[k]);
            put_u64(&b, ia, io[k]->iova);
            put_u64(&b, ia, t->region_size[i]);
        }
    }

    /* ---- dcp (t8103.dtsi:659-682, j293.dts:43-50, m1n1 dt_set_dcp_firmware) ---- */
    hex_name(name, sizeof(name), "dcp", DCP_BASE);
    node_set(t, DISPDT_NODE_DCP, name, -1, ph + PH_DCP);
    t->nodes[DISPDT_NODE_DCP].device = true;
    p = add(&b, DISPDT_NODE_DCP, "compatible", GPUDT_T_STRINGS, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    put_str(&b, p, "apple,t8103-dcp");
    put_str(&b, p, "apple,dcp");
    prop_u32(&b, DISPDT_NODE_DCP, "mboxes", GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_FRAMEWORK, ph + PH_DCP_MBOX);
    prop_str(&b, DISPDT_NODE_DCP, "mbox-names", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, "mbox");
    put_iommu(&b, add(&b, DISPDT_NODE_DCP, "iommus", GPUDT_T_CELLS, GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_FRAMEWORK),
              ph + PH_DCP_DART, 0);
    p = add(&b, DISPDT_NODE_DCP, "reg-names", GPUDT_T_STRINGS, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    for (i = 0; i < 6; i++)
        put_str(&b, p, dcp_regs[i].name);
    p = add(&b, DISPDT_NODE_DCP, "reg", GPUDT_T_REG, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    for (i = 0; i < 6; i++) {
        put_u64(&b, p, dcp_regs[i].addr);
        put_u64(&b, p, dcp_regs[i].size);
        check_reg(&b, adt, i ? "/arm-io/disp0" : "/arm-io/dcp", i ? (uint32_t)i - 1 : 0, dcp_regs[i].name, dcp_regs[i].addr);
    }
    /* <&pmgr_dcp 0 5 0x14>, <&pmgr_dcp 1 6> */
    p = add(&b, DISPDT_NODE_DCP, "apple,bw-scratch", GPUDT_T_CELLS, GPUDT_O_STATIC, GPUDT_F_PHANDLE | GPUDT_F_DRIVER_READS);
    put_cell(&b, p, ph + PH_PMGR_DCP);
    put_cell(&b, p, 0);
    put_cell(&b, p, 5);
    put_cell(&b, p, 0x14);
    p = add(&b, DISPDT_NODE_DCP, "apple,bw-doorbell", GPUDT_T_CELLS, GPUDT_O_STATIC, GPUDT_F_PHANDLE | GPUDT_F_DRIVER_READS);
    put_cell(&b, p, ph + PH_PMGR_DCP);
    put_cell(&b, p, 1);
    put_cell(&b, p, 6);
    p = add(&b, DISPDT_NODE_DCP, "apple,iomfb-surfaces", GPUDT_T_CELLS, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    put_cell(&b, p, 1);
    put_cell(&b, p, 1);
    put_cell(&b, p, 0);
    put_cell(&b, p, 0);
    prop_u32(&b, DISPDT_NODE_DCP, "clocks", GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_DRIVER_READS, ph + PH_CLK);
    prop_u32(&b, DISPDT_NODE_DCP, "#address-cells", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, 2);
    prop_u32(&b, DISPDT_NODE_DCP, "#size-cells", GPUDT_O_STATIC, GPUDT_F_FRAMEWORK, 2);
    prop_u32(&b, DISPDT_NODE_DCP, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_DCP);
    prop_str(&b, DISPDT_NODE_DCP, "status", GPUDT_O_ADT, GPUDT_F_FRAMEWORK, "okay");
    {
        /* m1n1 kboot.c:2221-2237: 12.3.1 and 12.4 run as 12.3; 13.5b4, 13.5 and 13.6.1 as 13.5 */
        uint32_t ver[3] = {0, 0, 0}, compat[3];

        if (cfg->fw_version_len >= 2) {
            ver[0] = cfg->fw_version[0];
            ver[1] = cfg->fw_version[1];
            ver[2] = cfg->fw_version_len >= 3 ? cfg->fw_version[2] : 0;
        } else {
            diag(t, DISPDT_D_FIRMWARE_UNKNOWN, NULL, 0, 0);
        }
        memcpy(compat, ver, sizeof(compat));
        if (ver[0] == 12 && (ver[1] == 3 || ver[1] == 4)) {
            compat[1] = 3;
            compat[2] = 0;
        } else if (ver[0] == 13 && (ver[1] == 5 || (ver[1] == 6 && ver[2] == 1))) {
            compat[1] = 5;
            compat[2] = 0;
        }
        memcpy(t->fw_compat, compat, sizeof(compat));
        p = add(&b, DISPDT_NODE_DCP, "apple,firmware-version", GPUDT_T_CELLS, GPUDT_O_FIRMWARE, GPUDT_F_DRIVER_READS);
        for (i = 0; i < 3; i++)
            put_cell(&b, p, ver[i]);
        p = add(&b, DISPDT_NODE_DCP, "apple,firmware-compat", GPUDT_T_CELLS, GPUDT_O_FIRMWARE, GPUDT_F_DRIVER_READS);
        for (i = 0; i < 3; i++)
            put_cell(&b, p, compat[i]);
    }
    /* memory-region, memory-region-names: in m1n1's order, the carve-outs then the framebuffer */
    {
        struct dispdt_prop *mr = add(&b, DISPDT_NODE_DCP, "memory-region", GPUDT_T_CELLS, GPUDT_O_SYNTH,
                                     GPUDT_F_PHANDLE | GPUDT_F_DRIVER_READS);
        struct dispdt_prop *mn = add(&b, DISPDT_NODE_DCP, "memory-region-names", GPUDT_T_STRINGS, GPUDT_O_SYNTH,
                                     GPUDT_F_DRIVER_READS);

        for (i = 0; i < 5; i++) {
            put_cell(&b, mr, ph + PH_REGION0 + (uint32_t)i);
            put_str(&b, mn, regions[i].fdt);
        }
    }

    node_set(t, DISPDT_NODE_PIODMA, "piodma", DISPDT_NODE_DCP, ph + PH_PIODMA);
    put_iommu(&b, add(&b, DISPDT_NODE_PIODMA, "iommus", GPUDT_T_CELLS, GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_FRAMEWORK),
              ph + PH_DISP0_DART, 4);
    prop_u32(&b, DISPDT_NODE_PIODMA, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_PIODMA);
    prop_u32(&b, DISPDT_NODE_PIODMA, "memory-region", GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_FRAMEWORK, ph + PH_REGION0 + 3);
    prop_str(&b, DISPDT_NODE_PIODMA, "memory-region-names", GPUDT_O_SYNTH, GPUDT_F_FRAMEWORK, regions[3].fdt);

    node_set(t, DISPDT_NODE_PANEL, "panel", DISPDT_NODE_DCP, ph + PH_PANEL);
    p = add(&b, DISPDT_NODE_PANEL, "compatible", GPUDT_T_STRINGS, GPUDT_O_STATIC, GPUDT_F_DRIVER_READS);
    put_str(&b, p, panel->compatible);
    put_str(&b, p, "apple,panel");
    prop_u32(&b, DISPDT_NODE_PANEL, "width-mm", GPUDT_O_STATIC, GPUDT_F_DRIVER_READS, panel->width_mm);
    prop_u32(&b, DISPDT_NODE_PANEL, "height-mm", GPUDT_O_STATIC, GPUDT_F_DRIVER_READS, panel->height_mm);
    prop_u32(&b, DISPDT_NODE_PANEL, "apple,max-brightness", GPUDT_O_STATIC, GPUDT_F_DRIVER_READS, panel->max_brightness);
    prop_u32(&b, DISPDT_NODE_PANEL, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_PANEL);

    /* ---- display-subsystem (t8103.dtsi:699-706). jxxx.dtsi:170 also lists dispext0's DART, which is not published ---- */
    node_set(t, DISPDT_NODE_DISPLAY, "display-subsystem", -1, ph + PH_DISPLAY);
    t->nodes[DISPDT_NODE_DISPLAY].device = true;
    prop_str(&b, DISPDT_NODE_DISPLAY, "compatible", GPUDT_O_STATIC, GPUDT_F_DRIVER_READS, "apple,display-subsystem");
    put_iommu(&b, add(&b, DISPDT_NODE_DISPLAY, "iommus", GPUDT_T_CELLS, GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_DRIVER_READS),
              ph + PH_DISP0_DART, 0);
    prop_u32(&b, DISPDT_NODE_DISPLAY, "phandle", GPUDT_O_SYNTH, GPUDT_F_PHANDLE, ph + PH_DISPLAY);
    {
        struct dispdt_prop *mr = add(&b, DISPDT_NODE_DISPLAY, "memory-region", GPUDT_T_CELLS, GPUDT_O_SYNTH,
                                     GPUDT_F_PHANDLE | GPUDT_F_DRIVER_READS);
        struct dispdt_prop *mn = add(&b, DISPDT_NODE_DISPLAY, "memory-region-names", GPUDT_T_STRINGS, GPUDT_O_SYNTH,
                                     GPUDT_F_DRIVER_READS);

        for (i = 0; i < 5; i++) {
            if (!regions[i].map_disp)
                continue;
            put_cell(&b, mr, ph + PH_REGION0 + (uint32_t)i);
            put_str(&b, mn, regions[i].fdt);
        }
    }

    /* ---- boot framebuffer (jxxx.dtsi:48-54, j293.dts:52-55, m1n1 dt_set_fb). Neither board has a notch ---- */
    if (cfg->fb_base) {
        const char *format = (cfg->fb_depth & 0xff) == 32   ? "x8r8g8b8"
                             : (cfg->fb_depth & 0xff) == 30 ? "x2r10g10b10"
                             : (cfg->fb_depth & 0xff) == 16 ? "r5g6b5"
                                                            : NULL;

        if (!format) {
            diag(t, DISPDT_D_FB_DEPTH, NULL, cfg->fb_depth, 0);
        } else {
            node_set(t, DISPDT_NODE_CHOSEN, "chosen", -1, 0);
            t->nodes[DISPDT_NODE_CHOSEN].existing = true;
            hex_name(name, sizeof(name), "framebuffer", cfg->fb_base);
            node_set(t, DISPDT_NODE_FRAMEBUFFER0, name, DISPDT_NODE_CHOSEN, 0);
            p = add(&b, DISPDT_NODE_FRAMEBUFFER0, "compatible", GPUDT_T_STRINGS, GPUDT_O_STATIC, GPUDT_F_INFO);
            put_str(&b, p, "apple,simple-framebuffer");
            put_str(&b, p, "simple-framebuffer");
            prop_reg1(&b, DISPDT_NODE_FRAMEBUFFER0, GPUDT_O_ADT, cfg->fb_base, (uint64_t)cfg->fb_stride * cfg->fb_height);
            prop_u32(&b, DISPDT_NODE_FRAMEBUFFER0, "width", GPUDT_O_ADT, GPUDT_F_INFO, cfg->fb_width);
            prop_u32(&b, DISPDT_NODE_FRAMEBUFFER0, "height", GPUDT_O_ADT, GPUDT_F_INFO, cfg->fb_height);
            prop_u32(&b, DISPDT_NODE_FRAMEBUFFER0, "stride", GPUDT_O_ADT, GPUDT_F_INFO, cfg->fb_stride);
            prop_str(&b, DISPDT_NODE_FRAMEBUFFER0, "format", GPUDT_O_ADT, GPUDT_F_INFO, format);
            prop_u32(&b, DISPDT_NODE_FRAMEBUFFER0, "panel", GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_INFO, ph + PH_PANEL);
            /* j293.dts:54 */
            prop_u32(&b, DISPDT_NODE_FRAMEBUFFER0, "post-init-providers", GPUDT_O_SYNTH, GPUDT_F_PHANDLE | GPUDT_F_INFO,
                     ph + PH_PANEL);
        }
    } else {
        diag(t, DISPDT_D_NO_FRAMEBUFFER, NULL, 0, 0);
    }

    return b.full ? DISPDT_ERR_OVERFLOW : DISPDT_OK;
}

const struct dispdt_prop *dispdt_find(const struct dispdt_tree *t, enum dispdt_node_id node, const char *name)
{
    for (uint32_t i = 0; i < t->nprops; i++)
        if (t->props[i].node == node && !strcmp(t->props[i].name, name))
            return &t->props[i];
    return NULL;
}

uint32_t dispdt_prop_to_iodt(const struct dispdt_prop *p, uint8_t *out)
{
    switch (p->type) {
        case GPUDT_T_CELLS:
            for (uint32_t i = 0; i + 4 <= p->len; i += 4)
                wr32le(out + i, rd32be(p->value + i));
            break;
        case GPUDT_T_REG:
            /* each 2-cell field is one native u64: low word first */
            for (uint32_t i = 0; i + 8 <= p->len; i += 8) {
                wr32le(out + i, rd32be(p->value + i + 4));
                wr32le(out + i + 4, rd32be(p->value + i));
            }
            break;
        default:
            if (p->len)
                memcpy(out, p->value, p->len);
            break;
    }
    return p->len;
}
