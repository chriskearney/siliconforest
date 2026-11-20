/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Scoped open declarations for Finch's actual local attribute storage. */
#if __has_feature(modules)
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
NS_ASSUME_NONNULL_BEGIN
@interface CSCustomAttributeKey : NSObject <NSCopying>
- (nullable instancetype)initWithKeyName:(NSString *)name;
- (nullable instancetype)initWithKeyName:(NSString *)name searchable:(BOOL)searchable
    searchableByDefault:(BOOL)byDefault unique:(BOOL)unique multiValued:(BOOL)multi;
@property(readonly, copy) NSString *keyName;
@property(readonly, getter=isSearchable) BOOL searchable;
@property(readonly, getter=isSearchableByDefault) BOOL searchableByDefault;
@property(readonly, getter=isUnique) BOOL unique;
@property(readonly, getter=isMultiValued) BOOL multiValued;
@end
@interface CSSearchableItemAttributeSet : NSObject <NSCopying>
- (instancetype)initWithItemContentType:(NSString *)identifier;
@property(nullable, strong) NSString *contentType, *displayName, *title;
@property(nullable, strong) NSArray<NSString *> *contentTypeTree;
- (void)setValue:(nullable id)value forCustomKey:(CSCustomAttributeKey *)key;
- (nullable id)valueForCustomKey:(CSCustomAttributeKey *)key;
+ (BOOL)supportsSecureCoding;
- (void)encodeWithCoder:(NSCoder *)coder;
- (nullable instancetype)initWithCoder:(NSCoder *)coder;
@end
/* No index/query/service class is supplied by this attribute-only provider. */
NS_ASSUME_NONNULL_END
