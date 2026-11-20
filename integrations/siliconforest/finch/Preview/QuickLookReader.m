/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Copyright (c) 2026 The Finch Project contributors.
 * Mined names, item/model storage and view lifetime from Finch
 * 2d9b1bb1af57e14462e4621d194929188a8845b0:userland/QuickLook/QuickLookUI.m.
 * SiliconForest: actual loaded state/page counts, image/PDF draw, page/zoom
 * bounds and explicit unsupported errors; no panel/generator/animation service. */
#import "QuickLookReader.h"
#import <AppKit/NSImage.h>
#import <AppKit/NSGraphicsContext.h>
#import <math.h>
#import <string.h>

/* Public operations implemented by the separately owned retained PDFKit. */
@protocol SFQuickLookPDFPage <NSObject>
- (NSRect)boundsForBox:(NSInteger)box;
- (NSInteger)rotation;
- (void)drawWithBox:(NSInteger)box toContext:(CGContextRef)context;
- (NSString *)string;
@end
@protocol SFQuickLookPDFDocument <NSObject>
- (instancetype)initWithURL:(NSURL *)url;
- (NSUInteger)pageCount;
- (id<SFQuickLookPDFPage>)pageAtIndex:(NSUInteger)index;
- (BOOL)isLocked;
@end

@interface SFQuickLookReaderException : NSException
- (instancetype)initWithCode:(NSInteger)code reason:(NSString *)reason;
@end
@implementation SFQuickLookReaderException {
    NSString *_sfReason;
    NSDictionary *_sfErrorInfo, *_sfInfo;
    NSError *_sfError;
}
- (instancetype)initWithCode:(NSInteger)code reason:(NSString *)reason {
    if ((self=[super initWithName:@"SFQuickLookReaderError" reason:@"" userInfo:nil])) {
        _sfReason=[reason copy]; _sfErrorInfo=@{NSLocalizedDescriptionKey:_sfReason};
        _sfError=[NSError errorWithDomain:@"org.siliconforest.QuickLook.Reader" code:code userInfo:_sfErrorInfo];
        _sfInfo=@{NSUnderlyingErrorKey:_sfError};
    }
    return self;
}
- (NSString *)reason { return _sfReason; }
- (NSDictionary *)userInfo { return _sfInfo; }
@end
static void fail(NSInteger code,NSString *reason) {
    @throw [[SFQuickLookReaderException alloc] initWithCode:code reason:reason];
}

@implementation NSURL(QLPreviewConvenienceAdditions)
- (NSURL *)previewItemURL { return self; }
- (NSString *)previewItemTitle { return self.lastPathComponent; }
@end

static CGRect fit(CGSize content,CGRect target) {
    if (content.width<=0 || content.height<=0 || target.size.width<=0 || target.size.height<=0)
        fail(1,@"Preview drawing requires positive content and target dimensions.");
    double scale=MIN(target.size.width/content.width,target.size.height/content.height);
    CGSize size=CGSizeMake(content.width*scale,content.height*scale);
    return CGRectMake(target.origin.x+(target.size.width-size.width)/2,
                      target.origin.y+(target.size.height-size.height)/2,size.width,size.height);
}

@implementation QLPreviewDocument {
    id<QLPreviewItem> _item;
    __weak QLPreviewView *_view;
    NSImage *_image;
    id<SFQuickLookPDFDocument> _pdf;
}
- (instancetype)initWithPreviewItem:(id<QLPreviewItem>)item forPreviewView:(QLPreviewView *)view {
    if ((self=[super init])) { _item=item; _view=view; }
    return self;
}
- (id<QLPreviewItem>)previewItem { return _item; }
- (QLPreviewView *)previewView { return _view; }
- (id)preview { return _item; }
- (NSURL *)currentURL { return [_item respondsToSelector:@selector(previewItemURL)] ? _item.previewItemURL : nil; }
- (BOOL)isLoaded { return _image!=nil || (_pdf && [_pdf pageCount]>0); }
- (BOOL)isRemote { return self.currentURL && !self.currentURL.isFileURL; }
- (BOOL)isSaving { return NO; }
- (BOOL)isGeneric { return NO; } /* No icon/generic fallback is supplied. */
- (BOOL)canShare { return NO; }
- (NSUInteger)numberOfPages { return _pdf ? [_pdf pageCount] : (_image ? 1 : 0); }
- (id)displayState { return _view.displayState; }
- (CGRect)bounds {
    if (_image) return (CGRect){CGPointZero,_image.size};
    if (_pdf && [_pdf pageCount]) {
        id<SFQuickLookPDFPage> page=[_pdf pageAtIndex:0];CGRect b=[page boundsForBox:1];
        return CGRectIsEmpty(b) ? [page boundsForBox:0] : b;
    }
    return CGRectZero;
}
- (void)startLoading {
    _image=nil; _pdf=nil;
    NSURL *url=self.currentURL;
    if (!url || !url.isFileURL) fail(2,@"This reader requires a local file preview item.");
    NSData *data=[NSData dataWithContentsOfURL:url];
    if (!data) fail(3,@"The preview item could not be read.");
    if (data.length>=5 && memcmp(data.bytes,"%PDF-",5)==0) {
        Class cls=NSClassFromString(@"PDFDocument");
        if (!cls) fail(4,@"The retained PDFKit document provider is unavailable.");
        id<SFQuickLookPDFDocument> pdf=[(id<SFQuickLookPDFDocument>)[cls alloc] initWithURL:url];
        if (!pdf || ![pdf pageCount] || ([pdf respondsToSelector:@selector(isLocked)] && [pdf isLocked]))
            fail(5,@"PDFKit could not open this PDF; locked/encrypted documents are unsupported here.");
        _pdf=pdf;
    } else {
        NSImage *image=[[NSImage alloc] initWithContentsOfURL:url];
        if (!image || image.size.width<=0 || image.size.height<=0)
            fail(6,@"This reader supports decodable images and readable PDFs only.");
        _image=image;
    }
    [_view refreshPreviewItem];
}
- (void)invalidate { _image=nil; _pdf=nil; [_view refreshPreviewItem]; }
- (BOOL)drawPage:(NSUInteger)index inRect:(CGRect)rect context:(CGContextRef)context {
    if (!context) fail(7,@"A drawing context is required.");
    if (!self.isLoaded || index>=self.numberOfPages) fail(8,@"The requested preview page is not loaded or is outside the document.");
    CGContextSaveGState(context);
    @try {
        CGContextClipToRect(context,rect);
        if (_image) {
            CGRect target=fit(_image.size,rect);
            [NSGraphicsContext saveGraphicsState];
            @try {
                [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:context flipped:NO]];
                [_image drawInRect:target fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
            } @finally { [NSGraphicsContext restoreGraphicsState]; }
        } else {
            id<SFQuickLookPDFPage> page=[_pdf pageAtIndex:index];
            if ([page rotation]%360) fail(9,@"Rotated PDF preview drawing is not implemented by this narrow adapter.");
            NSInteger box=1;CGRect b=[page boundsForBox:box];
            if (CGRectIsEmpty(b)) { box=0; b=[page boundsForBox:box]; }
            CGRect target=fit(b.size,rect);
            CGContextTranslateCTM(context,target.origin.x,target.origin.y);
            CGContextScaleCTM(context,target.size.width/b.size.width,target.size.height/b.size.height);
            CGContextTranslateCTM(context,-b.origin.x,-b.origin.y);
            [page drawWithBox:box toContext:context];
        }
    } @finally { CGContextRestoreGState(context); }
    return YES;
}
- (NSString *)stringForPage:(NSUInteger)index {
    if (!self.isLoaded || index>=self.numberOfPages) fail(8,@"Text requested outside a loaded document.");
    return _pdf ? [[_pdf pageAtIndex:index] string] : nil; /* Raster images have no text layer. */
}
@end

@implementation QLPreviewView {
    QLPreviewDocument *_document;
    id<QLPreviewItem> _previewItem;
    NSUInteger _currentPage;
    double _zoomFactor;
    NSUInteger _style;
}
- (instancetype)initWithFrame:(NSRect)frame style:(NSUInteger)style {
    if (style>1) fail(10,@"Unsupported preview view style.");
    if ((self=[super initWithFrame:frame])) { _style=style; _shouldCloseWithWindow=YES; _autoZooms=YES; _zoomFactor=1; }
    return self;
}
- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame style:0]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self=[super initWithCoder:coder])) { _shouldCloseWithWindow=YES; _autoZooms=YES; _zoomFactor=1; }
    return self;
}
- (QLPreviewDocument *)document { return _document; }
- (void)setDocument:(QLPreviewDocument *)document {
    _document=document; _previewItem=document.previewItem; _currentPage=0; [self refreshPreviewItem];
}
- (id<QLPreviewItem>)previewItem { return _previewItem; }
- (void)setPreviewItem:(id<QLPreviewItem>)item {
    if (!item) { self.document=nil; return; }
    QLPreviewDocument *document=[[QLPreviewDocument alloc] initWithPreviewItem:item forPreviewView:self];
    [document startLoading]; self.document=document;
}
- (NSUInteger)currentPage { return _currentPage; }
- (void)setCurrentPage:(NSUInteger)index {
    if (!_document.isLoaded || index>=_document.numberOfPages) fail(8,@"Preview page index is outside a loaded document.");
    _currentPage=index; [self setNeedsDisplay:YES];
}
- (double)zoomFactor { return _zoomFactor; }
- (void)setZoomFactor:(double)factor {
    if (!isfinite(factor) || factor<=0 || factor>32) fail(11,@"Preview zoom must be finite and within (0,32].");
    _zoomFactor=factor; [self setNeedsDisplay:YES];
}
- (BOOL)isLoaded { return _document.isLoaded; }
- (BOOL)isGeneric { return _document.isGeneric; }
- (BOOL)isRemote { return _document.isRemote; }
- (BOOL)canBeResized { return YES; }
- (NSUInteger)numberOfPages { return _document.numberOfPages; }
- (CGSize)naturalPreviewSize { return _document.bounds.size; }
- (BOOL)needsPageControl { return self.numberOfPages>1; }
- (BOOL)needsZoomControl { return self.isLoaded; }
- (double)maxZoomFactor { return 32; }
- (double)zoomFactorToFitWidth { return self.naturalPreviewSize.width>0 ? self.bounds.size.width/self.naturalPreviewSize.width : 0; }
- (CGRect)previewContentFrame {
    if (!self.isLoaded) return CGRectZero;
    CGRect base=_autoZooms ? fit(self.naturalPreviewSize,self.bounds) : (CGRect){self.bounds.origin,self.naturalPreviewSize};
    CGSize size=CGSizeMake(base.size.width*_zoomFactor,base.size.height*_zoomFactor);
    return CGRectMake(CGRectGetMidX(self.bounds)-size.width/2,CGRectGetMidY(self.bounds)-size.height/2,size.width,size.height);
}
- (BOOL)isOpaque { return NO; }
- (void)refreshPreviewItem { [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)dirty {
    if (!self.isLoaded) return;
    CGContextRef context=[[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(context);
    @try { CGContextClipToRect(context,self.bounds); [_document drawPage:_currentPage inRect:self.previewContentFrame context:context]; }
    @finally { CGContextRestoreGState(context); }
}
- (void)close { [_document invalidate]; self.document=nil; }
- (void)viewWillMoveToWindow:(id)window {
    if (!window && self.window && _shouldCloseWithWindow) [self close];
}
@end

@implementation QLSeamlessDocumentCloser
+ (instancetype)seamlessDocumentCloserForWindow:(id)window { return nil; } /* No seamless service. */
- (BOOL)isAnimating { return NO; }
@end
