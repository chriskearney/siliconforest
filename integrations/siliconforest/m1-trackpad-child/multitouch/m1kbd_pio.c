/* Original bounded PIO adapter, based on register semantics documented in
 * pinned Linux sources listed in ADAPTER.md. No Linux implementation copied. */
#include "m1kbd_hw.h"
#include "m1kbd_boards.h"
#include <string.h>

enum { CTRL=0, CFG=4, PIN=12, TXDATA=16, RXDATA=32, CLKDIV=48,
       RXCNT=52, WORD_DELAY=56, TXCNT=76, FIFOSTAT=0x10c,
       IE_XFER=0x130, IF_XFER=0x134, IE_FIFO=0x138, IF_FIFO=0x13c,
       SHIFTCFG=0x150, PINCFG=0x154, DELAY_PRE=0x160,
       DELAY_POST=0x168, DELAY_POST_CYCLES=0x194 };
enum { RUN=1, FIFO_RESET=12, CS_HIGH=2, RX_COMPLETE=1, TX_COMPLETE=2,
       FIFO_ERROR=(1u<<16)|(1u<<17), GPIO_LOCK=1u<<21,
       GPIO_PERIPH=3u<<5, GPIO_INPUT=1u<<9, GPIO_MODE=7u<<1 };
#define PS_RESET (1u<<31)
#define PS_AUTO (1u<<28)
#define PS_BUSY (1u<<11)
#define PS_DISABLE (1u<<10)
#define PS_SOFT_RESET (1u<<12)
#define PS_FLAGS (3u<<8)

static int rd(struct m1kbd_hw *h, unsigned r, uint32_t off, uint32_t *v)
{
    if (r>=M1KBD_REGIONS || (off&3) || off>h->board.size[r]-4) return M1KBD_INVALID;
    return h->io.read32(h->io.context,r,off,v) ? M1KBD_IO : M1KBD_OK;
}
static int wr(struct m1kbd_hw *h, unsigned r, uint32_t off, uint32_t v)
{
    if (r>=M1KBD_REGIONS || (off&3) || off>h->board.size[r]-4) return M1KBD_INVALID;
    return h->io.write32(h->io.context,r,off,v) ? M1KBD_IO : M1KBD_OK;
}
static int mask(struct m1kbd_hw *h, unsigned r, uint32_t off, uint32_t bits, uint32_t val)
{ uint32_t old; int e=rd(h,r,off,&old); return e ? e : wr(h,r,off,(old&~bits)|val); }
static uint64_t now(struct m1kbd_hw *h) { return h->io.now_us(h->io.context); }
static void delay(struct m1kbd_hw *h, uint32_t us) { h->io.delay_us(h->io.context,us); }
static int elapsed(struct m1kbd_hw *h, uint64_t start, uint32_t limit)
{ uint64_t t=now(h); return t<start || t-start>=limit; }
#define TRY(x) do { int err_=(x); if (err_) return err_; } while(0)

int m1kbd_hw_init(struct m1kbd_hw *h, const struct m1kbd_board *b, const struct m1kbd_io *io)
{
    const uint64_t bases[]={0x23510c000ull,0x23c100000ull,0x23d1f0000ull,0x23b700000ull,0x23d280000ull};
    const uint32_t sizes[]={0x4000,0x100000,0x4000,0x4000,0x4000};
    if (!h || !b || !io || !io->read32 || !io->write32 || !io->now_us || !io->delay_us)
        return M1KBD_INVALID;
    /* Init accepts only a fresh zeroed object; never erase a live owner. */
    if (h->initialized) return M1KBD_STATE;
    if (!m1kbd_board_product(b->qualified) || memcmp(b->base,bases,sizeof(bases)) ||
        memcmp(b->size,sizes,sizeof(sizes)) || b->clock_hz!=120000000 || b->speed_hz!=8000000)
        return M1KBD_BOARD;
    memset(h,0,sizeof(*h)); h->io=*io; h->board=*b; h->initialized=1;
    return M1KBD_OK;
}

static int power_sample(struct m1kbd_hw *h, unsigned region, uint32_t offset, uint32_t *v)
{
    uint64_t start=now(h);
    for (unsigned i=0;i<101;i++) {
        TRY(rd(h,region,offset,v));
        if (*v&(PS_RESET|PS_DISABLE|PS_SOFT_RESET)) return M1KBD_POWER;
        if (!(*v&PS_BUSY)) return M1KBD_OK;
        if (elapsed(h,start,100)) return M1KBD_TIMEOUT;
        delay(h,1);
    }
    return M1KBD_TIMEOUT;
}
static int activate(struct m1kbd_hw *h, uint32_t offset)
{
    /* The initial graph preflight is diagnostic, never an RMW source. */
    uint32_t v; TRY(power_sample(h,M1KBD_PMGR,offset,&v));
    /* Do not release a reset or disabled domain owned by another agent. */
    if (v&(PS_RESET|PS_BUSY|PS_DISABLE|PS_SOFT_RESET)) return M1KBD_POWER;
    /* Keep an already active domain exactly as found, including AUTO. */
    if ((v&0xff)==0xff) return M1KBD_OK;
    v=(v&~(PS_AUTO|PS_FLAGS|PS_BUSY|15u))|15u;
    TRY(wr(h,M1KBD_PMGR,offset,v));
    uint64_t start=now(h);
    for (unsigned i=0;i<101;i++) {
        TRY(rd(h,M1KBD_PMGR,offset,&v));
        if (v&(PS_RESET|PS_DISABLE|PS_SOFT_RESET)) return M1KBD_POWER;
        if ((v&0xf0)==0xf0 && !(v&PS_BUSY)) return M1KBD_OK;
        if (elapsed(h,start,100)) return M1KBD_TIMEOUT;
        delay(h,1);
    }
    return M1KBD_TIMEOUT;
}
static int power(struct m1kbd_hw *h)
{
    /* Observed DT semantics: SIO parents are HV-owned; NUB_GPIO always-on.
     * Verify these instead of writing their state. SPI_P/GPIO have ordinary
     * Linux domains, no firmware-owned/always-on property: hold active only.
     * No parent is reset, rolled back or powered down, including on failure. */
    const uint32_t offsets[]={0x1c0,0x1c8,0x218,0x258,0x130,0x80};
    for (unsigned i=0;i<6;i++) {
        uint32_t v; TRY(power_sample(h,i==5?M1KBD_NUB_PMGR:M1KBD_PMGR,offsets[i],&v));
        h->power_before[i]=v;
        if (v&(PS_RESET|PS_BUSY|PS_DISABLE|PS_SOFT_RESET)) return M1KBD_POWER;
        if ((i<2 || i==5) && (v&0xff)!=0xff) return M1KBD_POWER;
    }
    TRY(activate(h,0x218));
    TRY(activate(h,0x130));
    return activate(h,0x258);
}
static int pins(struct m1kbd_hw *h)
{
    /* Preflight every pin before changing any GPIO. Enable must be able to
     * toggle both levels, so any lock on it is a refusal. */
    const unsigned pin[]={46,47,48,49,195,13};
    for (unsigned i=0;i<6;i++) {
        TRY(rd(h,i==5?M1KBD_NUB_GPIO:M1KBD_GPIO,pin[i]*4,&h->gpio_before[i]));
        if (h->gpio_before[i]&GPIO_LOCK) return M1KBD_LOCKED;
    }
    for (unsigned pin=46;pin<=49;pin++)
        TRY(mask(h,M1KBD_GPIO,pin*4,GPIO_PERIPH|GPIO_INPUT,(1u<<5)|GPIO_INPUT));
    TRY(mask(h,M1KBD_NUB_GPIO,13*4,GPIO_PERIPH|GPIO_MODE|1u|GPIO_INPUT,(7u<<1)|GPIO_INPUT));
    /* Configure low until SPI is idle; reset sequence is issued below. */
    TRY(mask(h,M1KBD_GPIO,195*4,GPIO_PERIPH|GPIO_MODE|1u,1u<<1));
    h->gpio_access=1;
    return M1KBD_OK;
}
static int controller(struct m1kbd_hw *h)
{
    h->spi_access=1;
    TRY(wr(h,M1KBD_SPI,CTRL,0));
    TRY(wr(h,M1KBD_SPI,IE_FIFO,0)); TRY(wr(h,M1KBD_SPI,IE_XFER,0));
    TRY(wr(h,M1KBD_SPI,PIN,CS_HIGH));
    TRY(mask(h,M1KBD_SPI,SHIFTCFG,1u<<24,0));
    TRY(mask(h,M1KBD_SPI,PINCFG,1u<<9,1u<<1));
    TRY(wr(h,M1KBD_SPI,CTRL,FIFO_RESET));
    /* Hardware IRQ mode with interrupt enables zero: Linux's polled path.
     * 8-bit words, 8-byte thresholds, mode 0 and MSB first. */
    TRY(wr(h,M1KBD_SPI,CFG,1u<<5));
    TRY(wr(h,M1KBD_SPI,DELAY_PRE,0)); TRY(wr(h,M1KBD_SPI,DELAY_POST,0));
    TRY(wr(h,M1KBD_SPI,DELAY_POST_CYCLES,0));
    TRY(wr(h,M1KBD_SPI,CLKDIV,15));
    TRY(mask(h,M1KBD_SPI,SHIFTCFG,0x3fu<<16,8u<<16));
    /* Linux does not initialize WORD_DELAY. Require its inherited value to
     * be zero instead of silently assuming different transfer timing. */
    uint32_t v; TRY(rd(h,M1KBD_SPI,WORD_DELAY,&v));
    if (v!=0) return M1KBD_STATE;
    TRY(wr(h,M1KBD_SPI,CTRL,0));
    return M1KBD_OK;
}

static int cleanup(struct m1kbd_hw *h, int disable)
{
    int bad=0;
    if (h->spi_access) {
        bad |= wr(h,M1KBD_SPI,CTRL,0)!=0;
        bad |= wr(h,M1KBD_SPI,IE_FIFO,0)!=0;
        bad |= wr(h,M1KBD_SPI,IE_XFER,0)!=0;
        delay(h,65);
        bad |= mask(h,M1KBD_SPI,PIN,CS_HIGH,CS_HIGH)!=0;
        delay(h,250);
    }
    if (disable && h->gpio_access) bad |= mask(h,M1KBD_GPIO,195*4,1,0)!=0;
    h->cleanup_failed |= (unsigned)bad;
    return bad ? M1KBD_IO : M1KBD_OK;
}
int m1kbd_hw_start(struct m1kbd_hw *h)
{
    if (!h || !h->initialized || h->ready || h->busy || h->faulted) return M1KBD_STATE;
    h->busy=1;
    int e=power(h);
    if (!e) e=pins(h);
    if (!e) e=controller(h);
    if (!e) e=mask(h,M1KBD_GPIO,195*4,1,1);
    if (!e) { delay(h,5000); e=mask(h,M1KBD_GPIO,195*4,1,0); }
    if (!e) { delay(h,5000); e=mask(h,M1KBD_GPIO,195*4,1,1); }
    if (!e) { delay(h,50000); h->ready=1; }
    else { h->faulted=1; (void)cleanup(h,1); }
    h->busy=0;
    return e;
}
int m1kbd_hw_ready(struct m1kbd_hw *h, int *asserted)
{
    if (!h || !asserted) return M1KBD_INVALID;
    *asserted=0;
    if (!h->ready || h->busy || h->faulted) return M1KBD_STATE;
    uint32_t v; int e=rd(h,M1KBD_NUB_GPIO,13*4,&v);
    if (e) { h->faulted=1; h->ready=0; (void)cleanup(h,1); return e; }
    *asserted=!(v&1);
    return M1KBD_OK;
}

/* One shared deadline covers both halves of a write and all final FIFO drains.
 * A secondary iteration cap also prevents a broken time callback spinning forever. */
static int transfer(struct m1kbd_hw *h, const uint8_t *tx, uint8_t *rx, unsigned n, uint64_t start)
{
    if ((!tx && !rx) || (tx && rx) || !n || n>M1KBD_PACKET_SIZE) return M1KBD_INVALID;
    TRY(wr(h,M1KBD_SPI,CTRL,FIFO_RESET));
    TRY(wr(h,M1KBD_SPI,IF_XFER,UINT32_MAX)); TRY(wr(h,M1KBD_SPI,IF_FIFO,UINT32_MAX));
    TRY(wr(h,M1KBD_SPI,TXCNT,tx?n:0)); TRY(wr(h,M1KBD_SPI,RXCNT,rx?n:0));
    unsigned sent=0,received=0; uint32_t fs;
    TRY(rd(h,M1KBD_SPI,FIFOSTAT,&fs));
    if (((fs>>8)&255)>16 || (fs>>24)!=0) return M1KBD_FIFO;
    if (tx) {
        unsigned free=16-((fs>>8)&255);
        while (free-- && sent<n) { TRY(wr(h,M1KBD_SPI,TXDATA,tx[sent])); sent++; }
    }
    TRY(wr(h,M1KBD_SPI,CTRL,RUN));
    for (unsigned poll=0;poll<=M1KBD_TRANSACTION_US;poll++) {
        uint32_t flags,done;
        if (elapsed(h,start,M1KBD_TRANSACTION_US)) return M1KBD_TIMEOUT;
        TRY(rd(h,M1KBD_SPI,IF_FIFO,&flags));
        if (flags&FIFO_ERROR) return M1KBD_FIFO;
        TRY(rd(h,M1KBD_SPI,IF_XFER,&done)); TRY(rd(h,M1KBD_SPI,FIFOSTAT,&fs));
        unsigned tl=(fs>>8)&255,rl=fs>>24;
        if (tl>16 || rl>16 || rl>n-received) return M1KBD_FIFO;
        /* Linux ignores RX in TX-only mode. Whether this hardware latches
         * MISO with RXCNT=0 is not qualified: distinguish this refusal from
         * overflow instead of silently discarding unknown receive bytes. */
        if (!rx && rl) return M1KBD_RX_UNEXPECTED;
        if (tx) {
            /* Completion before all bytes have been submitted is invalid. */
            if ((done&TX_COMPLETE) && sent!=n) return M1KBD_FIFO;
            unsigned free=16-tl;
            while (free-- && sent<n) { TRY(wr(h,M1KBD_SPI,TXDATA,tx[sent])); sent++; }
            if (done&TX_COMPLETE) {
                if (tl) return M1KBD_FIFO;
                TRY(wr(h,M1KBD_SPI,CTRL,0)); return M1KBD_OK;
            }
        } else {
            while (rl--) { uint32_t v; TRY(rd(h,M1KBD_SPI,RXDATA,&v)); rx[received++]=(uint8_t)v; }
            if ((done&RX_COMPLETE) && received==n) {
                TRY(wr(h,M1KBD_SPI,CTRL,0)); return M1KBD_OK;
            }
            /* Completion may precede the last RX FIFO word. Continue bounded
             * drain; missing bytes never become a successful transfer. */
        }
        delay(h,1);
    }
    return M1KBD_TIMEOUT;
}
static int transaction(struct m1kbd_hw *h, const uint8_t *tx, uint8_t *rx)
{
    static const uint8_t expected_status[]={0xac,0x27,0x68,0xd5};
    uint8_t status[4];
    if (!h || (!tx && !rx)) return M1KBD_INVALID;
    if (!h->ready || h->busy || h->faulted) return M1KBD_STATE;
    h->busy=1; uint64_t start=now(h);
    int e=mask(h,M1KBD_SPI,PIN,CS_HIGH,0);
    if (!e) { delay(h,65); e=transfer(h,tx,rx,M1KBD_PACKET_SIZE,start); }
    if (!e && tx) {
        delay(h,200); e=transfer(h,0,status,4,start);
        if (!e && memcmp(status,expected_status,sizeof(status))) e=M1KBD_STATUS;
    }
    int ce=cleanup(h,e!=0);
    if (ce && !e) (void)cleanup(h,1);
    if (!e) e=ce;
    if (e) { h->faulted=1; h->ready=0; }
    h->busy=0;
    return e;
}
int m1kbd_hw_read_packet(struct m1kbd_hw *h, uint8_t p[M1KBD_PACKET_SIZE])
{
    if (!p) return M1KBD_INVALID;
    int asserted=0, e=m1kbd_hw_ready(h,&asserted);
    if (e) return e;
    if (!asserted) return M1KBD_NOT_READY;
    return transaction(h,0,p);
}
int m1kbd_hw_write_packet(struct m1kbd_hw *h, const uint8_t p[M1KBD_PACKET_SIZE])
{ if (!p) return M1KBD_INVALID; return transaction(h,p,0); }
int m1kbd_hw_stop(struct m1kbd_hw *h)
{
    if (!h || !h->initialized || h->busy) return M1KBD_STATE;
    h->busy=1; h->ready=0;
    int e=cleanup(h,1); h->busy=0; h->faulted=1;
    return e;
}
