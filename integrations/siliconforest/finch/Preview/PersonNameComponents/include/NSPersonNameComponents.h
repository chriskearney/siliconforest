/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Public names of the retained NSPersonNameComponents class. This is not an
 * Apple SDK header. The class and its formatter are already implemented in the
 * retained Foundation dylib; this declaration only makes that class visible to
 * the Swift overlay. Object properties are nullable because a new instance
 * stores nil for every field.
 */
#ifndef NSPersonNameComponents_h
#define NSPersonNameComponents_h

#import <Foundation/NSObject.h>

@class NSString;

@interface NSPersonNameComponents : NSObject <NSCopying, NSCoding>
- (instancetype)initWithNamePrefix:(NSString * _Nullable)namePrefix
                         givenName:(NSString * _Nullable)givenName
                        middleName:(NSString * _Nullable)middleName
                        familyName:(NSString * _Nullable)familyName
                        nameSuffix:(NSString * _Nullable)nameSuffix
                          nickname:(NSString * _Nullable)nickname;
@property (copy, nullable) NSString *namePrefix;
@property (copy, nullable) NSString *givenName;
@property (copy, nullable) NSString *middleName;
@property (copy, nullable) NSString *familyName;
@property (copy, nullable) NSString *nameSuffix;
@property (copy, nullable) NSString *nickname;
@property (copy, nullable) NSPersonNameComponents *phoneticRepresentation;
@end

#endif /* NSPersonNameComponents_h */
