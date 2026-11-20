/* SPDX-License-Identifier: MIT OR Apache-2.0 */
#import <Foundation/Foundation.h>
#include <stdio.h>
#import "SFNSUnit.h"
#include "Foundation_Finch.h"

NSMeasurement *SFMeasurementByConverting(NSMeasurement *measurement, NSUnit *unit) {
    return [measurement measurementByConvertingToUnit:unit];
}

void FinchRaise(NSString *name, const char *format, ...) {
    char buffer[512];
    va_list ap;
    va_start(ap, format);
    vsnprintf(buffer, sizeof buffer, format, ap);
    va_end(ap);
    [NSException raise:name format:@"%s", buffer];
    __builtin_unreachable();
}
