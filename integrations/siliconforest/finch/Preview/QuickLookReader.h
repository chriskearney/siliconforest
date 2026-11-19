/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Open reader declarations; native reference supplied names/types only. */
#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import <CoreGraphics/CoreGraphics.h>
extern NSString *const QLSeamlessOpeningDisplayStateContentsEDRStrengthKey;
extern NSString *const QLSeamlessOpeningDisplayStatePageKey;
extern NSString *const QLSeamlessOpeningDisplayStatePasswordKey;
@protocol QLPreviewItem <NSObject>
@property(readonly) NSURL *previewItemURL;
@optional
@property(readonly) NSString *previewItemTitle;
@end
@interface NSURL(QLPreviewConvenienceAdditions) <QLPreviewItem>
@end
@class QLPreviewView;
@interface QLPreviewDocument : NSObject
- (instancetype)initWithPreviewItem:(id<QLPreviewItem>)item forPreviewView:(QLPreviewView *)view;
@property(readonly) id<QLPreviewItem> previewItem;
@property(readonly, weak) QLPreviewView *previewView;
@property(copy) NSString *password;
@property NSUInteger state;
@property(readonly) NSURL *currentURL;
@property(readonly) id preview;
@property(readonly) BOOL isLoaded, isRemote, isSaving, isGeneric, canShare;
@property(readonly) NSUInteger numberOfPages;
@property(readonly) CGRect bounds;
@property(readonly) id displayState;
- (void)startLoading;
- (void)invalidate;
- (BOOL)drawPage:(NSUInteger)index inRect:(CGRect)rect context:(CGContextRef)context;
- (NSString *)stringForPage:(NSUInteger)index;
@end
@interface QLPreviewView : NSView
- (instancetype)initWithFrame:(NSRect)frame style:(NSUInteger)style;
@property(strong) id<QLPreviewItem> previewItem;
@property(strong) QLPreviewDocument *document;
@property(weak) id delegate;
@property(strong) id displayState;
@property BOOL shouldCloseWithWindow, autostarts, autoZooms;
@property double zoomFactor;
@property NSUInteger currentPage;
@property(readonly) BOOL isLoaded, isGeneric, isRemote, canBeResized, needsPageControl, needsZoomControl;
@property(readonly) NSUInteger numberOfPages;
@property(readonly) CGSize naturalPreviewSize;
@property(readonly) double maxZoomFactor, zoomFactorToFitWidth;
@property(readonly) CGRect previewContentFrame;
- (void)refreshPreviewItem;
- (void)close;
@end
/* Existing QTP's opener is recompiled unchanged; its factory reports absence. */
@interface QLSeamlessDocumentOpener : NSObject
+ (instancetype)seamlessDocumentOpenerForURL:(NSURL *)url;
@end
@interface QLSeamlessDocumentCloser : NSObject
@property(copy) NSDictionary *displayState;
@property(readonly,getter=isAnimating) BOOL animating;
+ (instancetype)seamlessDocumentCloserForWindow:(id)window;
@end
