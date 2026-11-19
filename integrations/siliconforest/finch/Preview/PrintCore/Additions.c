// SPDX-License-Identifier: MPL-2.0
// Appended to PureDarwin's PrintCore.c to preserve its dictionary-backed objects.
#include <math.h>

enum { kPMKeyNotFound = -9589 };

static CFStringRef printSettingsStorageKey(CFStringRef key)
{
    if (CFEqual(key, CFSTR("com.apple.print.PrintSettings.PMCopies")))
        return CFSTR("copies");
    if (CFEqual(key, CFSTR("com.apple.print.PrintSettings.PMFirstPage")))
        return CFSTR("first");
    if (CFEqual(key, CFSTR("com.apple.print.PrintSettings.PMLastPage")))
        return CFSTR("last");
    if (CFEqual(key, CFSTR("com.apple.print.JobInfo.PMJobName")))
        return CFSTR("jobName");
    return NULL;
}

static CFMutableDictionaryRef printExtraDictionary(CFMutableDictionaryRef object, CFStringRef key, Boolean create)
{
    CFMutableDictionaryRef values = (CFMutableDictionaryRef)CFDictionaryGetValue(object, key);
    if (!values && create) {
        values = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(object, key, values);
        CFRelease(values);
    }
    return values;
}

OSStatus PMPrintSettingsGetValue(PMPrintSettings settings, CFStringRef key, CFTypeRef *value)
{
    if (!isKind(settings, CFSTR("settings")) || !key || !value)
        return kPMInvalidParameter;
    CFStringRef storage = printSettingsStorageKey(key);
    CFDictionaryRef values = storage ? settings : printExtraDictionary(settings, CFSTR("values"), false);
    *value = values ? CFDictionaryGetValue(values, storage ? storage : key) : NULL;
    return kPMNoError;
}

OSStatus PMPrintSettingsSetValue(PMPrintSettings settings, CFStringRef key, CFTypeRef value, Boolean locked)
{
    if (!isKind(settings, CFSTR("settings")) || !key)
        return kPMInvalidParameter;
    CFStringRef storage = printSettingsStorageKey(key);
    CFMutableDictionaryRef values = storage ? settings : printExtraDictionary(settings, CFSTR("values"), value != NULL);
    if (value)
        CFDictionarySetValue(values, storage ? storage : key, value);
    else if (values)
        CFDictionaryRemoveValue(values, storage ? storage : key);
    CFMutableDictionaryRef locks = printExtraDictionary(settings, CFSTR("locks"), locked && value);
    if (locked && value)
        CFDictionarySetValue(locks, key, kCFBooleanTrue);
    else if (locks)
        CFDictionaryRemoveValue(locks, key);
    return kPMNoError;
}

static void importPrintSetting(const void *key, const void *value, void *context)
{
    PMPrintSettingsSetValue(context, key, value, false);
}

OSStatus PMPrintSettingsCreateWithDataRepresentation(CFDataRef data, PMPrintSettings *settings)
{
    if (!data || !settings)
        return kPMInvalidParameter;
    *settings = NULL;
    CFPropertyListRef plist = CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, NULL);
    if (!plist || CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        if (plist)
            CFRelease(plist);
        return kPMInvalidParameter;
    }
    PMPrintSettings result;
    OSStatus status = PMCreatePrintSettings(&result);
    if (status == kPMNoError) {
        CFDictionaryApplyFunction(plist, importPrintSetting, result);
        *settings = result;
    }
    CFRelease(plist);
    return status;
}

OSStatus PMSessionSetDataInSession(PMPrintSession session, CFStringRef key, CFTypeRef data)
{
    if (!isKind(session, CFSTR("session")) || !key)
        return kPMInvalidParameter;
    CFMutableDictionaryRef values = printExtraDictionary(session, CFSTR("sessionData"), data != NULL);
    if (data)
        CFDictionarySetValue(values, key, data);
    else if (values)
        CFDictionaryRemoveValue(values, key);
    return kPMNoError;
}

OSStatus PMSessionGetDataFromSession(PMPrintSession session, CFStringRef key, CFTypeRef *data)
{
    if (!isKind(session, CFSTR("session")) || !key || !data)
        return kPMInvalidParameter;
    CFDictionaryRef values = printExtraDictionary(session, CFSTR("sessionData"), false);
    *data = values ? CFDictionaryGetValue(values, key) : NULL;
    return *data ? kPMNoError : kPMKeyNotFound;
}

OSStatus PMSetScale(PMPageFormat format, double scale)
{
    if (!isKind(format, CFSTR("format")))
        return kPMInvalidPageFormat;
    if (!isfinite(scale) || scale <= 0.0)
        return kPMValueOutOfRange;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberDoubleType, &scale);
    CFDictionarySetValue(format, CFSTR("scale"), number);
    CFRelease(number);
    return kPMNoError;
}

OSStatus PMGetScale(PMPageFormat format, double *scale)
{
    if (!isKind(format, CFSTR("format")) || !scale)
        return kPMInvalidPageFormat;
    CFNumberRef number = CFDictionaryGetValue(format, CFSTR("scale"));
    *scale = 100.0;
    if (number)
        CFNumberGetValue(number, kCFNumberDoubleType, scale);
    return kPMNoError;
}

PMPrinter PMPrinterCreateFromPrinterID(CFStringRef printerID)
{
    return printerID && CFEqual(printerID, CFSTR("")) ? createObject(CFSTR("printer")) : NULL;
}

Boolean PMPrinterIsFax(PMPrinter printer)
{
    // The generic print-to-file destination has no fax transport.
    (void)printer;
    return false;
}
