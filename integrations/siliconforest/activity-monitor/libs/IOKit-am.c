// SPDX-License-Identifier: MIT
// What Apple's Activity Monitor imports from IOKit beyond what this system's IOKit has
// (docs/roadmap/issues/SF-AA-activity-monitor.md); built into an IOKit wrapper that re-exports the
// real library (kept beside it as IOKit.pd).
// There is no power-management daemon here: no assertion activity is recorded, and no power
// source (battery, UPS) is known to the system.
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>
#define EXPORT __attribute__((visibility("default")))
typedef int IOReturn;
EXPORT CFDictionaryRef IOPMCopyAssertionActivityAggregate(void) { return NULL; }
EXPORT IOReturn IOPMSetAssertionActivityAggregate(bool enable) { (void)enable; return 0; }
EXPORT IOReturn IOPSGetSupportedPowerSources(int *active, bool *battery, bool *ups)
{
	if (active) *active = 0;
	if (battery) *battery = false;
	if (ups) *ups = false;
	return 0;
}
// (bake-in step 9b) Additive HID modifier lock state stub (kIOReturnUnsupported = 0xe00002c7)
// formerly supplied only in ChonkCraft's fills.py.
EXPORT IOReturn IOHIDSetModifierLockState(unsigned connect, int selector, int state)
{
	(void)connect;
	(void)selector;
	(void)state;
	return (IOReturn)0xe00002c7;
}
