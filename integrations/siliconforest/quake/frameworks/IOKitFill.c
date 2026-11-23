// SPDX-License-Identifier: MIT
// The two IOKit calls QuakeSpasm imports that SiliconForest's IOKit does not
// export. The engine uses them to read and set the system mouse acceleration.
// SiliconForest has no such setting behind this API, so both report that it is
// unsupported and change nothing. Everything else re-exports the real IOKit.
#include <stdint.h>

#define kIOReturnUnsupported ((int32_t)0xe00002c7)

__attribute__((visibility("default")))
int32_t IOHIDGetAccelerationWithKey(uint32_t handle, const void *key, double *acceleration)
{
    (void)handle;
    (void)key;
    (void)acceleration;
    return kIOReturnUnsupported;
}

__attribute__((visibility("default")))
int32_t IOHIDSetAccelerationWithKey(uint32_t handle, const void *key, double acceleration)
{
    (void)handle;
    (void)key;
    (void)acceleration;
    return kIOReturnUnsupported;
}
