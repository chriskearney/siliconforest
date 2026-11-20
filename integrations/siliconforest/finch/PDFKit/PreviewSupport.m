// SPDX-License-Identifier: MIT
#import <PDFKit/PDFKit.h>

NSString *const PDFAnnotationPropertiesChangedNotification = @"PDFAnnotationPropertiesChangedNotificationNotification";
NSString *const PDFPageAnnotationAddedNotification = @"PDFPageAnnotationAddedNotificationNotification";
NSString *const PDFPageAnnotationRemovedNotification = @"PDFPageAnnotationRemovedNotificationNotification";
NSString *const PDFPageDrawingCompleteNotification = @"PDFPageDrawingComplete";
NSString *const PDFPageImageProperty_DarkModeRendering = @"PDFPageImageProperty_DarkModeRendering";
NSString *const PDFPageImageProperty_DrawAnnotations = @"PDFPageImageProperty_DrawAnnotations";
NSString *const PDFPageImageProperty_WithRotation = @"PDFPageImageProperty_WithRotation";
NSString *const PDFViewAnnotationsDidChangeNotification = @"PDFViewAnnotationsDidChange";
NSString *const kPDFDocumentWriteOption_UseAppendMode = @"PDFDocumentWriteOption_UseAppendMode";

static NSTextField *PDFStatusLabel(NSRect frame, NSString *status) {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setStringValue:status];
    return label;
}

@interface PDFEncryptionOptionsEditor : NSViewController
@property(nonatomic, retain) PDFDocument *document;
@property(nonatomic) BOOL showsOKCancelButtons;
@property(nonatomic, readonly) NSString *ownerPassword;
@property(nonatomic, readonly) PDFAccessPermissions accessPermissions;
@end

@implementation PDFEncryptionOptionsEditor

- (NSString *)ownerPassword { return nil; }
- (PDFAccessPermissions)accessPermissions { return [self.document accessPermissions]; }

- (void)loadView {
    NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 380, 98)] autorelease];
    [view addSubview:PDFStatusLabel(NSMakeRect(16, 56, 348, 22), @"Changing PDF encryption is unavailable.")];
    if (self.showsOKCancelButtons) {
        NSButton *cancel = [[[NSButton alloc] initWithFrame:NSMakeRect(276, 12, 88, 32)] autorelease];
        [cancel setTitle:@"Cancel"];
        [cancel setTarget:self];
        [cancel setAction:@selector(cancelButtonClicked:)];
        [cancel setKeyEquivalent:@"\x1b"];
        [view addSubview:cancel];
    }
    [self setView:view];
}

- (void)cancelButtonClicked:(id)sender {
    (void)sender;
    NSWindow *sheet = [[self view] window];
    if (sheet)
        [(NSApplication *)NSApp endSheet:sheet returnCode:NSModalResponseCancel];
}

- (void)dealloc {
    [_document release];
    [super dealloc];
}

@end

@interface PDFEncryptionOptionsViewer : NSViewController
@property(nonatomic, retain) PDFDocument *document;
@property(nonatomic) NSControlSize controlSize;
- (void)setPerformEditBlock:(void (^)(void))editBlock;
@property(nonatomic, readonly) NSString *ownerPassword;
@end

@implementation PDFEncryptionOptionsViewer {
    NSTextField *_status;
}

- (NSString *)ownerPassword { return nil; }

- (void)setControlSize:(NSControlSize)controlSize {
    _controlSize = controlSize;
    [_status setFont:[NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:controlSize]]];
}

- (void)setPerformEditBlock:(void (^)(void))editBlock {
    // The viewer has no edit control while the writer is unavailable.
    (void)editBlock;
}

- (void)updateEncryptionStatus {
    NSString *text = @"No PDF selected";
    if (_document)
        text = [_document isEncrypted] ? @"This PDF is encrypted." : @"This PDF is unencrypted.";
    [_status setStringValue:text];
}

- (void)setDocument:(PDFDocument *)document {
    if (_document != document) {
        [document retain];
        [_document release];
        _document = document;
    }
    [self updateEncryptionStatus];
}

- (void)loadView {
    NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 38)] autorelease];
    [_status release];
    _status = [PDFStatusLabel(NSMakeRect(12, 8, 316, 22), @"") retain];
    [view addSubview:_status];
    [self setControlSize:_controlSize];
    [self updateEncryptionStatus];
    [self setView:view];
}

- (void)dealloc {
    [_status release];
    [_document release];
    [super dealloc];
}

@end
