/* Host-only tests of the J313 acquisition policy (from test_window.c of the J293 window). */
#include "m1_boot_window.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const uint8_t nop[64] = {
    0xff, 0x55, 0xaa, 0x00,
    [60] = 0x68, 0x39, 0x97, 0x4b,
};

static enum m1_window_result feed(struct m1_boot_window *w, int port, const uint8_t *b,
                                  size_t n, uint64_t now)
{
    enum m1_window_result r = M1_WINDOW_WAIT;
    for (size_t i = 0; i < n; i++)
        r = m1_boot_window_feed(w, now, port, b[i]);
    return r;
}

int main(void)
{
    struct m1_boot_window w;
    assert(m1_boot_window_allowed(0x8103, "J313", 5, false));
    assert(m1_boot_window_allowed(0x8103, "j313", 5, false));
    assert(!m1_boot_window_allowed(0x8103, "J313", 5, true));
    assert(!m1_boot_window_allowed(0x8101, "J313", 5, false));
    assert(!m1_boot_window_allowed(0x8103, "J293", 5, false));
    assert(!m1_boot_window_allowed(0x8103, "j293", 5, false));
    assert(!m1_boot_window_allowed(0x8103, "J274", 5, false));
    assert(!m1_boot_window_allowed(0x8103, "J456", 5, false));
    assert(!m1_boot_window_allowed(0x8103, NULL, 5, false));
    assert(!m1_boot_window_allowed(0x8103, "J313X", 6, false));
    assert(!m1_boot_window_allowed(0x8103, "J313X", 5, false));
    assert(!m1_boot_window_allowed(0x8103, "J313", 4, false));

    m1_boot_window_init(&w, 10);
    assert(m1_boot_window_feed(&w, 9, -1, 0) == M1_WINDOW_WAIT);
    assert(m1_boot_window_feed(&w, 10, -1, 0) == M1_WINDOW_TIMEOUT);
    assert(feed(&w, 0, nop, 64, 10) == M1_WINDOW_TIMEOUT);

    /* Every incomplete prefix expires, including a complete magic/type header. */
    for (size_t n = 0; n < 64; n++) {
        m1_boot_window_init(&w, 10);
        assert(feed(&w, 0, nop, n, 9) == M1_WINDOW_WAIT);
        assert(m1_boot_window_feed(&w, 10, -1, 0) == M1_WINDOW_TIMEOUT);
    }
    m1_boot_window_init(&w, 10);
    assert(feed(&w, 0, nop, 63, 9) == M1_WINDOW_WAIT);
    assert(m1_boot_window_feed(&w, 10, 0, nop[63]) == M1_WINDOW_TIMEOUT);
    m1_boot_window_init(&w, 0);
    assert(feed(&w, 0, nop, 64, 0) == M1_WINDOW_TIMEOUT);
    m1_boot_window_init(&w, 10);
    assert(m1_boot_window_feed(&w, UINT64_MAX, 0, 0xff) == M1_WINDOW_TIMEOUT);

    for (int port = 0; port < 2; port++) {
        m1_boot_window_init(&w, 10);
        assert(feed(&w, port, nop, 64, 9) == M1_WINDOW_CLAIMED);
        assert(w.selected == (unsigned int)port);
        assert(memcmp(w.frame[port], nop, 64) == 0);
        assert(m1_boot_window_feed(&w, 11, 1 - port, 0) == M1_WINDOW_CLAIMED);
        assert(w.selected == (unsigned int)port);
    }
    /* No assembling one request out of two ports or out-of-range transports. */
    m1_boot_window_init(&w, 10);
    assert(feed(&w, 0, nop, 32, 1) == M1_WINDOW_WAIT);
    assert(feed(&w, 1, nop + 32, 32, 2) == M1_WINDOW_WAIT);
    assert(feed(&w, 2, nop, 64, 3) == M1_WINDOW_WAIT);
    assert(feed(&w, -1, nop, 64, 3) == M1_WINDOW_WAIT);
    assert(feed(&w, 1, nop, 64, 4) == M1_WINDOW_CLAIMED);

    /* Each single-byte corruption fails; a later valid frame resynchronizes. */
    for (size_t i = 0; i < 64; i++) {
        uint8_t bad[64];
        memcpy(bad, nop, 64);
        bad[i] ^= 1;
        m1_boot_window_init(&w, 10);
        assert(feed(&w, 0, bad, 64, 1) == M1_WINDOW_WAIT);
        assert(feed(&w, 0, nop, 64, 2) == M1_WINDOW_CLAIMED);
    }
    /* Well-checksummed non-NOP is refused (checksum computed independently below). */
    uint8_t other[64];
    memcpy(other, nop, 64);
    other[3] = 1;
    uint32_t sum = 0xdeadbeef;
    for (size_t i = 0; i < 60; i++)
        sum = sum * 31337u + (other[i] ^ 0x5au);
    sum ^= 0xaddedbad;
    for (size_t i = 0; i < 4; i++)
        other[60 + i] = (uint8_t)(sum >> (8 * i));
    m1_boot_window_init(&w, 10);
    assert(feed(&w, 0, other, 64, 1) == M1_WINDOW_WAIT);

    /* Negotiation payload retained without rewriting reserved or feature bytes. */
    uint8_t features[64];
    memcpy(features, nop, 64);
    memset(features + 4, 0xff, 8);
    const uint8_t checksum[] = {0x90, 0x8f, 0x73, 0xf0};
    memcpy(features + 60, checksum, 4);
    m1_boot_window_init(&w, 10);
    assert(feed(&w, 0, features, 64, 9) == M1_WINDOW_CLAIMED);
    assert(memcmp(w.frame[0], features, 64) == 0);

    /* Continuous garbage cannot restart the clock. */
    m1_boot_window_init(&w, 10);
    for (unsigned int t = 0; t < 10; t++)
        for (unsigned int i = 0; i < 512; i++)
            assert(m1_boot_window_feed(&w, t, i % 2, 0xff) == M1_WINDOW_WAIT);
    assert(m1_boot_window_feed(&w, 10, 0, 0xff) == M1_WINDOW_TIMEOUT);
    puts("PASS: host-only target refusal, full-frame/checksum, per-port isolation, fixed deadline");
}
