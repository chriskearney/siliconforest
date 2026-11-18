/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * C names QuickTime Player binds that SiliconForest's frameworks (15 November) lack, for the
 * frameworks that need no Objective-C. SF_LIB selects the framework. Constants carry their
 * documented values. Functions that have a substance here are implemented; the others are
 * absences (absent.h): they return the failure their interface documents and say so once.
 * Functions of the same image that the additions call are looked up at run time, because an
 * additions library is linked without the image it extends. */
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "absent.h"

#define SF_STRING(name, value) SF_EXPORT const CFStringRef name = CFSTR(value)

#if SF_LIB == 1 /* CoreFoundation: URL resource keys; each value is the key's own name */
#ifndef SF_MOVED /* in the CoreFoundation wrapper: terminal-app/compat/CoreFoundation.m */
SF_STRING(NSURLNameKey, "NSURLNameKey");
SF_STRING(NSURLFileSizeKey, "NSURLFileSizeKey");
SF_STRING(NSURLContentModificationDateKey, "NSURLContentModificationDateKey");
SF_STRING(NSURLParentDirectoryURLKey, "NSURLParentDirectoryURLKey");
SF_STRING(NSURLIsVolumeKey, "NSURLIsVolumeKey");
SF_STRING(NSURLVolumeNameKey, "NSURLVolumeNameKey");
SF_STRING(NSURLVolumeIsReadOnlyKey, "NSURLVolumeIsReadOnlyKey");
SF_STRING(NSURLHasHiddenExtensionKey, "NSURLHasHiddenExtensionKey");
SF_STRING(NSURLEffectiveIconKey, "NSURLEffectiveIconKey");
SF_STRING(NSURLFileResourceIdentifierKey, "NSURLFileResourceIdentifierKey");
#endif

#elif SF_LIB == 2 /* CoreGraphics */
typedef struct { double x, y, w, h; } SFRect;
typedef int32_t CGError;
enum { kSFCGErrorSuccess = 0, kSFCGErrorIllegalArgument = 1001, kSFCGErrorNotImplemented = 1006 };

#ifndef SF_MOVED /* in CoreGraphics: cocoa patch 0342 */
/* Public: the displays whose bounds intersect a rectangle. Real, over the display list. */
SF_EXPORT CGError CGGetDisplaysWithRect(SFRect rect, uint32_t maxDisplays, uint32_t *displays, uint32_t *matching) {
    CGError (*list)(uint32_t, uint32_t *, uint32_t *) = dlsym(RTLD_DEFAULT, "CGGetActiveDisplayList");
    SFRect (*bounds)(uint32_t) = dlsym(RTLD_DEFAULT, "CGDisplayBounds");
    uint32_t all[32], count = 0, found = 0;
    if (!matching) return kSFCGErrorIllegalArgument;
    *matching = 0;
    if (!list || !bounds) {
        SF_ABSENT("CGGetDisplaysWithRect: this CoreGraphics has no display list");
        return kSFCGErrorNotImplemented;
    }
    CGError e = list(32, all, &count);
    if (e != kSFCGErrorSuccess) return e;
    for (uint32_t i = 0; i < count; i++) {
        SFRect b = bounds(all[i]);
        bool hit = rect.x < b.x + b.w && b.x < rect.x + rect.w && rect.y < b.y + b.h && b.y < rect.y + rect.h;
        if (!hit) continue;
        if (displays && found < maxDisplays) displays[found] = all[i];
        found++;
    }
    *matching = displays ? (found < maxDisplays ? found : maxDisplays) : found;
    return kSFCGErrorSuccess;
}

#endif

/* Private window-server calls. SiliconForest's desktop is a Wayland compositor: there are
 * no window-server Spaces to create or show, no global hot keys and no connection
 * notifications. Argument and result shapes follow the community CGSInternal headers and
 * are not verified against macOS. */
SF_EXPORT uint64_t CGSSpaceCreate(int cid, void *null, CFDictionaryRef options) {
    (void)cid; (void)null; (void)options;
    SF_ABSENT("CGSSpaceCreate: there are no window-server Spaces; no Space is created (0)");
    return 0;
}
SF_EXPORT void CGSSpaceDestroy(int cid, uint64_t space) { (void)cid; (void)space; SF_ABSENT("CGSSpaceDestroy: there are no window-server Spaces"); }
SF_EXPORT void CGSSpaceSetAbsoluteLevel(int cid, uint64_t space, int level) { (void)cid; (void)space; (void)level; SF_ABSENT("CGSSpaceSetAbsoluteLevel: there are no window-server Spaces"); }
SF_EXPORT CFArrayRef CGSCopySpaces(int cid, int mask) { (void)cid; (void)mask; SF_ABSENT("CGSCopySpaces: there are no window-server Spaces (NULL)"); return NULL; }
SF_EXPORT void CGSAddWindowsToSpaces(int cid, CFArrayRef windows, CFArrayRef spaces) { (void)cid; (void)windows; (void)spaces; SF_ABSENT("CGSAddWindowsToSpaces: there are no window-server Spaces; windows are not moved"); }
SF_EXPORT void CGSRemoveWindowsFromSpaces(int cid, CFArrayRef windows, CFArrayRef spaces) { (void)cid; (void)windows; (void)spaces; SF_ABSENT("CGSRemoveWindowsFromSpaces: there are no window-server Spaces"); }
SF_EXPORT void CGSShowSpaces(int cid, CFArrayRef spaces) { (void)cid; (void)spaces; SF_ABSENT("CGSShowSpaces: there are no window-server Spaces; nothing is shown"); }
SF_EXPORT void CGSHideSpaces(int cid, CFArrayRef spaces) { (void)cid; (void)spaces; SF_ABSENT("CGSHideSpaces: there are no window-server Spaces"); }
SF_EXPORT CGError CGSSetHotKey(int cid, int uid, uint16_t unknown, uint16_t character, uint16_t keyCode, int modifiers) {
    (void)cid; (void)uid; (void)unknown; (void)character; (void)keyCode; (void)modifiers;
    SF_ABSENT("CGSSetHotKey: global hot keys are not available; none is registered");
    return kSFCGErrorNotImplemented;
}
SF_EXPORT CGError CGSSetHotKeyEnabled(int cid, int uid, bool enabled) { (void)cid; (void)uid; (void)enabled; SF_ABSENT("CGSSetHotKeyEnabled: global hot keys are not available"); return kSFCGErrorNotImplemented; }
SF_EXPORT CGError CGSRemoveHotKey(int cid, int uid) { (void)cid; (void)uid; SF_ABSENT("CGSRemoveHotKey: global hot keys are not available"); return kSFCGErrorNotImplemented; }
/* The output is left untouched on failure. */
SF_EXPORT CGError CGSIsZoomed(int cid, bool *zoomed) { (void)cid; (void)zoomed; SF_ABSENT("CGSIsZoomed: screen zoom state is not available"); return kSFCGErrorNotImplemented; }
SF_EXPORT CGError CGSRegisterConnectionNotifyProc(int cid, void *proc, int event, void *context) {
    (void)cid; (void)proc; (void)event; (void)context;
    SF_ABSENT("CGSRegisterConnectionNotifyProc: there are no window-server connection notifications; the callback will never run");
    return kSFCGErrorNotImplemented;
}
SF_EXPORT CGError CGSRemoveConnectionNotifyProc(int cid, void *proc, int event, void *context) { (void)cid; (void)proc; (void)event; (void)context; return kSFCGErrorNotImplemented; }

#elif SF_LIB == 3 /* CoreServices */
SF_STRING(kUTTypeQuickTimeMovie, "com.apple.quicktime-movie");
SF_STRING(kUTTypeAudiovisualContent, "public.audiovisual-content");
/* Shared file lists (recent documents). The list kinds are names; values as LaunchServices
 * has them, believed correct. This CoreServices keeps no recent-documents store that these
 * properties could live in. The names with a leading underscore are private spellings;
 * that they carry the public values is inferred. */
SF_STRING(_kLSSharedFileListRecentDocumentItems, "com.apple.LSSharedFileList.RecentDocuments");
SF_STRING(kLSSharedFileListApplicationRecentDocuments, "com.apple.LSSharedFileList.ApplicationRecentDocuments");
SF_STRING(_kLSSharedFileListRecentItemsMaxAmount, "com.apple.LSSharedFileList.MaxAmount");
/* A position marker, not an item: only its identity matters, and it must be the one this system's
 * LSSharedFileListInsertItemURL recognises (kLSSharedFileListItemBeforeFirst): a marker of our own was taken
 * for an item and compared as a CoreFoundation object (QuickTime Player crashed adding a recent document).
 * Set when the library loads; our own marker only if the system has none. */
static const char sfBeforeFirst = 0;
SF_EXPORT const void *_kLSSharedFileListItemBeforeFirst = &sfBeforeFirst;
__attribute__((constructor)) static void sfLinkBeforeFirst(void) {
    const void *const *systemMarker = dlsym(RTLD_DEFAULT, "kLSSharedFileListItemBeforeFirst");
    if (systemMarker != NULL && *systemMarker != NULL)
        _kLSSharedFileListItemBeforeFirst = *systemMarker;
}
SF_EXPORT CFTypeRef LSSharedFileListCopyProperty(void *list, CFStringRef name) {
    (void)list; (void)name;
    SF_ABSENT("LSSharedFileListCopyProperty: shared file lists keep no properties here (NULL)");
    return NULL;
}
SF_EXPORT int32_t LSSharedFileListSetProperty(void *list, CFStringRef name, CFTypeRef value) {
    (void)list; (void)name; (void)value;
    SF_ABSENT("LSSharedFileListSetProperty: shared file lists keep no properties here (unimpErr)");
    return -4;
}
SF_EXPORT int32_t LSSharedFileListRemoveAllItems(void *list) {
    (void)list;
    SF_ABSENT("LSSharedFileListRemoveAllItems is not implemented; the list is unchanged (unimpErr)");
    return -4;
}
/* Private. There is no Spotlight store to record a use in. */
SF_EXPORT void _MDItemMarkAsUsedWithURL(CFURLRef url) { (void)url; SF_ABSENT("_MDItemMarkAsUsedWithURL: there is no Spotlight store; the use is not recorded"); }
/* Private. True of this machine: SiliconForest has no AirDrop. */
SF_EXPORT bool _CSDeviceSupportsAirDrop(void) { return false; }

#elif SF_LIB == 4 /* CoreText */
SF_STRING(kCTFontContentSizeCategoryL, "UICTContentSizeCategoryL"); /* believed correct, not verified */
/* Private; its arguments are not established. 0 means "no size for this style". */
SF_EXPORT double CTFontDescriptorGetTextStyleSize(void) {
    SF_ABSENT("CTFontDescriptorGetTextStyleSize is not implemented; text styles have no size here (0)");
    return 0;
}

#elif SF_LIB == 5 /* ImageIO: documented values */
SF_STRING(kCGImagePropertyDepth, "Depth");
SF_STRING(kCGImagePropertyHasAlpha, "HasAlpha");

#elif SF_LIB == 6 /* Security */
enum { errSFSecUnimplemented = -4 };
/* Frees what a keychain search returned. Nothing here returns such data, so there is
 * nothing to free; data that is passed anyway is not ours to free and is reported. */
SF_EXPORT int32_t SecKeychainItemFreeContent(void *attributes, void *data) {
    if (!attributes && !data) return 0;
    SF_ABSENT("SecKeychainItemFreeContent: content of unknown origin is not freed (errSecUnimplemented)");
    return errSFSecUnimplemented;
}
SF_EXPORT int32_t SecRequirementCreateWithData(CFDataRef data, uint32_t flags, void **requirement) {
    (void)data; (void)flags;
    SF_ABSENT("SecRequirementCreateWithData: code requirements are not implemented (errSecUnimplemented)");
    if (requirement) *requirement = NULL;
    return errSFSecUnimplemented;
}
/* Private. */
SF_EXPORT int32_t SecCodeMapMemory(void *code, uint32_t flags) {
    (void)code; (void)flags;
    SF_ABSENT("SecCodeMapMemory is not implemented (errSecUnimplemented)");
    return errSFSecUnimplemented;
}

#elif SF_LIB == 7 /* CoreMedia */
typedef const void *SFFormatDescription;
/* Private. Real: the description says so itself through its public extension. */
SF_EXPORT bool FigVideoFormatDescriptionContainsAlphaChannel(SFFormatDescription description) {
    CFTypeRef (*extension)(SFFormatDescription, CFStringRef) = dlsym(RTLD_DEFAULT, "CMFormatDescriptionGetExtension");
    CFStringRef *key = dlsym(RTLD_DEFAULT, "kCMFormatDescriptionExtension_ContainsAlphaChannel");
    if (!description || !extension || !key) return false;
    CFTypeRef value = extension(description, *key);
    return value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
}
/* The scalar QuickTime Player passes on to MediaToolbox's dynamic-range label. The values
 * macOS uses are not established; 0 is this implementation's "not determined". */
SF_EXPORT int32_t CMVideoFormatDescriptionGetVideoDynamicRange(SFFormatDescription description) {
    (void)description;
    SF_ABSENT("CMVideoFormatDescriptionGetVideoDynamicRange: dynamic range is not classified (0)");
    return 0;
}
/* Private; its arguments are not established. The status is CoreMedia's "unsupported
 * operation" and no output is written. */
SF_EXPORT int32_t FigAudioFormatDescriptionGetRichestDecodableFormatAndChannelLayout(void) {
    SF_ABSENT("FigAudioFormatDescriptionGetRichestDecodableFormatAndChannelLayout is not implemented (-12782)");
    return -12782;
}

#elif SF_LIB == 8 /* MediaToolbox */
/* Private. QuickTime Player takes this function's address at start; no call site shows its
 * arguments. It reports failure and writes nothing. */
SF_EXPORT int32_t FigAssetCreateWithURL(void) {
    SF_ABSENT("FigAssetCreateWithURL is not implemented; no asset is created (-12782)");
    return -12782;
}

#elif SF_LIB == 9 /* CoreAudio */
#ifndef SF_MOVED /* in CoreAudio: cocoa patch 0346 */
#include <Block.h>
#include <dispatch/dispatch.h>
typedef struct { uint32_t selector, scope, element; } SFPropertyAddress;
typedef void (^SFListenerBlock)(uint32_t count, const SFPropertyAddress *addresses);
typedef int32_t (*SFListenerProc)(uint32_t object, uint32_t count, const SFPropertyAddress *addresses, void *context);
struct SFBlockListener { dispatch_queue_t queue; SFListenerBlock block; };
static int32_t SFRunBlockListener(uint32_t object, uint32_t count, const SFPropertyAddress *addresses, void *context) {
    struct SFBlockListener *listener = context;
    (void)object;
    SFPropertyAddress *copy = malloc(sizeof *copy * (count ? count : 1));
    if (!copy) return 0;
    for (uint32_t i = 0; i < count; i++) copy[i] = addresses[i];
    dispatch_async(listener->queue ? listener->queue : dispatch_get_global_queue(0, 0), ^{
        listener->block(count, copy);
        free(copy);
    });
    return 0;
}
/* Public. Real, over the function-pointer listener of the same framework: the block runs on
 * the given queue. The listener record lives as long as the process (the application binds
 * no call that removes a block listener). */
SF_EXPORT int32_t AudioObjectAddPropertyListenerBlock(uint32_t object, const SFPropertyAddress *address, dispatch_queue_t queue, SFListenerBlock block) {
    int32_t (*add)(uint32_t, const SFPropertyAddress *, SFListenerProc, void *) = dlsym(RTLD_DEFAULT, "AudioObjectAddPropertyListener");
    if (!address || !block) return -50; /* paramErr */
    if (!add) {
        SF_ABSENT("AudioObjectAddPropertyListenerBlock: this CoreAudio has no property listeners ('unop')");
        return 0x756e6f70; /* kAudioHardwareUnsupportedOperationError */
    }
    struct SFBlockListener *listener = malloc(sizeof *listener);
    if (!listener) return -108; /* memFullErr */
    listener->queue = queue;
    if (queue) dispatch_retain(queue);
    listener->block = Block_copy(block);
    int32_t status = add(object, address, SFRunBlockListener, listener);
    if (status != 0) {
        Block_release(listener->block);
        if (queue) dispatch_release(queue);
        free(listener);
    }
    return status;
}
#endif
#else
#error SF_LIB selects the framework
#endif
