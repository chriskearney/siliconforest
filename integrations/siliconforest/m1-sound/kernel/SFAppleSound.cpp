// SPDX-License-Identifier: GPL-2.0-only
/*
 * SFAppleSound: headphone-jack playback on the 13" M1 MacBook Pro (J293, T8103) for
 * SiliconForest.
 *
 * The pieces, each in its own file and usable by other drivers:
 *   sf_soc         register mappings by device tree node, PMGR power domains
 *   sf_gpio        Apple GPIO pins
 *   sf_i2c         Apple (PA Semi) I2C controller, polled
 *   sf_dart_fixed  one fixed DMA window behind a T8020 DART stream
 *   sf_mca         NCO clock, MCA cluster and I2S port, ADMAC transmit channel
 *   sf_cs42l83     CS42L83 headphone codec
 * This file owns the order in which they are brought up (that of the Omacom Linux
 * sound/soc/apple/macaudio.c "Headphone Jack" link: I2S, 64 bit clocks per frame, the
 * SoC provides the clocks, front-end cluster 0 routed to the port of cluster 2), the
 * playback ring, a test tone and the user interfaces.
 *
 * Apple device tree nodes used (J293):
 *   /arm-io/i2c2                     I2C controller, clock-gates I2C2
 *   /arm-io/i2c2/audio-codec-output  CS42L83, reg 0x48, reset nub-gpio pin 11,
 *                                    interrupt gpio pin 183 (level low; the GPIO block's
 *                                    group 0 interrupt, its first AIC interrupt)
 *   /arm-io/gpio, /arm-io/nub-gpio   pins; 162/163 are the i2c2 pins (function 1)
 *   /arm-io/nco                      clock synthesiser, one channel per cluster
 *   /arm-io/mca-switch               reg 0: clusters (0x4000 each), reg 1: DMA switch;
 *                                    clock-gates MCA0..MCA5 (parent AUDIO_P)
 *   /arm-io/admac-sio                audio DMA controller, channel 4 * cluster
 *   /arm-io/dart-sio                 its DART; stream 2 (mapper-admac)
 *
 * The speakers (TAS5770L amplifiers on i2c1/i2c3, the I2S ports of clusters 0 and 1,
 * shutdown gpio pin 181) are sf_speakers.cpp, which shares only the DART window and the
 * GPIO block with this file. The built-in microphones are not here: they hang off the
 * AOP coprocessor.
 *
 * Interfaces:
 *   /dev/sfaudio          write-only, one writer: signed 16-bit little-endian stereo
 *                         frames at kern.sf_sound.rate. Playback starts with the first
 *                         frames and stops when the writer has closed and all of it
 *                         has been played.
 *   /dev/sfmic            read-only, one reader: the headset microphone (the codec's one
 *                         converter) as signed 16-bit little-endian stereo frames, both
 *                         channels the same signal, at kern.sf_sound.rate. While it is
 *                         open the headphone stream runs (silence when nothing plays).
 *   kern.sf_sound.*       state, codec and transport registers, counters, and
 *     tone=<seconds>      play the test tone (tone_hz, tone_db below full scale)
 *     volume_db=<0..63>   codec attenuation in dB (63 mutes); default 30
 *     rate=<44100|48000>  sample rate, while nothing plays
 *     preroll_ms=<ms>     silence played while the codec's converter locks (see holding())
 *
 * Boot arguments:
 *   sfsound=0|1|2|3       0: nothing; 1: I2C and codec identification only; 2: also
 *                         DART and transport set up, no playback; 3 (default): all
 *   sfsound_tone=<s>      play the test tone for s seconds once brought up
 *   sfsound_delay=<ms>    wait before touching hardware (default 2000)
 *   sfspeakers=0          leave the speaker amplifiers alone (they stay in hardware shutdown)
 *   sfsound_fe=<0..3>     front-end cluster (default 0, as Linux); sfsound_port=<n>
 *                         the cluster whose I2S pins are driven (default 2, the jack)
 *
 * Locking: one mutex (gLock) covers the playback state and every register sequence of
 * the transport. One kernel thread polls the DMA rings every few milliseconds while
 * playing and reads the status registers that the sysctls report, so a reader never
 * holds the mutex across an I2C transfer. The jack has its own thread and the codec's
 * own lock (plug detection sleeps for up to a second): the codec's interrupt handler
 * only masks the pin and wakes that thread, which also looks at the pin ten times a
 * second, so a lost interrupt delays a jack event but cannot lose it.
 */
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOInterruptController.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOService.h>
#include <kern/clock.h>
#include <kern/thread.h>
#include <libkern/OSAtomic.h>
#include <miscfs/devfs/devfs.h>
#include <pexpert/pexpert.h>
#include <sys/conf.h>
#include <sys/errno.h>
#include <sys/sysctl.h>
#include <sys/systm.h>
#include <sys/uio.h>

#include "sf_cs42l83.h"
#include "sf_dart_fixed.h"
#include "sf_gpio.h"
#include "sf_i2c.h"
#include "sf_mca.h"
#include "sf_soc.h"
#include "sf_speakers.h"

#define LOG(fmt, ...) IOLog("SFSound: " fmt "\n", ##__VA_ARGS__)

#include "sf_board_gate.h"

#define T8103_CHIP_ID       0x8103

#define PIN_I2C2_SDA        162     /* /arm-io/gpio, function 1 */
#define PIN_I2C2_SCL        163
#define PIN_SPEAKER_SDZ     181     /* /arm-io/gpio: low keeps the speaker amplifiers shut down */
#define PIN_CODEC_IRQ       183
#define PIN_CODEC_RESET     11      /* /arm-io/nub-gpio */
#define CODEC_ADDR          0x48
#define ADMAC_STREAM        2       /* /arm-io/dart-sio/mapper-admac */

#define PERIOD_FRAMES       1024
#define FRAME_BYTES         8       /* two 32-bit slots */
#define PERIOD_BYTES        (PERIOD_FRAMES * FRAME_BYTES)
#define RING_PERIODS        8       /* at most 4 queued and 1 in flight; the rest are free to fill */
#define RING_BYTES          (RING_PERIODS * PERIOD_BYTES)
#define MIC_RING_BYTES      RING_BYTES  /* 8 periods of 1024 frames, two 32-bit slots */
#define MIC_FIFO_FRAMES     16384
#define RING_IOVA           0x04000000ULL
#define FIFO_FRAMES         16384   /* what a writer may queue ahead */
#define TRAILING_SILENCE    6       /* silent periods queued behind the last data before stopping */
#define ADMAC_COUNTER_HZ    24000000ULL

#define DEFAULT_RATE        48000
#define DEFAULT_ATTENUATION 30      /* dB below the codec's full scale */
#define DEFAULT_TONE_HZ     1000
#define DEFAULT_TONE_DB     20      /* dB below digital full scale */
#define MIN_TONE_DB         6

enum { kStateOff, kStateFailed, kStateCodecOnly, kStateIdle, kStatePlaying };
static const char *const kStateNames[] = { "off", "failed", "codec-only", "idle", "playing" };

static IOLock     *gLock;
static SFGpio      gGpio, gNub;
static SFI2C       gI2C;
static SFCs42l83   gCodec;
static SFDartFixed gDart;
static SFMca       gMca;
static SFMcaCapture gMic;               /* the front-end cluster's receiver, on the jack's port */

static uint32_t gLevel = 3;                 /* sfsound= */
static uint32_t gDelayMs = 2000;
static uint32_t gFe = 0, gPort = 2;
static uint32_t gSpeakers = 1;              /* sfspeakers= */
static int      gState = kStateOff;
static char     gFailure[96];               /* why the bring-up stopped */

static uint32_t gRate = DEFAULT_RATE;
static uint32_t gAttenuation = DEFAULT_ATTENUATION;
static uint32_t gToneHz = DEFAULT_TONE_HZ;
static uint32_t gToneDb = DEFAULT_TONE_DB;
static uint64_t gToneLeft;                  /* frames of tone still to generate */
static uint32_t gTonePhase;

/* writer -> thread, frames of two int32 */
static int32_t *gFifo;
static uint32_t gFifoHead, gFifoCount;
static bool     gDevOpen;
static int      gFifoEvent;                 /* sleep channel of a writer waiting for room */
static int      gMajor = -1;
static void    *gDevNode;

/* headset microphone: thread -> reader, frames of two int16 */
static uint8_t *gMicRing;
static uint64_t gMicIova;
static int16_t *gMicFifo;
static uint32_t gMicHead, gMicCount, gMicNext, gMicDropped;
static bool     gMicOpen;
static int      gMicEvent;
static uint64_t gMicPeriods, gMicFrames;
static int32_t  gMicPeak[2], gMicMean[2], gMicRms[2];    /* of the last period, in 24-bit units (of 8388608) */
static int32_t  gMicPeakSession[2];
static uint64_t gMicNonZero;                            /* samples that were not 0, since boot */
static int      gMicMajor = -1;
static void    *gMicNode;

/* one playback session */
static uint32_t gNext;                      /* ring period to fill next */
static uint32_t gSilentRun;                 /* silent periods queued in a row */
static uint64_t gSubmitted, gDone;          /* periods */
static uint64_t gFirstCounter, gLastCounter, gDoneAtFirst;
static uint32_t gLate;                      /* times the descriptor ring was found empty */
static uint32_t gRingErrors;
static uint64_t gFramesData, gFramesTone;
static uint64_t gUnmutedAt;                 /* uptime in ns */
static uint32_t gPrerollMs = 1500;          /* longest wait for the converter lock before data is played */
static uint64_t gFramesHeld;                /* silent frames played while waiting for it */
static int32_t  gLockMs = -1;               /* unmute to converter lock; -1 while not locked */
/* totals over all sessions */
static uint32_t gSessions;
static uint64_t gTotalDone;
static uint32_t gLastRateMilliHz;           /* measured over the last finished or running session */
static volatile int gJack = -1;             /* kSFJack...: 0 nothing, 1 headphones, 2 headset; -1 unknown */
static volatile int gJackButtons;           /* kSFJackButton... held now */
static IOService   *gService;
static IOLock      *gJackWait;
static volatile SInt32 gJackPending;        /* set by the interrupt handler */
static volatile UInt32 gJackIrqs;           /* interrupts taken for the codec's pin */
static uint32_t     gJackPolled;            /* services started because the pin was found low */
static bool         gJackIrqOk;             /* the interrupt registered */
static uint32_t gIdleTicks, gPlayTicks;
/* what the sysctls report: read by the thread, so readers never wait for the I2C bus */
static SFCs42l83Status gCodecSeen;
static SFMcaStatus     gMcaSeen;

/* ---- test tone ------------------------------------------------------------------------ */

/* 10^(-n/20) in Q16 for n = 0..5; each further 6 dB is one shift (6.02 dB, close enough) */
static const uint32_t kGainQ16[6] = { 65536, 58409, 52057, 46396, 41350, 36854 };

/* sin(pi * t / 32768) in Q15 for t in [-32768, 32767]: a parabola and one correction step */
static int32_t
sine_q15(int32_t t)
{
	int32_t a = t < 0 ? -t : t;
	int32_t y = (int32_t)(((int64_t)4 * t * (32768 - a)) >> 15);
	int32_t ay = y < 0 ? -y : y;
	int32_t z = (int32_t)(((int64_t)y * ay) >> 15);

	y += (int32_t)(((int64_t)7373 * (z - y)) >> 15);
	return y > 32767 ? 32767 : y < -32767 ? -32767 : y;
}

static int32_t
tone_sample(void)
{
	uint32_t db = gToneDb < MIN_TONE_DB ? MIN_TONE_DB : gToneDb;
	uint32_t gain = db / 6 >= 16 ? 0 : kGainQ16[db % 6] >> (db / 6);
	int32_t s = sine_q15((int32_t)(gTonePhase >> 16) - 32768);

	gTonePhase += (uint32_t)(((uint64_t)gToneHz << 32) / gRate);
	return (int32_t)((int64_t)s * gain);    /* Q15 * Q16: full scale is 2^31 */
}

/* ---- playback ------------------------------------------------------------------------- */

static uint64_t
uptime_ns(void)
{
	uint64_t abs = 0, ns = 0;

	clock_get_uptime(&abs);
	absolutetime_to_nanoseconds(abs, &ns);
	return ns;
}

/*
 * The codec's input converter takes about a second to lock to the frames after a start
 * (measured: 1.05 s at 48 kHz, 1.10 s at 44.1 kHz). Until it has, or kern.sf_sound.preroll_ms
 * have passed, silence is played and the data waits.
 */
static bool
holding(void)
{
	if (gLockMs >= 0 || gPrerollMs == 0)
		return false;
	return gUnmutedAt == 0 || uptime_ns() - gUnmutedAt < (uint64_t)gPrerollMs * 1000000;
}

/* Fills one ring period from the writer's FIFO, else the tone, else silence. */
static void
fill_period(uint32_t index)
{
	int32_t *dst = (int32_t *)(void *)(gDart.buf + index * PERIOD_BYTES);
	bool any = false;
	uint32_t taken = 0;

	if (holding()) {
		bzero(dst, PERIOD_BYTES);
		gFramesHeld += PERIOD_FRAMES;
		gSilentRun = 0;
		return;
	}

	for (unsigned i = 0; i < PERIOD_FRAMES; i++) {
		int32_t l = 0, r = 0;

		if (gFifoCount > 0) {
			l = gFifo[2 * gFifoHead];
			r = gFifo[2 * gFifoHead + 1];
			gFifoHead = (gFifoHead + 1) % FIFO_FRAMES;
			gFifoCount--;
			taken++;
			any = true;
		} else if (gToneLeft > 0) {
			l = r = tone_sample();
			gToneLeft--;
			gFramesTone++;
			any = true;
		}
		dst[2 * i] = l;
		dst[2 * i + 1] = r;
	}
	gFramesData += taken;
	gSilentRun = any ? 0 : gSilentRun + 1;
	if (taken > 0)
		IOLockWakeup(gLock, &gFifoEvent, false);
}

static void
queue_periods(void)
{
	while (!gMca.descRingFull()) {
		fill_period(gNext);
		gMca.submit(gDart.iova + (uint64_t)gNext * PERIOD_BYTES, PERIOD_BYTES);
		gNext = (gNext + 1) % RING_PERIODS;
		gSubmitted++;
	}
}

static uint32_t
measured_milli_hz(void)
{
	uint64_t periods = gDone - gDoneAtFirst;
	uint64_t ticks = gLastCounter - gFirstCounter;

	if (gFirstCounter == 0 || periods == 0 || ticks == 0)
		return 0;
	return (uint32_t)(periods * PERIOD_FRAMES * ADMAC_COUNTER_HZ * 1000 / ticks);
}

/* Reads the codec's and the transport's status registers into what the sysctls show. */
static void
refresh_status(void)
{
	gCodec.status(&gCodecSeen);
	if (gMca.attached)
		gMca.status(&gMcaSeen);
}

static void
log_codec(const char *when)
{
	refresh_status();
	const SFCs42l83Status &s = gCodecSeen;

	LOG("codec %s: pll_lock=0x%02x asp_rx=0x%02x src=0x%02x det1=0x%02x osc=0x%02x "
	    "pwr1=0x%02x hp_ctl=0x%02x vol=0x%02x/0x%02x asp_clk=0x%02x mclk_src=0x%02x pll_ctl1=0x%02x i2c_err=%d",
	    when, s.pllLock, s.aspRx, s.src, s.det1, s.oscSwitch, s.pwr1, s.hpCtl, s.volA, s.volB,
	    s.aspClk, s.mclkSrc, s.pllCtl1, s.error);
}

static void
log_transport(const char *when)
{
	gMca.status(&gMcaSeen);
	const SFMcaStatus &s = gMcaSeen;

	LOG("transport %s: nco=0x%08x/0x%08x mclk=0x%x syncgen=0x%x serdes=0x%x conf=0x%08x port en=0x%x clk=0x%x "
	    "data=0x%x mca_int=0x%08x admac tx=0x%x desc=0x%08x report=0x%08x status=0x%08x residue=0x%x",
	    when, s.ncoCtrl, s.ncoDiv, s.mclkStatus, s.syncgenStatus, s.serdesStatus, s.serdesConf, s.portEnables,
	    s.portClockSel, s.portDataSel, s.mcaIntState, s.admacTxEnabled, s.descRing, s.reportRing, s.chanStatus,
	    s.residue);
}

static void stop_playback(const char *why);

static uint32_t
isqrt64(uint64_t v)
{
	uint64_t r = 0, bit = 1ULL << 62;

	while (bit > v)
		bit >>= 2;
	for (; bit != 0; bit >>= 2) {
		if (v >= r + bit) {
			v -= r + bit;
			r = (r >> 1) + bit;
		} else {
			r >>= 1;
		}
	}
	return (uint32_t)r;
}

/* The codec's capture path and the receiver on, while a session runs. */
static void
mic_start(void)
{
	int err = gCodec.capture(true);

	if (err == 0)
		err = gMic.prepare();
	if (err != 0) {
		LOG("microphone: capture could not start (error %d)", err);
		gCodec.capture(false);
		return;
	}
	gMicNext = 0;
	gMicPeriods = 0;
	gMicPeakSession[0] = gMicPeakSession[1] = 0;
	while (!gMic.descRingFull()) {
		gMic.submit(gMicIova + (uint64_t)gMicNext * PERIOD_BYTES, PERIOD_BYTES);
		gMicNext = (gMicNext + 1) % RING_PERIODS;
	}
	gMic.start();
	LOG("microphone: capturing");
}

static void
mic_stop(void)
{
	uint32_t st[3];

	if (!gMic.running)
		return;
	gMic.status(st);
	gMic.stop();
	gCodec.capture(false);
	LOG("microphone: stopped after %llu periods; last period peak %d/%d mean %d/%d rms %d/%d, session peak %d/%d (of "
	    "8388608), %llu non-zero samples since boot, receiver 0x%x/0x%08x, %u frames not read in time", gMicPeriods,
	    gMicPeak[0], gMicPeak[1], gMicMean[0], gMicMean[1], gMicRms[0], gMicRms[1], gMicPeakSession[0],
	    gMicPeakSession[1], gMicNonZero, st[0], st[1], gMicDropped);
}

/* One captured period: statistics, and into the reader's FIFO (the oldest frames give way). */
static void
mic_take(uint32_t index)
{
	const int32_t *src = (const int32_t *)(const void *)(gMicRing + index * PERIOD_BYTES);
	int64_t sum[2] = { 0, 0 };
	uint64_t sq[2] = { 0, 0 };
	int32_t peak[2] = { 0, 0 };

	for (unsigned i = 0; i < PERIOD_FRAMES; i++) {
		int16_t frame[2];

		for (unsigned c = 0; c < 2; c++) {
			/* the converter has 24 bits: statistics at that resolution, the device's frames at 16 */
			int32_t v = src[2 * i + c] >> 8;
			frame[c] = (int16_t)(src[2 * i + c] >> 16);
			if (src[2 * i + c] != 0)
				gMicNonZero++;
			sum[c] += v;
			sq[c] += (uint64_t)((int64_t)v * v);
			if (v < 0)
				v = -v;
			if (v > peak[c])
				peak[c] = v;
		}
		if (gMicCount == MIC_FIFO_FRAMES) {
			gMicHead = (gMicHead + 1) % MIC_FIFO_FRAMES;
			gMicCount--;
			gMicDropped++;
		}
		memcpy(gMicFifo + 2 * ((gMicHead + gMicCount) % MIC_FIFO_FRAMES), frame, sizeof(frame));
		gMicCount++;
	}
	for (unsigned c = 0; c < 2; c++) {
		gMicPeak[c] = peak[c];
		gMicMean[c] = (int32_t)(sum[c] / PERIOD_FRAMES);
		gMicRms[c] = (int32_t)isqrt64(sq[c] / PERIOD_FRAMES);
		if (peak[c] > gMicPeakSession[c])
			gMicPeakSession[c] = peak[c];
	}
	gMicPeriods++;
	gMicFrames += PERIOD_FRAMES;
	IOLockWakeup(gLock, &gMicEvent, false);
}

static void
start_playback(void)
{
	int err;

	gNext = 0;
	gSilentRun = 0;
	gSubmitted = gDone = 0;
	gFirstCounter = gLastCounter = gDoneAtFirst = 0;
	gLate = gRingErrors = 0;
	gFramesData = gFramesTone = gFramesHeld = 0;
	gTonePhase = 0;
	gUnmutedAt = 0;
	gLockMs = -1;

	/* clocks to the codec first: its PLL locks to the bit clock */
	err = gMca.startClocks(gRate);
	if (err == 0)
		err = gCodec.configure(gRate);
	if (err == 0)
		err = gCodec.powerUp(gAttenuation);
	if (err != 0) {
		LOG("could not start playback at %u Hz (error %d)", gRate, err);
		gToneLeft = 0;
		gFifoCount = 0;
		IOLockWakeup(gLock, &gFifoEvent, false);
		gCodec.powerDown();
		gMca.stopClocks();
		return;
	}
	gMca.prepareDma();
	queue_periods();
	gMca.startDma();
	gCodec.mute(false);
	gUnmutedAt = uptime_ns();
	gState = kStatePlaying;
	gPlayTicks = 0;
	gSessions++;
	LOG("playing at %u Hz, codec attenuation %u dB, tone %llu frames at %u Hz -%u dB, writer %s", gRate,
	    gAttenuation, gToneLeft + gFramesTone, gToneHz, gToneDb, gDevOpen ? "open" : "none");
	log_transport("at start");
	if (gMicOpen)
		mic_start();
}

static void
service_playback(void)
{
	uint64_t counter = 0;
	unsigned n = gMca.drainReports(&counter);

	if (n > 0) {
		gDone += n;
		gTotalDone += n;
		gLastCounter = counter;
		if (gFirstCounter == 0) {
			gFirstCounter = counter;
			gDoneAtFirst = gDone;
		}
		gLastRateMilliHz = measured_milli_hz();
	}
	if (gMca.clearError()) {
		if (gRingErrors++ < 4)
			log_transport("ring error");
	}
	gDart.check("playback");
	/* the microphone follows its reader */
	if (gMicOpen && !gMic.running && gMic.attached) {
		mic_start();
	} else if (!gMicOpen && gMic.running) {
		mic_stop();
	} else if (gMic.running) {
		unsigned got = gMic.drainReports(NULL);
		for (unsigned i = 0; i < got; i++)
			mic_take((uint32_t)(gMicPeriods % RING_PERIODS));
		while (!gMic.descRingFull()) {
			gMic.submit(gMicIova + (uint64_t)gMicNext * PERIOD_BYTES, PERIOD_BYTES);
			gMicNext = (gMicNext + 1) % RING_PERIODS;
		}
		if (gMic.clearError())
			gRingErrors++;
	}
	/* an empty descriptor ring here means this thread fell several periods behind */
	if (gDone > 0 && gMca.descRingEmpty())
		gLate++;
	queue_periods();
	/*
	 * Until the codec's input converter has locked to the frames (its output is not
	 * valid before), ask every 50 ms: one short I2C transfer.
	 */
	if (gLockMs < 0 && gPlayTicks % 10 == 0 && gCodec.inputLocked()) {
		gLockMs = (int32_t)((uptime_ns() - gUnmutedAt) / 1000000);
		LOG("codec input converter locked %d ms after the unmute", gLockMs);
	}
	/* once a second, after the ring is full again: the registers the sysctls show */
	if (++gPlayTicks % 200 == 0)
		refresh_status();
	if (gToneLeft == 0 && !gDevOpen && !gMicOpen && gFifoCount == 0 && gSilentRun >= TRAILING_SILENCE)
		stop_playback("end of data");
}

static void
stop_playback(const char *why)
{
	uint32_t mhz = measured_milli_hz();

	log_codec("before stop");
	log_transport("before stop");
	mic_stop();
	/* the codec leaves the bit clock while it still runs */
	gCodec.powerDown();
	gMca.stopDma();
	gMca.stopClocks();
	gDart.check("stop");
	gState = kStateIdle;
	gIdleTicks = 0;
	LOG("stopped (%s): %llu periods queued, %llu played (%llu frames: %llu written, %llu tone, %llu held silent "
	    "before the lock), measured %u.%03u Hz against %u, converter lock %d ms, late %u, ring errors %u, "
	    "dart faults %u, i2c errors %u", why, gSubmitted, gDone, gDone * PERIOD_FRAMES, gFramesData, gFramesTone,
	    gFramesHeld, mhz / 1000, mhz % 1000, gRate, gLockMs, gLate, gRingErrors, gDart.faults, gI2C.errors);
}

/* ---- jack ----------------------------------------------------------------------------- */

static const char *const kJackNames[] = { "nothing plugged", "headphones", "headset" };

/* From the codec's jack path (its lock held): what is plugged or which buttons are down changed. */
static void
jack_changed(SFCs42l83 *codec, uint8_t pressed)
{
	if (codec->jack != gJack)
		LOG("jack: %s (type %u%s)", kJackNames[codec->jack], codec->hsType,
		    codec->remoteActive ? ", Apple remote" : "");
	if (codec->buttons != gJackButtons)
		LOG("jack buttons: held 0x%x, newly pressed 0x%x (1 play/pause, 2 volume up, 4 volume down, 8 voice)",
		    codec->buttons, pressed);
	gJack = codec->jack;
	gJackButtons = codec->buttons;
}

/*
 * The GPIO block's group 0 interrupt, in interrupt context. The codec's line is level
 * low and stays so until its status has been read over I2C: mask the pin, wake the
 * jack thread, which unmasks it after the service.
 */
static void
gpio_interrupt(__unused OSObject *target, __unused void *refCon, __unused IOService *nub, __unused int source)
{
	if (gGpio.irqPending(PIN_CODEC_IRQ)) {
		gGpio.irqMask(PIN_CODEC_IRQ);
		gGpio.irqAck(PIN_CODEC_IRQ);
		OSIncrementAtomic(&gJackIrqs);
		OSCompareAndSwap(0, 1, (volatile UInt32 *)&gJackPending);
		thread_wakeup((event_t)&gJackPending);
	}
}

static void
sf_jack_thread(__unused void *arg, __unused wait_result_t wr)
{
	for (;;) {
		bool irq = OSCompareAndSwap(1, 0, (volatile UInt32 *)&gJackPending);

		/* the line itself: low means the codec wants service, with or without an interrupt */
		if (irq || gGpio.get(PIN_CODEC_IRQ) == 0) {
			if (!irq)
				gJackPolled++;
			gCodec.jackService();
			gGpio.irqUnmask(PIN_CODEC_IRQ, SFGpio::kIrqLevelLow);
			/* a line that stays low (a codec that does not answer) must not spin */
			IOSleep(5);
			continue;
		}
		IOLockLock(gJackWait);
		if (!gJackPending) {
			AbsoluteTime deadline;
			clock_interval_to_deadline(100, kMillisecondScale, &deadline);
			IOLockSleepDeadline(gJackWait, (void *)&gJackPending, deadline, THREAD_UNINT);
		}
		IOLockUnlock(gJackWait);
	}
}

/* The codec's interrupt: AIC interrupt of GPIO group 0, described on this service as index 0. */
static void
jack_bring_up(void)
{
	uint32_t vector = 0;
	thread_t thread;
	UInt32 before;

	gJackWait = IOLockAlloc();
	gCodec.changed = jack_changed;
	gGpio.irqSetup(PIN_CODEC_IRQ);
	if (gJackWait != NULL && sf_adt_u32("/arm-io/gpio", "interrupts", 0, &vector) && vector != 0) {
		IOInterruptVectorNumber number = vector;
		const OSSymbol *controller = gIODTDefaultInterruptController;
		OSData *spec = OSData::withBytes(&number, sizeof(number));
		OSArray *controllers = OSArray::withObjects((const OSObject **)&controller, 1);
		OSArray *specs = spec ? OSArray::withObjects((const OSObject **)&spec, 1) : NULL;

		gJackIrqOk = controllers && specs && gService->setProperty(gIOInterruptControllersKey, controllers) &&
		    gService->setProperty(gIOInterruptSpecifiersKey, specs) &&
		    gService->registerInterrupt(0, gService, gpio_interrupt, NULL) == kIOReturnSuccess &&
		    gService->enableInterrupt(0) == kIOReturnSuccess;
		OSSafeReleaseNULL(spec);
		OSSafeReleaseNULL(controllers);
		OSSafeReleaseNULL(specs);
	}
	if (gJackWait == NULL || kernel_thread_start(sf_jack_thread, NULL, &thread) != KERN_SUCCESS) {
		LOG("jack: no thread; plug events are not followed");
		return;
	}
	thread_deallocate(thread);
	before = gJackIrqs;
	gGpio.irqUnmask(PIN_CODEC_IRQ, SFGpio::kIrqLevelLow);
	/* the self-test leaves one interrupt source of the codec asserted: the line must fire now */
	if (gCodec.jackStart(true) != 0) {
		LOG("jack: the codec's interrupt masks could not be written");
		return;
	}
	for (int i = 0; i < 50 && gCodec.irqServices == 0; i++)
		IOSleep(10);
	LOG("jack: codec interrupt on gpio pin %u, AIC interrupt %u: %s (%u interrupts, %u services, %u found by "
	    "looking at the pin); %s", PIN_CODEC_IRQ, vector,
	    !gJackIrqOk ? "NOT registered, the pin is polled" : gJackIrqs != before ? "delivered" : "registered but NOT delivered",
	    gJackIrqs - before, gCodec.irqServices, gJackPolled, kJackNames[gCodec.jack]);
	gJack = gCodec.jack;
}

/* ---- bring-up ------------------------------------------------------------------------- */

static void
fail(const char *what, int err)
{
	snprintf(gFailure, sizeof(gFailure), "%s (error %d)", what, err);
	LOG("bring-up stopped: %s", gFailure);
}

static void
bring_up(void)
{
	uint32_t addr = CODEC_ADDR, sid = ADMAC_STREAM;
	int err;

	gState = kStateFailed;
	if (!gGpio.attach("/arm-io/gpio") || !gNub.attach("/arm-io/nub-gpio")) {
		fail("GPIO blocks", ENXIO);
		return;
	}
	LOG("pins before: i2c2 sda(%u)=0x%08x scl(%u)=0x%08x, codec reset(nub %u)=0x%08x irq(%u)=0x%08x, "
	    "speaker shutdown(%u)=0x%08x", PIN_I2C2_SDA, gGpio.raw(PIN_I2C2_SDA), PIN_I2C2_SCL,
	    gGpio.raw(PIN_I2C2_SCL), PIN_CODEC_RESET, gNub.raw(PIN_CODEC_RESET), PIN_CODEC_IRQ, gGpio.raw(PIN_CODEC_IRQ),
	    PIN_SPEAKER_SDZ, gGpio.raw(PIN_SPEAKER_SDZ));
	/* i2c2_pins of the Linux device tree */
	gGpio.function(PIN_I2C2_SCL, 1);
	gGpio.function(PIN_I2C2_SDA, 1);
	if (!gI2C.attach("/arm-io/i2c2", 100000)) {
		fail("I2C controller i2c2", ENXIO);
		return;
	}
	if (sf_adt_u32("/arm-io/i2c2/audio-codec-output", "reg", 0, &addr))
		addr &= 0x7f;
	err = gCodec.probe(&gI2C, (uint8_t)addr, &gNub, PIN_CODEC_RESET);
	if (err != 0) {
		fail("CS42L83 probe", err);
		return;
	}
	LOG("CS42L83 at i2c2 0x%02x: device ID 0x%05x revision 0x%02x, reset pin now 0x%08x", addr, gCodec.devid,
	    gCodec.revid, gNub.raw(PIN_CODEC_RESET));
	log_codec("after init");
	jack_bring_up();
	gState = kStateCodecOnly;
	if (gLevel < 2)
		return;

	sf_adt_u32("/arm-io/dart-sio/mapper-admac", "reg", 0, &sid);
	err = gDart.attach("/arm-io/dart-sio", sid, RING_IOVA,
	    RING_BYTES + SF_SPK_PLAY_RING_BYTES + SF_SPK_SENSE_RING_BYTES + MIC_RING_BYTES);
	if (err != 0) {
		fail("dart-sio", err);
		return;
	}
	err = gMca.attach(gFe, 1u << gPort, 2, 2, 0);
	if (err != 0) {
		fail("audio transport", err);
		return;
	}
	gMicRing = gDart.buf + RING_BYTES + SF_SPK_PLAY_RING_BYTES + SF_SPK_SENSE_RING_BYTES;
	gMicIova = gDart.iova + RING_BYTES + SF_SPK_PLAY_RING_BYTES + SF_SPK_SENSE_RING_BYTES;
	/* receive SRAM block 1: block 0 is the speakers' sense */
	if (gMic.attach(gFe, 1u << gPort, false, 0, 2, 32, 2, 1) != 0)
		LOG("microphone: no receiver; /dev/sfmic will not work");
	gFifo = (int32_t *)IOMalloc(FIFO_FRAMES * 2 * sizeof(int32_t));
	gMicFifo = (int16_t *)IOMalloc(MIC_FIFO_FRAMES * 2 * sizeof(int16_t));
	if (gFifo == NULL || gMicFifo == NULL) {
		fail("FIFO", ENOMEM);
		return;
	}
	log_transport("attached");
	if (gLevel < 3) {
		LOG("transport set up; playback is off (sfsound=%u)", gLevel);
		return;
	}
	gState = kStateIdle;
	if (gSpeakers)
		sf_speakers_bring_up(&gGpio, &gDart, gDart.buf + RING_BYTES, gDart.iova + RING_BYTES,
		    gDart.buf + RING_BYTES + SF_SPK_PLAY_RING_BYTES, gDart.iova + RING_BYTES + SF_SPK_PLAY_RING_BYTES);
}

/* ---- /dev/sfaudio --------------------------------------------------------------------- */

static int
sf_audio_open(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	int err = 0;

	IOLockLock(gLock);
	if (gState < kStateIdle)
		err = ENXIO;
	else if (gDevOpen)
		err = EBUSY;
	else
		gDevOpen = true;
	IOLockUnlock(gLock);
	return err;
}

static int
sf_audio_close(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	IOLockLock(gLock);
	gDevOpen = false;
	IOLockUnlock(gLock);
	return 0;
}

static int
sf_audio_write(__unused dev_t dev, struct uio *uio, __unused int ioflag)
{
	int16_t chunk[2 * 256];
	int err = 0;

	while (err == 0 && uio_resid(uio) > 0) {
		user_ssize_t left = uio_resid(uio);
		unsigned frames = left >= 4 ? (unsigned)(left / 4 > 256 ? 256 : left / 4) : 0;

		if (frames == 0) {
			/* a trailing partial frame is dropped */
			err = uiomove((char *)chunk, (int)left, uio);
			break;
		}
		err = uiomove((char *)chunk, (int)(frames * 4), uio);
		if (err != 0)
			break;
		IOLockLock(gLock);
		for (unsigned i = 0; i < frames && err == 0; i++) {
			while (gFifoCount == FIFO_FRAMES && gState >= kStateIdle) {
				if (IOLockSleep(gLock, &gFifoEvent, THREAD_ABORTSAFE) != THREAD_AWAKENED) {
					err = EINTR;
					break;
				}
			}
			if (err == 0 && gState < kStateIdle)
				err = ENXIO;
			if (err != 0)
				break;
			uint32_t at = (gFifoHead + gFifoCount) % FIFO_FRAMES;
			gFifo[2 * at] = (int32_t)chunk[2 * i] * 65536;
			gFifo[2 * at + 1] = (int32_t)chunk[2 * i + 1] * 65536;
			gFifoCount++;
		}
		IOLockUnlock(gLock);
	}
	return err;
}

static struct cdevsw sf_audio_cdevsw = {
	sf_audio_open, sf_audio_close, eno_rdwrt, sf_audio_write,
	eno_ioctl, eno_stop, eno_reset, 0, eno_select, eno_mmap,
	eno_strat, eno_getc, eno_putc, 0
};

/* ---- /dev/sfmic ----------------------------------------------------------------------- */

static int
sf_mic_open(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	int err = 0;

	IOLockLock(gLock);
	if (gState < kStateIdle || !gMic.attached)
		err = ENXIO;
	else if (gMicOpen)
		err = EBUSY;
	else {
		gMicOpen = true;
		gMicHead = gMicCount = 0;
	}
	IOLockUnlock(gLock);
	return err;
}

static int
sf_mic_close(__unused dev_t dev, __unused int flags, __unused int devtype, __unused struct proc *p)
{
	IOLockLock(gLock);
	gMicOpen = false;
	IOLockWakeup(gLock, &gMicEvent, false);
	IOLockUnlock(gLock);
	return 0;
}

/* Whole frames; blocks until there is at least one. */
static int
sf_mic_read(__unused dev_t dev, struct uio *uio, __unused int ioflag)
{
	int16_t chunk[2 * 256];
	int err = 0;
	bool any = false;

	while (err == 0 && uio_resid(uio) >= 4) {
		unsigned want = (unsigned)(uio_resid(uio) / 4), got = 0;

		if (want > 256)
			want = 256;
		IOLockLock(gLock);
		while (gMicCount == 0 && !any && err == 0) {
			if (gState < kStateIdle)
				err = ENXIO;
			else if (IOLockSleep(gLock, &gMicEvent, THREAD_ABORTSAFE) != THREAD_AWAKENED)
				err = EINTR;
		}
		while (got < want && gMicCount > 0) {
			chunk[2 * got] = gMicFifo[2 * gMicHead];
			chunk[2 * got + 1] = gMicFifo[2 * gMicHead + 1];
			gMicHead = (gMicHead + 1) % MIC_FIFO_FRAMES;
			gMicCount--;
			got++;
		}
		IOLockUnlock(gLock);
		if (got == 0)
			break;
		err = uiomove((char *)chunk, (int)(got * 4), uio);
		any = true;
	}
	return err;
}

static struct cdevsw sf_mic_cdevsw = {
	sf_mic_open, sf_mic_close, sf_mic_read, eno_rdwrt,
	eno_ioctl, eno_stop, eno_reset, 0, eno_select, eno_mmap,
	eno_strat, eno_getc, eno_putc, 0
};

/* devfs is not there yet when the driver starts: keep trying from the thread. */
static void
publish_node(void)
{
	if (gDevNode != NULL)
		return;
	if (gMajor < 0)
		gMajor = cdevsw_add(-1, &sf_audio_cdevsw);
	if (gMajor >= 0)
		gDevNode = devfs_make_node(makedev(gMajor, 0), DEVFS_CHAR, 0, 0, 0666, "sfaudio");
	if (gMicMajor < 0)
		gMicMajor = cdevsw_add(-1, &sf_mic_cdevsw);
	if (gMicMajor >= 0 && gMicNode == NULL)
		gMicNode = devfs_make_node(makedev(gMicMajor, 0), DEVFS_CHAR, 0, 0, 0666, "sfmic");
	if (gDevNode != NULL)
		LOG("/dev/sfaudio published (major %d)%s", gMajor, gMicNode ? ", /dev/sfmic" : "");
}

/* ---- the thread ----------------------------------------------------------------------- */

static void
sf_sound_thread(__unused void *arg, __unused wait_result_t wr)
{
	uint32_t tone = 0;
	unsigned tick = 0;

	IOSleep(gDelayMs);
	IOLockLock(gLock);
	bring_up();
	if (gState == kStateIdle && PE_parse_boot_argn("sfsound_tone", &tone, sizeof(tone)) && tone > 0 && tone <= 600)
		gToneLeft = (uint64_t)tone * gRate;
	IOLockUnlock(gLock);

	for (;;) {
		bool playing;

		IOLockLock(gLock);
		if (gState == kStatePlaying) {
			service_playback();
		} else if (gState == kStateIdle) {
			if (gToneLeft > 0 || gFifoCount > 0 || gMicOpen) {
				start_playback();
			} else if (++gIdleTicks % 20 == 0) {
				refresh_status();
			}
		} else if (gState == kStateCodecOnly && ++gIdleTicks % 20 == 0) {
			refresh_status();
		}
		playing = gState == kStatePlaying;
		IOLockUnlock(gLock);

		if (gState >= kStateIdle && gDevNode == NULL && tick % (playing ? 200 : 10) == 0)
			publish_node();
		tick++;
		IOSleep(playing ? 5 : 100);
	}
}

/* ---- sysctl --------------------------------------------------------------------------- */

enum {
	kCtlTone, kCtlToneHz, kCtlToneDb, kCtlVolume, kCtlRate, kCtlJack, kCtlPeriods, kCtlFrames, kCtlLate,
	kCtlRingErrors, kCtlDartFaults, kCtlI2CErrors, kCtlRateMilliHz, kCtlSessions, kCtlPlaying, kCtlLockMs,
	kCtlPreroll, kCtlJackIrqs, kCtlJackServices, kCtlJackPolled, kCtlJackButtons, kCtlJackButtonEvents,
	kCtlJackPlugs, kCtlJackUnplugs, kCtlJackDetects, kCtlJackSelfTest, kCtlFifoFrames,
};

static int
sf_sysctl_int(struct sysctl_oid *oidp, __unused void *arg1, int arg2, struct sysctl_req *req)
{
	int value = 0, error;

	IOLockLock(gLock);
	switch (arg2) {
	case kCtlTone:        value = (int)(gToneLeft / gRate); break;
	case kCtlToneHz:      value = (int)gToneHz; break;
	case kCtlToneDb:      value = (int)gToneDb; break;
	case kCtlVolume:      value = (int)gAttenuation; break;
	case kCtlRate:        value = (int)gRate; break;
	case kCtlJack:        value = gJack; break;
	case kCtlPeriods:     value = (int)gTotalDone; break;
	case kCtlFrames:      value = (int)(gTotalDone * PERIOD_FRAMES); break;
	case kCtlLate:        value = (int)gLate; break;
	case kCtlRingErrors:  value = (int)gRingErrors; break;
	case kCtlDartFaults:  value = (int)gDart.faults; break;
	case kCtlI2CErrors:   value = (int)gI2C.errors; break;
	case kCtlRateMilliHz: value = (int)gLastRateMilliHz; break;
	case kCtlSessions:    value = (int)gSessions; break;
	case kCtlPlaying:     value = gState == kStatePlaying; break;
	case kCtlLockMs:      value = gLockMs; break;
	case kCtlPreroll:     value = (int)gPrerollMs; break;
	case kCtlJackIrqs:    value = (int)gJackIrqs; break;
	case kCtlJackServices: value = (int)gCodec.irqServices; break;
	case kCtlJackPolled:  value = (int)gJackPolled; break;
	case kCtlJackButtons: value = gJackButtons; break;
	case kCtlJackButtonEvents: value = (int)gCodec.buttonEvents; break;
	case kCtlJackPlugs:   value = (int)gCodec.plugEvents; break;
	case kCtlJackUnplugs: value = (int)gCodec.unplugEvents; break;
	case kCtlJackDetects: value = (int)gCodec.detectsDone; break;
	case kCtlJackSelfTest: value = (int)gCodec.hsType; break;
	case kCtlFifoFrames:  value = (int)gFifoCount; break;
	}
	IOLockUnlock(gLock);

	error = sysctl_handle_int(oidp, &value, 0, req);
	if (error != 0 || req->newptr == USER_ADDR_NULL)
		return error;

	if (arg2 == kCtlJackSelfTest) {
		/* outside gLock: the detection takes more than a second and has the codec's own lock */
		if (gState < kStateCodecOnly)
			return ENXIO;
		return gCodec.jackSelfTest() ? 0 : EBUSY;
	}
	IOLockLock(gLock);
	switch (arg2) {
	case kCtlTone:
		if (gState < kStateIdle)
			error = ENXIO;
		else if (value < 0 || value > 600)
			error = EINVAL;
		else
			gToneLeft = (uint64_t)value * gRate;
		break;
	case kCtlToneHz:
		if (value < 20 || value > 20000)
			error = EINVAL;
		else
			gToneHz = (uint32_t)value;
		break;
	case kCtlToneDb:
		if (value < MIN_TONE_DB || value > 96)
			error = EINVAL;
		else
			gToneDb = (uint32_t)value;
		break;
	case kCtlVolume:
		if (value < 0 || value > 63) {
			error = EINVAL;
		} else {
			gAttenuation = (uint32_t)value;
			if (gState == kStatePlaying)
				error = gCodec.setVolume(gAttenuation);
		}
		break;
	case kCtlPreroll:
		if (value < 0 || value > 5000)
			error = EINVAL;
		else
			gPrerollMs = (uint32_t)value;
		break;
	case kCtlRate:
		if (value != 44100 && value != 48000)
			error = EINVAL;
		else if (gState == kStatePlaying || gFifoCount > 0 || gToneLeft > 0)
			error = EBUSY;
		else
			gRate = (uint32_t)value;
		break;
	default:
		error = EPERM;
	}
	IOLockUnlock(gLock);
	return error;
}

static int
sf_sysctl_string(__unused struct sysctl_oid *oidp, __unused void *arg1, int arg2, struct sysctl_req *req)
{
	char text[640];

	text[0] = 0;
	IOLockLock(gLock);
	switch (arg2) {
	case 0:
		snprintf(text, sizeof(text), "%s%s%s codec=0x%05x rev=0x%02x jack=%d rate=%u fe=%u port=%u",
		    kStateNames[gState], gFailure[0] ? ": " : "", gFailure, gCodec.devid, gCodec.revid, gJack, gRate,
		    gFe, gPort);
		break;
	case 1:
		if (gState >= kStateCodecOnly) {
			const SFCs42l83Status &s = gCodecSeen;
			snprintf(text, sizeof(text), "pll_lock=0x%02x asp_rx=0x%02x src=0x%02x "
			    "det1=0x%02x osc=0x%02x pwr1=0x%02x hp_ctl=0x%02x vol=0x%02x/0x%02x asp_clk=0x%02x "
			    "mclk_src=0x%02x pll_ctl1=0x%02x i2c_err=%d", s.pllLock, s.aspRx, s.src,
			    s.det1, s.oscSwitch, s.pwr1, s.hpCtl, s.volA, s.volB, s.aspClk, s.mclkSrc, s.pllCtl1, s.error);
		}
		break;
	case 2:
		if (gMca.attached) {
			const SFMcaStatus &s = gMcaSeen;
			snprintf(text, sizeof(text), "nco=0x%08x/0x%08x mclk=0x%x syncgen=0x%x serdes=0x%x conf=0x%08x "
			    "port_en=0x%x port_clk=0x%x port_data=0x%x mca_int=0x%08x admac_tx=0x%x desc=0x%08x "
			    "report=0x%08x status=0x%08x residue=0x%x queued=%llu played=%llu", s.ncoCtrl, s.ncoDiv,
			    s.mclkStatus, s.syncgenStatus, s.serdesStatus, s.serdesConf, s.portEnables, s.portClockSel,
			    s.portDataSel, s.mcaIntState, s.admacTxEnabled, s.descRing, s.reportRing, s.chanStatus,
			    s.residue, gSubmitted, gDone);
		}
		break;
	case 3:
		snprintf(text, sizeof(text), "%s periods=%llu frames=%llu peak=%d/%d mean=%d/%d rms=%d/%d session_peak=%d/%d "
		    "nonzero=%llu dropped=%u", gMic.running ? "capturing" : "idle", gMicPeriods, gMicFrames, gMicPeak[0],
		    gMicPeak[1], gMicMean[0], gMicMean[1], gMicRms[0], gMicRms[1], gMicPeakSession[0], gMicPeakSession[1],
		    gMicNonZero, gMicDropped);
		break;
	}
	IOLockUnlock(gLock);
	return SYSCTL_OUT(req, text, strlen(text) + 1);
}

SYSCTL_DECL(_kern);
SYSCTL_NODE(_kern, OID_AUTO, sf_sound, CTLFLAG_RD | CTLFLAG_LOCKED, 0, "headphone jack audio");

#define SF_INT(name, id, flags, text) \
	SYSCTL_PROC(_kern_sf_sound, OID_AUTO, name, CTLTYPE_INT | (flags) | CTLFLAG_LOCKED, 0, id, sf_sysctl_int, "I", text)
#define SF_STR(name, id, text) \
	SYSCTL_PROC(_kern_sf_sound, OID_AUTO, name, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, 0, id, sf_sysctl_string, "A", text)

SF_STR(state, 0, "driver state, codec identification, jack");
SF_STR(codec, 1, "CS42L83 status registers as last read (every second while playing, every two otherwise)");
SF_STR(transport, 2, "NCO, MCA and ADMAC registers as last read");
SF_STR(mic, 3, "headset microphone capture: periods, and peak, mean and RMS of the last period (of 8388608)");
SF_INT(tone, kCtlTone, CTLFLAG_RW, "seconds of test tone left; write to play");
SF_INT(tone_hz, kCtlToneHz, CTLFLAG_RW, "test tone frequency");
SF_INT(tone_db, kCtlToneDb, CTLFLAG_RW, "test tone level, dB below full scale");
SF_INT(volume_db, kCtlVolume, CTLFLAG_RW, "codec attenuation in dB, 63 mutes");
SF_INT(rate, kCtlRate, CTLFLAG_RW, "sample rate");
SF_INT(jack, kCtlJack, CTLFLAG_RD, "0 nothing plugged, 1 headphones, 2 headset, -1 unknown");
SF_INT(fifo_frames, kCtlFifoFrames, CTLFLAG_RD, "frames a writer has queued that are not yet in the DMA ring");
SF_INT(jack_irqs, kCtlJackIrqs, CTLFLAG_RD, "codec interrupts taken");
SF_INT(jack_services, kCtlJackServices, CTLFLAG_RD, "times the codec's interrupt status was serviced");
SF_INT(jack_polled, kCtlJackPolled, CTLFLAG_RD, "services started by finding the interrupt line low without an interrupt");
SF_INT(jack_buttons, kCtlJackButtons, CTLFLAG_RD, "headset buttons held: 1 play/pause, 2 volume up, 4 volume down, 8 voice");
SF_INT(jack_button_events, kCtlJackButtonEvents, CTLFLAG_RD, "headset button presses seen");
SF_INT(jack_plugs, kCtlJackPlugs, CTLFLAG_RD, "plug events");
SF_INT(jack_unplugs, kCtlJackUnplugs, CTLFLAG_RD, "unplug events");
SF_INT(jack_detects, kCtlJackDetects, CTLFLAG_RD, "plug type detections completed");
SF_INT(jack_selftest, kCtlJackSelfTest, CTLFLAG_RW, "write: run the plug type detection once on the empty jack; reads the last type (3: none)");
SF_INT(periods, kCtlPeriods, CTLFLAG_RD, "DMA periods played since boot");
SF_INT(frames, kCtlFrames, CTLFLAG_RD, "frames played since boot (wraps)");
SF_INT(late, kCtlLate, CTLFLAG_RD, "times the descriptor ring ran empty in the last session");
SF_INT(ring_errors, kCtlRingErrors, CTLFLAG_RD, "DMA ring errors in the last session");
SF_INT(dart_faults, kCtlDartFaults, CTLFLAG_RD, "DART faults since boot");
SF_INT(i2c_errors, kCtlI2CErrors, CTLFLAG_RD, "failed I2C transfers since boot");
SF_INT(rate_mhz, kCtlRateMilliHz, CTLFLAG_RD, "sample rate measured from the DMA timestamps, in mHz");
SF_INT(sessions, kCtlSessions, CTLFLAG_RD, "playback sessions started");
SF_INT(playing, kCtlPlaying, CTLFLAG_RD, "1 while a session runs");
SF_INT(preroll_ms, kCtlPreroll, CTLFLAG_RW, "longest silent wait for the codec's converter lock before data plays; 0: none");
SF_INT(lock_ms, kCtlLockMs, CTLFLAG_RD, "last session: ms from unmute to the codec's converter lock, -1 if it never locked");

static struct sysctl_oid *const gOids[] = {
	&sysctl__kern_sf_sound,
	&sysctl__kern_sf_sound_state, &sysctl__kern_sf_sound_codec, &sysctl__kern_sf_sound_transport,
	&sysctl__kern_sf_sound_mic,
	&sysctl__kern_sf_sound_tone, &sysctl__kern_sf_sound_tone_hz, &sysctl__kern_sf_sound_tone_db,
	&sysctl__kern_sf_sound_volume_db, &sysctl__kern_sf_sound_rate, &sysctl__kern_sf_sound_jack,
	&sysctl__kern_sf_sound_periods, &sysctl__kern_sf_sound_frames, &sysctl__kern_sf_sound_late,
	&sysctl__kern_sf_sound_ring_errors, &sysctl__kern_sf_sound_dart_faults, &sysctl__kern_sf_sound_i2c_errors,
	&sysctl__kern_sf_sound_rate_mhz, &sysctl__kern_sf_sound_sessions, &sysctl__kern_sf_sound_playing,
	&sysctl__kern_sf_sound_lock_ms, &sysctl__kern_sf_sound_preroll_ms,
	&sysctl__kern_sf_sound_jack_irqs, &sysctl__kern_sf_sound_jack_services, &sysctl__kern_sf_sound_jack_polled,
	&sysctl__kern_sf_sound_jack_buttons, &sysctl__kern_sf_sound_jack_button_events,
	&sysctl__kern_sf_sound_jack_plugs, &sysctl__kern_sf_sound_jack_unplugs, &sysctl__kern_sf_sound_jack_detects,
	&sysctl__kern_sf_sound_jack_selftest, &sysctl__kern_sf_sound_fifo_frames,
};

/* ---- IOKit ---------------------------------------------------------------------------- */

class SFAppleSound : public IOService {
	OSDeclareDefaultStructors(SFAppleSound);

public:
	bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
	void systemWillShutdown(IOOptionBits specifier) APPLE_KEXT_OVERRIDE;
};

OSDefineMetaClassAndStructors(SFAppleSound, IOService);

/* Only on the board this driver's tables describe. */
static bool
sf_on_j293(void)
{
	IORegistryEntry *root = IORegistryEntry::fromPath("/", gIODTPlane);
	OSData *compatible = root ? OSDynamicCast(OSData, root->getProperty("compatible")) : NULL;
	bool yes = compatible != NULL &&
	    sf_board_compatible_is(compatible->getBytesNoCopy(), compatible->getLength(), "J293AP");

	OSSafeReleaseNULL(root);
	return yes;
}

bool
SFAppleSound::start(IOService *provider)
{
	IORegistryEntry *chosen;
	OSData *chip;
	uint32_t chipID = 0, value = 0;
	thread_t thread;

	if (!IOService::start(provider))
		return false;

	chosen = IORegistryEntry::fromPath("/chosen", gIODTPlane);
	chip = chosen ? OSDynamicCast(OSData, chosen->getProperty("chip-id")) : NULL;
	if (chip != NULL && chip->getLength() >= sizeof(uint32_t))
		chipID = *(const uint32_t *)chip->getBytesNoCopy();
	OSSafeReleaseNULL(chosen);
	if (chipID != T8103_CHIP_ID) {
		LOG("chip 0x%x is not T8103; nothing is done", chipID);
		return false;
	}
	/* J313 has its codec on i2c3, two amplifiers, and USB-C retimers on i2c2 */
	if (!sf_on_j293()) {
		LOG("not a J293: its audio buses and speaker model do not apply; nothing is done");
		return false;
	}

	PE_parse_boot_argn("sfsound", &gLevel, sizeof(gLevel));
	if (PE_parse_boot_argn("sfsound_delay", &value, sizeof(value)) && value <= 60000)
		gDelayMs = value;
	PE_parse_boot_argn("sfspeakers", &gSpeakers, sizeof(gSpeakers));
	if (PE_parse_boot_argn("sfsound_fe", &value, sizeof(value)) && value <= 3)
		gFe = value;
	if (PE_parse_boot_argn("sfsound_port", &value, sizeof(value)) && value <= 5)
		gPort = value;
	if (gLevel == 0) {
		LOG("off (sfsound=0)");
		return false;
	}

	gLock = IOLockAlloc();
	if (gLock == NULL)
		return false;
	gService = this;
	for (unsigned i = 0; i < sizeof(gOids) / sizeof(gOids[0]); i++)
		sysctl_register_oid(gOids[i]);
	if (kernel_thread_start(sf_sound_thread, NULL, &thread) != KERN_SUCCESS)
		return false;
	thread_deallocate(thread);
	registerService();
	return true;
}

/* Mute and power the codec down before the system goes, so nothing keeps sounding. */
void
SFAppleSound::systemWillShutdown(IOOptionBits specifier)
{
	sf_speakers_quiesce();
	if (gLock != NULL) {
		IOLockLock(gLock);
		if (gState == kStatePlaying) {
			gToneLeft = 0;
			gFifoCount = 0;
			stop_playback("shutdown");
		}
		if (gState >= kStateIdle)
			gState = kStateCodecOnly;
		IOLockWakeup(gLock, &gFifoEvent, false);
		IOLockUnlock(gLock);
	}
	IOService::systemWillShutdown(specifier);
}
