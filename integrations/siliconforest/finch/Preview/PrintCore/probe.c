// SPDX-License-Identifier: MIT
#include <CoreFoundation/CoreFoundation.h>
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>

int32_t PMRelease(CFTypeRef);
int32_t PMCreateSession(CFMutableDictionaryRef *);
int32_t PMCreatePageFormat(CFMutableDictionaryRef *);
int32_t PMGetCopies(CFMutableDictionaryRef, uint32_t *);
int32_t PMPrintSettingsCreateWithDataRepresentation(CFDataRef, CFMutableDictionaryRef *);
int32_t PMPrintSettingsGetValue(CFMutableDictionaryRef, CFStringRef, CFTypeRef *);
int32_t PMPrintSettingsSetValue(CFMutableDictionaryRef, CFStringRef, CFTypeRef, Boolean);
int32_t PMSessionSetDataInSession(CFMutableDictionaryRef, CFStringRef, CFTypeRef);
int32_t PMSessionGetDataFromSession(CFMutableDictionaryRef, CFStringRef, CFTypeRef *);
int32_t PMSetScale(CFMutableDictionaryRef, double);
int32_t PMGetScale(CFMutableDictionaryRef, double *);
CFMutableDictionaryRef PMPrinterCreateFromPrinterID(CFStringRef);
Boolean PMPrinterIsFax(CFMutableDictionaryRef);

int main(void)
{
    int raw = 4;
    CFNumberRef copies = CFNumberCreate(NULL, kCFNumberIntType, &raw);
    const void *keys[] = {CFSTR("com.apple.print.PrintSettings.PMCopies"), CFSTR("dev.siliconforest.probe")};
    const void *values[] = {copies, CFSTR("restored")};
    CFDictionaryRef plist = CFDictionaryCreate(NULL, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDataRef data = CFPropertyListCreateData(NULL, plist, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
    CFMutableDictionaryRef settings = NULL;
    assert(data && PMPrintSettingsCreateWithDataRepresentation(data, &settings) == 0 && settings);
    uint32_t count = 0;
    assert(PMGetCopies(settings, &count) == 0 && count == 4);
    CFTypeRef value = NULL;
    assert(PMPrintSettingsGetValue(settings, keys[1], &value) == 0 && CFEqual(value, values[1]));
    assert(PMPrintSettingsSetValue(settings, keys[1], NULL, false) == 0);
    assert(PMPrintSettingsGetValue(settings, keys[1], &value) == 0 && value == NULL);
    assert(PMRelease(settings) == 0);
    CFRelease(data);
    CFRelease(plist);
    CFRelease(copies);

    CFMutableDictionaryRef session, format;
    assert(PMCreateSession(&session) == 0 && PMCreatePageFormat(&format) == 0);
    assert(PMSessionSetDataInSession(session, CFSTR("context"), CFSTR("private")) == 0);
    assert(PMSessionGetDataFromSession(session, CFSTR("context"), &value) == 0);
    assert(CFEqual(value, CFSTR("private")));
    assert(PMSetScale(format, 75) == 0);
    double scale;
    assert(PMGetScale(format, &scale) == 0 && scale == 75);
    assert(PMSetScale(format, NAN) != 0 && PMSetScale(format, 0) != 0);
    assert(PMRelease(format) == 0 && PMRelease(session) == 0);
    assert(PMPrinterCreateFromPrinterID(CFSTR("unknown queue")) == NULL);
    CFMutableDictionaryRef printer = PMPrinterCreateFromPrinterID(CFSTR(""));
    assert(printer && !PMPrinterIsFax(printer) && PMRelease(printer) == 0);
    puts("PrintCore PASS for saved settings, session data, generic printer, and scale");
    return 0;
}
