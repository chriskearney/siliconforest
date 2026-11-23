// SPDX-License-Identifier: MIT
// ForceFeedback for the Mac build of SDL2 that QuakeSpasm ships. SDL2 links this
// framework unconditionally; SiliconForest has no force-feedback devices. Every
// call reports that the device has no such interface, so SDL's haptic layer finds
// nothing. Nothing here claims a device or an effect.
#include <stdint.h>

#define FFERR_NOINTERFACE ((int32_t)0x80004002)
#define NOFF(name) \
    __attribute__((visibility("default"))) int32_t name(void) { return FFERR_NOINTERFACE; }

NOFF(FFCreateDevice)
NOFF(FFDeviceCreateEffect)
NOFF(FFDeviceGetForceFeedbackCapabilities)
NOFF(FFDeviceGetForceFeedbackProperty)
NOFF(FFDeviceReleaseEffect)
NOFF(FFDeviceSendForceFeedbackCommand)
NOFF(FFDeviceSetForceFeedbackProperty)
NOFF(FFEffectGetEffectStatus)
NOFF(FFEffectSetParameters)
NOFF(FFEffectStart)
NOFF(FFEffectStop)
NOFF(FFIsForceFeedback)
NOFF(FFReleaseDevice)
