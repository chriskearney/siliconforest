/* Original Darwin-lab board guard. See ADAPTER.md for captured-byte sources. */
#include "m1kbd_hw.h"
#include "m1kbd_boards.h"
#include <string.h>

static uint32_t le32(const uint8_t *p)
{ return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24; }
static uint64_t le64(const uint8_t *p)
{ return (uint64_t)le32(p) | (uint64_t)le32(p+4)<<32; }
static unsigned le16(const uint8_t *p) { return p[0] | (unsigned)p[1]<<8; }
struct view { m1kbd_property_fn get; void *ctx; };
static int prop(struct view *v, const char *path, const char *key,
                const uint8_t **p, size_t *n)
{ *p = 0; *n = 0; return v->get(v->ctx,path,key,p,n) == 0 && *p != 0; }
static int bytes(struct view *v, const char *path, const char *key, const char *s, size_t len)
{ const uint8_t *p; size_t n; return prop(v,path,key,&p,&n) && n==len && !memcmp(p,s,n); }
static int words(struct view *v, const char *path, const char *key,
                 const uint32_t *expected, size_t count)
{
    const uint8_t *p; size_t n;
    if (!prop(v,path,key,&p,&n) || n != count*4) return 0;
    for (size_t i=0;i<count;i++) if (le32(p+4*i)!=expected[i]) return 0;
    return 1;
}
static int u32(struct view *v, const char *path, const char *key, uint32_t *out)
{ const uint8_t *p; size_t n; if (!prop(v,path,key,&p,&n)||n!=4)return 0; *out=le32(p); return 1; }
static int reg(struct view *v, const char *path, uint64_t address, uint64_t size)
{ const uint8_t *p; size_t n; return prop(v,path,"reg",&p,&n) && n==16 && le64(p)==address && le64(p+8)==size; }

/* These six IDs/parents and offsets independently agree in the captured
 * ADT devices/ps-regs table and original J293 Linux DT power-domain graph.
 * Do not treat undocumented ADT flags as Linux firmware-ownership flags. */
static const struct domain {
    uint16_t id, parent0, parent1;
    const char *name;
    uint64_t address;
} domains[M1KBD_POWER_DOMAINS] = {
    {33,0,0,"SIO_BUSIF",0x23b7001c0ull},
    {34,33,0,"SIO",0x23b7001c8ull},
    {44,34,0,"SPI_P",0x23b700218ull},
    {52,34,44,"SPI3",0x23b700258ull},
    {15,0,0,"GPIO",0x23b700130ull},
    {147,0,0,"NUB_GPIO",0x23d280080ull}
};
static int power_table(struct view *v)
{
    const uint8_t *d,*ps,*r; size_t dn,pn,rn;
    if (!prop(v,"/arm-io/pmgr","devices",&d,&dn) || !dn || dn%48 || dn/48>512 ||
        !prop(v,"/arm-io/pmgr","ps-regs",&ps,&pn) || !pn || pn%12 ||
        !prop(v,"/arm-io/pmgr","reg",&r,&rn) || !rn || rn%16) return 0;
    for (unsigned k=0;k<M1KBD_POWER_DOMAINS;k++) {
        const uint8_t *entry=0;
        for (size_t off=0;off<dn;off+=48) if (le16(d+off+26)==domains[k].id) {
            if (entry) return 0;
            entry=d+off;
        }
        if (!entry || (entry[0]&0x10) || le16(entry+4)!=domains[k].parent0 ||
            le16(entry+6)!=domains[k].parent1) return 0;
        size_t len=strlen(domains[k].name);
        if (memcmp(entry+32,domains[k].name,len+1)) return 0;
        size_t idx=entry[11];
        if (idx>=pn/12) return 0;
        unsigned ri=le32(ps+idx*12); uint64_t po=le32(ps+idx*12+4)+(uint64_t)entry[10]*8;
        if (ri>=rn/16) return 0;
        uint64_t base=le64(r+ri*16), size=le64(r+ri*16+8);
        if (base>=0x100000000ull || size>0x100000000ull-base || size<4 || po>size-4 ||
            base+po+0x200000000ull!=domains[k].address) return 0;
    }
    return 1;
}

/* Both identity strings must name the same board, byte for byte. Every other value checked
 * below is the same on J293 and J313 in Apple's 13.5 device trees (phandles are read). */
#define IDENTITY(target, compat, tag) { target, sizeof(target), compat, sizeof(compat), tag }
static const struct board_identity {
    const char *target; size_t target_size;
    const char *compatible; size_t compatible_size;
    uint32_t qualified;
} identities[] = {
    IDENTITY("J293", "J293AP\0MacBookPro17,1\0AppleARM", M1KBD_QUALIFIED_J293),
    IDENTITY("J313", "J313AP\0MacBookAir10,1\0AppleARM", M1KBD_QUALIFIED_J313),
};
static const struct board_identity *identify(struct view *v)
{
    const uint8_t *t,*c; size_t tn,cn;
    if (!prop(v,"/","target-type",&t,&tn) || !prop(v,"/","compatible",&c,&cn)) return 0;
    for (size_t i=0;i<sizeof(identities)/sizeof(identities[0]);i++) {
        const struct board_identity *id=&identities[i];
        if (tn==id->target_size && !memcmp(t,id->target,tn) &&
            cn==id->compatible_size && !memcmp(c,id->compatible,cn)) return id;
    }
    return 0;
}

int m1kbd_validate_board(m1kbd_property_fn get, void *ctx, struct m1kbd_board *out)
{
    struct view v={get,ctx}; uint32_t gpio,nub,aic; const uint8_t *p; size_t n;
    const uint32_t gate[]={52},clock[]={379},irq[]={617},ready_irq[]={13,0x06000001};
    if (!out) return M1KBD_INVALID;
    memset(out,0,sizeof(*out));
    if (!get) return M1KBD_INVALID;
    const struct board_identity *id=identify(&v);
    if (!id ||
        !bytes(&v,"/arm-io","compatible","arm-io,t8103",13) ||
        !bytes(&v,"/arm-io/spi3","compatible","spi-1,spimc",12) ||
        !bytes(&v,"/arm-io/spi3/ipd","compatible","hid-transport,spi",18) ||
        !bytes(&v,"/arm-io/spi3/ipd","device_type","ipd",4) ||
        !bytes(&v,"/arm-io/gpio","compatible","gpio,t8101",11) ||
        !bytes(&v,"/arm-io/nub-gpio","compatible","gpio,t8101",11) ||
        !bytes(&v,"/arm-io/pmgr","compatible","pmgr1,t8103",12) ||
        !bytes(&v,"/arm-io/aic","compatible","aic,1",6)) return M1KBD_BOARD;
    /* arm-io addresses are relative to the first 4-GiB range. */
    if (!prop(&v,"/arm-io","ranges",&p,&n) || n<24 || n%24 ||
        le64(p)!=0 || le64(p+8)!=0x200000000ull || le64(p+16)!=0x100000000ull ||
        !reg(&v,"/arm-io/spi3",0x3510c000,0x4000) ||
        !reg(&v,"/arm-io/gpio",0x3c100000,0x100000) ||
        !reg(&v,"/arm-io/nub-gpio",0x3d1f0000,0x4000)) return M1KBD_BOARD;
    if (!u32(&v,"/arm-io/gpio","AAPL,phandle",&gpio) || !gpio ||
        !u32(&v,"/arm-io/nub-gpio","AAPL,phandle",&nub) || !nub ||
        !u32(&v,"/arm-io/aic","AAPL,phandle",&aic) || !aic || gpio==nub || gpio==aic || nub==aic)
        return M1KBD_BOARD;
    const uint32_t cs[]={gpio,0x4750494f,49,1},enable_cs[]={gpio,0x4750494f,49,0x101};
    const uint32_t enable[]={gpio,0x4750494f,195,0x10101};
    const uint32_t spireg[]={0,125,0x08010000,0,20000,0,0,0};
    const uint32_t gpins[]={212},npins[]={23};
    if (!words(&v,"/arm-io/spi3","clock-gates",gate,1) ||
        !words(&v,"/arm-io/spi3","clock-ids",clock,1) ||
        !words(&v,"/arm-io/spi3","interrupts",irq,1) ||
        !words(&v,"/arm-io/spi3","interrupt-parent",&aic,1) ||
        !words(&v,"/arm-io/spi3","function-spi_cs0",cs,4) ||
        !words(&v,"/arm-io/spi3/ipd","function-enable_cs",enable_cs,4) ||
        !words(&v,"/arm-io/spi3/ipd","function-spi_en",enable,4) ||
        !words(&v,"/arm-io/spi3/ipd","interrupt-parent",&nub,1) ||
        !words(&v,"/arm-io/spi3/ipd","interrupts",ready_irq,2) ||
        !words(&v,"/arm-io/spi3/ipd","reg",spireg,8) ||
        !words(&v,"/arm-io/gpio","#gpio-pins",gpins,1) ||
        !words(&v,"/arm-io/nub-gpio","#gpio-pins",npins,1) || !power_table(&v)) return M1KBD_BOARD;
    const uint64_t base[]={0x23510c000ull,0x23c100000ull,0x23d1f0000ull,0x23b700000ull,0x23d280000ull};
    const uint32_t size[]={0x4000,0x100000,0x4000,0x4000,0x4000};
    memcpy(out->base,base,sizeof(base)); memcpy(out->size,size,sizeof(size));
    out->clock_hz=120000000; out->speed_hz=8000000; out->qualified=id->qualified;
    return M1KBD_OK;
}
