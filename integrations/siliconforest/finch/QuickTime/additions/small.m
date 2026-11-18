/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Single classes QuickTime Player binds from AVFAudio, CoreImage and WebKit. SF_LIB selects
 * the framework. Written from the public API documentation. */
#import <Foundation/Foundation.h>
#include "absent.h"

#if SF_LIB == 1 /* AVFAudio */
/* The routing arbiter negotiates the audio route with the user's other Apple devices.
 * SiliconForest takes part in no such negotiation, so arbitration ends at once: the default
 * device did not change and there was no error. That is the true outcome here. */
SF_EXPORT
@interface AVAudioRoutingArbiter : NSObject
@end
@implementation AVAudioRoutingArbiter
+ (id)sharedRoutingArbiter {
    static AVAudioRoutingArbiter *shared;
    @synchronized(self) {
        if (!shared) shared = [[self alloc] init];
    }
    return shared;
}
- (void)beginArbitrationWithCategory:(NSInteger)category completionHandler:(void (^)(BOOL defaultDeviceChanged, NSError *error))handler {
    (void)category;
    if (handler) handler(NO, nil);
}
- (void)leaveArbitration {
}
@end

/* macOS has only a small AVAudioSession. Nothing of it is implemented: the shared session
 * exists, and each request it gets is refused with an error. */
SF_EXPORT
@interface AVAudioSession : NSObject
@end
@implementation AVAudioSession
+ (id)sharedInstance {
    static AVAudioSession *shared;
    @synchronized(self) {
        if (!shared) shared = [[self alloc] init];
    }
    return shared;
}
static BOOL SFRefuse(NSError **error) {
    SF_ABSENT("AVAudioSession: audio session requests are not implemented; each is refused with an error");
    if (error)
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:-4 /* unimpErr */
                                 userInfo:[NSDictionary dictionaryWithObject:@"AVAudioSession is not available on SiliconForest" forKey:NSLocalizedDescriptionKey]];
    return NO;
}
- (BOOL)setPreferredOutputAudioScoreForSmartRouting:(NSInteger)score error:(NSError **)error { (void)score; return SFRefuse(error); }
- (BOOL)setActive:(BOOL)active error:(NSError **)error { (void)active; return SFRefuse(error); }
- (BOOL)setCategory:(NSString *)category error:(NSError **)error { (void)category; return SFRefuse(error); }
@end

#elif SF_LIB == 2 /* CoreImage */
/* There is no Core Image renderer to render into a destination. */
SF_EXPORT
@interface CIRenderDestination : NSObject
@end
@implementation CIRenderDestination
#define SF_NO_DESTINATION() \
    do { \
        SF_ABSENT("CIRenderDestination: there is no Core Image renderer; no destination can be made (nil)"); \
        [self release]; \
        return nil; \
    } while (0)
- (id)init { SF_NO_DESTINATION(); }
- (id)initWithPixelBuffer:(void *)buffer { (void)buffer; SF_NO_DESTINATION(); }
- (id)initWithIOSurface:(id)surface { (void)surface; SF_NO_DESTINATION(); }
@end

#elif SF_LIB == 3 /* WebKit */
/* There is no web engine behind this WebKit: no data store exists. */
SF_EXPORT
@interface WKWebsiteDataStore : NSObject
@end
@implementation WKWebsiteDataStore
+ (id)defaultDataStore {
    SF_ABSENT("WKWebsiteDataStore: there is no web engine; no data store exists (nil)");
    return nil;
}
+ (id)nonPersistentDataStore {
    SF_ABSENT("WKWebsiteDataStore: there is no web engine; no data store exists (nil)");
    return nil;
}
- (id)init {
    SF_ABSENT("WKWebsiteDataStore: there is no web engine; no data store exists (nil)");
    [self release];
    return nil;
}
@end
#else
#error SF_LIB selects the framework
#endif
