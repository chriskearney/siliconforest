// SPDX-License-Identifier: MIT
// SiliconForest CoreMIDI: no MIDI devices. Covers what javax.sound.midi's
// native side (libjsound) imports. Every query reports zero endpoints and
// every creation call fails with kMIDINotPermitted, so Java sees an empty
// MIDI system instead of failing to load the library.
#include <stdint.h>
#include <stddef.h>
#include <dlfcn.h>

typedef int32_t OSStatus;
typedef uint32_t MIDIObjectRef;
typedef const void *CFStringRef;
enum { kMIDINotPermitted = -10844 };

// The property keys are CFStrings made at load time through CoreFoundation,
// found with dlsym, so this image links only libSystem.
CFStringRef kMIDIPropertyName;
CFStringRef kMIDIPropertyManufacturer;
CFStringRef kMIDIPropertyModel;
CFStringRef kMIDIPropertyDisplayName;
CFStringRef kMIDIPropertyDriverVersion;
CFStringRef kMIDIPropertyOffline;
CFStringRef kMIDIPropertyUniqueID;

__attribute__((constructor)) static void make_keys(void) {
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
    CFStringRef (*make)(const void *, const char *, uint32_t) =
        cf ? (CFStringRef (*)(const void *, const char *, uint32_t))dlsym(cf, "CFStringCreateWithCString") : NULL;
    if (!make) return;
    kMIDIPropertyName = make(NULL, "name", 0x08000100);
    kMIDIPropertyManufacturer = make(NULL, "manufacturer", 0x08000100);
    kMIDIPropertyModel = make(NULL, "model", 0x08000100);
    kMIDIPropertyDisplayName = make(NULL, "displayName", 0x08000100);
    kMIDIPropertyDriverVersion = make(NULL, "driverVersion", 0x08000100);
    kMIDIPropertyOffline = make(NULL, "offline", 0x08000100);
    kMIDIPropertyUniqueID = make(NULL, "uniqueID", 0x08000100);
}

unsigned long MIDIGetNumberOfDestinations(void) { return 0; }
unsigned long MIDIGetNumberOfSources(void) { return 0; }
unsigned long MIDIGetNumberOfDevices(void) { return 0; }
MIDIObjectRef MIDIGetDestination(unsigned long i) { (void)i; return 0; }
MIDIObjectRef MIDIGetSource(unsigned long i) { (void)i; return 0; }
MIDIObjectRef MIDIGetDevice(unsigned long i) { (void)i; return 0; }
OSStatus MIDIClientCreate(void) { return kMIDINotPermitted; }
OSStatus MIDIClientCreateWithBlock(void) { return kMIDINotPermitted; }
OSStatus MIDIClientDispose(void) { return kMIDINotPermitted; }
OSStatus MIDIEndpointDispose(void) { return kMIDINotPermitted; }
OSStatus MIDIInputPortCreate(void) { return kMIDINotPermitted; }
OSStatus MIDIInputPortCreateWithBlock(void) { return kMIDINotPermitted; }
OSStatus MIDIOutputPortCreate(void) { return kMIDINotPermitted; }
OSStatus MIDIPortConnectSource(void) { return kMIDINotPermitted; }
OSStatus MIDIPortDisconnectSource(void) { return kMIDINotPermitted; }
OSStatus MIDIPortDispose(void) { return kMIDINotPermitted; }
OSStatus MIDIReceived(void) { return kMIDINotPermitted; }
OSStatus MIDIRestart(void) { return kMIDINotPermitted; }
OSStatus MIDISend(void) { return kMIDINotPermitted; }
OSStatus MIDISendSysex(void) { return kMIDINotPermitted; }
OSStatus MIDIFlushOutput(void) { return kMIDINotPermitted; }
OSStatus MIDIObjectGetIntegerProperty(void) { return kMIDINotPermitted; }
OSStatus MIDIObjectGetStringProperty(void) { return kMIDINotPermitted; }
void *MIDIPacketListInit(void *list) { (void)list; return NULL; }
void *MIDIPacketListAdd(void) { return NULL; }
