// SPDX-License-Identifier: GPL-2.0-only
/*
 * SFAppleTouchBar: the Touch Bar of the 13-inch M1 MacBook Pro (J293, T8103) as a row of
 * keys. Everything is in the kernel; no process has to be alive for the keys to work.
 *
 *   display   sf_adp      Apple display pipe "dispdfr", MIPI DSI host, Summit panel
 *                         (60 x 2008 shown of 64-pixel lines, XRGB8888), DART stream 0 of
 *                         /arm-io/dart-dispdfr
 *   touch     sf_z2       Z2 digitizer on SPI0 (sf_spi), chip select gpio 109, reset gpio 139,
 *                         interrupt gpio 194 (falling edge; interrupt group 1 of /arm-io/gpio,
 *                         because SFAppleSound owns group 0)
 *   keys      sf_tb_keys  layout, picture, touch-to-key logic (MIT, shared with the host tests)
 *   delivery  SFTouchBarKeys, an IOHIDDevice with a boot keyboard descriptor: the same path
 *             the built-in keyboard (SFM1SPIHID) takes into IOHIDFamily and from there into
 *             the SFHID key queue and the console
 *
 * Hardware constants are those of Linux arch/arm64/boot/dts/apple/t8103.dtsi and
 * t8103-j293.dts (omacom/linux-aurora). The digitizer's firmware is read from
 * /Library/Firmware/apple/dfrmtfw-j293.bin once the root file system is there (this
 * machine's own file, as the Wi-Fi firmware); its calibration is the Apple device
 * tree's /arm-io/spi0/multi-touch "multi-touch-calibration".
 *
 * The layer is chosen by the built-in keyboard's Fn key, as on a Mac: the default layer
 * (media) while Fn is up, the other one while it is held. SFM1SPIHID (the build of
 * ../build-spihid.nix) tells this driver about Fn and about typing with an IOService
 * message (sf_touchbar_kbd.h); typing keeps the strip lit like a touch does.
 *
 * One thread owns the hardware. gLock serialises it with the sysctl handlers.
 *
 * Boot arguments: sftouchbar=0 off, 1 survey only (nothing written), 2 display only,
 * 3 everything (default); sftouchbar_bright=<1..255> (default 128, tiny-dfr's);
 * sftouchbar_dim=<seconds>, sftouchbar_off=<seconds> (30, 60 as tiny-dfr; 0 never);
 * sftouchbar_default=media|fn (the layer shown while the keyboard's Fn key is up; media);
 * sftouchbar_hold=<seconds a key stays held without a finger report, 0 for ever; 3>;
 * sftouchbar_direct=1 pushes keys into the SFHID queue directly;
 * sftouchbar_dcs=0 does not read the panel's registers at start; sftouchbar_probe=1 runs the
 * fetch probe at start (the strip shows garbage for its 300 ms; kern.sf_touchbar.fetch_probe
 * runs it on request).
 */
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOInterruptController.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOLocks.h>
#include <IOKit/IOService.h>
#include <kern/clock.h>
#include <kern/thread.h>
#include <libkern/OSAtomic.h>
#include <pexpert/pexpert.h>
#include <stdarg.h>
#include <string.h>
#include <sys/errno.h>
#include <sys/fcntl.h>
#include <sys/sysctl.h>
#include <sys/systm.h>
#include <sys/vnode.h>

#include "IOHIDDevice.h"
#include "SFHIDEventQueue.h"
#include "sf_adp.h"
#include "sf_gpio.h"
#include "sf_soc.h"
#include "sf_spi.h"
#include "sf_tb_keys.h"
#include "sf_z2.h"
#include "sf_touchbar_kbd.h"

extern "C" {
vnode_t vfs_rootvnode(void);
}

#define LOG(fmt, ...) IOLog("SFTouchBar: " fmt "\n", ##__VA_ARGS__)

#include "sf_board_gate.h"

#define T8103_CHIP_ID   0x8103
#define SPI0_PHYS       0x235100000ULL
#define SPI0_CLOCK_HZ   200000000u      /* clk_200m */
#define Z2_HZ           11500000u       /* spi-max-frequency */
#define PIN_SPI_CLK     67
#define PIN_SPI_MOSI    68
#define PIN_SPI_MISO    69
#define PIN_CS          109
#define PIN_RESET       139
#define PIN_IRQ         194
#define IRQ_GROUP       1
#define FIRMWARE_PATH   "/Library/Firmware/apple/dfrmtfw-j293.bin"
#define TOUCH_NODE      "/arm-io/spi0/multi-touch"
#define ROOT_WAIT_S     120

/* ---- the key device ------------------------------------------------------------------- */

class SFTouchBarKeys : public IOHIDDevice {
	OSDeclareDefaultStructors(SFTouchBarKeys);

public:
	bool handleStart(IOService *provider) APPLE_KEXT_OVERRIDE;
	IOReturn newReportDescriptor(IOMemoryDescriptor **descriptor) const APPLE_KEXT_OVERRIDE;
	OSString *newTransportString() const APPLE_KEXT_OVERRIDE;
	OSString *newManufacturerString() const APPLE_KEXT_OVERRIDE;
	OSString *newProductString() const APPLE_KEXT_OVERRIDE;
	OSNumber *newVendorIDNumber() const APPLE_KEXT_OVERRIDE;
	OSNumber *newProductIDNumber() const APPLE_KEXT_OVERRIDE;
	OSNumber *newVersionNumber() const APPLE_KEXT_OVERRIDE;
	OSNumber *newLocationIDNumber() const APPLE_KEXT_OVERRIDE;
	OSNumber *newCountryCodeNumber() const APPLE_KEXT_OVERRIDE;
};

OSDefineMetaClassAndStructors(SFTouchBarKeys, IOHIDDevice);

/* A boot keyboard without LEDs: modifier bits, a reserved byte, six usages. */
static const uint8_t kKeyboardDescriptor[] = {
	0x05, 0x01, 0x09, 0x06, 0xa1, 0x01,
	0x05, 0x07, 0x19, 0xe0, 0x29, 0xe7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
	0x95, 0x01, 0x75, 0x08, 0x81, 0x01,
	0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x26, 0xff, 0x00, 0x05, 0x07, 0x19, 0x00, 0x2a, 0xff, 0x00, 0x81, 0x00,
	0xc0,
};

bool
SFTouchBarKeys::handleStart(IOService *provider)
{
	if (!IOHIDDevice::handleStart(provider))
		return false;
	setProperty("HIDDefaultBehavior", kOSBooleanTrue);
	setProperty("Built-In", kOSBooleanTrue);
	return true;
}

IOReturn
SFTouchBarKeys::newReportDescriptor(IOMemoryDescriptor **descriptor) const
{
	if (descriptor == NULL)
		return kIOReturnBadArgument;
	*descriptor = IOBufferMemoryDescriptor::withBytes(kKeyboardDescriptor, sizeof(kKeyboardDescriptor), kIODirectionNone);
	return *descriptor ? kIOReturnSuccess : kIOReturnNoMemory;
}

/* Not Apple's vendor number: nothing in IOHIDFamily is to treat this as an Apple keyboard with an Fn row. */
OSString *SFTouchBarKeys::newTransportString() const { return OSString::withCString("SPI"); }
OSString *SFTouchBarKeys::newManufacturerString() const { return OSString::withCString("SiliconForest"); }
OSString *SFTouchBarKeys::newProductString() const { return OSString::withCString("Touch Bar keys (J293)"); }
OSNumber *SFTouchBarKeys::newVendorIDNumber() const { return OSNumber::withNumber(0x5044, 32); }
OSNumber *SFTouchBarKeys::newProductIDNumber() const { return OSNumber::withNumber(0x5442, 32); }
OSNumber *SFTouchBarKeys::newVersionNumber() const { return OSNumber::withNumber(1, 32); }
OSNumber *SFTouchBarKeys::newLocationIDNumber() const { return OSNumber::withNumber(0x35100000, 32); }
OSNumber *SFTouchBarKeys::newCountryCodeNumber() const { return OSNumber::withNumber((unsigned long long)0, 32); }

/* ---- state ---------------------------------------------------------------------------- */

enum { kOff, kStarting, kSurveyed, kDisplayFailed, kDisplayOnly, kReady };

static IOLock       *gLock, *gWait;
static IOService    *gService;
static SFTouchBarKeys *gKeyDev;
static SFAdp         gAdp;
static SFGpio        gGpio;
static SFSpi         gSpi;
static SFZ2          gZ2;
static struct tb_state gKeys;
static uint32_t     *gShadow;           /* the picture before it is copied to the panel's buffer */
static int           gState = kOff;
static char          gReason[160] = "";
static uint32_t      gLevel = 3;
static uint32_t      gDefaultLayer = TB_LAYER_MEDIA;    /* the layer while Fn is up */
static uint32_t      gHoldMs = 3000;    /* a held key is let go after this long without a finger report */
static uint64_t      gLastFingerMs;
/* told by the keyboard's driver, in any context; taken up by the thread */
static volatile UInt32 gKbdFn, gKbdFnKnown, gKbdActivity, gKbdNotes;
static uint32_t      gFnApplied, gFailsafes, gLayerChanges, gKbdWakes;
static uint32_t      gBright = 128;     /* brightness while in use */
static uint32_t      gDimMs = 30000, gOffMs = 60000;
static uint32_t      gDirect;
static uint32_t      gDcs = 1, gProbe;   /* at start: ask the panel over DSI; run the fetch probe */
static uint64_t      gLastTouchMs;
static uint8_t       gSwallowed[32];    /* fingers that came down while the strip was dark */
static uint8_t       gHeldUsages[6];
static struct { unsigned finger, state, x, y; int key; uint32_t count; } gLast;      /* the last finger record */
/* counters */
static volatile UInt32 gIrqPending, gIrqs, gIrqSpurious;
static bool          gIrqRegistered;
static uint32_t      gIrqVector, gIrqPolled, gKeyEvents, gHidReports, gHidErrors, gDirectEvents, gInjected,
                     gRedraws, gWakes, gFirmwareBytes, gCalBytes, gBootIrq, gUploadMs, gVblankHz;
static uint32_t      gFbCrc;
static char          gFetch[240] = "not run";
static char          gTrace[500] = "not run";       /* result of the last flush_probe */
static char          gPanel[320] = "not read";

static uint64_t
now_ms(void)
{
	uint64_t ns;
	absolutetime_to_nanoseconds(mach_absolute_time(), &ns);
	return ns / 1000000;
}

static void
set_state(int state, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(gReason, sizeof(gReason), fmt, ap);
	va_end(ap);
	gState = state;
	LOG("state: %s%s%s", state == kReady ? "ready" : state == kDisplayOnly ? "display-only" :
	    state == kDisplayFailed ? "display-failed" : state == kSurveyed ? "surveyed" : "starting",
	    gReason[0] ? ": " : "", gReason);
}

/* ---- keys out ------------------------------------------------------------------------- */

static void
deliver(const struct tb_event *ev, int n)
{
	for (int i = 0; i < n; i++) {
		uint8_t usage = ev[i].usage;
		int slot = -1;

		gKeyEvents++;
		for (int k = 0; k < 6; k++) {
			if (gHeldUsages[k] == (ev[i].down ? 0 : usage) && slot < 0)
				slot = k;
		}
		if (slot >= 0)
			gHeldUsages[slot] = ev[i].down ? usage : 0;
		if (gKeyDev == NULL || gDirect) {
			SFHIDPushKeyboardEvent(usage, ev[i].down != 0);
			gDirectEvents++;
			continue;
		}
		uint8_t report[8] = { 0, 0, gHeldUsages[0], gHeldUsages[1], gHeldUsages[2], gHeldUsages[3], gHeldUsages[4],
			gHeldUsages[5] };
		IOBufferMemoryDescriptor *md = IOBufferMemoryDescriptor::withBytes(report, sizeof(report), kIODirectionNone);
		IOReturn kr = md ? gKeyDev->handleReport(md, kIOHIDReportTypeInput) : kIOReturnNoMemory;
		OSSafeReleaseNULL(md);
		if (kr == kIOReturnSuccess) {
			gHidReports++;
		} else {
			gHidErrors++;
			if (gHidErrors <= 4)
				LOG("key report refused by IOHIDFamily: 0x%x", kr);
		}
	}
}

static void
redraw(void)
{
	if (!gAdp.up || gShadow == NULL)
		return;
	tb_render(&gKeys, gShadow);
	memcpy(gAdp.fb, gShadow, TB_FB_BYTES);
	gAdp.flush();
	gRedraws++;
}

/* Brightness for the time since the last touch: in use, dimmed, dark (tiny-dfr's timeouts). */
static void
light(void)
{
	uint64_t idle = now_ms() - gLastTouchMs;
	unsigned want = (gOffMs != 0 && idle >= gOffMs) ? 0 : (gDimMs != 0 && idle >= gDimMs) ? 1 : gBright;

	if (gAdp.up && gAdp.brightness != (int)want)
		gAdp.setBrightness(want);
}

/* One finger of a digitizer report, real or injected. gLock held. */
static void
tb_finger(__unused void *ctx, unsigned finger, unsigned state, unsigned x, unsigned y)
{
	struct tb_event ev[2 * TB_MAX_KEYS];
	bool touching = state == 3 || state == 4;       /* APPLE_Z2_TOUCH_STARTED, _MOVED */
	uint8_t bit = (uint8_t)(1u << (finger & 7));
	int changed = 0, n;

	finger &= 0xff;
	gLast.finger = finger;
	gLast.state = state;
	gLast.x = x;
	gLast.y = y;
	gLast.key = touching ? tb_key_at(gKeys.layer, (int)(((uint64_t)(x > TB_TOUCH_X ? TB_TOUCH_X : x) * TB_W) / (TB_TOUCH_X + 1))) : -1;
	gLast.count++;
	gLastFingerMs = now_ms();
	if (touching) {
		bool dark = gAdp.up && gAdp.brightness == 0;
		gLastTouchMs = now_ms();
		if (dark || (gSwallowed[finger >> 3] & bit)) {
			/* a touch on the dark strip lights it and presses nothing: the keys were not visible */
			if (dark) {
				gWakes++;
				light();
			}
			gSwallowed[finger >> 3] |= bit;
			return;
		}
	} else if (gSwallowed[finger >> 3] & bit) {
		gSwallowed[finger >> 3] &= (uint8_t)~bit;
		return;
	}
	n = tb_touch(&gKeys, finger, touching, x, TB_TOUCH_Y > y ? TB_TOUCH_Y - 1 - y : 0, ev, 2 * TB_MAX_KEYS, &changed);
	light();
	if (changed)
		redraw();
	deliver(ev, n);
}

/* What the keyboard's driver told and the held-key failsafe, once per turn of the thread. gLock held. */
static void
housekeeping(void)
{
	struct tb_event ev[TB_MAX_KEYS];
	int changed = 0, n = 0;

	if (OSCompareAndSwap(1, 0, &gKbdActivity)) {
		/* typing counts as use of the strip: it stays lit, and lights if it was dark */
		if (gAdp.up && gAdp.brightness == 0)
			gKbdWakes++;
		gLastTouchMs = now_ms();
	}
	gFnApplied = gKbdFn;
	unsigned want = gFnApplied ? (gDefaultLayer == TB_LAYER_MEDIA ? TB_LAYER_FN : TB_LAYER_MEDIA) : gDefaultLayer;
	if (want != gKeys.layer) {
		/* a key held on the strip is released before the layer changes under the finger */
		n = tb_set_layer(&gKeys, want, ev, TB_MAX_KEYS, &changed);
		gLayerChanges++;
	} else if (gHoldMs != 0 && now_ms() - gLastFingerMs > gHoldMs) {
		/* a finger whose lift was never reported must not hold its key for ever */
		bool held = false;
		for (int k = 0; k < 6; k++)
			held = held || gHeldUsages[k] != 0;
		if (held) {
			n = tb_drop_all(&gKeys, ev, TB_MAX_KEYS, &changed);
			gFailsafes++;
			LOG("a key was held for %u ms without a finger report: released", gHoldMs);
		}
	}
	if (changed)
		redraw();
	deliver(ev, n);
}

/* ---- the digitizer's interrupt -------------------------------------------------------- */

static void
gpio_interrupt(__unused OSObject *target, __unused void *refCon, __unused IOService *nub, __unused int source)
{
	if (gGpio.irqPending(PIN_IRQ, IRQ_GROUP)) {
		gGpio.irqAck(PIN_IRQ, IRQ_GROUP);
		OSIncrementAtomic(&gIrqs);
		OSCompareAndSwap(0, 1, &gIrqPending);
		thread_wakeup((event_t)&gIrqPending);
	} else {
		/* nothing else is known to use this group: whatever latched there must not keep the line up */
		gGpio.irqAckAll(IRQ_GROUP);
		OSIncrementAtomic(&gIrqSpurious);
	}
}

/* Waits up to `ms` for the digitizer's edge; true when there was one. gLock not held. */
static bool
wait_irq(unsigned ms)
{
	if (!OSCompareAndSwap(1, 0, &gIrqPending)) {
		/* as SFAppleSound's jack thread waits for its pin: the handler wakes the event */
		IOLockLock(gWait);
		if (!gIrqPending) {
			AbsoluteTime deadline;
			clock_interval_to_deadline(ms, kMillisecondScale, &deadline);
			IOLockSleepDeadline(gWait, (void *)&gIrqPending, deadline, THREAD_UNINT);
		}
		IOLockUnlock(gWait);
		if (!OSCompareAndSwap(1, 0, &gIrqPending)) {
			/* an edge the interrupt controller did not deliver is still latched in the block */
			if (!gGpio.irqPending(PIN_IRQ, IRQ_GROUP))
				return false;
			gGpio.irqAck(PIN_IRQ, IRQ_GROUP);
			gIrqPolled++;
		}
	}
	return true;
}

/* During the firmware upload gLock is held by the caller; the wait itself takes no lock. */
static void
upload_wait(unsigned ms)
{
	wait_irq(ms);
}

static void
irq_bring_up(void)
{
	gGpio.irqSetup(PIN_IRQ, IRQ_GROUP);
	if (sf_adt_u32("/arm-io/gpio", "interrupts", IRQ_GROUP, &gIrqVector) && gIrqVector != 0) {
		IOInterruptVectorNumber number = gIrqVector;
		const OSSymbol *controller = gIODTDefaultInterruptController;
		OSData *spec = OSData::withBytes(&number, sizeof(number));
		OSArray *controllers = OSArray::withObjects((const OSObject **)&controller, 1);
		OSArray *specs = spec ? OSArray::withObjects((const OSObject **)&spec, 1) : NULL;

		gIrqRegistered = controllers && specs && gService->setProperty(gIOInterruptControllersKey, controllers) &&
		    gService->setProperty(gIOInterruptSpecifiersKey, specs) &&
		    gService->registerInterrupt(0, gService, gpio_interrupt, NULL) == kIOReturnSuccess &&
		    gService->enableInterrupt(0) == kIOReturnSuccess;
		OSSafeReleaseNULL(spec);
		OSSafeReleaseNULL(controllers);
		OSSafeReleaseNULL(specs);
	}
	gGpio.irqAck(PIN_IRQ, IRQ_GROUP);
	gGpio.irqUnmask(PIN_IRQ, SFGpio::kIrqFalling);
	LOG("digitizer interrupt: gpio pin %u, group %u, AIC interrupt %u: %s", PIN_IRQ, IRQ_GROUP, gIrqVector,
	    gIrqRegistered ? "registered" : "NOT registered, the block's latch is polled");
}

/* ---- survey --------------------------------------------------------------------------- */

static void
hex(char *out, size_t size, const uint8_t *p, unsigned n)
{
	size_t at = 0;
	out[0] = 0;
	for (unsigned i = 0; i < n && at + 3 < size; i++)
		at += snprintf(out + at, size - at, "%02x", p[i]);
}

static bool
contains(const char *text, const char *part)
{
	size_t n = strlen(part);
	for (; *text != 0; text++) {
		if (strncmp(text, part, n) == 0)
			return true;
	}
	return false;
}

/* The Apple device tree's nodes of the Touch Bar: names, registers, interrupts, power domains. */
static void
survey_tree(void)
{
	static const uint32_t wanted[] = { 0x28200000, 0x28400000, 0x28304000, 0x28600000, 0x35100000 };
	IORegistryEntry *io = IORegistryEntry::fromPath("/arm-io", gIODTPlane);
	OSIterator *it = io ? io->getChildIterator(gIODTPlane) : NULL;
	OSObject *o;

	while (it != NULL && (o = it->getNextObject()) != NULL) {
		IORegistryEntry *e = OSDynamicCast(IORegistryEntry, o);
		OSData *reg = e ? OSDynamicCast(OSData, e->getProperty("reg")) : NULL;
		const char *name = e ? e->getName(gIODTPlane) : NULL;
		bool hit = name != NULL && (contains(name, "dfr") || contains(name, "mipi"));

		for (unsigned i = 0; reg != NULL && !hit && i + 8 <= reg->getLength(); i += 16) {
			uint32_t lo = OSReadLittleInt32(reg->getBytesNoCopy(), i);
			for (unsigned w = 0; w < sizeof(wanted) / sizeof(wanted[0]); w++)
				hit = hit || lo == wanted[w];
		}
		if (!hit)
			continue;
		OSData *compat = OSDynamicCast(OSData, e->getProperty("compatible"));
		OSData *irqs = OSDynamicCast(OSData, e->getProperty("interrupts"));
		OSData *gates = OSDynamicCast(OSData, e->getProperty("clock-gates"));
		char regText[100] = "", irqText[60] = "", gateText[60] = "";
		size_t at = 0;
		for (unsigned i = 0; reg != NULL && i + 16 <= reg->getLength() && at + 24 < sizeof(regText); i += 16)
			at += snprintf(regText + at, sizeof(regText) - at, " 0x%llx+0x%llx",
			    OSReadLittleInt64(reg->getBytesNoCopy(), i), OSReadLittleInt64(reg->getBytesNoCopy(), i + 8));
		at = 0;
		for (unsigned i = 0; irqs != NULL && i + 4 <= irqs->getLength() && at + 8 < sizeof(irqText); i += 4)
			at += snprintf(irqText + at, sizeof(irqText) - at, " %u", OSReadLittleInt32(irqs->getBytesNoCopy(), i));
		at = 0;
		for (unsigned i = 0; gates != NULL && i + 4 <= gates->getLength() && at + 12 < sizeof(gateText); i += 4)
			at += snprintf(gateText + at, sizeof(gateText) - at, " 0x%x", OSReadLittleInt32(gates->getBytesNoCopy(), i));
		LOG("tree: /arm-io/%s compatible=%.40s reg=%s interrupts=%s clock-gates=%s", name,
		    compat ? (const char *)compat->getBytesNoCopy() : "-", regText, irqText, gateText);
	}
	OSSafeReleaseNULL(it);
	OSSafeReleaseNULL(io);

	/* the digitizer's node: property names and sizes only (the calibration is this machine's) */
	IORegistryEntry *touch = IORegistryEntry::fromPath(TOUCH_NODE, gIODTPlane);
	OSDictionary *props = touch ? touch->dictionaryWithProperties() : NULL;
	OSCollectionIterator *pi = props ? OSCollectionIterator::withCollection(props) : NULL;
	char line[400] = "";
	size_t at = 0;
	while (pi != NULL && (o = pi->getNextObject()) != NULL) {
		OSSymbol *key = OSDynamicCast(OSSymbol, o);
		OSData *d = key ? OSDynamicCast(OSData, props->getObject(key)) : NULL;
		if (key != NULL && at + 40 < sizeof(line))
			at += snprintf(line + at, sizeof(line) - at, " %s(%u)", key->getCStringNoCopy(), d ? d->getLength() : 0);
	}
	LOG("tree: %s %s:%s", TOUCH_NODE, touch ? "present" : "ABSENT", line);
	OSSafeReleaseNULL(pi);
	OSSafeReleaseNULL(props);
	OSSafeReleaseNULL(touch);
	LOG("as the boot loader left it: pmgr SPI0=0x%08x", sf_pmgr_state_named("SPI0"));
	if (gGpio.regs.va != NULL)
		LOG("as the boot loader left it: gpio clk/mosi/miso=0x%x/0x%x/0x%x cs(%u)=0x%x reset(%u)=0x%x irq(%u)=0x%x",
		    gGpio.raw(PIN_SPI_CLK), gGpio.raw(PIN_SPI_MOSI), gGpio.raw(PIN_SPI_MISO), PIN_CS, gGpio.raw(PIN_CS),
		    PIN_RESET, gGpio.raw(PIN_RESET), PIN_IRQ, gGpio.raw(PIN_IRQ));
}

/* ---- files ---------------------------------------------------------------------------- */

static bool
root_mounted(void)
{
	vnode_t root = vfs_rootvnode();
	if (root == NULLVP)
		return false;
	vnode_put(root);
	return true;
}

/* The whole file in IOMalloc memory; 0 or an errno value. */
static int
read_file(const char *path, uint8_t **out, size_t *size)
{
	vfs_context_t ctx = vfs_context_create(NULL);
	vnode_t vp = NULLVP;
	struct vnode_attr va;
	uint8_t *buf = NULL;
	size_t len = 0;
	int resid = 0;
	int error = vnode_open(path, FREAD, 0, 0, &vp, ctx);

	if (error != 0) {
		vfs_context_rele(ctx);
		return error;
	}
	VATTR_INIT(&va);
	VATTR_WANTED(&va, va_data_size);
	error = vnode_getattr(vp, &va, ctx);
	if (error == 0 && (va.va_data_size < 16 || va.va_data_size > 4 * 1024 * 1024))
		error = EFBIG;
	if (error == 0) {
		len = (size_t)va.va_data_size;
		buf = (uint8_t *)IOMalloc(len);
		if (buf == NULL)
			error = ENOMEM;
	}
	if (error == 0) {
		error = vn_rdwr(UIO_READ, vp, (caddr_t)buf, (int)len, 0, UIO_SYSSPACE, 0, vfs_context_ucred(ctx), &resid,
		    vfs_context_proc(ctx));
		if (error == 0 && resid != 0)
			error = EIO;
	}
	vnode_close(vp, FREAD, ctx);
	vfs_context_rele(ctx);
	if (error != 0) {
		if (buf != NULL)
			IOFree(buf, len);
		return error;
	}
	*out = buf;
	*size = len;
	return 0;
}

/* ---- bring-up ------------------------------------------------------------------------- */

/* The fetch probe with the pipe as adp_drm_bind() leaves it and with it running. gLock held. */
static void
run_fetch_probe(unsigned ms)
{
	uint64_t idleAddr = 0, runAddr = 0;
	uint32_t idle = gAdp.fetchProbe(ms, false, &idleAddr);
	uint32_t run = gAdp.fetchProbe(ms, true, &runAddr);

	snprintf(gFetch, sizeof(gFetch), "%s: layer pointed at unmapped memory; pipe running: dart error=0x%08x address=0x%llx; "
	    "pipe idle: dart error=0x%08x address=0x%llx", run ? "FETCHED" : "NOT-FETCHED", run, runAddr, idle, idleAddr);
	LOG("fetch probe: %s", gFetch);
	IOSleep(60);
	gAdp.dart.check("after the fetch probe");
}

static bool
display_bring_up(void)
{
	char text[640];
	uint8_t r[6][2];
	int e[6], err;

	gShadow = (uint32_t *)IOMallocAligned(TB_FB_BYTES, 0x4000);
	err = gShadow ? gAdp.attach(TB_H, TB_W, TB_FB_LINE) : ENOMEM;
	if (err != 0) {
		set_state(kDisplayFailed, "display pipe: error %d", err);
		return false;
	}
	/* the panel's own answers over DSI before anything is sent to it */
	static const uint8_t kDcs[6] = { 0x0a, 0x52, 0x54, 0xda, 0xdb, 0xdc };  /* power mode, brightness, control, IDs */
	memset(r, 0, sizeof(r));
	for (int i = 0; gDcs && i < 6; i++)
		e[i] = gAdp.dcsRead(kDcs[i], r[i], i == 1 ? 2 : 1);
	redraw();
	gFbCrc = tb_crc32(gAdp.fb, TB_FB_BYTES);
	gLastTouchMs = now_ms();
	err = gAdp.setBrightness(gBright);
	/* give the pipe a few frames, then see whether it faulted fetching the new buffers */
	IOSleep(100);
	gAdp.dart.check("after the first frames");
	gVblankHz = gAdp.vblankHz(500);
	gAdp.describe(text, sizeof(text));
	LOG("display: %s", text);
	LOG("display: layer %u drawn, frame buffer crc32=%08x (%u bytes at iova 0x%x), brightness %u %s, "
	    "vertical blank flags %u per second, dart faults %u", gKeys.layer, gFbCrc, TB_FB_BYTES, gAdp.fbIova, gBright,
	    err ? "NOT accepted by the DSI host" : "sent", gVblankHz, gAdp.dart.faults);
	if (gDcs) {
		uint8_t lvl[2] = { 0, 0 };
		int e2 = gAdp.dcsRead(0x52, lvl, 2);
		snprintf(gPanel, sizeof(gPanel), "at start: power_mode=0x%02x(error %d) display_on=%d sleep_out=%d brightness=0x%02x%02x(%d) "
		    "control=0x%02x(%d) id=%02x/%02x/%02x(%d/%d/%d); after brightness %u was sent: brightness=0x%02x%02x(%d)",
		    r[0][0], e[0], (r[0][0] >> 2) & 1, (r[0][0] >> 4) & 1, r[1][1], r[1][0], e[1], r[2][0], e[2], r[3][0], r[4][0],
		    r[5][0], e[3], e[4], e[5], gBright, lvl[1], lvl[0], e2);
		LOG("panel: %s", gPanel);
	}
	/* does the pipe really fetch what the layer points at? */
	if (gProbe)
		run_fetch_probe(300);
	return true;
}

static bool
touch_bring_up(void)
{
	IORegistryEntry *node;
	OSData *cal;
	uint8_t *fw = NULL;
	size_t fwLen = 0;
	char before[40], after[40];
	int err;

	if (sf_pmgr_enable_named("SPI0", true) != 0) {
		set_state(kDisplayOnly, "SPI0 power domain");
		return false;
	}
	gGpio.function(PIN_SPI_CLK, 1);
	gGpio.function(PIN_SPI_MOSI, 1);
	gGpio.function(PIN_SPI_MISO, 1);
	if (!gSpi.attach(SPI0_PHYS, SPI0_CLOCK_HZ) || !gZ2.attach(&gSpi, &gGpio, PIN_CS, PIN_RESET, Z2_HZ)) {
		set_state(kDisplayOnly, "SPI0 controller");
		return false;
	}
	gZ2.finger = tb_finger;
	irq_bring_up();

	for (int i = 0; i < ROOT_WAIT_S * 10 && !root_mounted(); i++)
		IOSleep(100);
	err = root_mounted() ? read_file(FIRMWARE_PATH, &fw, &fwLen) : ENOENT;
	if (err != 0) {
		set_state(kDisplayOnly, "digitizer firmware %s: error %d", FIRMWARE_PATH, err);
		return false;
	}
	gFirmwareBytes = (uint32_t)fwLen;
	node = IORegistryEntry::fromPath(TOUCH_NODE, gIODTPlane);
	cal = node ? OSDynamicCast(OSData, node->getProperty("multi-touch-calibration")) : NULL;
	gCalBytes = cal ? cal->getLength() : 0;

	/* apple_z2_probe(): in reset for 5 to 10 ms; apple_z2_boot(): release, the device raises its line */
	IOLockLock(gLock);
	gZ2.reset(true);
	IOSleep(8);
	OSCompareAndSwap(1, 0, &gIrqPending);
	gGpio.irqAck(PIN_IRQ, IRQ_GROUP);
	gZ2.reset(false);
	gBootIrq = wait_irq(20) ? 1 : 0;
	if (!gBootIrq) {
		/* Linux gives up here; the line is looked at for a little longer before this does */
		gBootIrq = wait_irq(200) ? 2 : 0;
	}
	if (!gBootIrq) {
		gZ2.reset(true);
		IOLockUnlock(gLock);
		IOFree(fw, fwLen);
		OSSafeReleaseNULL(node);
		set_state(kDisplayOnly, "the digitizer did not signal after reset (irq pin 0x%x, %u interrupts)",
		    gGpio.raw(PIN_IRQ), gIrqs);
		return false;
	}
	/* what the boot ROM answers to a read request, for comparison with the firmware's answer */
	gZ2.readPacket();
	hex(before, sizeof(before), gZ2.lastHeader, 16);
	uint64_t t0 = now_ms();
	err = gZ2.upload(fw, fwLen, cal ? (const uint8_t *)cal->getBytesNoCopy() : NULL, gCalBytes, upload_wait);
	gUploadMs = (uint32_t)(now_ms() - t0);
	hex(after, sizeof(after), gZ2.lastHeader, 16);
	IOLockUnlock(gLock);
	IOFree(fw, fwLen);
	OSSafeReleaseNULL(node);
	LOG("digitizer: firmware %u bytes, calibration %u bytes, boot signal %s, %u blobs in %u ms, error %d; reply to a "
	    "read request before the firmware %s, after %s; interrupts %u (%u found in the latch); bus %u kbit/s", gFirmwareBytes, gCalBytes,
	    gBootIrq == 1 ? "within 20 ms" : "late", gZ2.blobs, gUploadMs, err, before, after, gIrqs, gIrqPolled, gSpi.kbps());
	if (err != 0) {
		set_state(kDisplayOnly, "digitizer firmware upload: error %d", err);
		return false;
	}
	return true;
}

static void
sf_touchbar_thread(__unused void *arg, __unused wait_result_t wr)
{
	bool display = false, touch = false;

	gGpio.attach("/arm-io/gpio");
	survey_tree();
	gAdp.survey();
	if (gLevel < 2) {
		set_state(kSurveyed, "sftouchbar=1: nothing written");
		thread_terminate(current_thread());
		return;
	}
	IOLockLock(gLock);
	display = display_bring_up();
	IOLockUnlock(gLock);

	/* the key device does not need the display: a strip that stays dark can still be felt for */
	SFTouchBarKeys *dev = OSTypeAlloc(SFTouchBarKeys);
	if (dev != NULL && dev->init(NULL) && dev->attach(gService) && dev->start(gService)) {
		gKeyDev = dev;
		LOG("keys: IOHIDDevice published (boot keyboard descriptor, %u bytes)", (unsigned)sizeof(kKeyboardDescriptor));
	} else {
		LOG("keys: IOHIDDevice did not start; keys go to the SFHID queue directly");
		if (dev != NULL) {
			dev->detach(gService);
			dev->release();
		}
	}

	if (gLevel >= 3 && gGpio.regs.va != NULL)
		touch = touch_bring_up();
	if (touch)
		set_state(kReady, "%s", display ? "" : "the display is down, the keys work blind");
	else if (display && gState != kDisplayOnly)
		set_state(kDisplayOnly, "%s", gLevel < 3 ? "sftouchbar=2" : "no gpio block");

	for (;;) {
		bool irq = touch ? wait_irq(20) : (IOSleep(20), false);

		IOLockLock(gLock);
		if (touch && gZ2.booted && (irq || gGpio.get(PIN_IRQ) == 0)) {
			/* one packet per edge; a second look catches a packet that came while the first was read */
			for (int i = 0; i < 4; i++) {
				uint32_t had = gZ2.replies;
				if (gZ2.readPacket() != 0 || gZ2.replies == had)
					break;
			}
		}
		housekeeping();
		light();
		gAdp.tick();
		IOLockUnlock(gLock);
	}
}

/* ---- sysctl --------------------------------------------------------------------------- */

enum {
	kCtlLevel, kCtlLayer, kCtlDefaultLayer, kCtlFn, kCtlFnKnown, kCtlHoldMs, kCtlFailsafes, kCtlKbdNotes, kCtlKbdWakes,
	kCtlKbdReport, kCtlLayerChanges, kCtlBrightness, kCtlActual, kCtlDimMs, kCtlOffMs, kCtlIrqs, kCtlIrqPolled, kCtlPolls,
	kCtlReplies, kCtlReports, kCtlBadReports, kCtlFingers, kCtlSpiErrors, kCtlSpiTimeouts, kCtlKeyEvents,
	kCtlHidReports, kCtlHidErrors, kCtlDirect, kCtlInjected, kCtlFlushes, kCtlRedraws, kCtlDartFaults, kCtlDsiErrors,
	kCtlVblankHz, kCtlWakes, kCtlZ2Poll, kCtlFetchProbe, kCtlIdleMs, kCtlFlushProbe,
	kCtlState, kCtlDisplay, kCtlTouch, kCtlKeys, kCtlFbCrc, kCtlFetch, kCtlPanel, kCtlInject, kCtlTrace, kCtlLast,
};

static int
sf_sysctl_int(struct sysctl_oid *oidp, __unused void *arg1, int arg2, struct sysctl_req *req)
{
	int value = 0, error;

	IOLockLock(gLock);
	switch (arg2) {
	case kCtlLevel: value = (int)gLevel; break;
	case kCtlLayer: value = gKeys.layer; break;
	case kCtlDefaultLayer: value = (int)gDefaultLayer; break;
	case kCtlFn: value = (int)gKbdFn; break;
	case kCtlFnKnown: value = (int)gKbdFnKnown; break;
	case kCtlHoldMs: value = (int)gHoldMs; break;
	case kCtlFailsafes: value = (int)gFailsafes; break;
	case kCtlKbdNotes: value = (int)gKbdNotes; break;
	case kCtlKbdWakes: value = (int)gKbdWakes; break;
	case kCtlLayerChanges: value = (int)gLayerChanges; break;
	case kCtlBrightness: value = (int)gBright; break;
	case kCtlActual: value = gAdp.brightness; break;
	case kCtlDimMs: value = (int)gDimMs; break;
	case kCtlOffMs: value = (int)gOffMs; break;
	case kCtlIrqs: value = (int)gIrqs; break;
	case kCtlIrqPolled: value = (int)gIrqPolled; break;
	case kCtlPolls: value = (int)gZ2.polls; break;
	case kCtlReplies: value = (int)gZ2.replies; break;
	case kCtlReports: value = (int)gZ2.reports; break;
	case kCtlBadReports: value = (int)gZ2.badReports; break;
	case kCtlFingers: value = (int)gZ2.fingersSeen; break;
	case kCtlSpiErrors: value = (int)gZ2.spiErrors; break;
	case kCtlSpiTimeouts: value = (int)gSpi.timeouts; break;
	case kCtlKeyEvents: value = (int)gKeyEvents; break;
	case kCtlHidReports: value = (int)gHidReports; break;
	case kCtlHidErrors: value = (int)gHidErrors; break;
	case kCtlDirect: value = (int)gDirectEvents; break;
	case kCtlInjected: value = (int)gInjected; break;
	case kCtlFlushes: value = (int)gAdp.flushes; break;
	case kCtlRedraws: value = (int)gRedraws; break;
	case kCtlDartFaults: gAdp.dart.check("sysctl"); value = (int)gAdp.dart.faults; break;
	case kCtlDsiErrors: value = (int)gAdp.dsiErrors; break;
	case kCtlVblankHz: value = (int)gVblankHz; break;
	case kCtlWakes: value = (int)gWakes; break;
	case kCtlIdleMs: value = (int)(now_ms() - gLastTouchMs); break;
	default: break;
	}
	IOLockUnlock(gLock);
	error = sysctl_handle_int(oidp, &value, 0, req);
	if (error != 0 || req->newptr == USER_ADDR_NULL)
		return error;
	if (arg2 == kCtlKbdReport) {
		/*
		 * For tests: the keyboard's driver makes up a keyboard report with the Fn bit as given
		 * and looks at it as at one the keyboard sent. Then the thread gets a turn.
		 */
		OSDictionary *match = IOService::serviceMatching(kSFKeyboardServiceClass);
		IOService *kbd = match ? IOService::copyMatchingService(match) : NULL;
		IOReturn kr = kbd ? kbd->message(kSFTouchBarTestKeyboardReport, gService, (void *)(uintptr_t)(value & 1)) : kIOReturnNotFound;
		OSSafeReleaseNULL(match);
		OSSafeReleaseNULL(kbd);
		if (kr == kIOReturnSuccess) {
			IOLockLock(gLock);
			housekeeping();
			light();
			IOLockUnlock(gLock);
		}
		return kr == kIOReturnSuccess ? 0 : kr == kIOReturnNotFound ? ENOENT : kr == kIOReturnUnsupported ? ENOTSUP : EIO;
	}

	IOLockLock(gLock);
	switch (arg2) {
	case kCtlDefaultLayer:
		if (value < 0 || value >= TB_LAYERS) {
			error = EINVAL;
			break;
		}
		gDefaultLayer = (uint32_t)value;
		housekeeping();
		break;
	case kCtlHoldMs:
		if (value < 0) {
			error = EINVAL;
			break;
		}
		gHoldMs = (uint32_t)value;
		break;
	case kCtlBrightness:
		if (value < 1 || value > 255) {
			error = EINVAL;
			break;
		}
		gBright = (uint32_t)value;
		gLastTouchMs = now_ms();
		light();
		break;
	case kCtlDimMs:
	case kCtlOffMs:
		if (value < 0) {
			error = EINVAL;
			break;
		}
		*(arg2 == kCtlDimMs ? &gDimMs : &gOffMs) = (uint32_t)value;
		light();
		break;
	case kCtlVblankHz:
		gVblankHz = gAdp.vblankHz(1000);
		break;
	case kCtlZ2Poll:
		/* one read request to the digitizer: its answer is in kern.sf_touchbar.touch */
		error = gZ2.booted ? gZ2.readPacket() : ENXIO;
		break;
	case kCtlFlushProbe:
		gAdp.flushTrace(gTrace, sizeof(gTrace));
		break;
	case kCtlFetchProbe:
		if (!gAdp.up || value < 20 || value > 2000) {
			error = EINVAL;
			break;
		}
		run_fetch_probe((unsigned)value);
		break;
	default:
		error = EPERM;
		break;
	}
	IOLockUnlock(gLock);
	return error;
}

static int
sf_sysctl_string(__unused struct sysctl_oid *oidp, __unused void *arg1, int arg2, struct sysctl_req *req)
{
	char text[900];
	size_t at = 0;

	text[0] = 0;
	IOLockLock(gLock);
	switch (arg2) {
	case kCtlState:
		snprintf(text, sizeof(text), "%s%s%s", gState == kReady ? "ready" : gState == kDisplayOnly ? "display-only" :
		    gState == kDisplayFailed ? "display-failed" : gState == kSurveyed ? "surveyed" : gState == kStarting ?
		    "starting" : "off", gReason[0] ? ": " : "", gReason);
		break;
	case kCtlDisplay:
		gAdp.describe(text, sizeof(text));
		break;
	case kCtlTouch: {
		char hdr[40], rep[70];
		hex(hdr, sizeof(hdr), gZ2.lastHeader, 16);
		hex(rep, sizeof(rep), gZ2.lastReport, gZ2.lastReportLen < 32 ? gZ2.lastReportLen : 32);
		snprintf(text, sizeof(text), "booted=%d firmware_bytes=%u calibration_bytes=%u boot_signal=%u blobs=%u upload_ms=%u "
		    "irq_registered=%d irqs=%u irq_spurious=%u irq_polled=%u polls=%u replies=%u reports=%u bad_reports=%u fingers=%u "
		    "spi_errors=%u spi_timeouts=%u spi_kbps=%u irq_pin=%d last_header=%s last_report_len=%u last_report=%s", gZ2.booted,
		    gFirmwareBytes, gCalBytes, gBootIrq, gZ2.blobs, gUploadMs, gIrqRegistered, gIrqs, gIrqSpurious, gIrqPolled, gZ2.polls,
		    gZ2.replies, gZ2.reports, gZ2.badReports, gZ2.fingersSeen, gZ2.spiErrors, gSpi.timeouts, gSpi.kbps(),
		    gGpio.regs.va ? gGpio.get(PIN_IRQ) : -1, hdr, gZ2.lastReportLen, rep);
		break;
	}
	case kCtlKeys:
		/* the current layer: usage (hex) and the digitizer x of each key's middle */
		for (unsigned i = 0; i < tb_key_count(gKeys.layer) && at + 16 < sizeof(text); i++)
			at += snprintf(text + at, sizeof(text) - at, "%s%02x:%u", i ? " " : "", tb_key(gKeys.layer, i)->usage,
			    tb_key_touch_x(tb_key(gKeys.layer, i)));
		break;
	case kCtlFbCrc:
		snprintf(text, sizeof(text), "%08x", gAdp.up ? tb_crc32(gAdp.fb, TB_FB_BYTES) : 0);
		break;
	case kCtlFetch:
		strlcpy(text, gFetch, sizeof(text));
		break;
	case kCtlPanel:
		strlcpy(text, gPanel, sizeof(text));
		break;
	case kCtlTrace:
		strlcpy(text, gTrace, sizeof(text));
		break;
	case kCtlLast:
		/* the last finger record: where it was in the digitizer's units and which key is there */
		if (gLast.key >= 0)
			snprintf(text, sizeof(text), "n=%u finger=%u state=%u x=%u y=%u key=%d usage=%02x", gLast.count, gLast.finger,
			    gLast.state, gLast.x, gLast.y, gLast.key, tb_key(gKeys.layer, (unsigned)gLast.key)->usage);
		else
			snprintf(text, sizeof(text), "n=%u finger=%u state=%u x=%u y=%u key=none", gLast.count, gLast.finger,
			    gLast.state, gLast.x, gLast.y);
		break;
	default:
		break;
	}
	IOLockUnlock(gLock);
	return SYSCTL_OUT(req, text, strlen(text) + 1);
}

/*
 * kern.sf_touchbar.inject="<finger> <state> <x> <y>": one finger of a digitizer report, in
 * the digitizer's own units and states (3 started, 4 moved, anything else lifted), built
 * into a report and handed to the parser the real packets go through. For tests.
 */
static int
sf_sysctl_inject(__unused struct sysctl_oid *oidp, __unused void *arg1, __unused int arg2, struct sysctl_req *req)
{
	char text[64] = "";
	unsigned v[4] = { 0, 0, 0, 0 }, n = 0;
	uint8_t msg[24 + 30];
	int error = sysctl_handle_string(oidp, text, sizeof(text), req);

	if (error != 0 || req->newptr == USER_ADDR_NULL)
		return error;
	for (const char *p = text; *p != 0 && n < 4;) {
		while (*p == ' ')
			p++;
		if (*p < '0' || *p > '9')
			break;
		unsigned value = 0;
		while (*p >= '0' && *p <= '9')
			value = value * 10 + (unsigned)(*p++ - '0');
		v[n++] = value;
	}
	if (n != 4 || v[0] > 255 || v[1] > 255 || v[2] > 0xffff || v[3] > 0xffff)
		return EINVAL;
	memset(msg, 0, sizeof(msg));
	msg[16] = 1;                                    /* APPLE_Z2_NUM_FINGERS_OFFSET */
	msg[24] = (uint8_t)v[0];                        /* struct apple_z2_finger */
	msg[25] = (uint8_t)v[1];
	msg[28] = (uint8_t)v[2];
	msg[29] = (uint8_t)(v[2] >> 8);
	msg[30] = (uint8_t)v[3];
	msg[31] = (uint8_t)(v[3] >> 8);
	IOLockLock(gLock);
	if (gState < kDisplayFailed) {
		IOLockUnlock(gLock);
		return ENXIO;
	}
	gInjected++;
	gZ2.finger = tb_finger;
	gZ2.parse(msg, sizeof(msg));
	IOLockUnlock(gLock);
	return 0;
}

SYSCTL_DECL(_kern);
SYSCTL_NODE(_kern, OID_AUTO, sf_touchbar, CTLFLAG_RD | CTLFLAG_LOCKED, 0, "Touch Bar");

#define SF_INT(name, id, flags, text) \
	SYSCTL_PROC(_kern_sf_touchbar, OID_AUTO, name, CTLTYPE_INT | (flags) | CTLFLAG_LOCKED, 0, id, sf_sysctl_int, "I", text)
#define SF_STR(name, id, text) \
	SYSCTL_PROC(_kern_sf_touchbar, OID_AUTO, name, CTLTYPE_STRING | CTLFLAG_RD | CTLFLAG_LOCKED, 0, id, sf_sysctl_string, "A", text)

SF_STR(state, kCtlState, "off, starting, surveyed, display-failed, display-only or ready, with the reason");
SF_STR(display, kCtlDisplay, "display pipe registers read back");
SF_STR(touch, kCtlTouch, "digitizer protocol counters and the last answers");
SF_STR(keys, kCtlKeys, "the current layer's keys: usage:digitizer-x");
SF_STR(fb_crc, kCtlFbCrc, "CRC-32 of the frame buffer the panel scans out");
SF_STR(fetch, kCtlFetch, "result of the last fetch probe");
SF_STR(panel, kCtlPanel, "the panel's answers to DCS reads at start");
SF_STR(trace, kCtlTrace, "result of the last flush_probe");
SF_STR(last_touch, kCtlLast, "the last finger record, real or injected");
SF_INT(level, kCtlLevel, CTLFLAG_RD, "sftouchbar boot argument");
SF_INT(layer, kCtlLayer, CTLFLAG_RD, "the layer shown: 0 function keys, 1 media keys");
SF_INT(default_layer, kCtlDefaultLayer, CTLFLAG_RW, "the layer while the keyboard's Fn key is up (0 function keys, 1 media keys)");
SF_INT(fn, kCtlFn, CTLFLAG_RD, "the keyboard's Fn key as its driver last told");
SF_INT(fn_known, kCtlFnKnown, CTLFLAG_RD, "1 once the keyboard's driver has said where Fn is in its reports");
SF_INT(hold_ms, kCtlHoldMs, CTLFLAG_RW, "a held key is released after this long without a finger report (0 never)");
SF_INT(failsafes, kCtlFailsafes, CTLFLAG_RD, "times a held key was released for want of finger reports");
SF_INT(kbd_notes, kCtlKbdNotes, CTLFLAG_RD, "messages from the keyboard's driver");
SF_INT(kbd_wakes, kCtlKbdWakes, CTLFLAG_RD, "times typing lit the dark strip");
SF_INT(layer_changes, kCtlLayerChanges, CTLFLAG_RD, "layer changes");
SF_INT(kbd_report, kCtlKbdReport, CTLFLAG_RW, "write 0|1: the keyboard's driver takes a made-up report with Fn up|down");
SF_INT(brightness, kCtlBrightness, CTLFLAG_RW, "panel brightness while in use, 1..255");
SF_INT(actual_brightness, kCtlActual, CTLFLAG_RD, "brightness last sent to the panel");
SF_INT(dim_ms, kCtlDimMs, CTLFLAG_RW, "time without a touch until the strip dims (0 never)");
SF_INT(off_ms, kCtlOffMs, CTLFLAG_RW, "time without a touch until the strip goes dark (0 never)");
SF_INT(idle_ms, kCtlIdleMs, CTLFLAG_RD, "time since the last touch");
SF_INT(irqs, kCtlIrqs, CTLFLAG_RD, "digitizer interrupts taken");
SF_INT(irq_polled, kCtlIrqPolled, CTLFLAG_RD, "digitizer edges found in the GPIO latch without an interrupt");
SF_INT(polls, kCtlPolls, CTLFLAG_RD, "read requests sent to the digitizer");
SF_INT(replies, kCtlReplies, CTLFLAG_RD, "read requests answered with data");
SF_INT(reports, kCtlReports, CTLFLAG_RD, "digitizer reports read");
SF_INT(bad_reports, kCtlBadReports, CTLFLAG_RD, "digitizer reports with an impossible length or finger count");
SF_INT(fingers, kCtlFingers, CTLFLAG_RD, "finger records parsed (real and injected)");
SF_INT(spi_errors, kCtlSpiErrors, CTLFLAG_RD, "failed SPI transfers");
SF_INT(spi_timeouts, kCtlSpiTimeouts, CTLFLAG_RD, "SPI transfers that timed out");
SF_INT(key_events, kCtlKeyEvents, CTLFLAG_RD, "key presses and releases produced");
SF_INT(hid_reports, kCtlHidReports, CTLFLAG_RD, "keyboard reports IOHIDFamily accepted");
SF_INT(hid_errors, kCtlHidErrors, CTLFLAG_RD, "keyboard reports IOHIDFamily refused");
SF_INT(direct_events, kCtlDirect, CTLFLAG_RD, "key events pushed into the SFHID queue directly");
SF_INT(injected, kCtlInjected, CTLFLAG_RD, "finger records injected through kern.sf_touchbar.inject");
SF_INT(flushes, kCtlFlushes, CTLFLAG_RD, "frames presented");
SF_INT(redraws, kCtlRedraws, CTLFLAG_RD, "times the strip was drawn");
SF_INT(dart_faults, kCtlDartFaults, CTLFLAG_RD, "DART faults outside the fetch probe");
SF_INT(dsi_errors, kCtlDsiErrors, CTLFLAG_RD, "DSI commands that failed");
SF_INT(vblank_hz, kCtlVblankHz, CTLFLAG_RW, "vertical blank flags per second; a write measures again");
SF_INT(wakes, kCtlWakes, CTLFLAG_RD, "touches that only lit the dark strip");
SF_INT(z2_poll, kCtlZ2Poll, CTLFLAG_RW, "write: send one read request to the digitizer");
SF_INT(fetch_probe, kCtlFetchProbe, CTLFLAG_RW, "write <ms>: point the layer at unmapped memory for that long");
SF_INT(flush_probe, kCtlFlushProbe, CTLFLAG_RW, "write: present a frame and watch the front end; result in trace");
SYSCTL_PROC(_kern_sf_touchbar, OID_AUTO, inject, CTLTYPE_STRING | CTLFLAG_RW | CTLFLAG_LOCKED, 0, kCtlInject,
    sf_sysctl_inject, "A", "write \"finger state x y\": one finger of a digitizer report");

static struct sysctl_oid *const gOids[] = {
	&sysctl__kern_sf_touchbar,
	&sysctl__kern_sf_touchbar_state, &sysctl__kern_sf_touchbar_display, &sysctl__kern_sf_touchbar_touch,
	&sysctl__kern_sf_touchbar_keys, &sysctl__kern_sf_touchbar_fb_crc, &sysctl__kern_sf_touchbar_fetch,
	&sysctl__kern_sf_touchbar_panel, &sysctl__kern_sf_touchbar_level, &sysctl__kern_sf_touchbar_layer,
	&sysctl__kern_sf_touchbar_default_layer, &sysctl__kern_sf_touchbar_fn, &sysctl__kern_sf_touchbar_fn_known,
	&sysctl__kern_sf_touchbar_hold_ms, &sysctl__kern_sf_touchbar_failsafes, &sysctl__kern_sf_touchbar_kbd_notes,
	&sysctl__kern_sf_touchbar_kbd_wakes, &sysctl__kern_sf_touchbar_layer_changes, &sysctl__kern_sf_touchbar_kbd_report,
	&sysctl__kern_sf_touchbar_brightness, &sysctl__kern_sf_touchbar_actual_brightness,
	&sysctl__kern_sf_touchbar_dim_ms, &sysctl__kern_sf_touchbar_off_ms, &sysctl__kern_sf_touchbar_idle_ms,
	&sysctl__kern_sf_touchbar_irqs, &sysctl__kern_sf_touchbar_irq_polled, &sysctl__kern_sf_touchbar_polls,
	&sysctl__kern_sf_touchbar_replies, &sysctl__kern_sf_touchbar_reports, &sysctl__kern_sf_touchbar_bad_reports,
	&sysctl__kern_sf_touchbar_fingers, &sysctl__kern_sf_touchbar_spi_errors, &sysctl__kern_sf_touchbar_spi_timeouts,
	&sysctl__kern_sf_touchbar_key_events, &sysctl__kern_sf_touchbar_hid_reports, &sysctl__kern_sf_touchbar_hid_errors,
	&sysctl__kern_sf_touchbar_direct_events, &sysctl__kern_sf_touchbar_injected, &sysctl__kern_sf_touchbar_flushes,
	&sysctl__kern_sf_touchbar_redraws, &sysctl__kern_sf_touchbar_dart_faults, &sysctl__kern_sf_touchbar_dsi_errors,
	&sysctl__kern_sf_touchbar_vblank_hz, &sysctl__kern_sf_touchbar_wakes, &sysctl__kern_sf_touchbar_z2_poll,
	&sysctl__kern_sf_touchbar_fetch_probe, &sysctl__kern_sf_touchbar_inject, &sysctl__kern_sf_touchbar_trace,
	&sysctl__kern_sf_touchbar_last_touch,
	&sysctl__kern_sf_touchbar_flush_probe,
};

/* ---- the service ---------------------------------------------------------------------- */

class SFAppleTouchBar : public IOService {
	OSDeclareDefaultStructors(SFAppleTouchBar);

public:
	bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
	void systemWillShutdown(IOOptionBits specifier) APPLE_KEXT_OVERRIDE;
	IOReturn message(UInt32 type, IOService *provider, void *argument = NULL) APPLE_KEXT_OVERRIDE;
};

OSDefineMetaClassAndStructors(SFAppleTouchBar, IOService);

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
SFAppleTouchBar::start(IOService *provider)
{
	IORegistryEntry *chosen, *touch;
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
	touch = IORegistryEntry::fromPath(TOUCH_NODE, gIODTPlane);
	if (chipID != T8103_CHIP_ID || touch == NULL) {
		LOG("chip 0x%x %s %s: not a T8103 machine with a Touch Bar; nothing is done", chipID,
		    touch ? "with" : "without", TOUCH_NODE);
		OSSafeReleaseNULL(touch);
		return false;
	}
	OSSafeReleaseNULL(touch);
	if (!sf_on_j293()) {
		LOG("not a J293: no Touch Bar here; nothing is done");
		return false;
	}

	PE_parse_boot_argn("sftouchbar", &gLevel, sizeof(gLevel));
	if (PE_parse_boot_argn("sftouchbar_bright", &value, sizeof(value)) && value >= 1 && value <= 255)
		gBright = value;
	if (PE_parse_boot_argn("sftouchbar_dim", &value, sizeof(value)) && value <= 86400)
		gDimMs = value * 1000;
	if (PE_parse_boot_argn("sftouchbar_off", &value, sizeof(value)) && value <= 86400)
		gOffMs = value * 1000;
	PE_parse_boot_argn("sftouchbar_direct", &gDirect, sizeof(gDirect));
	PE_parse_boot_argn("sftouchbar_dcs", &gDcs, sizeof(gDcs));
	PE_parse_boot_argn("sftouchbar_probe", &gProbe, sizeof(gProbe));
	if (gLevel == 0) {
		LOG("off (sftouchbar=0)");
		return false;
	}
	gLock = IOLockAlloc();
	gWait = IOLockAlloc();
	if (gLock == NULL || gWait == NULL)
		return false;
	gService = this;
	tb_init(&gKeys);
	char which[16] = "";
	if (PE_parse_boot_argn("sftouchbar_default", which, sizeof(which)) && strcmp(which, "fn") == 0)
		gDefaultLayer = TB_LAYER_FN;
	if (PE_parse_boot_argn("sftouchbar_hold", &value, sizeof(value)) && value <= 3600)
		gHoldMs = value * 1000;
	gKeys.layer = (uint8_t)gDefaultLayer;
	gState = kStarting;
	for (unsigned i = 0; i < sizeof(gOids) / sizeof(gOids[0]); i++)
		sysctl_register_oid(gOids[i]);
	if (kernel_thread_start(sf_touchbar_thread, NULL, &thread) != KERN_SUCCESS)
		return false;
	thread_deallocate(thread);
	registerService();
	return true;
}

/*
 * From the keyboard's driver, on its own work loop: nothing is done here but to note the
 * state and wake the thread, so the keyboard never waits for the Touch Bar.
 */
IOReturn
SFAppleTouchBar::message(UInt32 type, IOService *provider, void *argument)
{
	if (type != kSFTouchBarKeyboardMessage)
		return IOService::message(type, provider, argument);
	uintptr_t word = (uintptr_t)argument;
	gKbdFn = (word & kSFTouchBarKeyboardFn) ? 1 : 0;
	if (word & kSFTouchBarKeyboardFnKnown)
		gKbdFnKnown = 1;
	if (word & kSFTouchBarKeyboardActivity)
		gKbdActivity = 1;
	OSIncrementAtomic(&gKbdNotes);
	if (gWait != NULL) {
		IOLockLock(gWait);
		IOLockWakeup(gWait, (void *)&gIrqPending, true);
		IOLockUnlock(gWait);
	}
	return kIOReturnSuccess;
}

/* A strip left lit by a system that is gone would burn in: dark, and the digitizer in reset. */
void
SFAppleTouchBar::systemWillShutdown(IOOptionBits specifier)
{
	if (gLock != NULL) {
		IOLockLock(gLock);
		gOffMs = 1;
		gDimMs = 0;
		gLastTouchMs = 0;
		if (gAdp.up)
			gAdp.setBrightness(0);
		if (gZ2.gpio != NULL)
			gZ2.reset(true);
		IOLockUnlock(gLock);
	}
	IOService::systemWillShutdown(specifier);
}
