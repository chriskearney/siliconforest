// SPDX-License-Identifier: MIT
#import <PDFKit/PDFKit.h>
#include <dlfcn.h>
#include <stdio.h>

@protocol PDFEncryptionProbe
- (void)setDocument:(PDFDocument *)document;
- (void)setShowsOKCancelButtons:(BOOL)shows;
- (NSView *)view;
- (NSString *)ownerPassword;
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        void *provider = dlopen("/System/Library/Frameworks/PDFKit.framework/Versions/A/PDFKit", RTLD_NOW | RTLD_LOCAL);
        if (!provider) return 3;
        Class documentClass = NSClassFromString(@"PDFDocument");
        Class annotationClass = NSClassFromString(@"PDFAnnotation");
        Class editorClass = NSClassFromString(@"PDFEncryptionOptionsEditor");
        Class viewerClass = NSClassFromString(@"PDFEncryptionOptionsViewer");
        if (!documentClass || !annotationClass || !editorClass || !viewerClass) return 4;
        NSString **propertyName = dlsym(provider, "PDFAnnotationPropertiesChangedNotification");
        NSString **pageName = dlsym(provider, "PDFViewAnnotationsDidChangeNotification");
        if (!propertyName || !pageName) return 5;

        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        PDFDocument *doc = [[[documentClass alloc] initWithURL:url] autorelease];
        PDFPage *page = [doc pageAtIndex:0];
        PDFAnnotation *anno = [[[annotationClass alloc] initWithBounds:NSMakeRect(10, 10, 4, 4) forType:@"Text" withProperties:nil] autorelease];
        if (!page || !anno) return 6;

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        __block unsigned properties = 0, adds = 0, removals = 0;
        id property = [center addObserverForName:*propertyName object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (note.object == nil && note.userInfo[@"annotation"] == anno &&
                [note.userInfo[@"key"] isEqual:@"/Contents"])
                properties++;
        }];
        id lifecycle = [center addObserverForName:*pageName object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (note.object == nil && note.userInfo[@"annotation"] == anno && note.userInfo[@"page"] == page) {
                NSNumber *change = note.userInfo[@"changeType"];
                if (change && change.unsignedIntegerValue == 0) adds++;
                if (change && change.unsignedIntegerValue == 2) removals++;
            }
        }];
        [page addAnnotation:anno];
        [anno setContents:@"Preview probe"];
        [page removeAnnotation:anno];
        [center removeObserver:property];
        [center removeObserver:lifecycle];
        if (properties != 1 || adds != 1 || removals != 1) return 7;

        id<PDFEncryptionProbe> editor = [[[editorClass alloc] init] autorelease];
        [editor setDocument:doc];
        [editor setShowsOKCancelButtons:YES];
        id<PDFEncryptionProbe> viewer = [[[viewerClass alloc] init] autorelease];
        [viewer setDocument:doc];
        NSArray *controls = [viewer.view subviews];
        if (controls.count != 1 || ![[controls.firstObject stringValue] isEqual:@"This PDF is unencrypted."] ||
            [editor.view subviews].count != 2 || editor.ownerPassword || viewer.ownerPassword) return 8;
        puts("PDFKit annotation notifications and read-only encryption controls passed");
        return 0;
    }
}
