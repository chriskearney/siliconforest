/* SPDX-License-Identifier: MIT */
/* Private-feature absence providers for a staged QuickTime load. Method layouts
 * are our declarations checked against runtime metadata emitted by our own
 * Linux-built reference program. No Apple SDK or implementation is copied. */
#import <Foundation/Foundation.h>
#include <CoreMedia/CoreMedia.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <math.h>
static NSError *unavailable(NSString *domain){return [NSError errorWithDomain:domain code:1 userInfo:@{NSLocalizedDescriptionKey:@"This private service is unavailable on SiliconForest"}];}
static void diagnostic(const char *name){fprintf(stderr,"%s: unavailable on SiliconForest\n",name);}
#if SF_KIND==1
@interface PFVideoAVObjectBuilder:NSObject
- (id)initWithVideoAsset:(id)asset videoAdjustments:(id)adjustments;
@end
@implementation PFVideoAVObjectBuilder
- (id)init{diagnostic("PhotosFormats object builder");[self release];return nil;}
- (id)initWithVideoAsset:(id)asset videoAdjustments:(id)adjustments{(void)asset;(void)adjustments;return [self init];}
@end
@interface PFVideoAdjustments:NSObject
- (id)initWithPropertyListDictionary:(NSDictionary *)dictionary;
- (id)initWithSlowMotionTimeRange:(CMTimeRange)range rate:(float)rate;
@end
@implementation PFVideoAdjustments
- (id)init{diagnostic("PhotosFormats adjustments");[self release];return nil;}
- (id)initWithPropertyListDictionary:(NSDictionary *)dictionary{(void)dictionary;return [self init];}
- (id)initWithSlowMotionTimeRange:(CMTimeRange)range rate:(float)rate{(void)range;(void)rate;return [self init];}
+ (id)defaultSlowMotionAdjustmentsForAsset:(id)asset{(void)asset;diagnostic("PhotosFormats default adjustments");return nil;}
+ (BOOL)isRecognizedSlowMotionFormatWithIdentifier:(id)identifier version:(id)version{(void)identifier;(void)version;return NO;}
+ (NSURL *)defaultVideoAdjustmentsURLForVideoURL:(NSURL *)url{(void)url;return nil;}
/* the playback rate a high-frame-rate movie's slow part would get: slow motion is not offered here, so every movie
   plays at its own rate (1); QuickTime treats a rate of 1 or more as "not slow motion" */
+ (float)defaultSlowMotionRateForNominalFrameRate:(float)rate{if(rate>60.5f)diagnostic("PhotosFormats slow motion");return 1.0f;}
@end
@interface PFSlowMotionUtilities:NSObject @end
@implementation PFSlowMotionUtilities
+ (id)timeRangeMapperForSourceDuration:(double)duration slowMotionRate:(float)rate slowMotionTimeRange:(CMTimeRange)range forExport:(BOOL)export{
 (void)duration;(void)rate;(void)range;(void)export;diagnostic("PhotosFormats slow-motion mapper");return nil;
}
+ (id)assetFromVideoAsset:(id)asset slowMotionRate:(float)rate slowMotionTimeRange:(CMTimeRange)range forExport:(BOOL)export outAudioMix:(id *)mix outTimeRangeMapper:(id *)mapper{
 (void)asset;(void)rate;(void)range;(void)export;if(mix)*mix=nil;if(mapper)*mapper=nil;diagnostic("PhotosFormats slow-motion asset");return nil;
}
+ (id)slowMotionSourceAssetPropertyKeys{return @[];}
+ (id)audioMixForScaledComposition:(id)composition timeRangeMapper:(id)mapper{(void)composition;(void)mapper;return nil;}
@end
#elif SF_KIND==2
id GEOManagedObjectContext(BOOL create){(void)create;return nil;}
@interface GeoKitPlace:NSObject @end
@implementation GeoKitPlace
- (id)init{diagnostic("GeoKit place database");[self release];return nil;}
/* the order a place search is sorted in (the database has none here) */
+ (NSSortDescriptor *)populationSortDescriptor{return [NSSortDescriptor sortDescriptorWithKey:@"population" ascending:NO];}
@end
@interface GEOCity:GeoKitPlace @end
@implementation GEOCity @end
#elif SF_KIND==3
NSString *const ASAttributeContentVersion=@"_ContentVersion";
@interface MADownloadOptions:NSObject {
 BOOL _discretionary,_allowsCellularAccess,_allowsExpensiveAccess,_doNotBlockBeforeFirstUnlock,_doNotBlockOnNetworkStatus,_requiresPowerPluggedIn;
 long _timeoutIntervalForResource;
}
@property BOOL discretionary,allowsCellularAccess,allowsExpensiveAccess,doNotBlockBeforeFirstUnlock,doNotBlockOnNetworkStatus,requiresPowerPluggedIn;
@property long timeoutIntervalForResource;
@end
@implementation MADownloadOptions
@synthesize discretionary=_discretionary,allowsCellularAccess=_allowsCellularAccess,allowsExpensiveAccess=_allowsExpensiveAccess,doNotBlockBeforeFirstUnlock=_doNotBlockBeforeFirstUnlock,doNotBlockOnNetworkStatus=_doNotBlockOnNetworkStatus,requiresPowerPluggedIn=_requiresPowerPluggedIn,timeoutIntervalForResource=_timeoutIntervalForResource;
@end
@interface MAAsset:NSObject @end
@implementation MAAsset
+ (void)startCatalogDownload:(NSString *)type options:(MADownloadOptions *)options then:(void (^)(long))callback{
 (void)type;(void)options;diagnostic("MobileAsset catalog");if(callback)dispatch_async(dispatch_get_global_queue(0,0),^{callback(-1);});
}
+ (void)startCatalogDownload:(NSString *)type then:(void (^)(long))callback{[self startCatalogDownload:type options:nil then:callback];}
- (void)startDownload:(void (^)(long))callback{diagnostic("MobileAsset download");if(callback)dispatch_async(dispatch_get_global_queue(0,0),^{callback(-1);});}
- (void)startDownload:(MADownloadOptions *)options then:(void (^)(long))callback{(void)options;[self startDownload:callback];}
- (NSURL *)getLocalFileUrl{return nil;}
- (NSString *)getLocalFilePath{return nil;}
- (NSURL *)getLocalUrl{return nil;}
- (NSDictionary *)attributes{return @{};}
- (BOOL)wasLocal{return NO;}
@end
@interface MAAssetQuery:NSObject {NSString *_assetType;}
- (long)queryMetaDataSync;
@end
@implementation MAAssetQuery
- (id)initWithType:(NSString *)type{if((self=[super init]))_assetType=[type copy];return self;}
- (id)initWithType:(NSString *)type andPurpose:(NSString *)purpose{(void)purpose;return [self initWithType:type];}
- (void)dealloc{[_assetType release];[super dealloc];}
- (NSString *)assetType{return _assetType;}
- (NSArray *)results{return @[];}
- (NSArray *)assetIds{return @[];}
- (long)resultCode{return -1;}
- (BOOL)isDone{return YES;}
- (long)queryMetaDataSync{diagnostic("MobileAsset query");return -1;}
- (void)queryMetaData:(void (^)(long))callback{if(callback)dispatch_async(dispatch_get_global_queue(0,0),^{callback([self queryMetaDataSync]);});}
- (long)addKeyValuePair:(NSString *)key with:(id)value{(void)key;(void)value;return -1;}
- (long)addKeyValueArray:(NSString *)key with:(NSArray *)values{(void)key;(void)values;return -1;}
- (long)addKeyValueNull:(NSString *)key{(void)key;return -1;}
- (void)returnTypes:(long)types{(void)types;}
@end
#elif SF_KIND==4
@interface MPDisplayMgr:NSObject @end
@implementation MPDisplayMgr
+ (id)sharedMgr{diagnostic("MonitorPanel display manager");return nil;}
- (id)init{[self release];return nil;}
@end
#endif
