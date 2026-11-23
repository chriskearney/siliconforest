/* SPDX-License-Identifier: MIT */
/* Host test of the board check SFAppleSound and SFAppleTouchBar make before touching hardware. */
#include <assert.h>
#include <stdio.h>

#include "../kernel/sf_board_gate.h"

#define IS(s, n) sf_board_compatible_is((s), (n), "J293AP")

int main(void)
{
    static const char j293[] = "J293AP\0MacBookPro17,1\0AppleARM", j313[] = "J313AP\0MacBookAir10,1\0AppleARM";

    assert(IS(j293, sizeof(j293)));
    assert(IS("J293AP", 7));
    assert(!IS(j313, sizeof(j313)));
    assert(!IS("J293APX", 8));
    assert(!IS("J293", 5));
    assert(!IS("J293AP", 6)); /* not terminated inside the property */
    assert(!IS("", 1));
    assert(!IS(j293, 0));
    assert(!IS(NULL, 7));
    assert(!sf_board_compatible_is(j293, sizeof(j293), NULL));
    puts("board gate checks passed");
    return 0;
}
