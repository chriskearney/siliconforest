#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Add our real bounded local-file engine to Finch's retained player model."""
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
def change(old,new):
 global s
 assert s.count(old)==1,old[:100]
 s=s.replace(old,new)
change('#import "AVFInternal.h"','#import "AVFInternal.h"\n#import "SFPlayerMedia.h"')
change('    AVAsset *_fasset;','    AVAsset *_fasset;\n    SFPlayerMedia *_sfMedia;')
change('''        _fstatus = AVPlayerItemStatusReadyToPlay;
    } else {''','''        if ([SFPlayerMedia needsBackend:_fasset]) {
            NSError *failure = nil;
            _sfMedia = [[SFPlayerMedia alloc] initWithAsset:_fasset error:&failure];
            _fstatus = _sfMedia ? AVPlayerItemStatusReadyToPlay : AVPlayerItemStatusFailed;
            _ferror = failure;
        } else {
            _fstatus = AVPlayerItemStatusReadyToPlay;
        }
    } else {''')
change('- (AVAsset *)asset { return _fasset; }','- (AVAsset *)asset { return _fasset; }\n- (SFPlayerMedia *)_siliconForestMedia { return _sfMedia; }\n- (void)_siliconForestPlaybackFailed { [self willChangeValueForKey:@"status"]; _fstatus=AVPlayerItemStatusFailed; _ferror=[_sfMedia playbackError] ?: [NSError errorWithDomain:@"SiliconForestPlayer" code:-1 userInfo:nil]; [self didChangeValueForKey:@"status"]; }')
change('''{
    AVAssetTrack *track = [_fasset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVFMovie *movie =''','''{
    if (_sfMedia) return [_sfMedia copyImageAtTime:time index:indexOut];
    AVAssetTrack *track = [_fasset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    AVFMovie *movie =''')
change('- (void)setVolume:(float)v { _fvolume = v; }','- (void)setVolume:(float)v { _fvolume = MAX(0,MIN(1,v)); [[_fitem _siliconForestMedia] setVolume:_fmuted ? 0 : _fvolume]; }')
change('- (void)setMuted:(BOOL)m { _fmuted = m; }','- (void)setMuted:(BOOL)m { _fmuted = m; [[_fitem _siliconForestMedia] setVolume:m ? 0 : _fvolume]; }')
change('''    double elapsed = (host_seconds() - _fanchorHost) * _frate;
    CMTime t = CMTimeAdd(_fanchorTime, CMTimeMakeWithSeconds(elapsed, 600));''','''    SFPlayerMedia *media = [_fitem _siliconForestMedia];
    double clock = media.hasAudio ? [media clockSeconds] : NAN;
    double elapsed = (host_seconds() - _fanchorHost) * _frate;
    CMTime t = isfinite(clock) ? CMTimeMakeWithSeconds(clock,600) : CMTimeAdd(_fanchorTime, CMTimeMakeWithSeconds(elapsed, 600));''')
change('''    if (_frate > 0 && item.status == AVPlayerItemStatusReadyToPlay)
        [self _finchStartClock];''','''    if (item.status == AVPlayerItemStatusFailed) { [self setRate:0]; return; }
    if (_frate > 0 && item.status == AVPlayerItemStatusReadyToPlay)
        [self _finchStartClock];''')
change('''    _fanchorHost = host_seconds();
    __weak AVPlayer *weakSelf = self;''','''    _fanchorHost = host_seconds();
    SFPlayerMedia *media = [_fitem _siliconForestMedia];
    if (media && ![media startAtSeconds:CMTimeGetSeconds(_fanchorTime) volume:_fmuted ? 0 : _fvolume]) {
        [_fitem _siliconForestPlaybackFailed];
        [self _finchSetControl:AVPlayerTimeControlStatusPaused];
        [self willChangeValueForKey:@"rate"]; _frate = 0; [self didChangeValueForKey:@"rate"];
        return;
    }
    __weak AVPlayer *weakSelf = self;''')
change('''    CMTime now = [self currentTime];
    [_ftimer invalidate];''','''    CMTime now = [self currentTime];
    [[_fitem _siliconForestMedia] pause];
    [_ftimer invalidate];''')
change('''    AVPlayerItem *item = _fitem;
    [_ftimer invalidate];''','''    AVPlayerItem *item = _fitem;
    [[item _siliconForestMedia] pause];
    [_ftimer invalidate];''')
change('''- (void)setRate:(float)rate
{
    if (rate == _frate)''','''- (void)setRate:(float)rate
{
    /* Device output is rate-one only; never pretend time-pitch/reverse audio. */
    if (rate != 0 && _fitem.status == AVPlayerItemStatusFailed) return;
    if ([SFPlayerMedia needsBackend:_fitem.asset] && rate != 0 && rate != 1) return;
    if (rate == _frate)''')
change('- (AVPlayerStatus)status { return _fstatus; }\n- (NSError *)error { return nil; }','- (AVPlayerStatus)status { return _fstatus; }\n- (NSError *)error { return _fitem.error; }\n- (NSDictionary *)sfPlaybackStatistics { return [[_fitem _siliconForestMedia] statistics] ?: @{}; }\n- (NSArray *)sfPlaybackFrameDigests { return [[_fitem _siliconForestMedia] frameDigests] ?: @[]; }')
change('''    if (!item || item.status != AVPlayerItemStatusReadyToPlay || !self.superlayer)
        return;''','''    if (!item || item.status != AVPlayerItemStatusReadyToPlay)
        return;''')
change('''    CMTime now = [self currentTime];
    [_fitem _finchSetTime:now];''','''    CMTime now = [self currentTime];
    if ([[_fitem _siliconForestMedia] playbackError]) {
        [_fitem _siliconForestPlaybackFailed]; [self setRate:0]; return;
    }
    [_fitem _finchSetTime:now];''')
change('''    if (_frate > 0 && CMTIME_IS_NUMERIC(d) && CMTimeCompare(now, d) >= 0)
        [self _finchReachedEnd];''','''    if (_frate > 0 && CMTIME_IS_NUMERIC(d) && CMTimeCompare(now, d) >= 0 &&
        (![_fitem _siliconForestMedia] || [[_fitem _siliconForestMedia] isAudioDrained]))
        [self _finchReachedEnd];''')
change('''    BOOL _fshownAny;
    NSDictionary *_fattributes;''','''    BOOL _fshownAny;
    __weak AVPlayerItem *_sfShownItem;
    CGSize _sfPixelSize, _sfShownPixelSize;
    NSDictionary *_fattributes;''')
# (QTP2) the size in device pixels the picture is shown at, from the view that hosts the layer: pictures are made at
# that size (drawn at their own size they are copied, not resampled); a new size shows the current picture again
change('''    CGImageRef im = [item _finchCopyImageAtTime:item.currentTime sampleIndex:&index];
    if (!im)
        return;
    if (!_fshownAny || index != _fshown) {''','''    [[item _siliconForestMedia] setOutputPixelSize:_sfPixelSize];
    CGImageRef im = [item _finchCopyImageAtTime:item.currentTime sampleIndex:&index];
    if (!im)
        return;
    if (!_fshownAny || index != _fshown || !CGSizeEqualToSize(_sfShownPixelSize, _sfPixelSize)) {
        _sfShownPixelSize = _sfPixelSize;''')
change('''    AVPlayerItem *item = _fplayer.currentItem;
    if (!item || item.status != AVPlayerItemStatusReadyToPlay)
        return;''','''    AVPlayerItem *item = _fplayer.currentItem;
    if (item != _sfShownItem) {
        _sfShownItem=item; _fshownAny=NO; self.contents=nil;
        if (_fready) { [self willChangeValueForKey:@"readyForDisplay"]; _fready=NO; [self didChangeValueForKey:@"readyForDisplay"]; }
    }
    if (!item || item.status != AVPlayerItemStatusReadyToPlay)
        return;''')
# Expose actual rendered-frame count for our test, not an Apple API/capability.
change('- (BOOL)isReadyForDisplay { return _fready; }','- (BOOL)isReadyForDisplay { return _fready; }\n- (NSUInteger)sfDisplayedFrameIndex { return _fshown; }\n- (void)sfSetDisplayPixelSize:(CGSize)size { _sfPixelSize = size; }')
for name in ['canPlayFastForward','canPlaySlowForward','canPlayReverse','canPlaySlowReverse','canPlayFastReverse']:
 change('- (BOOL)'+name+' { return _floaded; }','- (BOOL)'+name+' { return _floaded && _fstatus == AVPlayerItemStatusReadyToPlay && !_sfMedia; }')
p.write_text(s)
