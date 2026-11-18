/* SPDX-License-Identifier: MIT */
/* Our local playback engine: AVAssetReader -> actual VideoToolbox, decoded NV12 -> CPU image, ExtAudioFile ->
 * retained AudioQueue output.
 *
 * Streamed (QTP, 18 November): the file is no longer decoded whole before it plays (that was capped at 512 MiB of
 * NV12, about 5 s of 1080p). A decoder thread keeps a window of decoded pictures ahead of the time the display last
 * asked for (about one second, at most 96 pictures or 256 MiB) and frees those it has passed. A request outside the
 * window (a seek backward, or far forward) restarts the reader at the sync sample before the time and discards the
 * pictures before it, except the last one at or before it. Sound is read from the file in small pieces as the queue
 * returns its buffers, from the position playback starts at. Preparing the item decodes the first window
 * synchronously, so a file that cannot be decoded still fails there. The interface is unchanged; -frameDigests now
 * lists the pictures decoded so far (all of them once the file has played through).
 */
#import <AVFoundation/AVFoundation.h>
#import "SFPlayerMedia.h"
#include <AudioToolbox/AudioQueue.h>
#include "VideoToolbox.h"
#include <libswscale/swscale.h>
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
#include <libavutil/md5.h>
#include <pthread.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include <time.h>
#include <sys/time.h>
#include "SFPlaybackClock.h"

#define SF_AHEAD_SECONDS 1.0
#define SF_MAX_PICTURES 96
#define SF_MAX_PICTURE_BYTES (256u * 1024u * 1024u)
#define SF_AUDIO_BUFFERS 6
#define SF_REORDER_PICTURES 8
#define SF_AUDIO_BUFFER_FRAMES 4096

typedef struct { CMTime pts; size_t width,height; uint8_t *bytes; } SFMediaFrame;

@interface SFPlayerMedia () {
@public
 pthread_mutex_t _lock;pthread_cond_t _changed;
 /* video: decoded pictures in presentation order, the oldest the one on screen */
 SFMediaFrame *_frames;size_t _frameCount,_frameCapacity,_frameBytes;
 CMTime _want,_seekTo,_dropBefore,_runStart;BOOL _seekPending,_endOfVideo,_stopThread,_threadStarted,_hardware,_hasVideo,_passedByDisplay;
 pthread_t _thread;double _fps;size_t _decoded,_submitted,_seeks,_digestConflicts;
 CMTime _mediaOffset;BOOL _rangeRun;   /* a reader started inside the file gives media times (no edit list): this far ahead */
 AVAsset *_asset;AVAssetTrack *_track;AVAssetReader *_reader;AVAssetReaderTrackOutput *_output;VTDecompressionSessionRef _session;
 NSMutableDictionary *_digests;
 struct SwsContext *_scale;CGImageRef _cachedImage;CMTime _cachedPTS;int _cachedWidth,_cachedHeight,_outWidth,_outHeight;BOOL _digesting;
 /* sound: the file's PCM read as the queue needs it */
 ExtAudioFileRef _audio;AudioStreamBasicDescription _format;SInt64 _audioFrames,_audioRead,_audioStartFrame;
 size_t _audioQueued,_audioReturned;BOOL _audioEnd;
 AudioQueueRef _queue;double _baseSeconds,_deviceRate;BOOL _running,_closing;
 SFPlaybackClock _playbackClock;double _rawClock,_clockError;
 _Atomic(OSStatus) _error;unsigned _callbacks;
}
- (void)closeQueue;
@end

static void sfKeepStatus(SFPlayerMedia *s,OSStatus status){if(status)s->_error=status;}
static NSError *sfError(OSStatus status,NSString *operation){return [NSError errorWithDomain:@"SiliconForestPlayer" code:status?:-1 userInfo:@{NSLocalizedDescriptionKey:operation}];}
static double sfSeconds(CMTime t){return CMTIME_IS_NUMERIC(t)?CMTimeGetSeconds(t):NAN;}

static void sfFreeFrames(SFPlayerMedia *s){for(size_t n=0;n<s->_frameCount;n++)free(s->_frames[n].bytes);s->_frameCount=0;s->_frameBytes=0;}
static void sfDropFirst(SFPlayerMedia *s){
 s->_frameBytes-=s->_frames[0].width*s->_frames[0].height*3/2;free(s->_frames[0].bytes);
 memmove(s->_frames,s->_frames+1,(s->_frameCount-1)*sizeof(SFMediaFrame));s->_frameCount--;
}
/* everything before the picture shown at `time` goes (that picture stays); the display's own passing is noted, so
   that asking for an earlier time later is known to be a seek backward */
static void sfPrune(SFPlayerMedia *s,CMTime time,BOOL byDisplay){
 if(!CMTIME_IS_NUMERIC(time))return;
 while(s->_frameCount>=2&&CMTimeCompare(s->_frames[1].pts,time)<=0){sfDropFirst(s);if(byDisplay)s->_passedByDisplay=YES;}
}
static BOOL sfWindowFull(SFPlayerMedia *s){
 if(s->_frameCount>=SF_MAX_PICTURES||s->_frameBytes>=SF_MAX_PICTURE_BYTES)return YES;
 if(!s->_frameCount)return NO;
 double last=sfSeconds(s->_frames[s->_frameCount-1].pts),want=sfSeconds(s->_want);
 if(!isfinite(want))want=sfSeconds(s->_frames[0].pts);
 return isfinite(last)&&isfinite(want)&&last-want>=SF_AHEAD_SECONDS;
}

static void sfDecoded(void *context,void *source,OSStatus status,VTDecodeInfoFlags flags,CVImageBufferRef image,CMTime pts,CMTime duration){
 (void)source;(void)flags;(void)duration;__unsafe_unretained SFPlayerMedia *s=(__bridge SFPlayerMedia *)context;
 if(status||!image||!isfinite(CMTimeGetSeconds(pts))){pthread_mutex_lock(&s->_lock);s->_error=status?:-1;pthread_mutex_unlock(&s->_lock);return;}
 /* (the picture is copied and its digest taken without the lock: the sound's queue callbacks share it) */
 pthread_mutex_lock(&s->_lock);
 if(s->_rangeRun&&CMTIME_IS_NUMERIC(s->_mediaOffset))pts=CMTimeSubtract(pts,s->_mediaOffset);
 /* after a seek, the pictures from the sync sample up to two before the target are never shown: decoded, not kept */
 BOOL skip=CMTIME_IS_NUMERIC(s->_dropBefore)&&CMTimeGetSeconds(pts)<CMTimeGetSeconds(s->_dropBefore)-2.0/s->_fps;
 s->_decoded++;
 pthread_mutex_unlock(&s->_lock);
 if(skip)return;
 OSStatus failure=0;uint8_t *data=NULL;size_t size=0,w=CVPixelBufferGetWidth(image),h=CVPixelBufferGetHeight(image);
 if(!w||!h||w>4096||h>2160||(w&1)||(h&1)||CVPixelBufferGetPixelFormatType(image)!=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange||CVPixelBufferGetPlaneCount(image)!=2)failure=-1;
 if(!failure){size=w*h*3/2;data=malloc(size);if(!data)failure=-1;}
 if(!failure&&CVPixelBufferLockBaseAddress(image,kCVPixelBufferLock_ReadOnly))failure=-1;
 if(!failure){
  const uint8_t *y=CVPixelBufferGetBaseAddressOfPlane(image,0),*uv=CVPixelBufferGetBaseAddressOfPlane(image,1);
  size_t ys=CVPixelBufferGetBytesPerRowOfPlane(image,0),us=CVPixelBufferGetBytesPerRowOfPlane(image,1);
  if(!y||!uv||ys<w||us<w)failure=-1;
  else{for(size_t n=0;n<h;n++)memcpy(data+n*w,y+n*ys,w);for(size_t n=0;n<h/2;n++)memcpy(data+w*h+n*w,uv+n*us,w);}
  CVPixelBufferUnlockBaseAddress(image,kCVPixelBufferLock_ReadOnly);
 }
 /* (QTP2) the digest of each picture only when a test asks for them (SF_PLAYER_DIGESTS=1): it was three quarters of
    the decoder thread's time */
 char md5[33]={0};
 if(!failure&&s->_digesting){uint8_t digest[16];av_md5_sum(digest,data,size);for(unsigned n=0;n<16;n++)snprintf(md5+2*n,3,"%02x",digest[n]);}
 pthread_mutex_lock(&s->_lock);
 if(failure){free(data);s->_error=failure;pthread_mutex_unlock(&s->_lock);return;}
 /* the digest of every picture decoded, once per presentation time */
 if(s->_digesting){ NSNumber *key=@(CMTimeGetSeconds(pts));
   NSString *text=[NSString stringWithUTF8String:md5],*known=s->_digests[key];
   if(!known)s->_digests[key]=text;else if(![known isEqualToString:text])s->_digestConflicts++; }
 if(s->_frameCount==s->_frameCapacity){size_t capacity=s->_frameCapacity?s->_frameCapacity*2:64;void *next=realloc(s->_frames,capacity*sizeof(SFMediaFrame));if(!next){free(data);s->_error=-1;pthread_mutex_unlock(&s->_lock);return;}s->_frames=next;s->_frameCapacity=capacity;}
 /* in presentation order (a decoder may hand pictures over in decode order) */
 size_t at=s->_frameCount;while(at>0&&CMTimeCompare(s->_frames[at-1].pts,pts)>0)at--;
 memmove(s->_frames+at+1,s->_frames+at,(s->_frameCount-at)*sizeof(SFMediaFrame));
 s->_frames[at]=(SFMediaFrame){.pts=pts,.width=w,.height=h,.bytes=data};s->_frameCount++;s->_frameBytes+=size;
 /* after a seek: the pictures before the target go, but the last one at or before it stays */
 sfPrune(s,s->_dropBefore,NO);
 pthread_cond_broadcast(&s->_changed);
 pthread_mutex_unlock(&s->_lock);
}

/* the decode time of the sync sample at or before `time`, from which a reader can start */
static CMTime sfSyncStart(AVAssetTrack *track,CMTime time){
 if(!CMTIME_IS_NUMERIC(time)||CMTimeCompare(time,kCMTimeZero)<=0||![track respondsToSelector:@selector(makeSampleCursorWithPresentationTimeStamp:)])return kCMTimeZero;
 AVSampleCursor *cursor=[track makeSampleCursorWithPresentationTimeStamp:time];
 if(!cursor)return kCMTimeZero;
 for(int guard=0;guard<100000;guard++){
  if(cursor.currentSampleSyncInfo.sampleIsFullSync)break;
  if([cursor stepInDecodeOrderByCount:-1]!=-1)return kCMTimeZero;
 }
 CMTime start=cursor.decodeTimeStamp;
 return CMTIME_IS_NUMERIC(start)&&CMTimeCompare(start,kCMTimeZero)>0?start:kCMTimeZero;
}

/* decoder side: (re)open the reader at the sync sample before `time` */
static BOOL sfOpenReader(__unsafe_unretained SFPlayerMedia *s,CMTime time,NSError **error){
 if(s->_session){VTDecompressionSessionInvalidate(s->_session);CFRelease(s->_session);s->_session=NULL;}
 [s->_reader cancelReading];s->_reader=nil;s->_output=nil;
 NSError *readError=nil;AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:s->_asset error:&readError];
 if(!reader){if(error)*error=readError?:sfError(-1,@"Cannot read video track");return NO;}
 CMTime start=sfSyncStart(s->_track,CMTIME_IS_NUMERIC(s->_mediaOffset)?CMTimeAdd(time,s->_mediaOffset):time);
 s->_rangeRun=CMTimeCompare(start,kCMTimeZero)>0;
 if(s->_rangeRun)reader.timeRange=CMTimeRangeMake(start,kCMTimePositiveInfinity);
 AVAssetReaderTrackOutput *output=[[AVAssetReaderTrackOutput alloc] initWithTrack:s->_track outputSettings:nil];
 if(![reader canAddOutput:output]){if(error)*error=sfError(-1,@"Cannot read video track");return NO;}
 [reader addOutput:output];if(![reader startReading]){if(error)*error=reader.error?:sfError(-1,@"Cannot start video reader");return NO;}
 s->_reader=reader;s->_output=output;
 return YES;
}

/* decoder side: one sample read and decoded; NO at the end of the track or on an error */
static BOOL sfDecodeOne(__unsafe_unretained SFPlayerMedia *s){
 CMSampleBufferRef sample=NULL;
 for(;;){
  sample=[s->_output copyNextSampleBuffer];
  if(!sample)break;
  if(!CMSampleBufferGetDataBuffer(sample)&&!CMSampleBufferGetNumSamples(sample)){CFRelease(sample);continue;}
  break;
 }
 if(!sample){
  if(s->_session){sfKeepStatus(s,VTDecompressionSessionFinishDelayedFrames(s->_session));sfKeepStatus(s,VTDecompressionSessionWaitForAsynchronousFrames(s->_session));}
  if(s->_reader.status==AVAssetReaderStatusFailed&&!s->_error)s->_error=-1;
  return NO;
 }
 if(!s->_session){
  int32_t pixel=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;CFNumberRef number=CFNumberCreate(NULL,kCFNumberSInt32Type,&pixel);
  const void *keys[]={kCVPixelBufferPixelFormatTypeKey};const void *values[]={number};
  CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
  VTDecompressionOutputCallbackRecord callback={sfDecoded,(__bridge void *)s};
  sfKeepStatus(s,VTDecompressionSessionCreate(NULL,CMSampleBufferGetFormatDescription(sample),NULL,attrs,&callback,&s->_session));CFRelease(number);CFRelease(attrs);
  if(s->_session){CFTypeRef hardware=NULL;if(!VTSessionCopyProperty(s->_session,kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,NULL,&hardware)){s->_hardware=hardware==kCFBooleanTrue;if(hardware)CFRelease(hardware);}}
 }
 if(!s->_error&&s->_session){
  sfKeepStatus(s,VTDecompressionSessionDecodeFrame(s->_session,sample,0,NULL,NULL));
  if(!s->_error)sfKeepStatus(s,VTDecompressionSessionWaitForAsynchronousFrames(s->_session));
 }
 CFRelease(sample);s->_submitted++;
 return !s->_error;
}

static void *sfDecoderThread(void *context){
 /* not retained: the thread must not keep its owner alive (-dealloc stops and joins it) */
 __unsafe_unretained SFPlayerMedia *s=(__bridge SFPlayerMedia *)context;
 @autoreleasepool {
 pthread_mutex_lock(&s->_lock);
 for(;;){
  while(!s->_stopThread&&!s->_seekPending&&(s->_endOfVideo||s->_error||sfWindowFull(s)))pthread_cond_wait(&s->_changed,&s->_lock);
  if(s->_stopThread)break;
  if(s->_seekPending){
   CMTime target=s->_seekTo;s->_seekPending=NO;s->_seeks++;sfFreeFrames(s);s->_endOfVideo=NO;s->_dropBefore=target;s->_runStart=target;s->_passedByDisplay=NO;
   pthread_mutex_unlock(&s->_lock);
   @autoreleasepool { if(!sfOpenReader(s,target,NULL)&&!s->_error)s->_error=-1; }
   pthread_mutex_lock(&s->_lock);
   pthread_cond_broadcast(&s->_changed);
   continue;
  }
  pthread_mutex_unlock(&s->_lock);
  BOOL more;@autoreleasepool { more=sfDecodeOne(s); }
  pthread_mutex_lock(&s->_lock);
  if(!more){s->_endOfVideo=YES;pthread_cond_broadcast(&s->_changed);}
 }
 pthread_mutex_unlock(&s->_lock);
 }
 return NULL;
}

static void sfStartThread(SFPlayerMedia *s){
 if(s->_threadStarted||!s->_hasVideo)return;
 if(!pthread_create(&s->_thread,NULL,sfDecoderThread,(__bridge void *)s))s->_threadStarted=YES;
 else s->_error=-1;
}

/* sound: one queue buffer read from the file (under the lock) */
static void sfFeed(SFPlayerMedia *s,AudioQueueRef queue,AudioQueueBufferRef buffer){
 if(s->_closing||s->_error||s->_audioEnd)return;
 UInt32 frames=buffer->mAudioDataBytesCapacity/s->_format.mBytesPerFrame;
 AudioBufferList list={1,{{s->_format.mChannelsPerFrame,frames*s->_format.mBytesPerFrame,buffer->mAudioData}}};
 OSStatus status=ExtAudioFileRead(s->_audio,&frames,&list);
 if(status){s->_error=status;return;}
 if(!frames){s->_audioEnd=YES;s->_audioFrames=s->_audioRead;return;}   /* the file's real end (the stated length can differ by the codec's padding) */
 buffer->mAudioDataByteSize=frames*s->_format.mBytesPerFrame;
 status=AudioQueueEnqueueBuffer(queue,buffer,0,NULL);
 if(status)s->_error=status;else{s->_audioRead+=frames;s->_audioQueued+=frames;}
}
static void sfReturned(void *context,AudioQueueRef queue,AudioQueueBufferRef buffer){
 __unsafe_unretained SFPlayerMedia *s=(__bridge SFPlayerMedia *)context;pthread_mutex_lock(&s->_lock);
 if(!s->_closing){s->_audioReturned+=buffer->mAudioDataByteSize/s->_format.mBytesPerFrame;s->_callbacks++;sfFeed(s,queue,buffer);}
 pthread_mutex_unlock(&s->_lock);
}
/* a picture's pixels are kept for the next one when the image lets them go (one spare: 13 MB at 2444x1375, whose
   pages were faulted in afresh for every picture) */
static pthread_mutex_t sfSpareLock=PTHREAD_MUTEX_INITIALIZER;static void *sfSpare;static size_t sfSpareSize;
static void sfFreeImage(void *info,const void *bytes,size_t size){
 (void)info;void *old=NULL;
 pthread_mutex_lock(&sfSpareLock);old=sfSpare;sfSpare=(void *)bytes;sfSpareSize=size;pthread_mutex_unlock(&sfSpareLock);
 free(old);
}
static void *sfTakePixels(size_t size){
 void *p=NULL;
 pthread_mutex_lock(&sfSpareLock);if(sfSpare&&sfSpareSize==size){p=sfSpare;sfSpare=NULL;}pthread_mutex_unlock(&sfSpareLock);
 return p?p:malloc(size);
}

@implementation SFPlayerMedia
+ (BOOL)needsBackend:(AVAsset *)asset {
 AVAssetTrack *video=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
 if([asset tracksWithMediaType:AVMediaTypeAudio].count)return YES;
 CMFormatDescriptionRef description=video.formatDescriptions.count?(__bridge CMFormatDescriptionRef)video.formatDescriptions.firstObject:NULL;
 OSType codec=description?CMFormatDescriptionGetMediaSubType(description):0;
 return codec==kCMVideoCodecType_H264||codec==kCMVideoCodecType_HEVC||codec==0x76703039;
}
- (instancetype)initWithAsset:(AVAsset *)asset error:(NSError **)error {
 if(!(self=[super init]))return nil;pthread_mutex_init(&_lock,NULL);pthread_cond_init(&_changed,NULL);atomic_init(&_error,0);
 _cachedPTS=kCMTimeInvalid;_want=kCMTimeInvalid;_dropBefore=kCMTimeInvalid;_runStart=kCMTimeZero;_mediaOffset=kCMTimeInvalid;_digests=[NSMutableDictionary dictionary];
 {const char *d=getenv("SF_PLAYER_DIGESTS");_digesting=d&&d[0]=='1';}
 NSURL *url=[asset respondsToSelector:@selector(URL)]?[(AVURLAsset *)asset URL]:nil;
 if(!url.isFileURL){if(error)*error=sfError(-1,@"Only local files are supported");return nil;}
 _asset=asset;_track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
 if(_track){
  _hasVideo=YES;_fps=_track.nominalFrameRate>0?_track.nominalFrameRate:30;
  if(!sfOpenReader(self,kCMTimeZero,error))return nil;
  /* the first window now, on this thread: a file that cannot be decoded fails here, as before */
  BOOL more=YES;
  while(more&&!_error&&!sfWindowFull(self))more=sfDecodeOne(self);
  if(!more)_endOfVideo=YES;
  if(_error||!_frameCount){if(error)*error=_reader.error?:sfError(_error,@"Video decode failed");return nil;}
  /* the media timeline's offset from the presentation one (an edit list): the earliest media presentation time
     of the first samples against the earliest picture this whole-file reader gave */
  AVSampleCursor *cursor=[_track respondsToSelector:@selector(makeSampleCursorAtFirstSampleInDecodeOrder)]?[_track makeSampleCursorAtFirstSampleInDecodeOrder]:nil;
  CMTime earliest=kCMTimePositiveInfinity;
  for(int n=0;cursor&&n<32;n++){CMTime p=cursor.presentationTimeStamp;if(CMTIME_IS_NUMERIC(p)&&CMTimeCompare(p,earliest)<0)earliest=p;if([cursor stepInDecodeOrderByCount:1]!=1)break;}
  _mediaOffset=CMTIME_IS_NUMERIC(earliest)?CMTimeSubtract(earliest,_frames[0].pts):kCMTimeZero;
 }
 if([asset tracksWithMediaType:AVMediaTypeAudio].count){
  OSStatus status=ExtAudioFileOpenURL((__bridge CFURLRef)url,&_audio);
  if(!status){UInt32 bytes=sizeof(_format);status=ExtAudioFileGetProperty(_audio,kExtAudioFileProperty_FileDataFormat,&bytes,&_format);}
  if(!status&&(!_format.mChannelsPerFrame||_format.mChannelsPerFrame>2||!isfinite(_format.mSampleRate)||_format.mSampleRate<8000||_format.mSampleRate>192000))status=-1;
  if(!status){UInt32 channels=_format.mChannelsPerFrame;double rate=_format.mSampleRate;_format=(AudioStreamBasicDescription){rate,kAudioFormatLinearPCM,kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked,channels*2,1,channels*2,channels,16,0};status=ExtAudioFileSetProperty(_audio,kExtAudioFileProperty_ClientDataFormat,sizeof(_format),&_format);}
  if(!status){SInt64 length=0;UInt32 bytes=sizeof(length);status=ExtAudioFileGetProperty(_audio,kExtAudioFileProperty_FileLengthFrames,&bytes,&length);_audioFrames=length;}
  if(!status&&_audioFrames<=0)status=-1;
  if(status){if(_audio){ExtAudioFileDispose(_audio);_audio=NULL;}if(error)*error=sfError(status,@"Audio decode failed");return nil;}
 }
 return self;
}
- (void)dealloc {
 [self closeQueue];
 pthread_mutex_lock(&_lock);_stopThread=YES;pthread_cond_broadcast(&_changed);pthread_mutex_unlock(&_lock);
 if(_threadStarted)pthread_join(_thread,NULL);
 if(_session){VTDecompressionSessionInvalidate(_session);CFRelease(_session);}
 [_reader cancelReading];
 sfFreeFrames(self);free(_frames);if(_audio)ExtAudioFileDispose(_audio);
 if(_cachedImage)CGImageRelease(_cachedImage);sws_freeContext(_scale);pthread_cond_destroy(&_changed);pthread_mutex_destroy(&_lock);
}
- (BOOL)hasAudio {return _audio!=NULL;}
- (BOOL)isAudioDrained {pthread_mutex_lock(&_lock);BOOL result=!_audio||(_queue&&_audioEnd&&_audioReturned>=_audioQueued);pthread_mutex_unlock(&_lock);return result;}
- (NSError *)playbackError {return _error?sfError(_error,@"Playback failed"):nil;}
- (void)closeQueue {
 pthread_mutex_lock(&_lock);_closing=YES;AudioQueueRef queue=_queue;pthread_mutex_unlock(&_lock);
 if(queue){AudioQueueStop(queue,true);AudioQueueDispose(queue,true);}
 pthread_mutex_lock(&_lock);_queue=NULL;_running=NO;_closing=NO;sfPlaybackClockReset(&_playbackClock);pthread_mutex_unlock(&_lock);
}
- (BOOL)startAtSeconds:(double)seconds volume:(float)volume {
 sfStartThread(self);
 if(!_audio)return YES;if(!isfinite(seconds)||seconds<0)return NO;
 if(_queue&&fabs([self clockSeconds]-seconds)>.002)[self closeQueue];
 if(!_queue){
  SInt64 frame=(SInt64)floor(seconds*_format.mSampleRate);if(frame>_audioFrames)frame=_audioFrames;
  pthread_mutex_lock(&_lock);
  _baseSeconds=seconds;_audioStartFrame=frame;_audioRead=frame;_audioQueued=0;_audioReturned=0;_audioEnd=frame>=_audioFrames;_callbacks=0;_error=0;
  OSStatus status=ExtAudioFileSeek(_audio,frame);
  pthread_mutex_unlock(&_lock);
  if(status){_error=status;return NO;}
  _error=AudioQueueNewOutput(&_format,sfReturned,(__bridge void *)self,NULL,NULL,0,&_queue);if(_error)return NO;
  UInt32 size=sizeof(_deviceRate);_error=AudioQueueGetProperty(_queue,kAudioQueueDeviceProperty_SampleRate,&_deviceRate,&size);
  if(_error||!isfinite(_deviceRate)||_deviceRate<=0){if(!_error)_error=-1;[self closeQueue];return NO;}
  pthread_mutex_lock(&_lock);
  for(unsigned n=0;n<SF_AUDIO_BUFFERS&&!_error;n++){AudioQueueBufferRef buffer=NULL;_error=AudioQueueAllocateBuffer(_queue,SF_AUDIO_BUFFER_FRAMES*_format.mBytesPerFrame,&buffer);if(!_error)sfFeed(self,_queue,buffer);}
  pthread_mutex_unlock(&_lock);
 }
 if(!_error)_error=AudioQueueSetParameter(_queue,kAudioQueueParam_Volume,volume);
 if(!_error)sfKeepStatus(self,AudioQueueStart(_queue,NULL));
 pthread_mutex_lock(&_lock);_running=!_error;sfPlaybackClockReset(&_playbackClock);BOOL running=_running;pthread_mutex_unlock(&_lock);return running;
}
- (void)pause {if(_queue){OSStatus status=AudioQueuePause(_queue);if(status)_error=status;}pthread_mutex_lock(&_lock);_running=NO;sfPlaybackClockReset(&_playbackClock);pthread_mutex_unlock(&_lock);}
- (void)setVolume:(float)volume {if(_queue){OSStatus status=AudioQueueSetParameter(_queue,kAudioQueueParam_Volume,volume);if(status)_error=status;}}
- (double)clockSeconds {
 if(!_queue||!_deviceRate)return NAN;AudioTimeStamp time={0};OSStatus status=AudioQueueGetCurrentTime(_queue,NULL,&time,NULL);if(status){_error=status;return NAN;}
 double seconds=_baseSeconds+time.mSampleTime/_deviceRate;
 if([self isAudioDrained])seconds=MAX(seconds,(double)_audioFrames/_format.mSampleRate);
 struct timespec host;clock_gettime(CLOCK_MONOTONIC,&host);
 pthread_mutex_lock(&_lock);
 _rawClock=seconds;
 double value=sfPlaybackClockSample(&_playbackClock,seconds,host.tv_sec+host.tv_nsec/1e9,_running);
 _clockError=value-seconds;
 pthread_mutex_unlock(&_lock);
 return value;
}
- (CGImageRef)copyImageAtTime:(CMTime)time index:(size_t *)outIndex {
 if(!_hasVideo||!CMTIME_IS_NUMERIC(time))return NULL;
 sfStartThread(self);
 pthread_mutex_lock(&_lock);
 _want=time;
 double t=CMTimeGetSeconds(time),frame=1.0/_fps;
 /* outside the decoded window: back before it (the display had passed those pictures, or the time is before
    where this run of the reader started), or more than the read-ahead beyond it */
 BOOL seek=NO;
 if(!_seekPending){
  if(_frameCount){
   double first=sfSeconds(_frames[0].pts),last=sfSeconds(_frames[_frameCount-1].pts);
   if(t<first-frame/2&&(_passedByDisplay||t<sfSeconds(_runStart)-frame/2))seek=YES;
   else if(!_endOfVideo&&t>last+SF_AHEAD_SECONDS)seek=YES;
  } else if(!_endOfVideo&&t>sfSeconds(_runStart)+SF_AHEAD_SECONDS)seek=YES;
  else if(_endOfVideo&&t<sfSeconds(_runStart)-frame/2)seek=YES;
 }
 if(seek){_seekTo=time;_seekPending=YES;}
 pthread_cond_broadcast(&_changed);
 /* wait (briefly) until the picture for the time is settled: the decoder has passed the time, reached the end,
    or holds the exact picture */
 /* (the deadline is kept on the monotonic clock: a timed wait may return early, so it is only a nap) */
 struct timespec begun;clock_gettime(CLOCK_MONOTONIC,&begun);
 for(;;){
  sfPrune(self,time,YES);
  /* settled once the decoder is past the time by more than a stream's reordering (B-pictures come after the
     later picture they depend on: with only that later one decoded, an earlier picture would be shown) */
  BOOL settled=_error||(!_seekPending&&(_endOfVideo||(_frameCount&&sfSeconds(_frames[_frameCount-1].pts)>=t+SF_REORDER_PICTURES*frame)));
  if(settled)break;
  struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
  /* (longer right after a seek: the decoder starts at the sync sample before the target, up to seconds earlier) */
  double limit=(_seekPending||(CMTIME_IS_NUMERIC(_dropBefore)&&CMTimeCompare(_dropBefore,_runStart)==0&&CMTimeCompare(_runStart,time)==0))?2500:400;
  if((now.tv_sec-begun.tv_sec)*1000.0+(now.tv_nsec-begun.tv_nsec)/1e6>=limit)break;
  pthread_cond_broadcast(&_changed);
  struct timeval wall;gettimeofday(&wall,NULL);
  struct timespec until={wall.tv_sec,(long)wall.tv_usec*1000+5*1000*1000};if(until.tv_nsec>=1000000000){until.tv_sec++;until.tv_nsec-=1000000000;}
  pthread_cond_timedwait(&_changed,&_lock,&until);
 }
 pthread_cond_broadcast(&_changed);
 if(!_frameCount){pthread_mutex_unlock(&_lock);return _cachedImage?CGImageRetain(_cachedImage):NULL;}
 SFMediaFrame *chosen=&_frames[0];
 size_t index=(size_t)llround(MAX(0,sfSeconds(chosen->pts))*_fps);
 if(outIndex)*outIndex=index;
 int w=(int)chosen->width,h=(int)chosen->height,ow=w,oh=h;
 if(_outWidth>=16&&_outHeight>=16){ow=_outWidth;oh=_outHeight;}
 if(_cachedImage&&CMTimeCompare(_cachedPTS,chosen->pts)==0&&_cachedWidth==ow&&_cachedHeight==oh){CGImageRef image=CGImageRetain(_cachedImage);pthread_mutex_unlock(&_lock);return image;}
 /* the picture's bytes are copied under the lock and converted outside it (the decoder may free the picture) */
 uint8_t *nv12=malloc((size_t)w*h*3/2);if(!nv12){pthread_mutex_unlock(&_lock);return NULL;}
 memcpy(nv12,chosen->bytes,(size_t)w*h*3/2);
 CMTime pts=chosen->pts;
 pthread_mutex_unlock(&_lock);
 /* (QTP2) at the size the display asked for, in the window's own layout (B, G, R, a skipped byte), scaled and
    converted in one pass on four threads (the decoded size took the M1 ~150 ms a picture to resample when drawn) */
 size_t bytes=(size_t)ow*oh*4;
 uint8_t *pixels=sfTakePixels(bytes);if(!pixels){free(nv12);return NULL;}
 if(!_scale){_scale=sws_alloc_context();if(_scale){_scale->threads=4;_scale->flags=SWS_BILINEAR;}}
 AVFrame *in=av_frame_alloc(),*out=av_frame_alloc();int converted=-1;
 if(_scale&&in&&out){
  in->format=AV_PIX_FMT_NV12;in->width=w;in->height=h;in->data[0]=nv12;in->data[1]=nv12+(size_t)w*h;in->linesize[0]=w;in->linesize[1]=w;
  /* (video range; BT.709 for HD as players take it when the stream does not say, BT.601 below) */
  in->color_range=AVCOL_RANGE_MPEG;in->colorspace=h>=720?AVCOL_SPC_BT709:AVCOL_SPC_SMPTE170M;in->chroma_location=AVCHROMA_LOC_LEFT;
  out->format=AV_PIX_FMT_BGRA;out->width=ow;out->height=oh;out->data[0]=pixels;out->linesize[0]=ow*4;out->color_range=AVCOL_RANGE_JPEG;
  converted=sws_scale_frame(_scale,out,in);
 }
 av_frame_free(&in);av_frame_free(&out);free(nv12);
 if(converted<0){
  static int said;if(!said++)fprintf(stderr,"SiliconForest player: picture conversion %dx%d -> %dx%d failed (%d)\n",w,h,ow,oh,converted);
  free(pixels);return NULL;
 }
 CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,pixels,bytes,sfFreeImage);CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
 CGImageRef image=provider&&color?CGImageCreate(ow,oh,8,32,(size_t)ow*4,color,kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little,provider,NULL,false,kCGRenderingIntentDefault):NULL;
 if(provider)CGDataProviderRelease(provider);else free(pixels);if(color)CGColorSpaceRelease(color);
 if(!image)return NULL;
 pthread_mutex_lock(&_lock);if(_cachedImage)CGImageRelease(_cachedImage);_cachedImage=CGImageRetain(image);_cachedPTS=pts;_cachedWidth=ow;_cachedHeight=oh;pthread_mutex_unlock(&_lock);
 return image;
}
- (void)setOutputPixelSize:(CGSize)size {
 int w=isfinite(size.width)&&size.width>=16&&size.width<=8192?(int)lround(size.width):0,h=isfinite(size.height)&&size.height>=16&&size.height<=8192?(int)lround(size.height):0;
 pthread_mutex_lock(&_lock);_outWidth=w&&h?w:0;_outHeight=w&&h?h:0;pthread_mutex_unlock(&_lock);
}
- (NSArray *)frameDigests {
 pthread_mutex_lock(&_lock);NSArray *times=[[_digests allKeys] sortedArrayUsingSelector:@selector(compare:)];
 NSMutableArray *result=[NSMutableArray arrayWithCapacity:times.count];for(NSNumber *pts in times)[result addObject:@{@"pts":pts,@"md5":_digests[pts]}];
 pthread_mutex_unlock(&_lock);return result;
}
- (NSDictionary *)statistics {
 double clock=[self clockSeconds];pthread_mutex_lock(&_lock);
 NSDictionary *result=@{@"videoFrames":@(_decoded),@"videoSamples":@(_submitted),@"hardware":@(_hardware),@"audioFrames":@(_audioFrames),@"audioQueued":@(_audioRead),@"audioReturned":@(_audioReturned),@"callbacks":@(_callbacks),@"clientRate":@(_format.mSampleRate),@"deviceRate":@(_deviceRate),@"clock":@(isfinite(clock)?clock:0),@"error":@(_error),@"frameBytes":@(_frameBytes),@"framesHeld":@(_frameCount),@"endOfVideo":@(_endOfVideo),@"readerRestarts":@(_seeks),@"digestConflicts":@(_digestConflicts),@"mediaOffset":@(CMTIME_IS_NUMERIC(_mediaOffset)?CMTimeGetSeconds(_mediaOffset):0)};
 NSMutableDictionary *withClock=[result mutableCopy];withClock[@"rawClock"]=@(_rawClock);withClock[@"clockError"]=@(_clockError);withClock[@"clockResyncs"]=@(_playbackClock.resyncs);
 pthread_mutex_unlock(&_lock);return withClock;
}
@end
