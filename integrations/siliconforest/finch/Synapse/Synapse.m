/* SPDX-License-Identifier: MIT */
#import "Synapse.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <unistd.h>

static const char documentAttribute[] = "com.siliconforest.synapse.document";
static const char coachingAttribute[] = "com.siliconforest.synapse.form-coaching";
enum { metadataLimit = 8192 };

static void setError(NSError **error, int code)
{
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

static int openRegularFile(NSURL *url, NSError **error)
{
    if (![url isFileURL]) {
        setError(error, EINVAL);
        return -1;
    }
    int fd = open([url fileSystemRepresentation], O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        setError(error, errno);
        return -1;
    }
    struct stat st;
    int result = fstat(fd, &st);
    if (result < 0 || !S_ISREG(st.st_mode)) {
        int code = result < 0 ? errno : EINVAL;
        close(fd);
        setError(error, code);
        return -1;
    }
    return fd;
}

static NSData *readMetadata(NSURL *url, const char *name, NSError **error)
{
    if (error) *error = nil;
    int fd = openRegularFile(url, error);
    if (fd < 0) return nil;
    unsigned char bytes[metadataLimit];
    ssize_t length = fgetxattr(fd, name, bytes, sizeof(bytes), 0, 0);
    int code = errno;
    close(fd);
    if (length >= 0) return [NSData dataWithBytes:bytes length:(NSUInteger)length];
    if (code != ENOATTR) setError(error, code);
    return nil;
}

static BOOL writeMetadata(NSURL *url, const char *name, NSData *data, NSError **error)
{
    if (error) *error = nil;
    if ([data length] > metadataLimit) {
        setError(error, E2BIG);
        return NO;
    }
    int fd = openRegularFile(url, error);
    if (fd < 0) return NO;
    int result = fsetxattr(fd, name, [data bytes], [data length], 0, 0);
    int code = errno;
    close(fd);
    if (result < 0) setError(error, code);
    return result == 0;
}

@implementation SYDocumentAttributes

- (instancetype)initWithSourceBundleIdentifier:(NSString *)identifier indexKey:(NSString *)key
                               originalFileURL:(NSURL *)url receivedDate:(NSDate *)date sender:(NSString *)sender
{
    self = [super init];
    if (self) {
        _sourceBundleIdentifier = [identifier copy];
        _indexKey = [key copy];
        _originalFileURL = [url copy];
        _receivedDate = [date copy];
        _sender = [sender copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return self;
}

+ (instancetype)documentAttributesForFileAtURL:(NSURL *)url error:(NSError **)error
{
    NSData *data = readMetadata(url, documentAttribute, error);
    if (!data) return nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                         format:NULL error:error];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        if (plist) setError(error, EINVAL);
        return nil;
    }
    NSString *identifier = [plist objectForKey:@"sourceBundleIdentifier"];
    NSString *key = [plist objectForKey:@"indexKey"];
    NSString *path = [plist objectForKey:@"originalPath"];
    NSDate *date = [plist objectForKey:@"receivedDate"];
    NSString *sender = [plist objectForKey:@"sender"];
    if ((identifier && ![identifier isKindOfClass:[NSString class]]) ||
        (key && ![key isKindOfClass:[NSString class]]) ||
        (path && ![path isKindOfClass:[NSString class]]) ||
        (date && ![date isKindOfClass:[NSDate class]]) ||
        (sender && ![sender isKindOfClass:[NSString class]])) {
        setError(error, EINVAL);
        return nil;
    }
    return [[self alloc] initWithSourceBundleIdentifier:identifier indexKey:key
          originalFileURL:path ? [NSURL fileURLWithPath:path] : nil receivedDate:date sender:sender];
}

- (BOOL)saveToFileURL:(NSURL *)url error:(NSError **)error
{
    if (_originalFileURL && ![_originalFileURL isFileURL]) {
        setError(error, EINVAL);
        return NO;
    }
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    if (_sourceBundleIdentifier) [plist setObject:_sourceBundleIdentifier forKey:@"sourceBundleIdentifier"];
    if (_indexKey) [plist setObject:_indexKey forKey:@"indexKey"];
    if (_originalFileURL) [plist setObject:[_originalFileURL path] forKey:@"originalPath"];
    if (_receivedDate) [plist setObject:_receivedDate forKey:@"receivedDate"];
    if (_sender) [plist setObject:_sender forKey:@"sender"];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0
                                                              options:0 error:error];
    return data && writeMetadata(url, documentAttribute, data, error);
}

@end

@implementation SYFormFillingDocumentAttributes

- (instancetype)initWithFormFillingCoachingDisabled:(BOOL)disabled
{
    self = [super init];
    if (self) _formFillingCoachingDisabled = disabled;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return self;
}

+ (instancetype)formFillingDocumentAttributesForFileAtURL:(NSURL *)url error:(NSError **)error
{
    NSError *readError = nil;
    NSData *data = readMetadata(url, coachingAttribute, &readError);
    if (error) *error = readError;
    if (readError) return nil;
    if (!data) return [[self alloc] initWithFormFillingCoachingDisabled:NO];
    const unsigned char *flag = [data bytes];
    if ([data length] != 1 || *flag > 1) {
        setError(error, EINVAL);
        return nil;
    }
    return [[self alloc] initWithFormFillingCoachingDisabled:*flag];
}

+ (void)formFillingDocumentAttributesForFileAtURL:(NSURL *)url
                                      completion:(void (^)(SYFormFillingDocumentAttributes *, NSError *))completion
{
    if (completion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            SYFormFillingDocumentAttributes *attributes = [self formFillingDocumentAttributesForFileAtURL:url error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(attributes, error); });
        });
    }
}

- (BOOL)saveToFileURL:(NSURL *)url error:(NSError **)error
{
    unsigned char value = _formFillingCoachingDisabled ? 1 : 0;
    return writeMetadata(url, coachingAttribute, [NSData dataWithBytes:&value length:1], error);
}

@end

@implementation SYDocumentWorkflowsClient

- (void)hasOriginalDocumentForFileAtURL:(NSURL *)url completion:(void (^)(BOOL, NSError *))completion
{
    [self hasLastModifiedDocumentForFileAtURL:url completion:completion];
}

- (void)hasLastModifiedDocumentForFileAtURL:(NSURL *)url completion:(void (^)(BOOL, NSError *))completion
{
    if (completion) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            SYDocumentAttributes *attributes = [SYDocumentAttributes documentAttributesForFileAtURL:url error:&error];
            if (attributes) setError(&error, ENOTSUP);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
        });
    }
}

- (void)openOriginalDocumentForFileAtURL:(NSURL *)url completion:(void (^)(id, NSError *))completion
{
    [self openLastModifiedDocumentForFileAtURL:url completion:completion];
}

- (void)openLastModifiedDocumentForFileAtURL:(NSURL *)url completion:(void (^)(id, NSError *))completion
{
    (void)url;
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = nil;
            setError(&error, ENOTSUP);
            completion(nil, error);
        });
    }
}

@end
