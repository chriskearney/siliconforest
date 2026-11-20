/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Foundation names QuickTime Player binds that SiliconForest's Foundation (15 November) lacks. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "absent.h"

/* Documented values. */
SF_EXPORT NSString *const NSKeyedArchiveRootObjectKey = @"root";
SF_EXPORT NSString *const NSAppleScriptErrorBriefMessage = @"NSAppleScriptErrorBriefMessage";
SF_EXPORT NSString *const NSMetadataItemPixelHeightKey = @"kMDItemPixelHeight";
SF_EXPORT NSString *const NSMetadataItemPixelWidthKey = @"kMDItemPixelWidth";

/* "-[Class selector]" or "+[Class selector]" for a receiver and a selector: real. */
SF_EXPORT NSString *_NSFullMethodName(id object, SEL selector) {
    Class cls = object_getClass(object);
    BOOL meta = cls && class_isMetaClass(cls);
    return [NSString stringWithFormat:@"%c[%s %s]", meta ? '+' : '-', cls ? class_getName(meta ? (Class)object : cls) : "nil",
                                      selector ? sel_getName(selector) : "(null)"];
}

/* Private; its arguments are not established. No description is produced. */
SF_EXPORT NSString *NSLocalizedFileSizeDescription(void) {
    SF_ABSENT("NSLocalizedFileSizeDescription is not implemented; no file-size text is produced");
    return nil;
}

/* AppleScript: there is no scripting runtime. */
SF_EXPORT
@interface NSAppleScript : NSObject {
    NSString *_sfSource;
}
@end
@implementation NSAppleScript
- (id)initWithSource:(NSString *)source {
    if ((self = [super init])) _sfSource = [source copy];
    return self;
}
- (id)initWithContentsOfURL:(NSURL *)url error:(NSDictionary **)error {
    (void)url;
    [self sfError:error];
    [self release];
    return nil;
}
- (void)dealloc {
    [_sfSource release];
    [super dealloc];
}
- (NSString *)source { return _sfSource; }
- (BOOL)isCompiled { return NO; }
- (void)sfError:(NSDictionary **)error {
    SF_ABSENT("NSAppleScript: there is no AppleScript runtime; scripts fail with error -1753");
    if (error)
        *error = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:-1753], @"NSAppleScriptErrorNumber",
                               @"AppleScript is not available on SiliconForest", @"NSAppleScriptErrorMessage",
                               @"AppleScript is not available", NSAppleScriptErrorBriefMessage, nil];
}
- (BOOL)compileAndReturnError:(NSDictionary **)error { [self sfError:error]; return NO; }
- (id)executeAndReturnError:(NSDictionary **)error { [self sfError:error]; return nil; }
- (id)executeAppleEvent:(id)event error:(NSDictionary **)error { (void)event; [self sfError:error]; return nil; }
@end

/* A name specifier is a value: container, key and name. Evaluating it needs the scripting
 * machinery, which resolves nothing here. */
@interface NSScriptObjectSpecifier : NSObject
- (id)initWithContainerClassDescription:(id)description containerSpecifier:(id)container key:(NSString *)key;
@end
SF_EXPORT
@interface NSNameSpecifier : NSScriptObjectSpecifier {
    NSString *_sfName;
}
@end
@implementation NSNameSpecifier
- (id)initWithContainerClassDescription:(id)description containerSpecifier:(id)container key:(NSString *)key name:(NSString *)name {
    if ((self = [super initWithContainerClassDescription:description containerSpecifier:container key:key])) _sfName = [name copy];
    return self;
}
- (NSString *)name { return _sfName; }
- (void)setName:(NSString *)name {
    [name retain];
    [_sfName release];
    _sfName = name;
}
- (void)dealloc {
    [_sfName release];
    [super dealloc];
}
@end

/* Spotlight items: there is no metadata store, so no item can be made for a file. */
SF_EXPORT
@interface NSMetadataItem : NSObject
@end
@implementation NSMetadataItem
- (id)initWithURL:(NSURL *)url {
    (void)url;
    SF_ABSENT("NSMetadataItem: there is no Spotlight store; no item exists for any file");
    [self release];
    return nil;
}
- (id)valueForAttribute:(NSString *)key { (void)key; return nil; }
- (NSDictionary *)valuesForAttributes:(NSArray *)keys { (void)keys; return [NSDictionary dictionary]; }
- (NSArray *)attributes { return [NSArray array]; }
@end

/* NSFileWrapper is not defined here: this system's class is AppKit's, and this library
 * re-exports AppKit's class symbols (additions/foundation-reexports.txt), so that one class of
 * that name exists in the process. */

#ifndef SF_MOVED /* in the Foundation wrapper: terminal-app/compat/Foundation.m */
/* File coordination. With no other process presenting files and no coordination service,
 * coordinating an access is running it: the accessor is called at once with the same URL.
 * Presenters are kept so that adding and removing them balances. */
SF_EXPORT
@interface NSFileCoordinator : NSObject {
    id _sfPresenter;
    NSString *_sfPurpose;
}
@end
@implementation NSFileCoordinator
static NSMutableArray *sfPresenters;
+ (void)addFilePresenter:(id)presenter {
    @synchronized([NSFileCoordinator class]) {
        if (!sfPresenters) sfPresenters = [[NSMutableArray alloc] init];
        if (presenter && [sfPresenters indexOfObjectIdenticalTo:presenter] == NSNotFound) [sfPresenters addObject:presenter];
    }
}
+ (void)removeFilePresenter:(id)presenter {
    @synchronized([NSFileCoordinator class]) {
        if (presenter) [sfPresenters removeObjectIdenticalTo:presenter];
    }
}
+ (NSArray *)filePresenters {
    @synchronized([NSFileCoordinator class]) {
        return sfPresenters ? [NSArray arrayWithArray:sfPresenters] : [NSArray array];
    }
}
- (id)initWithFilePresenter:(id)presenter {
    if ((self = [super init])) _sfPresenter = [presenter retain];
    return self;
}
- (NSString *)purposeIdentifier {
    if (!_sfPurpose) _sfPurpose = [[[NSProcessInfo processInfo] globallyUniqueString] copy];
    return _sfPurpose;
}
- (void)setPurposeIdentifier:(NSString *)purpose {
    [_sfPurpose release];
    _sfPurpose = [purpose copy];
}
- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error byAccessor:(void (^)(NSURL *))reader {
    (void)options;
    if (error) *error = nil;
    if (reader) reader(url);
}
- (void)coordinateWritingItemAtURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error byAccessor:(void (^)(NSURL *))writer {
    (void)options;
    if (error) *error = nil;
    if (writer) writer(url);
}
- (void)coordinateReadingItemAtURL:(NSURL *)readURL options:(NSUInteger)readOptions writingItemAtURL:(NSURL *)writeURL options:(NSUInteger)writeOptions
                             error:(NSError **)error byAccessor:(void (^)(NSURL *, NSURL *))accessor {
    (void)readOptions; (void)writeOptions;
    if (error) *error = nil;
    if (accessor) accessor(readURL, writeURL);
}
- (void)cancel {
}
- (void)dealloc {
    [_sfPresenter release];
    [_sfPurpose release];
    [super dealloc];
}
@end
#endif
