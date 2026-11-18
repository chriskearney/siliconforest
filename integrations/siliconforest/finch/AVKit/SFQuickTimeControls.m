/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * The rest of the AVKit names QuickTime Player binds or instantiates: the controls view
 * controller it subclasses, the time resolver, the volume slider, the Touch Bar recording
 * provider, the two media-selection menu builders and the audio-only view its nib names.
 *
 * Superclasses, selector names and argument types are the ones the Objective-C runtime
 * reports for these classes (our own metadata probe; see PRIVATE-ABI.md). Behaviour is
 * written from what our probes observed and no further:
 *   - the volume slider is a working control;
 *   - the time resolver holds the values the probes saw it hold and seeks the controller;
 *     it is not notification-exact (TIME-RESOLVER-2026-11-15.md lists what is unknown);
 *   - everything else is an absence: it can be created or called, does nothing it cannot
 *     do properly, and says so once on stderr. Nothing here pretends to work. */
#import <AppKit/AppKit.h>
#import <AVKit/SFPlayerController.h>
#include <math.h>
#include <stdio.h>

#define SF_EXPORT __attribute__((visibility("default")))

static void SFAbsent(BOOL *said, const char *what) {
    if (!*said) {
        *said = YES;
        fprintf(stderr, "AVKit: %s\n", what);
    }
}

/* ---- controls view controllers -------------------------------------------------------- */

SF_EXPORT
@interface AVControlsViewController : NSViewController {
    AVPlayerController *_sfPlayerController;
}
@property(retain) AVPlayerController *playerController;
@end

@implementation AVControlsViewController
- (AVPlayerController *)playerController {
    return _sfPlayerController;
}
- (void)setPlayerController:(AVPlayerController *)controller {
    if (controller == _sfPlayerController) return;
    [self willChangeValueForKey:@"playerController"];
    [_sfPlayerController release];
    _sfPlayerController = [controller retain];
    [self didChangeValueForKey:@"playerController"];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    return [key isEqualToString:@"playerController"] ? NO : [super automaticallyNotifiesObserversForKey:key];
}
/* A subclass that brings no nib still gets a view: an empty one. */
- (void)loadView {
    if ([self nibName] != nil) {
        [super loadView];
        return;
    }
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 44)];
    [self setView:view];
    [view release];
}
- (void)dealloc {
    [_sfPlayerController release];
    [super dealloc];
}
@end

SF_EXPORT
@interface AVPlayerControlsViewController : AVControlsViewController {
    id _sfShareButton;
}
@property(retain) id shareButton;
@property(readonly) id shareController;
@end

@implementation AVPlayerControlsViewController
- (id)init {
    static BOOL said;
    SFAbsent(&said, "AVPlayerControlsViewController has no built-in transport, trim or share controls here; "
                    "a subclass gets an empty view and the player controller it is given");
    return [super init];
}
- (id)shareButton {
    return _sfShareButton;
}
- (void)setShareButton:(id)button {
    [button retain];
    [_sfShareButton release];
    _sfShareButton = button;
}
/* No sharing services exist on SiliconForest. */
- (id)shareController {
    static BOOL said;
    SFAbsent(&said, "AVPlayerControlsViewController.shareController: no sharing services, returning nil");
    return nil;
}
- (void)controlTextDidBeginEditing:(NSNotification *)note {
    (void)note;
}
- (void)controlTextDidEndEditing:(NSNotification *)note {
    (void)note;
}
/* Subclasses forward observations they do not recognise to super; NSObject would raise. */
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    (void)path; (void)object; (void)change; (void)context;
}
- (void)dealloc {
    [_sfShareButton release];
    [super dealloc];
}
@end

/* ---- time resolver -------------------------------------------------------------------- */

SF_EXPORT
@interface AVPlayerControllerTimeResolver : NSObject {
    AVPlayerController *_sfController;
    double _sfTime, _sfInterval, _sfResolution, _sfMinTime, _sfMaxTime;
    double _sfControllerTimeAtRequest;
    BOOL _sfPending;
}
@property(retain) AVPlayerController *playerController;
@property double currentTime, currentTimeWithinEndTimes, targetTime, targetTimeWithinEndTimes;
@property double interval, resolution, minTime, maxTime;
@end

@implementation AVPlayerControllerTimeResolver
- (id)init {
    if ((self = [super init])) _sfInterval = 1; /* observed default; every other scalar starts at 0 */
    return self;
}
+ (NSSet *)keyPathsForValuesAffectingCurrentTimeWithinEndTimes {
    return [NSSet setWithObject:@"currentTime"];
}
- (AVPlayerController *)playerController {
    return _sfController;
}
- (void)setPlayerController:(AVPlayerController *)controller {
    [controller retain];
    [_sfController release];
    _sfController = controller;
    _sfPending = NO;
    if (controller != nil) {
        _sfMinTime = [controller minTime];
        _sfMaxTime = [controller maxTime];
    }
}
/* Without a controller the four time properties are one stored value (observed). With one,
 * a request is reported back until the controller's own time moves, then the controller's
 * time is reported. */
- (double)sfTime {
    if (_sfController == nil) return _sfTime;
    double now = [_sfController currentTime];
    if (_sfPending && now == _sfControllerTimeAtRequest) return _sfTime;
    _sfPending = NO;
    return now;
}
- (void)sfSetTime:(double)seconds {
    static BOOL said;
    [self willChangeValueForKey:@"currentTime"];
    _sfTime = seconds;
    if (_sfController != nil && !isnan(seconds)) {
        SFAbsent(&said, "AVPlayerControllerTimeResolver seeks the controller directly; settled-seek and "
                        "notification order are not those of macOS");
        _sfControllerTimeAtRequest = [_sfController currentTime];
        _sfPending = YES;
        [_sfController seekToTime:seconds];
    }
    [self didChangeValueForKey:@"currentTime"];
}
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    return [key isEqualToString:@"currentTime"] ? NO : [super automaticallyNotifiesObserversForKey:key];
}
- (double)currentTime { return [self sfTime]; }
- (void)setCurrentTime:(double)t { [self sfSetTime:t]; }
- (double)currentTimeWithinEndTimes { return [self sfTime]; }
- (void)setCurrentTimeWithinEndTimes:(double)t { [self sfSetTime:t]; }
- (double)targetTime { return [self sfTime]; }
- (void)setTargetTime:(double)t { [self sfSetTime:t]; }
- (double)targetTimeWithinEndTimes { return [self sfTime]; }
- (void)setTargetTimeWithinEndTimes:(double)t { [self sfSetTime:t]; }
- (double)interval { return _sfInterval; }
- (void)setInterval:(double)v { _sfInterval = v; }
- (double)resolution { return _sfResolution; }
- (void)setResolution:(double)v { _sfResolution = v; }
- (double)minTime { return _sfMinTime; }
- (void)setMinTime:(double)v { _sfMinTime = v; }
- (double)maxTime { return _sfMaxTime; }
- (void)setMaxTime:(double)v { _sfMaxTime = v; }
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    (void)path; (void)object; (void)change; (void)context;
}
- (void)dealloc {
    [_sfController release];
    [super dealloc];
}
@end

/* ---- volume control ------------------------------------------------------------------- */

@protocol AVVolumeControlViewDelegate <NSObject>
@optional
- (void)volumeControlViewDidChangeVolume:(id)view;
- (void)volumeControlViewDidChangeMutedState:(id)view;
@end

SF_EXPORT
@interface AVVolumeControlView : NSView {
    id<AVVolumeControlViewDelegate> _sfDelegate; /* not retained */
    double _sfVolume;
    BOOL _sfMuted;
}
@property(assign) id<AVVolumeControlViewDelegate> delegate;
@property(nonatomic) double volume;
@property(nonatomic, getter=isMuted) BOOL muted;
@end

@implementation AVVolumeControlView
- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) _sfVolume = 1;
    return self;
}
- (id<AVVolumeControlViewDelegate>)delegate { return _sfDelegate; }
- (void)setDelegate:(id<AVVolumeControlViewDelegate>)delegate { _sfDelegate = delegate; }
- (double)volume { return _sfVolume; }
- (void)setVolume:(double)volume {
    _sfVolume = volume < 0 ? 0 : (volume > 1 ? 1 : volume);
    [self setNeedsDisplay:YES];
}
- (BOOL)isMuted { return _sfMuted; }
- (void)setMuted:(BOOL)muted {
    _sfMuted = muted;
    [self setNeedsDisplay:YES];
}
@end

SF_EXPORT
@interface AVVolumeControlSlider : AVVolumeControlView {
    NSSlider *_sfSlider;
}
@end

@implementation AVVolumeControlSlider
- (void)sfMakeSlider {
    _sfSlider = [[NSSlider alloc] initWithFrame:[self bounds]];
    [_sfSlider setMinValue:0];
    [_sfSlider setMaxValue:1];
    [_sfSlider setDoubleValue:_sfVolume];
    [_sfSlider setContinuous:YES];
    [_sfSlider setTarget:self];
    [_sfSlider setAction:@selector(sfSliderMoved:)];
    [_sfSlider setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self addSubview:_sfSlider];
}
- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self sfMakeSlider];
    return self;
}
- (id)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        _sfVolume = 1;
        [self sfMakeSlider];
    }
    return self;
}
- (void)sfSliderMoved:(id)sender {
    (void)sender;
    BOOL wasMuted = _sfMuted;
    _sfVolume = [_sfSlider doubleValue];
    _sfMuted = NO;
    if ([_sfDelegate respondsToSelector:@selector(volumeControlViewDidChangeVolume:)])
        [_sfDelegate volumeControlViewDidChangeVolume:self];
    if (wasMuted && [_sfDelegate respondsToSelector:@selector(volumeControlViewDidChangeMutedState:)])
        [_sfDelegate volumeControlViewDidChangeMutedState:self];
}
- (void)setVolume:(double)volume {
    [super setVolume:volume];
    [_sfSlider setDoubleValue:_sfMuted ? 0 : _sfVolume];
}
- (void)setMuted:(BOOL)muted {
    [super setMuted:muted];
    [_sfSlider setDoubleValue:muted ? 0 : _sfVolume];
}
- (NSView *)firstKeyView {
    return _sfSlider;
}
- (void)setUpKeyViewLoopWithNextKeyView:(NSView *)next {
    [_sfSlider setNextKeyView:next];
}
- (void)dealloc {
    [_sfSlider release];
    [super dealloc];
}
@end

/* ---- Touch Bar recording controls: no Touch Bar items for recording ---------------------- */

SF_EXPORT
@interface AVTouchBarRecordingControlsProvider : NSResponder {
    id _sfRecordingController; /* not retained */
    NSInteger _sfControlsType;
}
@end

@implementation AVTouchBarRecordingControlsProvider
- (void)setControlsType:(NSInteger)type { _sfControlsType = type; }
- (NSInteger)controlsType { return _sfControlsType; }
- (void)setRecordingControlsController:(id)controller { _sfRecordingController = controller; }
- (id)recordingControlsController { return _sfRecordingController; }
- (id)touchBar {
    static BOOL said;
    SFAbsent(&said, "AVTouchBarRecordingControlsProvider: no recording controls for the Touch Bar, returning nil");
    return nil;
}
- (id)touchBar:(id)touchBar makeItemForIdentifier:(id)identifier {
    (void)touchBar; (void)identifier;
    return nil;
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    (void)path; (void)object; (void)change; (void)context;
}
@end

/* ---- media selection menus -------------------------------------------------------------- *
 * Arguments as the caller passes them: the menu to fill, the player controller, the target
 * and action for the items. macOS leaves the menu empty when the controller reports no
 * options (observed, MENU-2026-11-15.md); what a filled menu looks like is not established,
 * and audio or subtitle selection does not reach our player. The menu is left as it is. */
SF_EXPORT void AVAddAudibleMediaSelectionOptionsToMenu(NSMenu *menu, id playerController, id target, SEL action) {
    static BOOL said;
    (void)menu; (void)playerController; (void)target; (void)action;
    SFAbsent(&said, "AVAddAudibleMediaSelectionOptionsToMenu: audio track selection is not implemented, menu left unchanged");
}
SF_EXPORT void AVAddLegibleMediaSelectionOptionsToMenu(NSMenu *menu, id playerController, id target, SEL action) {
    static BOOL said;
    (void)menu; (void)playerController; (void)target; (void)action;
    SFAbsent(&said, "AVAddLegibleMediaSelectionOptionsToMenu: subtitle selection is not implemented, menu left unchanged");
}

/* ---- audio-only view --------------------------------------------------------------------- *
 * Named only in the audio document's nib, so its interface is not in any import table. It
 * exists so that the nib loads; it draws a plain dark panel, not a waveform or controls.
 * A message it does not implement raises "unrecognized selector", which names the gap. */
SF_EXPORT
@interface AVAudioView : NSView
@end

@implementation AVAudioView
- (void)sfSay {
    static BOOL said;
    SFAbsent(&said, "AVAudioView is a placeholder panel: no audio-only controls or waveform are drawn");
}
- (id)initWithFrame:(NSRect)frame {
    [self sfSay];
    return [super initWithFrame:frame];
}
- (id)initWithCoder:(NSCoder *)coder {
    [self sfSay];
    return [super initWithCoder:coder];
}
- (BOOL)isOpaque {
    return YES;
}
- (void)drawRect:(NSRect)rect {
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1] set];
    NSRectFill(rect);
}
@end
