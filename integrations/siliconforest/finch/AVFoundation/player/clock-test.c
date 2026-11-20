/* SPDX-License-Identifier: MIT */
#include "SFPlaybackClock.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    /* The measured M1 counter advances 1024/48000 s per block. At 30 Hz,
       flooring it near a picture boundary loses pictures despite 30 ticks/s. */
    unsigned aliased = 0;
    for (unsigned phase = 0; phase < 128; phase++) {
        SFPlaybackClock c = {0};
        double offset = phase / 128.0 * (1024.0 / 48000.0);
        double previous = -1;
        unsigned changes = 0, raw_changes = 0;
        long last = -1, raw_last = -1;
        for (unsigned tick = 0; tick < 9000; tick++) {
            double host = tick / 30.0;
            double raw = floor((host + offset) * 48000.0 / 1024) * 1024 / 48000.0;
            double value = sfPlaybackClockSample(&c, raw, host, true);
            assert(value >= previous);
            assert(fabs(value - raw) <= SF_PLAYBACK_CLOCK_BOUND + 1e-9);
            /* AVPlayer represents the clock as CMTime at timescale 600. */
            long index = (long)floor(round(value * 600) / 20.0 + 1e-9);
            long raw_index = (long)floor(round(raw * 600) / 20.0 + 1e-9);
            if (last >= 0) { changes += index != last; raw_changes += raw_index != raw_last; }
            last = index; raw_last = raw_index; previous = value;
        }
        assert(changes == 8999);
        if (raw_changes < 8900) aliased++;
    }
    assert(aliased > 0);
    /* A device clock with a different rate must remain the authority over a
       long run. Occasional delayed observations must not accumulate drift. */
    for (int sign = -1; sign <= 1; sign += 2) {
        SFPlaybackClock drift = {0};
        double previous = -1;
        for (unsigned tick = 0; tick < 72000; tick++) {
            double host = tick / 120.0;
            double raw = floor(host * (1 + sign * .0003) * 48000 / 1024) * 1024 / 48000.0;
            double value = sfPlaybackClockSample(&drift, raw, host, true);
            assert(value >= previous);
            assert(fabs(value - raw) <= SF_PLAYBACK_CLOCK_BOUND + 1e-9);
            previous = value;
        }
    }
    SFPlaybackClock c = {0};
    assert(sfPlaybackClockSample(&c, 10, 1, true) == 10);
    assert(sfPlaybackClockSample(&c, 10, 1.02, true) > 10);
    double frozen = sfPlaybackClockSample(&c, 10, 1.1, true);
    assert(sfPlaybackClockSample(&c, 10, 100, true) == frozen);
    assert(sfPlaybackClockSample(&c, 10, 101, false) == 10);
    assert(!c.valid);
    assert(sfPlaybackClockSample(&c, 10, 102, true) == 10);
    assert(sfPlaybackClockSample(&c, 2, 103, true) == 2); /* seek backwards */
    assert(sfPlaybackClockSample(&c, 42, 104, true) == 42); /* seek forwards */
    assert(sfPlaybackClockSample(&c, 43, 1, true) == 43); /* new host epoch */
    assert(isnan(sfPlaybackClockSample(&c, NAN, 2, true)) && !c.valid);
    puts("playback clock: 128 counter phases over 300 s, alias reproduction, +/-300ppm drift over 600 s, bound, stall, pause/resume, seeks PASS");
}
