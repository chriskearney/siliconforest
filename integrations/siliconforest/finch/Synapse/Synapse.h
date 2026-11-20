/* SPDX-License-Identifier: MIT */
#pragma once
#import <Foundation/Foundation.h>

@interface SYDocumentAttributes : NSObject <NSCopying>
@property(nonatomic, readonly, copy) NSString *sourceBundleIdentifier;
@property(nonatomic, readonly, copy) NSString *indexKey;
@property(nonatomic, readonly, copy) NSURL *originalFileURL;
@property(nonatomic, readonly, copy) NSDate *receivedDate;
@property(nonatomic, readonly, copy) NSString *sender;

- (instancetype)initWithSourceBundleIdentifier:(NSString *)identifier indexKey:(NSString *)key
                               originalFileURL:(NSURL *)url receivedDate:(NSDate *)date sender:(NSString *)sender;
+ (instancetype)documentAttributesForFileAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveToFileURL:(NSURL *)url error:(NSError **)error;
@end

@interface SYFormFillingDocumentAttributes : NSObject <NSCopying>
@property(nonatomic, readonly) BOOL formFillingCoachingDisabled;

- (instancetype)initWithFormFillingCoachingDisabled:(BOOL)disabled;
+ (instancetype)formFillingDocumentAttributesForFileAtURL:(NSURL *)url error:(NSError **)error;
+ (void)formFillingDocumentAttributesForFileAtURL:(NSURL *)url
                                      completion:(void (^)(SYFormFillingDocumentAttributes *, NSError *))completion;
- (BOOL)saveToFileURL:(NSURL *)url error:(NSError **)error;
@end

@interface SYDocumentWorkflowsClient : NSObject
- (void)hasOriginalDocumentForFileAtURL:(NSURL *)url completion:(void (^)(BOOL, NSError *))completion;
- (void)hasLastModifiedDocumentForFileAtURL:(NSURL *)url completion:(void (^)(BOOL, NSError *))completion;
- (void)openOriginalDocumentForFileAtURL:(NSURL *)url completion:(void (^)(id, NSError *))completion;
- (void)openLastModifiedDocumentForFileAtURL:(NSURL *)url completion:(void (^)(id, NSError *))completion;
@end
