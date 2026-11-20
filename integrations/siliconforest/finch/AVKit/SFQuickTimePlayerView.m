/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Messages Apple's QuickTime Player sends to AVPlayerView, AVPlayerController and AVPlayer that the public
 * interface does not declare (macOS keeps them private). Types are read from the application's call sites;
 * what they do is what the names and the application's use say, written here from that. A setting this
 * player cannot act on is kept and answered, and says so once on stderr. */
#import <AVKit/AVKit.h>
#import <AVKit/SFPlayerController.h>
#import <AVFoundation/AVFoundation.h>
#include <objc/runtime.h>
#include <math.h>
#include <stdio.h>

static char kController, kLayoutMode, kControlsMargin, kSlowMotionDelegate, kCanZoomH, kCanZoomV, kZoomed,
    kCanHideControls, kAlternatePreview, kFixedLayerSize, kStereoEnable, kStereoEyes, kDisplaySleep, kDisplays;

static void sfOnce(const char *what)
{
    static NSMutableSet *said;
    @synchronized([AVPlayerView class]) {
        if (!said)
            said = [NSMutableSet new];
        NSString *key = [NSString stringWithUTF8String:what];
        if ([said containsObject:key])
            return;
        [said addObject:key];
    }
    fprintf(stderr, "SiliconForest AVKit: %s\n", what);
}

static id sfGet(id object, const void *key) { return objc_getAssociatedObject(object, key); }
static void sfSet(id object, const void *key, id value) { objc_setAssociatedObject(object, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL sfBool(id object, const void *key) { return [sfGet(object, key) boolValue]; }
static void sfSetBool(id object, const void *key, BOOL value) { sfSet(object, key, [NSNumber numberWithBool:value]); }

/* the content's size: the controller's, else the current item's presentation size */
static CGSize sfContentSize(AVPlayerView *view)
{
    AVPlayerController *controller = sfGet(view, &kController);
    AVPlayer *player = controller ? controller.player : view.player;
    CGSize size = player.currentItem ? [player.currentItem presentationSize] : CGSizeZero;
    return (size.width > 0 && size.height > 0) ? size : CGSizeZero;
}

@implementation AVPlayerView (SFQuickTimePrivate)

- (AVPlayerController *)playerController
{
    return sfGet(self, &kController);
}

- (void)setPlayerController:(AVPlayerController *)controller
{
    sfSet(self, &kController, controller);
    if (controller && controller.player != self.player)
        [self setPlayer:controller.player];
}

/* how the player layer sits in the view; every mode is drawn as the aspect fit (the only layout here) */
- (NSInteger)playerLayerLayoutMode
{
    return [sfGet(self, &kLayoutMode) integerValue];
}

- (void)setPlayerLayerLayoutMode:(NSInteger)mode
{
    if (mode != 0)
        sfOnce("player layer layout modes other than the aspect fit are drawn as the aspect fit");
    sfSet(self, &kLayoutMode, [NSNumber numberWithInteger:mode]);
    [self setNeedsLayout:YES];
}

/* the player layer's frame in a view of that size: the content fitted, its aspect kept, centred */
- (CGRect)playerLayerFrameForBoundsSize:(CGSize)size playerLayerLayoutMode:(NSInteger)mode
{
    (void)mode;
    CGSize content = sfContentSize(self);
    if (content.width <= 0 || content.height <= 0 || size.width <= 0 || size.height <= 0)
        return CGRectMake(0, 0, size.width, size.height);
    CGFloat scale = fmin(size.width / content.width, size.height / content.height);
    CGFloat w = content.width * scale, h = content.height * scale;
    return CGRectMake(round((size.width - w) / 2), round((size.height - h) / 2), round(w), round(h));
}

- (CGRect)playerLayerFrame
{
    return [self playerLayerFrameForBoundsSize:NSSizeToCGSize(self.bounds.size) playerLayerLayoutMode:[self playerLayerLayoutMode]];
}

- (CGSize)currentVideoSize
{
    return [self playerLayerFrame].size;
}

/* space kept free around the floating controls; this player draws its own bar at the bottom */
- (void)setFloatingPlaybackControlsMargin:(NSEdgeInsets)margin
{
    sfOnce("the floating controls' margin is kept; the transport bar is drawn at the bottom");
    sfSet(self, &kControlsMargin, [NSValue valueWithBytes:&margin objCType:@encode(NSEdgeInsets)]);
}

- (NSEdgeInsets)floatingPlaybackControlsMargin
{
    NSEdgeInsets margin = {0, 0, 0, 0};
    [(NSValue *)sfGet(self, &kControlsMargin) getValue:&margin];
    return margin;
}

- (id)slowMotionDelegate { return objc_getAssociatedObject(self, &kSlowMotionDelegate); }
- (void)setSlowMotionDelegate:(id)delegate { objc_setAssociatedObject(self, &kSlowMotionDelegate, delegate, OBJC_ASSOCIATION_ASSIGN); }

/* zooming (QuickTime's magnify gesture) is not done by this view: the answers are kept */
- (BOOL)canZoomHorizontally { return sfBool(self, &kCanZoomH); }
- (void)setCanZoomHorizontally:(BOOL)value { sfSetBool(self, &kCanZoomH, value); }
- (BOOL)canZoomVertically { return sfBool(self, &kCanZoomV); }
- (void)setCanZoomVertically:(BOOL)value { sfSetBool(self, &kCanZoomV, value); }
- (BOOL)isZoomed { return sfBool(self, &kZoomed); }
- (void)setZoomed:(BOOL)value
{
    if (value)
        sfOnce("zoomed video is drawn unzoomed");
    sfSetBool(self, &kZoomed, value);
}

- (BOOL)canHideControls { return sfBool(self, &kCanHideControls); }
- (void)setCanHideControls:(BOOL)value { sfSetBool(self, &kCanHideControls, value); }

- (BOOL)showsAlternateMediaTrackPreview { return sfBool(self, &kAlternatePreview); }
- (void)setShowsAlternateMediaTrackPreview:(BOOL)value { sfSetBool(self, &kAlternatePreview, value); }

- (void)setFixedPlayerLayerSize:(CGSize)size { sfSet(self, &kFixedLayerSize, [NSValue valueWithSize:NSSizeFromCGSize(size)]); }
- (CGSize)fixedPlayerLayerSize { return NSSizeToCGSize([(NSValue *)sfGet(self, &kFixedLayerSize) sizeValue]); }

/* stereo (spatial) video is not decoded here: never available */
- (BOOL)enableStereoEyesIfAvailable { return sfBool(self, &kStereoEnable); }
- (void)setEnableStereoEyesIfAvailable:(BOOL)value { sfSetBool(self, &kStereoEnable, value); }
- (NSInteger)stereoEyes { return [sfGet(self, &kStereoEyes) integerValue]; }
- (void)setStereoEyes:(NSInteger)eyes { sfSet(self, &kStereoEyes, [NSNumber numberWithInteger:eyes]); }

- (BOOL)automaticDisplaySleepManagement { return sfBool(self, &kDisplaySleep); }
- (void)setAutomaticDisplaySleepManagement:(BOOL)value { sfSetBool(self, &kDisplaySleep, value); }

/* the time display's styles (elapsed, remaining, timecode, frames on macOS): this view's bar shows the elapsed
   time only, so none is offered to choose from; the chosen one is kept */
static char kTimeStyle;
- (NSArray *)allowedTimeDisplayStyles { return [NSArray array]; }
- (NSArray *)availableTimeDisplayStyles { return [NSArray array]; }

/* whether the view keeps its controls off the picture (full screen); they are drawn below it here */
static char kUnobscured;
- (BOOL)prefersUnobscuredContent { return [objc_getAssociatedObject(self, &kUnobscured) boolValue]; }
- (void)setPrefersUnobscuredContent:(BOOL)value { objc_setAssociatedObject(self, &kUnobscured, [NSNumber numberWithBool:value], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

/* the magnification at which the picture is shown at its own size (View > Actual Size) */
- (double)_calculateMagnificationForActualSize
{
    CGSize content = sfContentSize(self);
    CGRect frame = [self playerLayerFrame];
    if (content.width <= 0 || frame.size.width <= 0)
        return 1.0;
    return [self magnification] * content.width / frame.size.width;
}
- (NSInteger)timeDisplayStyle { return [objc_getAssociatedObject(self, &kTimeStyle) integerValue]; }
- (void)setTimeDisplayStyle:(NSInteger)style { objc_setAssociatedObject(self, &kTimeStyle, [NSNumber numberWithInteger:style], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

/* the slow part of a high-frame-rate movie, which the view marks on its time line on macOS: slow motion is not
   offered here (PhotosFormats), so the range is kept and nothing is marked */
static char kSlowMotionRange;
- (CMTimeRange)slowMotionTimeRange
{
    CMTimeRange range = kCMTimeRangeInvalid;
    [(NSValue *)objc_getAssociatedObject(self, &kSlowMotionRange) getValue:&range];
    return range;
}
- (void)setSlowMotionTimeRange:(CMTimeRange)range
{
    objc_setAssociatedObject(self, &kSlowMotionRange, [NSValue valueWithBytes:&range objCType:@encode(CMTimeRange)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* the object behind the view's Share menu on macOS: sharing is not offered by this view */
- (id)shareController { return nil; }

/* the bar of edit (trim) controls: not available here; the handler is called as when the change is done */
- (void)hideEditControlsViewControllerWithCompletionHandler:(void (^)(void))handler
{
    if (handler)
        handler();
}

- (void)showEditControlsViewController:(id)controller withCompletionHandler:(void (^)(void))handler
{
    (void)controller;
    sfOnce("edit (trim) controls are not shown by this view");
    if (handler)
        handler();
}

/* the controls drawn again now (while paused no picture time redraws them) */
- (void)sfRedrawControls
{
    for (NSView *view in self.subviews)
        if ([view respondsToSelector:@selector(sfIdleHidden)]) { [view setHidden:NO]; [view display]; }
    [self setNeedsDisplay:YES];
}

/* the keyboard, as AVKit's player view has it: space plays or pauses, the left and right arrows step one picture
   back or forward (pausing) */
- (BOOL)acceptsFirstResponder { return self.player != nil; }

- (void)keyDown:(NSEvent *)event
{
    NSString *keys = [event charactersIgnoringModifiers];
    unichar key = [keys length] ? [keys characterAtIndex:0] : 0;
    NSUInteger modifiers = [event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask | NSAlternateKeyMask);
    AVPlayer *player = self.player;
    if (player && !modifiers && key == ' ') {
        if (player.rate != 0)
            [player pause];
        else
            [player play];
        [self sfRedrawControls];
        return;
    }
    if (player && !modifiers && (key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey)) {
        [player pause];
        [player.currentItem stepByCount:key == NSRightArrowFunctionKey ? 1 : -1];
        [self sfRedrawControls];
        return;
    }
    [super keyDown:event];
}

/* trimming (public on macOS) is not available in this view */
- (BOOL)canBeginTrimming { return NO; }
- (BOOL)isTrimming { return NO; }

@end

@implementation AVPlayer (SFQuickTimePrivate)

/* the displays the picture is on (one panel here): kept, no effect */
- (void)_setDisplaysUsedForPlayback:(id)displays { objc_setAssociatedObject(self, &kDisplays, displays, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)_displaysUsedForPlayback { return objc_getAssociatedObject(self, &kDisplays); }

/* nothing played here is copy-protected: the status is the one the application itself assumes when it does not
   check (1), so no protection alert is shown */
- (NSInteger)_externalProtectionStatus { return 1; }

/* how sound with more than two channels is rendered (macOS 10.15+); this player mixes it to the output: kept */
static char kMultichannel;
- (void)setMultichannelAudioStrategy:(id)strategy { objc_setAssociatedObject(self, &kMultichannel, strategy, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)multichannelAudioStrategy { return objc_getAssociatedObject(self, &kMultichannel); }

@end

/* Media names QuickTime Player asks AVFoundation objects for that this AVFoundation does not have. */
static char kFieldMode;

@implementation AVPlayerItemTrack (SFQuickTimePrivate)

/* (public on macOS) how interlaced video is shown; nil is the default, as there: the field mode is kept and the
   frames are shown as decoded (no deinterlacing here) */
- (NSString *)videoFieldMode { return objc_getAssociatedObject(self, &kFieldMode); }
- (void)setVideoFieldMode:(NSString *)mode
{
    if (mode != nil)
        sfOnce("deinterlacing is not done here: video fields are shown as decoded");
    objc_setAssociatedObject(self, &kFieldMode, mode, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end

@implementation AVAsset (SFQuickTimePrivate)

/* groups of alternate tracks (one plays at a time): the asset's track groups */
- (NSArray *)alternateTrackGroups
{
    return [self respondsToSelector:@selector(trackGroups)] ? [self performSelector:@selector(trackGroups)] : [NSArray array];
}

/* the group of alternate audio tracks: alternative audio is not read here */
- (id)audioAlternatesTrackGroup { return nil; }

/* the video dynamic ranges the asset has: this player shows standard range only, so none beyond it is reported */
- (NSArray *)availableVideoDynamicRanges { return [NSArray array]; }

@end

@implementation AVAssetTrack (SFQuickTimePrivate)
- (NSArray *)availableVideoDynamicRanges { return [NSArray array]; }
@end

@implementation AVPlayerItem (SFQuickTimePrivate)

/* whether the item's asset has video or audio (private on macOS; QuickTime Player picks its video or audio-only
   view by it): from the asset's tracks; an item track that is turned off does not count for the "enabled" forms */
- (BOOL)sfHasTrackOfType:(NSString *)type enabledOnly:(BOOL)enabledOnly
{
    if (enabledOnly) {
        for (AVPlayerItemTrack *track in self.tracks)
            if ([track isEnabled] && [[[track assetTrack] mediaType] isEqualToString:type])
                return YES;
        if ([self.tracks count] > 0)
            return NO;
    }
    return [[self.asset tracksWithMediaType:type] count] > 0;
}

- (BOOL)hasVideo { return [self sfHasTrackOfType:AVMediaTypeVideo enabledOnly:NO]; }

/* (private on macOS) a hint that the item will be the only one playing (full screen): kept, no effect here */
static char kExclusive;
- (BOOL)shouldOptimizeForExclusivePlayback { return [objc_getAssociatedObject(self, &kExclusive) boolValue]; }
- (void)setShouldOptimizeForExclusivePlayback:(BOOL)value { objc_setAssociatedObject(self, &kExclusive, [NSNumber numberWithBool:value], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)hasAudio { return [self sfHasTrackOfType:AVMediaTypeAudio enabledOnly:NO]; }
- (BOOL)hasEnabledVideo { return [self sfHasTrackOfType:AVMediaTypeVideo enabledOnly:YES]; }
- (BOOL)hasEnabledAudio { return [self sfHasTrackOfType:AVMediaTypeAudio enabledOnly:YES]; }

@end
