#include "SFM1SPIHID.h"
#include "SFM1SPITrackpad.h"
#include "m1tp_child_policy.h"
#include "trackpad_reference.h"
#include "SFHIDEventQueue.h"
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/IOLib.h>
#include <libkern/c++/OSData.h>
#include <libkern/libkern.h>
#include <libkern/OSAtomic.h>
#include <mach/kmod.h>
#include <pexpert/pexpert.h>

#define super IOHIDDevice
OSDefineMetaClassAndStructors(SFM1SPIHID,IOHIDDevice);

/* A failed start detaches and can be matched again by IOResources. The
 * module refuses unload; keep the single opt-in probe claim until reboot,
 * including on probe/start failure. No second instance may touch hardware. */
static volatile UInt32 gSFM1KeyboardProbeClaimed=0;

/* The experimental module cannot be unloaded, including on start failure.
 * This is an explicit failure, not evidence of callback quiescence. */
extern "C" kern_return_t sf_m1kbd_stop(kmod_info_t *, void *) { return KERN_FAILURE; }

/* receive(): a packet that was consumed here and carries no message. Not a
 * dlsp_result; only returned once multitouch mode has been requested. */
#define SF_M1_SKIP 3

static bool recordBytes(IORegistryEntry *entry, const char *key, const void *bytes, unsigned length)
{
    OSData *data=OSData::withBytes(bytes,length);
    if (!data) return false;
    bool result=entry->setProperty(key,data);
    data->release();
    return result;
}
static unsigned metadataSpanValid(size_t n, uint16_t off, uint16_t len)
{ return off<=n && len<=n-off; }
static void recordDeviceMetadata(IORegistryEntry *entry, const uint8_t *p, size_t n, int error)
{
    struct m1kbd_device_metadata h;
    unsigned present=(unsigned)m1kbd_device_metadata_header(p,n,&h);
    static_assert(sizeof(h)==24,"device metadata numeric header ABI");
    (void)recordBytes(entry,"SFM1KeyboardDeviceMetadataV1",&h,sizeof(h));
    entry->setProperty("SFM1KeyboardDeviceMetadataError",(uint64_t)(int64_t)error,64);
    entry->setProperty("SFM1KeyboardDeviceMetadataPresent",(uint64_t)present,32);
    IOLog("SFM1SPIHID: device metadata bytes=%u header_present=%u reason=%d u0=%u u1=%u count=%u vendor=%04x product=%04x version=%04x\n",
          (unsigned)n,present,error,(unsigned)h.words[0],(unsigned)h.words[1],
          (unsigned)h.words[2],(unsigned)h.words[3],(unsigned)h.words[4],(unsigned)h.words[5]);
    IOLog("SFM1SPIHID: unused metadata spans vendor=%u/%u/%u product=%u/%u/%u serial=%u/%u/%u (offset/length/valid; no string bytes)\n",
          (unsigned)h.words[6],(unsigned)h.words[7],present?metadataSpanValid(n,h.words[6],h.words[7]):0u,
          (unsigned)h.words[8],(unsigned)h.words[9],present?metadataSpanValid(n,h.words[8],h.words[9]):0u,
          (unsigned)h.words[10],(unsigned)h.words[11],present?metadataSpanValid(n,h.words[10],h.words[11]):0u);
}
static void recordInterfaceMetadata(IORegistryEntry *entry, const uint8_t *p, size_t n, int error)
{
    struct m1kbd_interface_metadata h;
    unsigned present=(unsigned)m1kbd_interface_metadata_header(p,n,&h);
    static_assert(sizeof(h)==16,"interface metadata numeric header ABI");
    (void)recordBytes(entry,"SFM1KeyboardInterfaceMetadataV1",&h,sizeof(h));
    entry->setProperty("SFM1KeyboardInterfaceMetadataError",(uint64_t)(int64_t)error,64);
    entry->setProperty("SFM1KeyboardInterfaceMetadataPresent",(uint64_t)present,32);
    IOLog("SFM1SPIHID: interface metadata bytes=%u header_present=%u reason=%d u0=%u interface=%u u2=%u u3=%u u4=%u country=%u input=%u output=%u control=%u name=%u/%u/%u (offset/length/valid; no string bytes)\n",
          (unsigned)n,present,error,(unsigned)h.prefix[0],(unsigned)h.prefix[1],
          (unsigned)h.prefix[2],(unsigned)h.prefix[3],(unsigned)h.prefix[4],(unsigned)h.prefix[5],
          (unsigned)h.words[0],(unsigned)h.words[1],(unsigned)h.words[2],
          (unsigned)h.words[3],(unsigned)h.words[4],present?metadataSpanValid(n,h.words[3],h.words[4]):0u);
}
bool SFM1SPIHID::init(OSDictionary *properties)
{
    transportLoop=nullptr; transportGate=nullptr; pollTimer=nullptr;
    stopping=false; published=false; touchedHardware=false; gateAdded=false; timerAdded=false;
    descriptorLength=0; bzero(&identity,sizeof(identity)); nextID=0; usedRequestKeys=0;
    packetsRead=0; reportsDelivered=0; otherMessages=0;
    bzero(&lastObservation,sizeof(lastObservation)); lastCountersUS=0;
    countersDirty=false; requestPending=false;
    pendingReport=0; pendingSubdevice=0; requestID=0;
    bzero(packet,sizeof(packet)); bzero(descriptor,sizeof(descriptor)); dlsp_init(&wire);
    bzero(&trackpadEnumeration,sizeof(trackpadEnumeration));
    bzero(&trackpadInterface,sizeof(trackpadInterface));
    trackpadEnumeration.version=M1TP_OBSERVATION_VERSION;
    trackpadEnumeration.result=M1TP_OBS_NOT_ATTEMPTED;
    trackpadEnumeration.stage=M1TP_OBS_BEFORE_IO;
    t2Enabled=false; t2Phase=0; childInitialized=false; childAttached=false; childStarted=false;
    privateStopRunning=false; privateStopDone=false;
    childOwned=nullptr; childSink=nullptr; t2Provider=nullptr; t2CommitData=nullptr;
    bzero(&childState,sizeof(childState));
    childState.version=DL_M1_TP_CHILD_STATE_VERSION;
    childState.byte_size=sizeof(childState);
    t2Dispatches=0; childObserved=0; childRejected=0; childSubmitted=0;
    m1tp_trace_init(&trackpadTrace);
    mtEnabled=false; lineIdle=false; mtSelftestDone=false; mtInjectDone=false; mtTypingLogged=false;
    mtSelftest=0; mtDebug=0; mtDebugHex=0; mtModeAttempts=0; mtResets=0; mtResponses=0;
    mtWireDrops=0; mtLoggedEvents=0; mtInjectSubmitted=0; mtInjectOffered=0; bzero(mtKeys,sizeof(mtKeys));
    mtModeDueUS=0; mtTouchReports=0; mtBasicReports=0; mtPointerReports=0;
    bzero(&mtConfig,sizeof(mtConfig)); bzero(&mtFrame,sizeof(mtFrame)); bzero(mtBuffer,sizeof(mtBuffer));
    m1tp_mt_init(&mtState,nullptr); m1tp_mt_init(&mtScratch,nullptr);
    return super::init(properties);
}
IOService *SFM1SPIHID::probe(IOService *provider, SInt32 *score)
{
    int enabled=0, trackpadOptIn=0, childOptIn=0;
    if (!PE_parse_boot_argn("sfm1kbd",&enabled,sizeof(enabled)) || enabled!=1) return nullptr;
    /* Experimental T1 bundle: both explicit opt-ins precede the one-shot
     * claim, so neither default nor keyboard-only boots reach this probe. */
    if (!PE_parse_boot_argn("sfm1trackpadenum",&trackpadOptIn,sizeof(trackpadOptIn)) ||
        trackpadOptIn!=1) return nullptr;
    bool childToken=PE_parse_boot_argn("sfm1trackpadchild",&childOptIn,sizeof(childOptIn));
    if (childToken && childOptIn!=1) return nullptr;
    t2Enabled=childToken && childOptIn==1;
    if (!OSCompareAndSwap(0,1,&gSFM1KeyboardProbeClaimed)) {
        IOLog("SFM1SPIHID: probe refused; one attempt already claimed this boot, registry_id=%llu\n",
              (unsigned long long)getRegistryEntryID());
        return nullptr;
    }
    IOLog("SFM1SPIHID: sole probe attempt claimed, registry_id=%llu\n",
          (unsigned long long)getRegistryEntryID());
    mtConfigure();
    return super::probe(provider,score);
}
IOWorkLoop *SFM1SPIHID::getWorkLoop() const { return transportLoop; }
bool SFM1SPIHID::start(IOService *provider)
{
    if (t2Enabled) {
        t2Provider=provider;
        if (t2Provider) t2Provider->retain();
        if (!t2Provider || !setProperty(kIOHIDRegisterServiceKey,kOSBooleanFalse) ||
            getProperty(kIOHIDRegisterServiceKey)!=kOSBooleanFalse || !publishChildState()) {
            childFault((int32_t)kIOReturnNoMemory); disposeTransport(); return false;
        }
    }
    transportLoop=IOWorkLoop::workLoop();
    if (!transportLoop) { disposeTransport(); return false; }
    transportGate=IOCommandGate::commandGate(this);
    /* WorkLoop delivery avoids passive thread-call actions waiting outside
     * the workloop gate. cancelTimeout joins the signal callout; removal
     * then prevents checkForWork from invoking a stale owner. */
    pollTimer=IOTimerEventSource::timerEventSource(kIOTimerEventSourceOptionsPriorityWorkLoop,this,poll);
    if (!transportGate || !pollTimer) { disposeTransport(); return false; }
    if (transportLoop->addEventSource(transportGate)!=kIOReturnSuccess) {
        disposeTransport(); return false;
    }
    gateAdded=true;
    if (transportLoop->addEventSource(pollTimer)!=kIOReturnSuccess) {
        disposeTransport(); return false;
    }
    timerAdded=true;
    /* IOHIDDevice calls handleStart before asking for the real descriptor.
     * No timer is armed and report operations are Unsupported during init. */
    if (!super::start(provider)) { disposeTransport(); return false; }
    if (t2Enabled) return startT2(provider);
    published=true;
    if (pollTimer->setTimeoutMS(2)!=kIOReturnSuccess) {
        super::stop(provider); disposeTransport(); return false;
    }
    setProperty("SFM1KeyboardPhase","descriptor-published-awaiting-input");
    return true;
}
bool SFM1SPIHID::handleStart(IOService *provider)
{
    bool gated=super::handleStart(provider) &&
        transportGate && transportGate->runAction(startGated)==kIOReturnSuccess;
    /* The gate has returned: preserve the enumeration snapshot on success or
     * failure, before IOHIDDevice publishes interfaces or start() arms the
     * timer. A failed copy fails start; it never changes the raw result. */
    bool preserved=preserveTrackpadEnumeration(provider);
    return gated && preserved;
}
IOReturn SFM1SPIHID::startGated(OSObject *owner, void *, void *, void *, void *)
{
    SFM1SPIHID *self=OSDynamicCast(SFM1SPIHID,owner);
    if (!self || self->stopping) return kIOReturnNotReady;
    return self->startHardware()?kIOReturnSuccess:kIOReturnError;
}
bool SFM1SPIHID::startHardware()
{
    int e=hardware.open();
    if (e) { fail(e,"board-or-map"); return false; }
    touchedHardware=true;
    e=hardware.start();
    const struct m1kbd_hw *h=hardware.state();
    if (!recordBytes(this,"SFM1KeyboardPowerBefore",h->power_before,sizeof(h->power_before)) ||
        !recordBytes(this,"SFM1KeyboardGPIOBefore",h->gpio_before,sizeof(h->gpio_before))) {
        fail(M1KBD_IO,"observation-allocation"); return false;
    }
    if (e) { fail(e,"controller-start"); return false; }
    setProperty("SFM1KeyboardPhase","controller-ready");
    if (!enumerate()) return false;
    setProperty("HIDDefaultBehavior",kOSBooleanTrue);
    setProperty("Built-In",kOSBooleanTrue);
    IOLog("SFM1SPIHID: CRC-checked J293 keyboard descriptor acquired (%u bytes); input not yet observed\n",
          (unsigned)descriptorLength);
    return true;
}
int SFM1SPIHID::receive(struct dlsp_message *message)
{
    int e=hardware.readPacket(packet);
    lineIdle=e==M1KBD_NOT_READY;
    if (e==M1KBD_NOT_READY) return DLSP_WAIT;
    if (e) { fail(e,"read-packet"); return DLSP_INVALID; }
    packetsRead++;
    countersDirty=true;
    /* The trackpad's reply to the mode request (write flag, interface 2). The
     * Linux transport has no handler for it (spihid_process_response) and
     * silently drops a reply without payload, which this wire engine would
     * treat as a fatal protocol error. Nothing else is ever requested from
     * interface 2, so the reply is counted and consumed here. */
    if (mtModeAttempts && packet[0]==0x40 && packet[1]==2 &&
        dlsp_crc16(packet,254)==(uint16_t)(packet[254]|(uint16_t)(packet[255]<<8))) {
        if (!mtResponses++)
            IOLog("SFM1SPIHID: MT stage=mode-response command=%02x report=%02x payload_bytes=%u first=%02x%02x\n",
                  (unsigned)packet[8],(unsigned)packet[9],(unsigned)(packet[14]|(packet[15]<<8)),
                  (unsigned)packet[16],(unsigned)packet[17]);
        return SF_M1_SKIP;
    }
    e=dlsp_push(&wire,packet,sizeof(packet),message);
    m1kbd_observe(packet,sizeof(packet),e==DLSP_MESSAGE?message:nullptr,
                  (unsigned)wire.last_error,&lastObservation);
    /* As in Linux (spihid_process_read, spihid_verify_msg), a damaged or
     * unexpected trackpad packet in multitouch mode is dropped, not fatal.
     * Keyboard and management packets keep the strict handling below. */
    if (e==DLSP_INVALID && mtModeAttempts && packet[1]==2) {
        if (mtWireDrops++<4)
            IOLog("SFM1SPIHID: MT stage=packet-dropped parser_error=%u flags=%02x offset=%u remain=%u length=%u\n",
                  (unsigned)wire.last_error,(unsigned)packet[0],(unsigned)(packet[2]|(packet[3]<<8)),
                  (unsigned)(packet[4]|(packet[5]<<8)),(unsigned)(packet[6]|(packet[7]<<8)));
        return SF_M1_SKIP;
    }
    if (e==DLSP_INVALID) {
        setProperty("SFM1KeyboardProtocolError",(uint64_t)wire.last_error,32);
        fail(M1KBD_INVALID,"packet-or-message");
    }
    return e;
}
bool SFM1SPIHID::waitResponse(uint8_t report, uint8_t subdevice, uint16_t responseLength,
                            struct dlsp_message *message)
{
    /* One synchronous request at a time, each semantic key once per instance.
     * Never release a claim, even if encoding, transport or response fails.
     * Firmware response IDs need not echo our outbound global counter. */
    if (!m1tp_claim_request(&usedRequestKeys,report,subdevice)) {
        fail(M1KBD_STATE,"request-key"); return false;
    }
    uint8_t id=nextID++;
    requestPending=true; pendingReport=report; pendingSubdevice=subdevice; requestID=id;
    if (dlsp_request(0xd0,0x20,report,subdevice,id,responseLength,nullptr,0,packet)!=0) {
        fail(M1KBD_INVALID,"request-encode"); return false;
    }
    int e=hardware.writePacket(packet);
    if (e) { fail(e,"write-request"); return false; }
    uint64_t start=SFM1KeyboardHW::clockUS();
    for (unsigned polls=0;polls<1000;polls++) {
        if (SFM1KeyboardHW::clockUS()-start>=1000000) break;
        e=receive(message);
        if (e==DLSP_INVALID) return false;
        if (e==DLSP_BOOT) { fail(M1KBD_STATE,"unexpected-reboot"); return false; }
        if (e==DLSP_MESSAGE) {
            if (message->flags==0x20) { otherMessages++; continue; }
            if (!m1kbd_response_matches(message,report,subdevice)) {
                fail(M1KBD_STATUS,"response-identity"); return false;
            }
            requestPending=false;
            return true;
        }
        IOSleep(1);
    }
    fail(M1KBD_TIMEOUT,"response-timeout"); return false;
}
bool SFM1SPIHID::enumerate()
{
    struct dlsp_message message;
    bool boot=false;
    uint64_t start=SFM1KeyboardHW::clockUS();
    for (unsigned polls=0;polls<1000;polls++) {
        if (SFM1KeyboardHW::clockUS()-start>=1000000) break;
        int e=receive(&message);
        if (e==DLSP_INVALID) return false;
        if (e==DLSP_BOOT) { boot=true; break; }
        if (e==DLSP_MESSAGE) { fail(M1KBD_STATE,"message-before-boot"); return false; }
        IOSleep(1);
    }
    if (!boot) { fail(M1KBD_TIMEOUT,"boot-timeout"); return false; }
    setProperty("SFM1KeyboardPhase","boot-notification-verified");
    if (!waitResponse(1,0xd0,0,&message)) return false;
    /* Device metadata comes from the controller, not our selected descriptor.
     * The product must be the one of the board the guard accepted (m1kbd_boards.h). */
    int metadataError=m1kbd_device_info(message.payload,message.payload_length,m1kbd_board_product(hardware.state()->board.qualified),&identity);
    recordDeviceMetadata(this,message.payload,message.payload_length,metadataError);
    if (metadataError) {
        fail(M1KBD_BOARD,"device-metadata"); return false;
    }
    if (!waitResponse(2,1,512,&message)) return false;
    metadataError=m1kbd_interface_info(message.payload,message.payload_length,&identity);
    recordInterfaceMetadata(this,message.payload,message.payload_length,metadataError);
    if (metadataError) {
        fail(M1KBD_INVALID,"interface-metadata"); return false;
    }
    if (!waitResponse(0x10,1,512,&message)) return false;
    if (!message.payload_length || message.payload_length>sizeof(descriptor)) {
        fail(M1KBD_INVALID,"descriptor-length"); return false;
    }
    memcpy(descriptor,message.payload,message.payload_length);
    descriptorLength=message.payload_length;
    return enumerateTrackpad();
}
bool SFM1SPIHID::enumerateTrackpad()
{
    /* T1 enumeration only: two read queries to the info target (0xd0, command
     * 0x20). No feature, SET, output or actuator request, no mode switch and
     * no child device. A failure here fails the whole experimental start. */
    struct dlsp_message message;
    struct m1tp_observation *o=&trackpadEnumeration;
    o->stage=M1TP_OBS_INFO_REQUEST;
    if (!waitResponse(2,2,512,&message)) { o->result=M1TP_OBS_INFO_REQUEST_FAILED; return false; }
    o->stage=M1TP_OBS_INFO_RECEIVED;
    o->metadata_payload_bytes=(uint32_t)message.payload_length;
    if (message.payload && message.payload_length)  /* fixed raw header only, never strings */
        memcpy(o->metadata_header,message.payload,
               message.payload_length<sizeof(o->metadata_header)?message.payload_length:sizeof(o->metadata_header));
    if (m1tp_interface_info(message.payload,message.payload_length,&trackpadInterface)!=M1TP_OK) {
        o->result=M1TP_OBS_INFO_INVALID;
        fail(M1KBD_INVALID,"trackpad-interface-metadata"); return false;
    }
    IOLog("SFM1SPIHID: trackpad interface metadata bytes=%u interface=%u country=%u input=%u output=%u control=%u (no string bytes)\n",
          (unsigned)message.payload_length,(unsigned)trackpadInterface.interface,(unsigned)trackpadInterface.country,
          (unsigned)trackpadInterface.max_input,(unsigned)trackpadInterface.max_output,(unsigned)trackpadInterface.max_control);
    o->stage=M1TP_OBS_DESC_REQUEST;
    if (!waitResponse(0x10,2,512,&message)) { o->result=M1TP_OBS_DESC_REQUEST_FAILED; return false; }
    o->stage=M1TP_OBS_DESC_RECEIVED;
    o->descriptor_payload_bytes=(uint32_t)message.payload_length;
    if (m1tp_copy_descriptor(o->descriptor,sizeof(o->descriptor),&o->descriptor_bytes,
                             message.payload,message.payload_length)!=M1TP_OK) {
        o->result=M1TP_OBS_DESC_INVALID;
        fail(M1KBD_INVALID,"trackpad-descriptor-length"); return false;
    }
    o->stage=M1TP_OBS_COMPLETE; o->result=M1TP_OBS_ENUM_OK;
    IOLog("SFM1SPIHID: CRC-checked J293 trackpad descriptor acquired (%u bytes); enumeration only, no mode write or pointer input\n",
          (unsigned)o->descriptor_bytes);
    return true;
}
bool SFM1SPIHID::preserveTrackpadEnumeration(IOService *provider)
{
    trackpadEnumeration.request_mask=usedRequestKeys;
    OSData *data=OSData::withBytes(&trackpadEnumeration,sizeof(trackpadEnumeration));
    /* Plain property copies only: no publishResource, registerService or
     * notifier. IOResources keeps its reference after a failed start detaches. */
    bool providerRecorded=data && provider && provider->setProperty(M1TP_OBSERVATION_KEY,data);
    bool instanceRecorded=data && setProperty(M1TP_OBSERVATION_KEY,data);
    IOLog("SFM1SPIHID: trackpad enumeration result=%d stage=%u request_mask=%u metadata_bytes=%u descriptor_payload_bytes=%u descriptor_bytes=%u diagnostic_copy=%u provider_preserved=%u instance_recorded=%u (enumeration only, not pointer input)\n",
          (int)trackpadEnumeration.result,(unsigned)trackpadEnumeration.stage,(unsigned)trackpadEnumeration.request_mask,
          (unsigned)trackpadEnumeration.metadata_payload_bytes,(unsigned)trackpadEnumeration.descriptor_payload_bytes,
          (unsigned)trackpadEnumeration.descriptor_bytes,data?1u:0u,providerRecorded?1u:0u,instanceRecorded?1u:0u);
    if (data) data->release();
    return providerRecorded && instanceRecorded;
}
void SFM1SPIHID::poll(OSObject *owner, IOTimerEventSource *)
{
    SFM1SPIHID *self=OSDynamicCast(SFM1SPIHID,owner);
    if (!self || self->stopping || !self->published) return;
    if (self->t2Enabled && __atomic_load_n(&self->t2Phase,__ATOMIC_ACQUIRE)!=1) return;
    if (self->t2Enabled && m1tp_trace_announce(&self->trackpadTrace))
        IOLog("DL24_TP_TRACE version=1 passive=1 cap02=16 cap3f=2 cap44=1 motion_reserved=1\n");
    if (self->mtEnabled && self->mtSelftest) {
        if (!self->mtSelftestDone) { self->mtSelftestDone=true; self->mtRunSelftest(false); }
        /* sfm1tpselftest=2: the first time user space opens /dev/usb_hid_kbd,
         * the scenario's pointer reports also go through the real child. */
        if (self->mtSelftest==2 && !self->mtInjectDone && SFHIDKeyboardIsGrabbed()) {
            self->mtInjectDone=true; self->mtRunSelftest(true);
        }
    }
    struct dlsp_message message;
    /* A bounded batch lets other workloop users run, even with ready held low.
     * Partial messages remain in the bounded heap reassembly buffer. */
    for (unsigned budget=0;budget<8;budget++) {
        if (self->t2Enabled && (self->stopping ||
            __atomic_load_n(&self->t2Phase,__ATOMIC_ACQUIRE)!=1)) break;
        int e=self->receive(&message);
        if (e==DLSP_INVALID) return;
        if (e==DLSP_BOOT) { self->fail(M1KBD_STATE,"runtime-device-reboot"); return; }
        if (e==DLSP_WAIT) break;
        if (e==SF_M1_SKIP) continue;
        if (self->t2Enabled && (self->stopping ||
            __atomic_load_n(&self->t2Phase,__ATOMIC_ACQUIRE)!=1)) break;
        int eligible=m1kbd_keyboard_input(&message,self->identity.max_input);
        if (eligible<0) { self->fail(M1KBD_INVALID,"input-size"); return; }
        if (eligible) {
            IOBufferMemoryDescriptor *report=IOBufferMemoryDescriptor::withBytes(
                message.payload,message.payload_length,kIODirectionNone);
            if (!report) { self->fail(M1KBD_IO,"input-allocation"); return; }
            /* Disable-while-typing only reads the keyboard report (ID 1, the
             * modifier byte, a reserved byte and six usages, as its descriptor
             * says); delivery is unchanged. */
            if (self->mtEnabled && message.payload_length>=9 && message.payload[0]==0x01) {
                bool typing=self->mtState.keyboard_active;
                m1tp_mt_keyboard_report(&self->mtState,SFM1KeyboardHW::clockUS(),message.payload,
                                        message.payload_length,self->mtKeys);
                if (!typing && self->mtState.keyboard_active && !self->mtTypingLogged) {
                    self->mtTypingLogged=true;
                    IOLog("SFM1SPIHID: MT stage=first-typing report_bytes=%u (touches that land while typing are ignored; no key data logged)\n",
                          (unsigned)message.payload_length);
                }
            }
            if (self->t2Enabled) { self->retain(); self->t2Dispatches++; }
            IOReturn kr=self->handleReport(report,kIOHIDReportTypeInput);
            if (self->t2Enabled) { self->t2Dispatches--; self->release(); }
            report->release();
            if (kr!=kIOReturnSuccess) { self->fail((int)kr,"hid-input"); return; }
            self->reportsDelivered++;
            if (self->reportsDelivered==1) {
                self->publishCounters(true);
                IOLog("SFM1SPIHID: first device-1 input report accepted by IOHID; physical typing not yet verified\n");
            }
        } else if (self->t2Enabled && message.device==2 && message.flags==0x20 && message.command==0x10) {
            if (self->mtEnabled) self->mtRoute(&message);
            else { self->traceTrackpad(&message); self->routeTrackpad(&message); }
        } else {
            /* Management/trackpad/aux reports are consumed but never relabeled
             * as keyboard events or evidence of supported native trackpad. */
            self->otherMessages++;
        }
    }
    /* The mode request goes out between reads, when the controller has
     * nothing pending. */
    if (self->mtEnabled && self->mtModeDueUS && self->lineIdle && !self->stopping &&
        SFM1KeyboardHW::clockUS()>=self->mtModeDueUS) self->mtSendEnable();
    self->publishCounters(false);
    if (!self->stopping && self->pollTimer->setTimeoutMS(2)!=kIOReturnSuccess)
        self->fail(M1KBD_IO,"timer-rearm");
}
void SFM1SPIHID::traceTrackpad(const struct dlsp_message *message)
{
    struct m1tp_trace_record r;
    if (!m1tp_trace_select(&trackpadTrace,message,&r)) return;
    IOLog("DL24_TP_BEGIN seq=%u id=%02x bytes=%u reason=%u seen02=%u seen3f=%u seen44=%u\n",
          (unsigned)r.sequence,(unsigned)r.report_id,(unsigned)r.bytes,(unsigned)r.reason,
          (unsigned)r.seen02,(unsigned)r.seen3f,(unsigned)r.seen44);
    char hex[129];
    for (size_t index=0;index<(r.bytes+63u)/64u;index++) {
        (void)m1tp_trace_hex(message->payload,r.bytes,index,hex);
        IOLog("DL24_TP_HEX seq=%u index=%u data=%s\n",
              (unsigned)r.sequence,(unsigned)index,hex);
    }
    IOLog("DL24_TP_END seq=%u bytes=%u crc16=%04x\n",
          (unsigned)r.sequence,(unsigned)r.bytes,(unsigned)r.crc16);
}
void SFM1SPIHID::publishCounters(bool force)
{
    if (!force && !countersDirty) return;
    uint64_t t=SFM1KeyboardHW::clockUS();
    if (!force && lastCountersUS && t-lastCountersUS<100000) return;
    setProperty("SFM1KeyboardPackets",packetsRead,64);
    setProperty("SFM1KeyboardReports",reportsDelivered,64);
    setProperty("SFM1KeyboardOtherMessages",otherMessages,64);
    setProperty("SFM1KeyboardCountersUS",t,64);
    if (t2Enabled) {
        setProperty("SFM1TrackpadObserved",childObserved,64);
        setProperty("SFM1TrackpadRejected",childRejected,64);
        setProperty("SFM1TrackpadSubmitted",childSubmitted,64);
        if (mtEnabled) {
            setProperty("SFM1TrackpadTouchReports",mtTouchReports,64);
            setProperty("SFM1TrackpadBasicReports",mtBasicReports,64);
            setProperty("SFM1TrackpadPointerReports",mtPointerReports,64);
        }
    }
    lastCountersUS=t; countersDirty=false;
}
void SFM1SPIHID::fail(int error, const char *phase)
{
    stopping=true;
    if (t2Enabled) {
        if (t2Committed()) __atomic_store_n(&t2Phase,2,__ATOMIC_RELEASE);
        childFault((int32_t)error);
    }
    setProperty("SFM1KeyboardPhase",phase);
    setProperty("SFM1KeyboardError",(uint64_t)(int64_t)error,64);
    publishCounters(true);
    (void)recordBytes(this,"SFM1KeyboardLastWireHeaderV1",&lastObservation,sizeof(lastObservation));
    const struct m1kbd_observation *o=&lastObservation;
    IOLog("SFM1SPIHID: last completed packet present=%u flags=%02x device=%02x offset=%u remain=%u length=%u parser_error=%u\n",
          o->packet_available,o->packet_flags,o->packet_device,o->offset,o->remain,o->length,o->parser_error);
    IOLog("SFM1SPIHID: last decoded message present=%u flags=%02x device=%02x command=%02x report=%02x subdevice=%02x id=%u response_length=%u payload_length=%u\n",
          o->message_available,o->flags,o->device,o->command,o->report,o->subdevice,o->id,o->response_length,o->payload_length);
    if (requestPending)
        IOLog("SFM1SPIHID: pending request device=d0 command=20 report=%02x subdevice=%02x request_id=%u (response id diagnostic only)\n",
              (unsigned)pendingReport,(unsigned)pendingSubdevice,(unsigned)requestID);
    IOLog("SFM1SPIHID: stopped at %s, error %d; no automatic retry\n",phase,error);
    /* During init no producer exists. During a callback the workloop gate
     * serializes this stop; no callback unmaps resources or frees itself. */
    if (touchedHardware && !hardware.state()->busy) {
        /* Keep mappings until quiesce; core stop is synchronous. */
        struct m1kbd_hw *h=const_cast<struct m1kbd_hw *>(hardware.state());
        int e=m1kbd_hw_stop(h);
        if (e) setProperty("SFM1KeyboardCleanupError",(uint64_t)(int64_t)e,64);
    }
}
IOReturn SFM1SPIHID::stopGated(OSObject *owner, void *, void *, void *, void *)
{
    SFM1SPIHID *self=OSDynamicCast(SFM1SPIHID,owner);
    if (!self) return kIOReturnBadArgument;
    self->stopping=true; self->published=false;
    if (self->pollTimer) self->pollTimer->cancelTimeout();
    return kIOReturnSuccess;
}
void SFM1SPIHID::quiesce()
{
    if (t2Committed()) {
        IOLog("SFM1SPIHID: TEARDOWN_DEFERRED quiesce refused\n"); return;
    }
    if (transportGate && gateAdded) {
        IOReturn kr=transportGate->runAction(stopGated);
        if (kr!=kIOReturnSuccess) panic("SFM1SPIHID: refusing teardown without workloop quiescence");
    }
    else { stopping=true; published=false; }
    if (pollTimer && timerAdded) {
        pollTimer->cancelTimeout();
        transportLoop->removeEventSource(pollTimer); timerAdded=false;
    }
    if (hardware.state()->busy) panic("SFM1SPIHID: live transport after workloop quiescence");
    int e=hardware.closeAfterQuiesce();
    if (e) setProperty("SFM1KeyboardCleanupError",(uint64_t)(int64_t)e,64);
}
void SFM1SPIHID::handleStop(IOService *provider)
{
    if (t2Committed()) { (void)transportGate->runAction(stopT2Gated); return; }
    if (t2Enabled && !childState.faulted) childFault((int32_t)kIOReturnError);
    rollbackChild(); quiesce(); super::handleStop(provider);
}
void SFM1SPIHID::stop(IOService *provider)
{
    if (t2Committed()) {
        (void)transportGate->runAction(stopT2Gated);
        return;
    }
    if (privateStopDone || privateStopRunning) return;
    privateStopRunning=true;
    rollbackChild(); super::stop(provider);
    privateStopRunning=false; privateStopDone=true;
    disposeTransport();
}
void SFM1SPIHID::disposeTransport()
{
    if (t2Committed()) {
        IOLog("SFM1SPIHID: TEARDOWN_DEFERRED dispose refused\n"); return;
    }
    rollbackChild();
    quiesce();
    if (transportGate && gateAdded) { transportLoop->removeEventSource(transportGate); gateAdded=false; }
    if (pollTimer) { pollTimer->release(); pollTimer=nullptr; }
    if (transportGate) { transportGate->release(); transportGate=nullptr; }
    if (transportLoop) { transportLoop->release(); transportLoop=nullptr; }
    if (t2CommitData) { t2CommitData->release(); t2CommitData=nullptr; }
    if (t2Provider) { t2Provider->release(); t2Provider=nullptr; }
}
void SFM1SPIHID::free()
{
    if (t2Committed()) {
        IOLog("SFM1SPIHID: invariant violation; committed free refused\n"); return;
    }
    disposeTransport(); super::free();
}
bool SFM1SPIHID::terminate(IOOptionBits options)
{
    (void)options;
    /* IOResources is permanent. Dynamic detach is unsupported in this
     * first candidate; start-failure cleanup still calls stop directly. */
    return false;
}
IOReturn SFM1SPIHID::newReportDescriptor(IOMemoryDescriptor **out) const
{
    if (!out) return kIOReturnBadArgument;
    *out=nullptr;
    if (!descriptorLength) return kIOReturnNotReady;
    *out=IOBufferMemoryDescriptor::withBytes(descriptor,descriptorLength,kIODirectionNone);
    return *out?kIOReturnSuccess:kIOReturnNoMemory;
}
OSString *SFM1SPIHID::newTransportString() const { return OSString::withCString("SPI"); }
OSString *SFM1SPIHID::newProductString() const { return OSString::withCString("Apple SPI Keyboard (J293)"); }
OSNumber *SFM1SPIHID::newVendorIDNumber() const { return OSNumber::withNumber(identity.vendor,32); }
OSNumber *SFM1SPIHID::newProductIDNumber() const { return OSNumber::withNumber(identity.product,32); }
OSNumber *SFM1SPIHID::newVersionNumber() const { return OSNumber::withNumber(identity.version,32); }
OSNumber *SFM1SPIHID::newLocationIDNumber() const { return OSNumber::withNumber(0x3510c000,32); }
OSNumber *SFM1SPIHID::newCountryCodeNumber() const { return OSNumber::withNumber(identity.country,32); }

#include "SFM1SPIHIDChild.inc"
#include "SFM1SPIHIDMultitouch.inc"
