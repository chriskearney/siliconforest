/* SPDX-License-Identifier: MIT
   TextEdit reads a file with readFromURL:options:documentAttributes:error:,
   which the dock AppKit does not implement. initWithURL: on
   NSAttributedString only raises. NSRichTextReader's
   attributedStringWithData: is the reader that parses RTF. The menu nib
   also binds NSMenuItem.objectValue, and that key is missing. */
#import <Foundation/Foundation.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>

extern NSString * const NSDocumentTypeDocumentAttribute;
extern NSString * const NSRTFTextDocumentType;

@interface NSMutableAttributedString (SFTextEditRead)
- (void)setAttributedString:(NSAttributedString *)attrString;
@end

static void sf_read_log(const char *msg)
{
    if (!getenv("SF_LOG_EXC"))
        return;
    fprintf(stderr, "SF_TE_READ %s\n", msg);
    fflush(stderr);
}

static BOOL sf_readFromURL(id self, SEL _cmd, NSURL *url, NSDictionary *options, NSDictionary **attrs, NSError **error)
{
    (void)_cmd;
    (void)options;
    NSError *local = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error ? error : &local];
    if (!data) {
        NSError *shown = error && *error ? *error : local;
        char buf[300];
        snprintf(buf, sizeof buf, "fail %s", shown ? [[shown description] UTF8String] : "nil");
        sf_read_log(buf);
        return NO;
    }
    Class reader = objc_lookUpClass("NSRichTextReader");
    id loaded = nil;
    BOOL owned = NO;
    if (reader) {
        loaded = ((id (*)(id, SEL, id))objc_msgSend)((id)reader,
            sel_registerName("attributedStringWithData:"), data);
    }
    if (!loaded) {
        NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!plain)
            plain = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!plain) {
            sf_read_log("fail undecoded");
            return NO;
        }
        loaded = [[NSAttributedString alloc] initWithString:plain];
        [plain release];
        owned = YES;
        sf_read_log("plain");
    } else {
        NSUInteger n = ((NSUInteger (*)(id, SEL))objc_msgSend)(loaded, sel_registerName("length"));
        char buf[64];
        snprintf(buf, sizeof buf, "rtf len=%lu", (unsigned long)n);
        sf_read_log(buf);
    }
    [(NSMutableAttributedString *)self setAttributedString:loaded];
    if (owned)
        [loaded release];
    if (attrs) {
        static NSDictionary *doc;
        if (!doc)
            doc = [[NSDictionary alloc] initWithObjectsAndKeys:
                   NSRTFTextDocumentType, NSDocumentTypeDocumentAttribute, nil];
        *attrs = doc;
    }
    return YES;
}

static char sf_object_value_key;

static id sf_objectValue(id self, SEL _cmd)
{
    (void)_cmd;
    return objc_getAssociatedObject(self, &sf_object_value_key);
}

static void sf_setObjectValue(id self, SEL _cmd, id value)
{
    (void)_cmd;
    objc_setAssociatedObject(self, &sf_object_value_key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

__attribute__((constructor))
static void sf_document_read_install(void)
{
    Class storage = objc_lookUpClass("NSTextStorage");
    if (storage)
        class_replaceMethod(storage, sel_registerName("readFromURL:options:documentAttributes:error:"),
                            (IMP)sf_readFromURL, "c@:@@@@");
    Class item = objc_lookUpClass("NSMenuItem");
    if (!item)
        return;
    class_addMethod(item, sel_registerName("objectValue"), (IMP)sf_objectValue, "@@:");
    class_addMethod(item, sel_registerName("setObjectValue:"), (IMP)sf_setObjectValue, "v@:@");
}
