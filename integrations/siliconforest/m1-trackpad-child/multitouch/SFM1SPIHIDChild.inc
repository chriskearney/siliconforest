/* Original T2-only lifecycle. Included by SFM1SPIHID.cpp after the frozen
 * transport implementation. No SPI encoder/request or async report API. */

bool SFM1SPIHID::t2Committed() const
{ return t2Enabled && __atomic_load_n(&t2Phase,__ATOMIC_ACQUIRE)!=0; }

bool SFM1SPIHID::handleOpen(IOService *client, IOOptionBits options, void *argument)
{
    /* M1: legacy T1 base-start can already match/open before timer arm. */
    if (t2Enabled && (__atomic_load_n(&t2Phase,__ATOMIC_ACQUIRE)!=1 || isInactive()))
        return false;
    return super::handleOpen(client,options,argument);
}
IOReturn SFM1SPIHID::newUserClient(task_t task, void *security, UInt32 type,
    OSDictionary *properties, IOUserClient **out)
{
    if (t2Enabled && (__atomic_load_n(&t2Phase,__ATOMIC_ACQUIRE)!=1 || isInactive())) {
        if (out) *out=nullptr;
        return kIOReturnNotReady;
    }
    return super::newUserClient(task,security,type,properties,out);
}

void SFM1SPIHID::removeChildState()
{
    removeProperty(DL_M1_TP_CHILD_STATE_PROPERTY);
    if (t2Provider) t2Provider->removeProperty(DL_M1_TP_CHILD_STATE_PROPERTY);
    if (childOwned && childInitialized) childOwned->removeProperty(DL_M1_TP_CHILD_STATE_PROPERTY);
}
bool SFM1SPIHID::installChildState(OSData *data)
{
    /* Do not short-circuit the three independent immutable copies. */
    bool a=data && setProperty(DL_M1_TP_CHILD_STATE_PROPERTY,data);
    bool b=data && t2Provider && t2Provider->setProperty(DL_M1_TP_CHILD_STATE_PROPERTY,data);
    bool c=!childInitialized || (data && childOwned && childOwned->setProperty(DL_M1_TP_CHILD_STATE_PROPERTY,data));
    if (!a || !b || !c) {
        removeChildState();
        IOLog("SFM1SPIHID: T2 diagnostic publication failed parent=%u provider=%u child=%u; old ready copies removed\n",
              a?1u:0u,b?1u:0u,c?1u:0u);
        return false;
    }
    return true;
}
bool SFM1SPIHID::publishChildState()
{
    /* Never modify OSData visible to MIG; invalidate before allocating a
     * replacement. A reader may already hold an older snapshot. */
    removeChildState();
    OSData *copy=OSData::withBytes(&childState,sizeof(childState));
    bool okay=installChildState(copy);
    if (copy) copy->release();
    return okay;
}
void SFM1SPIHID::childFault(int32_t error)
{
    childSink=nullptr;
    if (childOwned) childOwned->markRetired();
    childState.route_ready=0; childState.faulted=1;
    if (!childState.last_error)
        childState.last_error=error?error:(int32_t)kIOReturnError;
    bool saved=publishChildState();
    IOLog("SFM1SPIHID: T2 fault committed=%u cause=%d diagnostic=%u (not input)\n",
          childState.committed,(int)childState.last_error,saved?1u:0u);
}

bool SFM1SPIHID::prepareChild()
{
    static_assert(SF_TRACKPAD_DESCRIPTOR_LENGTH==DL_M1_TP_DESCRIPTOR_BYTES,"reference length");
    if (trackpadEnumeration.result!=M1TP_OBS_ENUM_OK ||
        trackpadEnumeration.stage!=M1TP_OBS_COMPLETE ||
        trackpadEnumeration.request_mask!=M1TP_CLAIM_MASK ||
        trackpadInterface.interface!=2 ||
        trackpadEnumeration.descriptor_payload_bytes!=DL_M1_TP_DESCRIPTOR_BYTES ||
        !sf_trackpad_descriptor_matches(trackpadEnumeration.descriptor,trackpadEnumeration.descriptor_bytes,
                                        sf_trackpad_descriptor_sha256)) {
        childFault((int32_t)kIOReturnUnsupported); return false;
    }
    childOwned=new SFM1SPITrackpad;
    /* Multitouch mode: the acquired descriptor is still the identity guard
     * above, but the child publishes the pointer report this driver
     * synthesizes (buttons, X, Y, wheel) instead of the device's own. */
    childInitialized=childOwned && (mtEnabled ?
        childOwned->initWithSnapshot(m1tp_mt_pointer_descriptor,sizeof(m1tp_mt_pointer_descriptor),
            identity.vendor,identity.product,identity.version,trackpadInterface.country) :
        childOwned->initWithSnapshot(trackpadEnumeration.descriptor,
            trackpadEnumeration.descriptor_bytes,identity.vendor,identity.product,identity.version,
            trackpadInterface.country));
    if (!childInitialized) {
        childFault((int32_t)kIOReturnNoMemory); return false;
    }
    if (!childOwned->attach(this)) { childFault((int32_t)kIOReturnError); return false; }
    childAttached=true;
    childStarted=childOwned->start(this);
    if (!childStarted) { childFault((int32_t)kIOReturnError); return false; }
    return true;
}
void SFM1SPIHID::rollbackChild()
{
    if (t2Committed()) {
        IOLog("SFM1SPIHID: TEARDOWN_DEFERRED child rollback refused\n"); return;
    }
    /* Private startup has no producer or matching callback. Move the allocation
     * reference before stop reentry; releasing a sink never releases ownership. */
    SFM1SPITrackpad *child=childOwned;
    bool attached=childAttached, started=childStarted;
    childSink=nullptr; childOwned=nullptr; childInitialized=false; childAttached=false; childStarted=false;
    if (!child) return;
    if (started) child->stop(this); // failed base start already stopped itself
    if (attached) child->detach(this);
    child->release();
}
bool SFM1SPIHID::startT2(IOService *provider)
{
    if (!prepareChild()) rollbackChild(); // explicit keyboard-only fallback
    struct dl_m1_trackpad_child_state_v1 next=childState;
    next.committed=1;
    next.route_ready=childStarted && !next.faulted ? 1u : 0u;
    t2CommitData=OSData::withBytes(&next,sizeof(next));
    IOReturn commitError=!t2CommitData ? kIOReturnNoMemory :
        !transportGate ? kIOReturnNotReady : transportGate->runAction(commitT2Gated);
    if (commitError!=kIOReturnSuccess) {
        childFault((int32_t)commitError);
        rollbackChild(); stop(provider); return false;
    }
    /* From here no false return or rollback, even if a concurrent runtime
     * stop/diagnostic failure inhibits registration. Explicit pins remain. */
    t2CommitData->release(); t2CommitData=nullptr;
    if (__atomic_load_n(&t2Phase,__ATOMIC_ACQUIRE)==1)
        registerService(kIOServiceAsynchronous);
    if (childOwned && childOwned->admitting() && !childOwned->isInactive())
        childOwned->registerService(kIOServiceAsynchronous);
    IOLog("SFM1SPIHID: T2 committed retained cohort; asynchronous registration requested (not input)\n");
    return true;
}
IOReturn SFM1SPIHID::commitT2Gated(OSObject *owner, void *, void *, void *, void *)
{
    SFM1SPIHID *self=OSDynamicCast(SFM1SPIHID,owner);
    if (!self || self->stopping || self->t2Committed() || !self->t2CommitData ||
        (self->childOwned && (!self->childStarted || self->childOwned->isInactive())))
        return kIOReturnNotReady;
    IOReturn kr=self->pollTimer->setTimeoutMS(2);
    if (kr!=kIOReturnSuccess) return kr;
    self->retain(); // permanent boot pin: intentionally no release path
    if (self->childOwned) {
        self->childOwned->retain(); // second permanent boot pin
        self->childOwned->markCommitted();
    }
    __atomic_store_n(&self->t2Phase,1,__ATOMIC_RELEASE);
    self->published=true;
    self->childState.committed=1;
    self->childSink=self->childStarted && !self->childState.faulted ? self->childOwned : nullptr;
    self->childState.route_ready=self->childSink?1u:0u;
    /* Request touch data once the pointer child can take the result; without
     * a child the controller stays in its basic mode. */
    if (self->mtEnabled && self->childSink) self->mtModeDueUS=SFM1KeyboardHW::clockUS();
    else self->mtEnabled=false;
    if (!self->installChildState(self->t2CommitData))
        self->childFault((int32_t)kIOReturnNoMemory); // runtime failure, retain cohort
    return kIOReturnSuccess;
}
IOReturn SFM1SPIHID::stopT2Gated(OSObject *owner, void *, void *, void *, void *)
{
    SFM1SPIHID *self=OSDynamicCast(SFM1SPIHID,owner);
    if (!self || !self->t2Committed()) return kIOReturnNotReady;
    __atomic_store_n(&self->t2Phase,2,__ATOMIC_RELEASE);
    self->stopping=true; self->published=false; self->childSink=nullptr;
    if (self->childOwned) self->childOwned->markRetired();
    self->childState.route_ready=0; self->childState.stop_requested=1;
    if (self->pollTimer) self->pollTimer->cancelTimeout();
    bool saved=self->publishChildState();
    IOLog("SFM1SPIHID: TEARDOWN_DEFERRED dispatches=%u diagnostic=%u (retained until reboot)\n",
          self->t2Dispatches,saved?1u:0u);
    return kIOReturnSuccess;
}
void SFM1SPIHID::retireChild(SFM1SPITrackpad *expected)
{
    if (!expected || !transportGate || !gateAdded) return;
    IOReturn kr=transportGate->runAction(retireChildGated,expected);
    if (kr!=kIOReturnSuccess) {
        /* Child's atomic admission already closed; never destroy on failure. */
        removeChildState();
        IOLog("SFM1SPIHID: T2 recursive sink clear failed=%d; retained\n",(int)kr);
    }
}
IOReturn SFM1SPIHID::retireChildGated(OSObject *owner, void *arg, void *, void *, void *)
{
    SFM1SPIHID *self=OSDynamicCast(SFM1SPIHID,owner);
    SFM1SPITrackpad *child=static_cast<SFM1SPITrackpad *>(arg);
    if (!self || !child) return kIOReturnBadArgument;
    if (self->childSink==child) self->childSink=nullptr;
    if (self->childOwned==child && self->t2Committed()) {
        child->markRetired();
        self->childState.route_ready=0; self->childState.stop_requested=1;
        (void)self->publishChildState();
    }
    return kIOReturnSuccess;
}

void SFM1SPIHID::routeTrackpad(const struct dlsp_message *message)
{
    childObserved++; countersDirty=true;
    int eligible=m1tp_child_input(message);
    if (eligible!=1) {
        childRejected++;
        if (childRejected==1)
            IOLog("SFM1SPIHID: T2 input rejected id=%u bytes=%u (no payload)\n",
                  message->payload && message->payload_length?(unsigned)message->payload[0]:0u,
                  (unsigned)message->payload_length);
        return; // no route fault/last_error change for ordinary input refusal
    }
    SFM1SPITrackpad *child=childSink;
    if (!child) return;
    if (!child->admitting() || child->isInactive()) { retireChild(child); return; }
    IOBufferMemoryDescriptor *report=IOBufferMemoryDescriptor::withBytes(
        message->payload,message->payload_length,kIODirectionNone);
    if (!report) { childFault((int32_t)kIOReturnNoMemory); return; }
    retain(); child->retain(); t2Dispatches++;
    /* M4: synchronous base handleReport uses retained IOHIDDevice::_workLoop.
     * Never invoke an async API or resolve the provider loop after detach. */
    IOReturn kr=child->handleReport(report,kIOHIDReportTypeInput);
    t2Dispatches--;
    if (kr==kIOReturnSuccess) {
        childSubmitted++;
        if (childSubmitted==1)
            IOLog("SFM1SPIHID: first dev2 input submitted to passive child; physical input unverified\n");
    } else childFault((int32_t)kr);
    report->release(); child->release(); release();
}
