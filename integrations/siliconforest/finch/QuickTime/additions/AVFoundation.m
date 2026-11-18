/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * AVFoundation classes QuickTime Player binds that the staged AVFoundation lacks. Three kinds:
 *   models      compositions' instructions and audio mixes hold what they are given; the
 *               staged player does not apply them, and says so;
 *   absences    export, image generation, composition editing, AVCHD collections and capture
 *               outputs exist as classes and fail through the interface's own error path
 *               (a failed status, NO with an NSError, or nil), saying why once;
 *   real        the time formatter formats.
 * Written from the public API documentation. */
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <string.h>
#import <objc/message.h>
#include "absent.h"

typedef struct { int64_t value; int32_t timescale; uint32_t flags; int64_t epoch; } SFTime;       /* CMTime */
typedef struct { SFTime start, duration; } SFTimeRange;                                             /* CMTimeRange */
static const SFTime SFTimeInvalid = {0, 0, 0, 0};
static const SFTime SFTimeZero = {0, 1, 1, 0};

static NSError *SFAVError(NSString *what) {
    return [NSError errorWithDomain:@"AVFoundationErrorDomain" code:-11800 /* AVErrorUnknown */
                           userInfo:[NSDictionary dictionaryWithObject:[what stringByAppendingString:@" is not available on SiliconForest"]
                                                                forKey:NSLocalizedDescriptionKey]];
}

@interface AVAsset : NSObject
@end
@interface AVCaptureOutput : NSObject
@end
@interface AVAssetReaderOutput : NSObject
@end

#define SF_OBJECT(type, getter, setter, ivar) \
    - (type)getter { return ivar; } \
    - (void)setter:(type)value { id old = (id)ivar; ivar = [value copy]; [old release]; }
#define SF_SCALAR(type, getter, setter, ivar) \
    - (type)getter { return ivar; } \
    - (void)setter:(type)value { ivar = value; }
#define SF_MODEL_NOTE() SF_ABSENT("AVFoundation: video compositions and audio mixes are kept as given; the player does not apply them")

/* ---- models ------------------------------------------------------------------------------ */

SF_EXPORT
@interface AVMutableAudioMixInputParameters : NSObject {
    int32_t _sfTrackID;
    NSMutableArray *_sfRamps;
}
@end
@implementation AVMutableAudioMixInputParameters
+ (id)audioMixInputParameters { return [[[self alloc] init] autorelease]; }
+ (id)audioMixInputParametersWithTrack:(id)track {
    AVMutableAudioMixInputParameters *p = [self audioMixInputParameters];
    if ([track respondsToSelector:@selector(trackID)]) p->_sfTrackID = ((int32_t (*)(id, SEL))objc_msgSend)(track, @selector(trackID));
    return p;
}
- (id)init {
    SF_MODEL_NOTE();
    if ((self = [super init])) _sfRamps = [[NSMutableArray alloc] init];
    return self;
}
SF_SCALAR(int32_t, trackID, setTrackID, _sfTrackID)
- (void)setVolumeRampFromStartVolume:(float)start toEndVolume:(float)end timeRange:(SFTimeRange)range {
    [_sfRamps addObject:[NSArray arrayWithObjects:[NSNumber numberWithFloat:start], [NSNumber numberWithFloat:end],
                                                  [NSValue valueWithBytes:&range objCType:@encode(SFTimeRange)], nil]];
}
- (void)setVolume:(float)volume atTime:(SFTime)time {
    SFTimeRange range = {time, SFTimeZero};
    [self setVolumeRampFromStartVolume:volume toEndVolume:volume timeRange:range];
}
/* The last ramp set whose range starts at or before the time, as seconds compare. */
- (BOOL)getVolumeRampForTime:(SFTime)time startVolume:(float *)start endVolume:(float *)end timeRange:(SFTimeRange *)range {
    double t = time.timescale ? (double)time.value / time.timescale : 0;
    for (NSArray *ramp in [_sfRamps reverseObjectEnumerator]) {
        SFTimeRange r;
        [[ramp objectAtIndex:2] getValue:&r];
        double s = r.start.timescale ? (double)r.start.value / r.start.timescale : 0;
        if (s > t) continue;
        if (start) *start = [[ramp objectAtIndex:0] floatValue];
        if (end) *end = [[ramp objectAtIndex:1] floatValue];
        if (range) *range = r;
        return YES;
    }
    return NO;
}
- (void)dealloc {
    [_sfRamps release];
    [super dealloc];
}
@end

SF_EXPORT
@interface AVMutableAudioMix : NSObject {
    NSArray *_sfInputParameters;
}
@end
@implementation AVMutableAudioMix
+ (id)audioMix { return [[[self alloc] init] autorelease]; }
- (id)init {
    SF_MODEL_NOTE();
    if ((self = [super init])) _sfInputParameters = [[NSArray alloc] init];
    return self;
}
SF_OBJECT(NSArray *, inputParameters, setInputParameters, _sfInputParameters)
- (void)dealloc {
    [_sfInputParameters release];
    [super dealloc];
}
@end

SF_EXPORT
@interface AVMutableVideoCompositionLayerInstruction : NSObject {
    int32_t _sfTrackID;
    NSMutableArray *_sfSteps;
}
@end
@implementation AVMutableVideoCompositionLayerInstruction
+ (id)videoCompositionLayerInstruction { return [[[self alloc] init] autorelease]; }
+ (id)videoCompositionLayerInstructionWithAssetTrack:(id)track {
    AVMutableVideoCompositionLayerInstruction *i = [self videoCompositionLayerInstruction];
    if ([track respondsToSelector:@selector(trackID)]) i->_sfTrackID = ((int32_t (*)(id, SEL))objc_msgSend)(track, @selector(trackID));
    return i;
}
- (id)init {
    SF_MODEL_NOTE();
    if ((self = [super init])) _sfSteps = [[NSMutableArray alloc] init];
    return self;
}
SF_SCALAR(int32_t, trackID, setTrackID, _sfTrackID)
- (void)setTransform:(CGAffineTransform)transform atTime:(SFTime)time {
    [_sfSteps addObject:[NSArray arrayWithObjects:@"transform", [NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)],
                                                  [NSValue valueWithBytes:&time objCType:@encode(SFTime)], nil]];
}
- (void)setOpacity:(float)opacity atTime:(SFTime)time {
    [_sfSteps addObject:[NSArray arrayWithObjects:@"opacity", [NSNumber numberWithFloat:opacity],
                                                  [NSValue valueWithBytes:&time objCType:@encode(SFTime)], nil]];
}
- (void)dealloc {
    [_sfSteps release];
    [super dealloc];
}
@end

SF_EXPORT
@interface AVMutableVideoCompositionInstruction : NSObject {
    SFTimeRange _sfTimeRange;
    NSArray *_sfLayerInstructions;
    CGColorRef _sfBackground;
    BOOL _sfPostProcessing;
}
@end
@implementation AVMutableVideoCompositionInstruction
+ (id)videoCompositionInstruction { return [[[self alloc] init] autorelease]; }
- (id)init {
    SF_MODEL_NOTE();
    if ((self = [super init])) {
        _sfLayerInstructions = [[NSArray alloc] init];
        _sfPostProcessing = YES;
    }
    return self;
}
SF_SCALAR(SFTimeRange, timeRange, setTimeRange, _sfTimeRange)
SF_SCALAR(BOOL, enablePostProcessing, setEnablePostProcessing, _sfPostProcessing)
SF_OBJECT(NSArray *, layerInstructions, setLayerInstructions, _sfLayerInstructions)
- (CGColorRef)backgroundColor { return _sfBackground; }
- (void)setBackgroundColor:(CGColorRef)color {
    if (color) CFRetain(color);
    if (_sfBackground) CFRelease(_sfBackground);
    _sfBackground = color;
}
- (void)dealloc {
    [_sfLayerInstructions release];
    if (_sfBackground) CFRelease(_sfBackground);
    [super dealloc];
}
@end

SF_EXPORT
@interface AVMutableVideoComposition : NSObject {
    CGSize _sfRenderSize;
    float _sfRenderScale;
    SFTime _sfFrameDuration;
    int32_t _sfSourceTrack;
    NSArray *_sfInstructions;
}
@end
@implementation AVMutableVideoComposition
+ (id)videoComposition { return [[[self alloc] init] autorelease]; }
- (id)init {
    SF_MODEL_NOTE();
    if ((self = [super init])) {
        _sfRenderScale = 1;
        _sfFrameDuration = SFTimeInvalid;
        _sfInstructions = [[NSArray alloc] init];
    }
    return self;
}
SF_SCALAR(CGSize, renderSize, setRenderSize, _sfRenderSize)
SF_SCALAR(float, renderScale, setRenderScale, _sfRenderScale)
SF_SCALAR(SFTime, frameDuration, setFrameDuration, _sfFrameDuration)
SF_SCALAR(int32_t, sourceTrackIDForFrameTiming, setSourceTrackIDForFrameTiming, _sfSourceTrack)
SF_OBJECT(NSArray *, instructions, setInstructions, _sfInstructions)
- (void)dealloc {
    [_sfInstructions release];
    [super dealloc];
}
@end

/* ---- compositions: empty, and they stay empty --------------------------------------------- */

SF_EXPORT
@interface AVComposition : AVAsset
@end
@implementation AVComposition
- (NSArray *)tracks { return [NSArray array]; }
- (CGSize)naturalSize { return CGSizeMake(0, 0); }
- (SFTime)duration { return SFTimeZero; }
@end

SF_EXPORT
@interface AVMutableComposition : AVComposition {
    CGSize _sfNaturalSize;
}
@end
@implementation AVMutableComposition
+ (id)composition { return [[[self alloc] init] autorelease]; }
+ (id)compositionWithURLAssetInitializationOptions:(NSDictionary *)options { (void)options; return [self composition]; }
- (CGSize)naturalSize { return _sfNaturalSize; }
- (void)setNaturalSize:(CGSize)size { _sfNaturalSize = size; }
- (id)addMutableTrackWithMediaType:(NSString *)type preferredTrackID:(int32_t)trackID {
    (void)type; (void)trackID;
    SF_ABSENT("AVMutableComposition: composition editing is not implemented; no track is added (nil)");
    return nil;
}
- (BOOL)insertTimeRange:(SFTimeRange)range ofAsset:(id)asset atTime:(SFTime)time error:(NSError **)error {
    (void)range; (void)asset; (void)time;
    SF_ABSENT("AVMutableComposition: composition editing is not implemented; nothing is inserted");
    if (error) *error = SFAVError(@"Editing a composition");
    return NO;
}
- (void)insertEmptyTimeRange:(SFTimeRange)range { (void)range; SF_ABSENT("AVMutableComposition: composition editing is not implemented; nothing is inserted"); }
- (void)removeTimeRange:(SFTimeRange)range { (void)range; }
- (void)removeTrack:(id)track { (void)track; }
@end

/* ---- export: every session fails ----------------------------------------------------------- */

SF_EXPORT
@interface AVAssetExportSession : NSObject {
    id _sfAsset;
    NSString *_sfPreset, *_sfFileType;
    NSURL *_sfOutputURL;
    NSInteger _sfStatus;
    NSError *_sfError;
    id _sfAudioMix, _sfVideoComposition;
    BOOL _sfMultiPass, _sfOptimize;
    SFTimeRange _sfTimeRange;
}
@end
@implementation AVAssetExportSession
+ (NSArray *)allExportPresets { return [NSArray array]; }
+ (NSArray *)exportPresetsCompatibleWithAsset:(id)asset { (void)asset; return [NSArray array]; }
+ (void)determineCompatibilityOfExportPreset:(NSString *)preset withAsset:(id)asset outputFileType:(NSString *)type completionHandler:(void (^)(BOOL))handler {
    (void)preset; (void)asset; (void)type;
    SF_ABSENT("AVAssetExportSession: export is not implemented; no preset is compatible");
    if (handler) handler(NO);
}
+ (id)exportSessionWithAsset:(id)asset presetName:(NSString *)preset { return [[[self alloc] initWithAsset:asset presetName:preset] autorelease]; }
- (id)initWithAsset:(id)asset presetName:(NSString *)preset {
    if ((self = [super init])) {
        _sfAsset = [asset retain];
        _sfPreset = [preset copy];
    }
    return self;
}
- (id)asset { return _sfAsset; }
- (NSString *)presetName { return _sfPreset; }
- (NSArray *)supportedFileTypes { return [NSArray array]; }
- (NSInteger)status { return _sfStatus; }
- (NSError *)error { return _sfError; }
- (float)progress { return 0; }
SF_OBJECT(NSString *, outputFileType, setOutputFileType, _sfFileType)
SF_OBJECT(NSURL *, outputURL, setOutputURL, _sfOutputURL)
SF_SCALAR(BOOL, canPerformMultiplePassesOverSourceMediaData, setCanPerformMultiplePassesOverSourceMediaData, _sfMultiPass)
SF_SCALAR(BOOL, shouldOptimizeForNetworkUse, setShouldOptimizeForNetworkUse, _sfOptimize)
SF_SCALAR(SFTimeRange, timeRange, setTimeRange, _sfTimeRange)
- (id)audioMix { return _sfAudioMix; }
- (void)setAudioMix:(id)mix { [mix retain]; [_sfAudioMix release]; _sfAudioMix = mix; }
- (id)videoComposition { return _sfVideoComposition; }
- (void)setVideoComposition:(id)composition { [composition retain]; [_sfVideoComposition release]; _sfVideoComposition = composition; }
/* Status 4 is AVAssetExportSessionStatusFailed; the handler runs off the caller's stack, as documented. */
- (void)exportAsynchronouslyWithCompletionHandler:(void (^)(void))handler {
    SF_ABSENT("AVAssetExportSession: export is not implemented; the session fails");
    [_sfError release];
    _sfError = [SFAVError(@"Exporting a movie") retain];
    _sfStatus = 4;
    if (handler) {
        void (^copy)(void) = [handler copy];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            copy();
            [copy release];
        });
    }
}
- (void)cancelExport {
    if (_sfStatus != 4) _sfStatus = 5; /* cancelled */
}
- (void)dealloc {
    [_sfAsset release]; [_sfPreset release]; [_sfFileType release]; [_sfOutputURL release]; [_sfError release];
    [_sfAudioMix release]; [_sfVideoComposition release];
    [super dealloc];
}
@end

/* ---- still images: every request fails ------------------------------------------------------ */

SF_EXPORT
@interface AVAssetImageGenerator : NSObject {
    id _sfAsset;
    CGSize _sfMaximumSize;
    BOOL _sfTransform;
    SFTime _sfBefore, _sfAfter;
    id _sfVideoComposition;
}
@end
@implementation AVAssetImageGenerator
+ (id)assetImageGeneratorWithAsset:(id)asset { return [[[self alloc] initWithAsset:asset] autorelease]; }
- (id)initWithAsset:(id)asset {
    if ((self = [super init])) _sfAsset = [asset retain];
    return self;
}
- (id)asset { return _sfAsset; }
SF_SCALAR(CGSize, maximumSize, setMaximumSize, _sfMaximumSize)
SF_SCALAR(BOOL, appliesPreferredTrackTransform, setAppliesPreferredTrackTransform, _sfTransform)
SF_SCALAR(SFTime, requestedTimeToleranceBefore, setRequestedTimeToleranceBefore, _sfBefore)
SF_SCALAR(SFTime, requestedTimeToleranceAfter, setRequestedTimeToleranceAfter, _sfAfter)
- (id)videoComposition { return _sfVideoComposition; }
- (void)setVideoComposition:(id)composition { [composition retain]; [_sfVideoComposition release]; _sfVideoComposition = composition; }
- (CGImageRef)copyCGImageAtTime:(SFTime)time actualTime:(SFTime *)actual error:(NSError **)error {
    (void)time;
    SF_ABSENT("AVAssetImageGenerator: still images from movies are not implemented; requests fail");
    if (actual) *actual = SFTimeInvalid;
    if (error) *error = SFAVError(@"Generating an image from a movie");
    return NULL;
}
/* Result 1 is AVAssetImageGeneratorFailed; one call per requested time, as documented. */
- (void)generateCGImagesAsynchronouslyForTimes:(NSArray *)times completionHandler:(void (^)(SFTime, CGImageRef, SFTime, NSInteger, NSError *))handler {
    SF_ABSENT("AVAssetImageGenerator: still images from movies are not implemented; requests fail");
    if (!handler) return;
    void (^copy)(SFTime, CGImageRef, SFTime, NSInteger, NSError *) = [handler copy];
    NSArray *requested = [times copy];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (NSValue *value in requested) {
            SFTime t = SFTimeInvalid;
            [value getValue:&t];
            copy(t, NULL, SFTimeInvalid, 1, SFAVError(@"Generating an image from a movie"));
        }
        [requested release];
        [copy release];
    });
}
- (void)cancelAllCGImageGeneration {
}
- (void)dealloc {
    [_sfAsset release]; [_sfVideoComposition release];
    [super dealloc];
}
@end

/* ---- classes whose objects cannot be made --------------------------------------------------- */

#define SF_REFUSE(message) \
    do { \
        SF_ABSENT(message); \
        [self release]; \
        return nil; \
    } while (0)

SF_EXPORT
@interface AVAssetReaderAudioMixOutput : AVAssetReaderOutput
@end
@implementation AVAssetReaderAudioMixOutput
+ (id)assetReaderAudioMixOutputWithAudioTracks:(NSArray *)tracks audioSettings:(NSDictionary *)settings {
    return [[[self alloc] initWithAudioTracks:tracks audioSettings:settings] autorelease];
}
- (id)initWithAudioTracks:(NSArray *)tracks audioSettings:(NSDictionary *)settings {
    (void)tracks; (void)settings;
    SF_REFUSE("AVAssetReaderAudioMixOutput: mixing several audio tracks while reading is not implemented (nil)");
}
- (id)init { SF_REFUSE("AVAssetReaderAudioMixOutput: mixing several audio tracks while reading is not implemented (nil)"); }
@end

/* Private: a folder of camera recordings (AVCHD) as a collection of assets. */
SF_EXPORT
@interface AVAssetCollection : NSObject
@end
@implementation AVAssetCollection
+ (id)assetCollectionWithURL:(NSURL *)url options:(NSDictionary *)options {
    (void)url; (void)options;
    SF_ABSENT("AVAssetCollection: AVCHD camera folders are not supported (nil)");
    return nil;
}
- (id)init { SF_REFUSE("AVAssetCollection: AVCHD camera folders are not supported (nil)"); }
@end

/* Capture: there are no capture devices and no capture pipeline. */
SF_EXPORT
@interface AVCaptureMovieFileOutput : AVCaptureOutput
@end
@implementation AVCaptureMovieFileOutput
- (id)init { SF_REFUSE("AVCaptureMovieFileOutput: there is no capture pipeline; recording is unavailable (nil)"); }
@end
SF_EXPORT
@interface AVCaptureAudioFileOutput : AVCaptureOutput
@end
@implementation AVCaptureAudioFileOutput
+ (NSArray *)availableOutputFileTypes { return [NSArray array]; }
- (id)init { SF_REFUSE("AVCaptureAudioFileOutput: there is no capture pipeline; recording is unavailable (nil)"); }
@end
SF_EXPORT
@interface AVCaptureAudioPreviewOutput : AVCaptureOutput
@end
@implementation AVCaptureAudioPreviewOutput
- (id)init { SF_REFUSE("AVCaptureAudioPreviewOutput: there is no capture pipeline; audio preview is unavailable (nil)"); }
@end
SF_EXPORT
@interface AVCaptureConnection : NSObject
@end
@implementation AVCaptureConnection
+ (id)connectionWithInputPorts:(NSArray *)ports output:(id)output {
    (void)ports; (void)output;
    SF_ABSENT("AVCaptureConnection: there is no capture pipeline (nil)");
    return nil;
}
- (id)init { SF_REFUSE("AVCaptureConnection: there is no capture pipeline (nil)"); }
- (id)initWithInputPorts:(NSArray *)ports output:(id)output { (void)ports; (void)output; SF_REFUSE("AVCaptureConnection: there is no capture pipeline (nil)"); }
@end

/* ---- time formatter: real --------------------------------------------------------------------- *
 * Private. Formats a time in seconds or a CMTime as [-][H:]MM:SS; "full width" always shows
 * hours. Other styles macOS may have are not known and not offered. */
SF_EXPORT
@interface AVTimeFormatter : NSFormatter {
    BOOL _sfFullWidth;
}
@end
@implementation AVTimeFormatter
SF_SCALAR(BOOL, isFullWidth, setFullWidth, _sfFullWidth)
- (NSString *)sfStringFromSeconds:(double)seconds {
    if (isnan(seconds) || isinf(seconds)) return @"--:--";
    BOOL negative = seconds < 0;
    long long total = (long long)floor(fabs(seconds));
    long long h = total / 3600, m = (total / 60) % 60, s = total % 60;
    if (h > 0 || _sfFullWidth) return [NSString stringWithFormat:@"%s%lld:%02lld:%02lld", negative ? "-" : "", h, m, s];
    return [NSString stringWithFormat:@"%s%02lld:%02lld", negative ? "-" : "", m, s];
}
- (NSString *)stringFromSeconds:(double)seconds { return [self sfStringFromSeconds:seconds]; }
- (NSString *)stringFromCMTime:(SFTime)time {
    if (!(time.flags & 1) || time.timescale == 0) return [self sfStringFromSeconds:NAN];
    return [self sfStringFromSeconds:(double)time.value / time.timescale];
}
- (NSString *)stringForObjectValue:(id)object {
    if ([object isKindOfClass:[NSNumber class]]) return [self sfStringFromSeconds:[object doubleValue]];
    if ([object isKindOfClass:[NSValue class]] && strcmp([object objCType], @encode(SFTime)) == 0) {
        SFTime t;
        [object getValue:&t];
        return [self stringFromCMTime:t];
    }
    return nil;
}
- (BOOL)getObjectValue:(id *)object forString:(NSString *)string errorDescription:(NSString **)error {
    (void)object; (void)string;
    if (error) *error = @"AVTimeFormatter does not parse times";
    return NO;
}
@end
