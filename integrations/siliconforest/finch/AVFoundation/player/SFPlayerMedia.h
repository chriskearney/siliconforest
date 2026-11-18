/* SPDX-License-Identifier: MIT */
/* Private bounded local-file playback backend. No device or frame is fabricated. */
#import <Foundation/Foundation.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreGraphics/CoreGraphics.h>
@class AVAsset;
@interface SFPlayerMedia : NSObject
+ (BOOL)needsBackend:(AVAsset *)asset;
- (instancetype)initWithAsset:(AVAsset *)asset error:(NSError **)error;
- (BOOL)startAtSeconds:(double)seconds volume:(float)volume;
- (void)pause;
- (double)clockSeconds;
- (BOOL)hasAudio;
- (BOOL)isAudioDrained;
- (NSError *)playbackError;
- (void)setVolume:(float)volume;
- (CGImageRef)copyImageAtTime:(CMTime)time index:(size_t *)index;
/* the size in pixels pictures are made at (zero: the decoded size); they are B, G, R and a skipped byte in memory */
- (void)setOutputPixelSize:(CGSize)size;
- (NSDictionary *)statistics;
- (NSArray *)frameDigests;
@end
