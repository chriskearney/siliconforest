/* SPDX-License-Identifier: MIT */
#ifndef SF_URL_RESOURCE_READER_H
#define SF_URL_RESOURCE_READER_H
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSError.h>
typedef NSString *NSURLResourceKey __attribute__((swift_wrapper(struct)));
NSDictionary<NSURLResourceKey, id> * _Nullable SFURLReadResourceValues(
    NSURL * _Nonnull url, NSArray<NSURLResourceKey> * _Nonnull keys,
    NSError * _Nullable * _Nullable error);
#endif
