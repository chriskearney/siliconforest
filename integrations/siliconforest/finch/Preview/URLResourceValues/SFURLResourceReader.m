/* SPDX-License-Identifier: MIT
 * Private read adapter over retained NSURL metadata and the open Finch UTI
 * provider. No NSURL category is installed and no global provider is replaced.
 */
#import <Foundation/Foundation.h>
#import "SFURLResourceReader.h"
#include <dlfcn.h>
#include <pthread.h>
@interface NSURL (SFURLRetainedReadDeclarations)
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error;
@end
@interface NSObject (SFURLTypeDeclarations)
+ (id)typeWithIdentifier:(NSString *)identifier;
@end
typedef NSString *(*SFTypeForPath)(NSString *, BOOL, BOOL);
static pthread_once_t sf_uti_once = PTHREAD_ONCE_INIT;
static void *sf_uti_handle;
static SFTypeForPath sf_type_for_path;
static void sf_load_types(void) {
    sf_uti_handle = dlopen("/System/Library/Frameworks/UniformTypeIdentifiers.framework/Versions/A/UniformTypeIdentifiers", RTLD_NOW | RTLD_LOCAL);
    if (sf_uti_handle) sf_type_for_path = (SFTypeForPath)dlsym(sf_uti_handle, "_UTFinchTypeIdentifierForPath");
}
static NSDictionary *sf_unsupported(NSError **error, NSString *reason) {
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:3328
        userInfo:@{NSLocalizedDescriptionKey:reason}];
    return nil;
}
NSDictionary *SFURLReadResourceValues(NSURL *url, NSArray *keys, NSError **error) {
    if (error) *error = nil;
    if (![url respondsToSelector:@selector(getResourceValue:forKey:error:)])
        return sf_unsupported(error, @"Retained NSURL resource reader unavailable.");
    @try {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            id value = nil;
            if (![url getResourceValue:&value forKey:key error:error]) return nil;
            BOOL wantsType = [key isEqualToString:@"NSURLTypeIdentifierKey"] || [key isEqualToString:@"NSURLContentTypeKey"];
            if (!value && wantsType && [url isFileURL]) {
                id directory = nil, package = nil;
                if (![url getResourceValue:&directory forKey:@"NSURLIsDirectoryKey" error:error]) return nil;
                if (!directory) return sf_unsupported(error, @"Directory metadata unavailable for content type lookup.");
                BOOL isDirectory = [directory boolValue];
                if (isDirectory) {
                    if (![url getResourceValue:&package forKey:@"NSURLIsPackageKey" error:error]) return nil;
                    if (!package) return sf_unsupported(error, @"Package metadata unavailable for directory content type lookup.");
                }
                pthread_once(&sf_uti_once, sf_load_types);
                Class typeClass = NSClassFromString(@"UTType");
                if (!sf_type_for_path || !typeClass)
                    return sf_unsupported(error, @"Retained Finch content type provider unavailable.");
                NSString *identifier = sf_type_for_path([url path], isDirectory, [package boolValue]);
                if (!identifier) return sf_unsupported(error, @"Content type provider returned no identifier.");
                value = [key isEqualToString:@"NSURLTypeIdentifierKey"] ? (id)identifier : [(id)typeClass typeWithIdentifier:identifier];
                if (!value) return sf_unsupported(error, @"Content type identifier could not be represented.");
            }
            if (value) [result setObject:value forKey:key];
        }
        return result;
    } @catch (NSException *e) {
        return sf_unsupported(error, [e reason] ?: @"Retained resource reader raised an exception.");
    }
}
