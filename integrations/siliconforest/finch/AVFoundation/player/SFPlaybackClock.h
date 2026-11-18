/* SPDX-License-Identifier: MIT */
/* A continuous media clock disciplined by the output queue's block counter.
 * The queue position is a staircase, not a per-sample presentation timestamp.
 * Sampling that staircase at the movie rate aliases into repeated/skipped
 * pictures. Keep host-time progression while it agrees with the audio counter;
 * re-anchor on a seek/discontinuity and never advance through stalled audio. */
#ifndef SF_PLAYBACK_CLOCK_H
#define SF_PLAYBACK_CLOCK_H
#include <stdbool.h>
#include <math.h>

#define SF_PLAYBACK_CLOCK_BOUND .040
typedef struct {
    bool valid;
    double anchor, host, raw, changed, last_host, output;
    unsigned resyncs;
} SFPlaybackClock;

static inline void sfPlaybackClockReset(SFPlaybackClock *clock) {
    clock->valid = false;
}

static inline double sfPlaybackClockSample(SFPlaybackClock *clock,
                                           double raw, double host, bool running) {
    if (!running || !isfinite(raw) || !isfinite(host)) {
        sfPlaybackClockReset(clock);
        return raw;
    }
    if (!clock->valid || host < clock->last_host || raw < clock->raw) {
        if (clock->valid) clock->resyncs++;
        clock->valid = true;
        clock->anchor = clock->output = clock->raw = raw;
        clock->host = clock->changed = clock->last_host = host;
        return raw;
    }
    if (raw != clock->raw) clock->changed = host;
    double value = clock->anchor + host - clock->host;
    if (raw - value > SF_PLAYBACK_CLOCK_BOUND) {
        value = raw;
        clock->resyncs++;
    } else if (value - raw > SF_PLAYBACK_CLOCK_BOUND ||
               host - clock->changed > SF_PLAYBACK_CLOCK_BOUND) {
        /* Freeze without a backwards jump while audio is stalled/behind. */
        value = fmax(clock->output, raw);
    }
    if (fabs(value - (clock->anchor + host - clock->host)) > 1e-12) {
        clock->anchor = value;
        clock->host = host;
    }
    clock->raw = raw;
    clock->last_host = host;
    clock->output = value;
    return value;
}
#endif
