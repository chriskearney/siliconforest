/* SPDX-License-Identifier: MIT */
#import <Foundation/NSObject.h>
@class NSString;
@interface UTType : NSObject
+ (nullable instancetype)typeWithIdentifier:(nonnull NSString *)identifier __attribute__((swift_name("lookup(identifier:)")));
+ (nullable instancetype)typeWithFilenameExtension:(nonnull NSString *)extension __attribute__((swift_name("lookup(filenameExtension:)")));
+ (nullable instancetype)typeWithFilenameExtension:(nonnull NSString *)extension
                                  conformingToType:(nonnull UTType *)type __attribute__((swift_name("lookup(filenameExtension:conformingTo:)")));
@property(readonly, copy) NSString * _Nonnull identifier;
@property(readonly, copy) NSString * _Nullable preferredFilenameExtension;
- (BOOL)conformsToType:(UTType * _Nonnull)type __attribute__((swift_name("conforms(to:)")));
@end
