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
- (NSInteger)timeDisplayStyle { return [objc_getAssociatedObject(self, &kTimeStyle) integerValue]; }
- (void)setTimeDisplayStyle:(NSInteger)style { objc_setAssociatedObject(self, &kTimeStyle, [NSNumber numberWithInteger:style], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

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
