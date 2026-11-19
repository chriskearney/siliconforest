/* SPDX-License-Identifier: MIT */
#include <CoreFoundation/CFCalendar.h>
#include <stdint.h>
/* Exact declarations from the open CFCalendar_Internal.h (CoreFoundation1338). */
Boolean _CFCalendarComposeAbsoluteTimeV(CFCalendarRef calendar, CFAbsoluteTime *atp,
    const char *componentDesc, int32_t *vector, int32_t count);
Boolean _CFCalendarDecomposeAbsoluteTimeV(CFCalendarRef calendar, CFAbsoluteTime at,
    const char *componentDesc, int32_t *_Nonnull *_Nonnull vector, int32_t count);
