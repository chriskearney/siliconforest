/* SPDX-License-Identifier: MIT */
/* Real read-through scalar/transport adapter. It does not implement the
 * native controller's private UI, inspection or KVO notification families. */
#import <AVKit/SFPlayerController.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>
@interface AVPlayerController (SFQuickTimePrivate)
- (void)setLooping:(BOOL)looping;
@end
@implementation AVPlayerController
- (void)dealloc {
    [self setLooping:NO];   // (QTP) removes the end-of-item observer
    [_sfControllerPlayer release];[super dealloc];
}
- (AVPlayer *)player { return _sfControllerPlayer; }
- (void)setPlayer:(AVPlayer *)value {
    if(value==_sfControllerPlayer)return;
    [value retain];[_sfControllerPlayer release];_sfControllerPlayer=value;
    value.muted=_sfControllerMuted;
}
- (double)volume { return _sfControllerPlayer.volume; }
- (void)setVolume:(double)value { _sfControllerPlayer.volume=(float)value; }
- (BOOL)isMuted { return _sfControllerMuted; }
- (void)setMuted:(BOOL)value {
    _sfControllerMuted=value;_sfControllerPlayer.muted=value;
}
- (double)rate { return _sfControllerPlayer.rate; }
- (void)setRate:(double)value { _sfControllerPlayer.rate=(float)value; }
- (double)defaultPlaybackRate { return _sfControllerPlayer.defaultRate; }
- (void)setDefaultPlaybackRate:(double)value { _sfControllerPlayer.defaultRate=(float)value; }
- (BOOL)hasContent {
    return _sfControllerPlayer.currentItem!=nil;
}
- (double)contentDuration {
    if(_sfControllerPlayer.currentItem.status!=AVPlayerItemStatusReadyToPlay)return NAN;
    return CMTimeGetSeconds(_sfControllerPlayer.currentItem.duration);
}
- (double)contentDurationWithinEndTimes { return self.contentDuration; }
- (double)currentTime {
    return _sfControllerPlayer.currentItem.status==AVPlayerItemStatusReadyToPlay?
        CMTimeGetSeconds(_sfControllerPlayer.currentTime):NAN;
}
- (double)currentTimeWithinEndTimes { return self.currentTime; }
- (double)minTime { return 0; }
- (double)maxTime { return self.contentDuration; }
- (BOOL)isPlaying { return _sfControllerPlayer.rate!=0; }
- (BOOL)canPlay { return _sfControllerPlayer.currentItem.status==AVPlayerItemStatusReadyToPlay; }
- (BOOL)canPause { return self.canPlay; }
- (BOOL)canSeek { return self.canPlay&&isfinite(self.contentDuration); }
- (BOOL)hasVideo {
    return self.hasContent&&[[_sfControllerPlayer.currentItem.asset tracksWithMediaType:AVMediaTypeVideo] count]>0;
}
- (BOOL)sfHasEnabledTrackType:(NSString *)type {
    if(!self.hasContent)return NO;
    for(AVPlayerItemTrack *track in _sfControllerPlayer.currentItem.tracks)
        if(track.isEnabled&&[track.assetTrack.mediaType isEqual:type])return YES;
    return NO;
}
- (BOOL)hasEnabledAudio { return [self sfHasEnabledTrackType:AVMediaTypeAudio]; }
- (BOOL)hasEnabledVideo { return [self sfHasEnabledTrackType:AVMediaTypeVideo]; }
- (NSInteger)status {
    AVPlayerItem *item=_sfControllerPlayer.currentItem;
    if(!item)return 0;
    if(item.status==AVPlayerItemStatusReadyToPlay)return 2;
    if(item.status==AVPlayerItemStatusFailed)return 3;
    return 1;
}
- (NSError *)error { return _sfControllerPlayer.error; }
- (void)play:(id)sender { (void)sender;if(self.canPlay)[_sfControllerPlayer play]; }
- (void)pause:(id)sender { (void)sender;[_sfControllerPlayer pause]; }
- (void)togglePlayback:(id)sender {
    if(self.isPlaying)[self pause:sender];else [self play:sender];
}
- (void)seekToTime:(double)seconds {
    if(!self.canSeek||!isfinite(seconds))return;
    seconds=fmax(self.minTime,fmin(self.maxTime,seconds));
    [_sfControllerPlayer seekToTime:CMTimeMakeWithSeconds(seconds,600000)];
}
@end

#include <objc/runtime.h>
static char kLooping, kLoopObserver;

/* (QTP) messages Apple's QuickTime Player sends to the controller (private on macOS); types from its call sites */
@implementation AVPlayerController (SFQuickTimePrivate)

- (instancetype)initWithPlayer:(AVPlayer *)player
{
    if ((self = [self init]))
        [self setPlayer:player];
    return self;
}

- (CGSize)contentDimensions
{
    AVPlayerItem *item = self.player.currentItem;
    return item ? [item presentationSize] : CGSizeZero;
}

/* chapters, alternative audio and subtitles are not read by this player */
- (BOOL)canSeekChapterBackward { return NO; }
- (BOOL)canSeekChapterForward { return NO; }
- (void)seekChapterBackward:(id)sender { (void)sender; }
- (void)seekChapterForward:(id)sender { (void)sender; }
- (BOOL)hasAudioMediaSelectionOptions { return NO; }
- (BOOL)hasLegibleMediaSelectionOptions { return NO; }
- (BOOL)hasShareableContent { return NO; }
- (BOOL)hasStereoVideo { return NO; }

/* what the application calls when a movie it opened should start by itself */
- (void)autoplay:(id)sender { (void)sender; [self play:nil]; }

- (void)setPlaying:(BOOL)playing
{
    if (playing)
        [self play:nil];
    else
        [self pause:nil];
}

- (void)seekFrameForward:(id)sender { (void)sender; [self.player pause]; [self.player.currentItem stepByCount:1]; }
- (void)seekFrameBackward:(id)sender { (void)sender; [self.player pause]; [self.player.currentItem stepByCount:-1]; }

/* looping: at the end of the item, back to its start and on */
- (BOOL)isLooping { return [objc_getAssociatedObject(self, &kLooping) boolValue]; }

- (void)setLooping:(BOOL)looping
{
    objc_setAssociatedObject(self, &kLooping, [NSNumber numberWithBool:looping], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id observer = objc_getAssociatedObject(self, &kLoopObserver);
    if (observer) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        objc_setAssociatedObject(self, &kLoopObserver, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!looping)
        return;
    AVPlayerController *controller = self;   // not retained: the observer goes when looping is turned off or in -dealloc
    observer = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:nil
                                                                  queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        AVPlayer *player = controller.player;
        if (note.object != player.currentItem)
            return;
        [player seekToTime:kCMTimeZero];
        [player play];
    }];
    objc_setAssociatedObject(self, &kLoopObserver, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

