/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Method signatures derived from Finch 2d9b1bb implementations.
 * Type definitions and inheritance supplied by SiliconForest; no SDK headers. */
#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
@class PDFAction, PDFActionURL, PDFActionGoTo, PDFDestination, PDFBorder, PDFAnnotation, PDFOutline, PDFPage, PDFSelection, PDFDocument, PDFView, PDFThumbnailView;
/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <PDFKit/Numeric.h>
#import <PDFKit/KNumeric.h>
typedef NSString *PDFDocumentAttribute,*PDFDocumentWriteOption,*PDFAnnotationSubtype,*PDFAnnotationKey,*PDFBorderKey;
typedef NSRect PDFRect;
typedef NSPoint PDFPoint;
typedef NSSize PDFSize;
typedef NSInteger PDFDisplayBox,PDFBorderStyle,PDFDocumentPermissions,PDFPrintScalingMode;
typedef NSUInteger PDFAccessPermissions,PDFSelectionGranularity;
typedef NSInteger PDFDisplayMode, PDFDisplayDirection, PDFInterpolationQuality;
typedef NSUInteger PDFAreaOfInterest;
typedef NSEdgeInsets PDFEdgeInsets;
enum {
    kPDFNoArea = 0,
    kPDFInterpolationQualityHigh = 2,
};
@protocol PDFDocumentDelegate <NSObject>
@end
@protocol PDFViewDelegate <NSObject>
@end
@protocol PDFPageOverlayViewProvider <NSObject>
@end

extern NSString * const PDFDocumentDidUnlockNotification;
extern NSString * const PDFDocumentDidBeginFindNotification;
extern NSString * const PDFDocumentDidEndFindNotification;
extern NSString * const PDFDocumentDidBeginPageFindNotification;
extern NSString * const PDFDocumentDidEndPageFindNotification;
extern NSString * const PDFDocumentDidFindMatchNotification;
extern NSString * const PDFDocumentDidBeginWriteNotification;
extern NSString * const PDFDocumentDidEndWriteNotification;
extern NSString * const PDFDocumentDidBeginPageWriteNotification;
extern NSString * const PDFDocumentDidEndPageWriteNotification;
extern NSString * const PDFDocumentFoundSelectionKey;
extern NSString * const PDFDocumentPageIndexKey;
extern NSString * const PDFViewDocumentChangedNotification;
extern NSString * const PDFViewChangedHistoryNotification;
extern NSString * const PDFViewPageChangedNotification;
extern NSString * const PDFViewScaleChangedNotification;
extern NSString * const PDFViewAnnotationHitNotification;
extern NSString * const PDFViewCopyPermissionNotification;
extern NSString * const PDFViewPrintPermissionNotification;
extern NSString * const PDFViewAnnotationWillHitNotification;
extern NSString * const PDFViewSelectionChangedNotification;
extern NSString * const PDFViewDisplayModeChangedNotification;
extern NSString * const PDFViewDisplayBoxChangedNotification;
extern NSString * const PDFViewVisiblePagesChangedNotification;
extern NSString * const PDFThumbnailViewDocumentEditedNotification;

@interface PDFAction : NSObject
- (NSString *)type;
- (id)copyWithZone:(NSZone *)zone;
- (void)dealloc;
@end

@interface PDFActionURL : PDFAction
- (instancetype)init;
- (instancetype)initWithURL:(NSURL *)url;
- (NSURL *)URL;
- (void)setURL:(NSURL *)url;
- (id)copyWithZone:(NSZone *)zone;
- (void)dealloc;
@end

@interface PDFActionGoTo : PDFAction
- (instancetype)init;
- (instancetype)initWithDestination:(PDFDestination *)destination;
- (PDFDestination *)destination;
- (void)setDestination:(PDFDestination *)destination;
- (id)copyWithZone:(NSZone *)zone;
- (void)dealloc;
@end

@interface PDFDestination : NSObject
- (instancetype)init;
- (instancetype)initWithPage:(PDFPage *)page atPoint:(PDFPoint)point;
- (PDFPage *)page;
- (PDFPoint)point;
- (CGFloat)zoom;
- (void)setZoom:(CGFloat)zoom;
- (NSComparisonResult)compare:(PDFDestination *)other;
- (id)copyWithZone:(NSZone *)zone;
@end

@interface PDFBorder : NSObject
- (instancetype)init;
- (PDFBorderStyle)style;
- (void)setStyle:(PDFBorderStyle)style;
- (CGFloat)lineWidth;
- (void)setLineWidth:(CGFloat)width;
- (NSArray *)dashPattern;
- (void)setDashPattern:(NSArray *)pattern;
- (NSDictionary *)borderKeyValues;
- (void)drawInRect:(PDFRect)rect;
- (id)copyWithZone:(NSZone *)zone;
- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)dealloc;
@end

@interface PDFAnnotation : NSObject
- (instancetype)init;
- (instancetype)initWithBounds:(PDFRect)bounds forType:(PDFAnnotationSubtype)type withProperties:(NSDictionary *)properties;
- (PDFPage *)page;
- (void)setPage:(PDFPage *)page;
- (NSString *)type;
- (void)setType:(NSString *)type;
- (PDFRect)bounds;
- (void)setBounds:(PDFRect)bounds;
- (BOOL)shouldDisplay;
- (void)setShouldDisplay:(BOOL)value;
- (BOOL)shouldPrint;
- (void)setShouldPrint:(BOOL)value;
- (NSDate *)modificationDate;
- (void)setModificationDate:(NSDate *)date;
- (NSString *)userName;
- (void)setUserName:(NSString *)name;
- (PDFAnnotation *)popup;
- (void)setPopup:(PDFAnnotation *)popup;
- (PDFBorder *)border;
- (void)setBorder:(PDFBorder *)border;
- (NSColor *)color;
- (void)setColor:(NSColor *)color;
- (NSString *)contents;
- (void)setContents:(NSString *)contents;
- (PDFAction *)action;
- (void)setAction:(PDFAction *)action;
- (BOOL)hasAppearanceStream;
- (BOOL)isHighlighted;
- (void)setHighlighted:(BOOL)value;
- (BOOL)setValue:(id)value forAnnotationKey:(PDFAnnotationKey)key;
- (BOOL)setBoolean:(BOOL)value forAnnotationKey:(PDFAnnotationKey)key;
- (BOOL)setRect:(PDFRect)value forAnnotationKey:(PDFAnnotationKey)key;
- (NSDictionary *)annotationKeyValues;
- (id)valueForAnnotationKey:(PDFAnnotationKey)key;
- (void)removeValueForAnnotationKey:(PDFAnnotationKey)key;
- (void)drawWithBox:(PDFDisplayBox)box inContext:(CGContextRef)context;
- (id)copyWithZone:(NSZone *)zone;
- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)dealloc;
@property(readonly,getter=isHighlighted) BOOL highlighted;
@end

@interface PDFOutline : NSObject
- (instancetype)init;
- (PDFDocument *)document;
- (PDFOutline *)parent;
- (NSUInteger)numberOfChildren;
- (NSUInteger)index;
- (PDFOutline *)childAtIndex:(NSUInteger)index;
- (void)insertChild:(PDFOutline *)child atIndex:(NSUInteger)index;
- (void)removeFromParent;
- (NSString *)label;
- (void)setLabel:(NSString *)label;
- (BOOL)isOpen;
- (void)setIsOpen:(BOOL)value;
- (PDFDestination *)destination;
- (void)setDestination:(PDFDestination *)destination;
- (PDFAction *)action;
- (void)setAction:(PDFAction *)action;
- (void)dealloc;
@property(readonly,getter=isOpen) BOOL open;
@end

@interface PDFPage : NSObject
- (instancetype)initWithImage:(NSImage *)image options:(NSDictionary *)options;
- (instancetype)initWithImage:(NSImage *)image;
- (instancetype)init;
- (PDFDocument *)document;
- (CGPDFPageRef)pageRef;
- (NSString *)label;
- (PDFRect)boundsForBox:(PDFDisplayBox)box;
- (void)setBounds:(PDFRect)bounds forBox:(PDFDisplayBox)box;
- (NSInteger)rotation;
- (void)setRotation:(NSInteger)rotation;
- (NSArray *)annotations;
- (BOOL)displaysAnnotations;
- (void)setDisplaysAnnotations:(BOOL)value;
- (void)addAnnotation:(PDFAnnotation *)annotation;
- (void)removeAnnotation:(PDFAnnotation *)annotation;
- (PDFAnnotation *)annotationAtPoint:(PDFPoint)point;
- (CGAffineTransform)transformForBox:(PDFDisplayBox)box;
- (void)transformContext:(CGContextRef)context forBox:(PDFDisplayBox)box;
- (void)drawWithBox:(PDFDisplayBox)box;
- (void)transformContextForBox:(PDFDisplayBox)box;
- (void)drawWithBox:(PDFDisplayBox)box toContext:(CGContextRef)context;
- (NSImage *)thumbnailOfSize:(PDFSize)size forBox:(PDFDisplayBox)box;
- (NSString *)string;
- (NSAttributedString *)attributedString;
- (NSUInteger)numberOfCharacters;
- (PDFRect)characterBoundsAtIndex:(NSInteger)index;
- (NSInteger)characterIndexAtPoint:(PDFPoint)point;
- (PDFSelection *)selectionForRange:(NSRange)range;
- (PDFSelection *)selectionForWordAtPoint:(PDFPoint)point;
- (PDFSelection *)selectionForLineAtPoint:(PDFPoint)point;
- (PDFSelection *)selectionFromPoint:(PDFPoint)startPoint toPoint:(PDFPoint)endPoint;
- (PDFSelection *)selectionForRect:(PDFRect)rect;
- (NSData *)dataRepresentation;
- (id)copyWithZone:(NSZone *)zone;
- (void)dealloc;
@end

@interface PDFSelection : NSObject
- (instancetype)init;
- (instancetype)initWithDocument:(PDFDocument *)document;
- (NSArray *)pages;
- (NSColor *)color;
- (void)setColor:(NSColor *)color;
- (NSString *)string;
- (NSAttributedString *)attributedString;
- (PDFRect)boundsForPage:(PDFPage *)page;
- (NSUInteger)numberOfTextRangesOnPage:(PDFPage *)page;
- (NSRange)rangeAtIndex:(NSUInteger)index onPage:(PDFPage *)page;
- (NSArray *)selectionsByLine;
- (void)addSelection:(PDFSelection *)selection;
- (void)addSelections:(NSArray *)selections;
- (void)extendSelectionAtEnd:(NSInteger)succeed;
- (void)extendSelectionAtStart:(NSInteger)precede;
- (void)extendSelectionForLineBoundaries;
- (void)drawForPage:(PDFPage *)page active:(BOOL)active;
- (void)drawForPage:(PDFPage *)page withBox:(PDFDisplayBox)box active:(BOOL)active;
- (id)copyWithZone:(NSZone *)zone;
- (void)dealloc;
@end

@interface PDFDocument : NSObject
- (instancetype)init;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithData:(NSData *)data;
- (NSURL *)documentURL;
- (CGPDFDocumentRef)documentRef;
- (NSDictionary *)documentAttributes;
- (void)setDocumentAttributes:(NSDictionary *)attributes;
- (NSInteger)majorVersion;
- (NSInteger)minorVersion;
- (BOOL)isEncrypted;
- (BOOL)isLocked;
- (BOOL)unlockWithPassword:(NSString *)password;
- (BOOL)allowsPrinting;
- (BOOL)allowsCopying;
- (BOOL)allowsDocumentChanges;
- (BOOL)allowsDocumentAssembly;
- (BOOL)allowsContentAccessibility;
- (BOOL)allowsCommenting;
- (BOOL)allowsFormFieldEntry;
- (PDFAccessPermissions)accessPermissions;
- (PDFDocumentPermissions)permissionsStatus;
- (NSString *)string;
- (id<PDFDocumentDelegate>)delegate;
- (void)setDelegate:(id<PDFDocumentDelegate>)delegate;
- (PDFOutline *)outlineRoot;
- (void)setOutlineRoot:(PDFOutline *)outline;
- (NSUInteger)pageCount;
- (PDFPage *)pageAtIndex:(NSUInteger)index;
- (NSUInteger)indexForPage:(PDFPage *)page;
- (void)insertPage:(PDFPage *)page atIndex:(NSUInteger)index;
- (void)removePageAtIndex:(NSUInteger)index;
- (void)exchangePageAtIndex:(NSUInteger)a withPageAtIndex:(NSUInteger)b;
- (Class)pageClass;
- (NSArray *)findString:(NSString *)query withOptions:(NSStringCompareOptions)options;
- (void)beginFindString:(NSString *)query withOptions:(NSStringCompareOptions)options;
- (void)beginFindStrings:(NSArray *)queries withOptions:(NSStringCompareOptions)options;
- (PDFSelection *)findString:(NSString *)query fromSelection:(PDFSelection *)selection withOptions:(NSStringCompareOptions)options;
- (BOOL)isFinding;
- (void)cancelFindString;
- (PDFSelection *)selectionForEntireDocument;
- (PDFSelection *)selectionFromPage:(PDFPage *)startPage atCharacterIndex:(NSUInteger)start toPage:(PDFPage *)endPage atCharacterIndex:(NSUInteger)end;
- (PDFSelection *)selectionFromPage:(PDFPage *)startPage atPoint:(PDFPoint)startPoint toPage:(PDFPage *)endPage atPoint:(PDFPoint)endPoint;
- (PDFSelection *)selectionFromPage:(PDFPage *)startPage atPoint:(PDFPoint)startPoint toPage:(PDFPage *)endPage atPoint:(PDFPoint)endPoint withGranularity:(PDFSelectionGranularity)granularity;
- (NSData *)dataRepresentation;
- (NSData *)dataRepresentationWithOptions:(NSDictionary *)options;
- (BOOL)writeToFile:(NSString *)path;
- (BOOL)writeToFile:(NSString *)path withOptions:(NSDictionary *)options;
- (BOOL)writeToURL:(NSURL *)url;
- (BOOL)writeToURL:(NSURL *)url withOptions:(NSDictionary *)options;
- (NSPrintOperation *)printOperationForPrintInfo:(NSPrintInfo *)printInfo scalingMode:(PDFPrintScalingMode)scaleMode autoRotate:(BOOL)doRotate;
- (PDFSelection *)outlineItemForSelection:(PDFSelection *)selection;
- (Class)classForAnnotationType:(NSString *)annotationType;
- (id)copyWithZone:(NSZone *)zone;
- (void)dealloc;
@property(readonly,getter=isEncrypted) BOOL encrypted;
@property(readonly,getter=isLocked) BOOL locked;
@property(readonly,getter=isFinding) BOOL finding;
@end

@interface PDFView : NSView
- (instancetype)initWithFrame:(NSRect)frame;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (PDFDocument *)document;
- (void)setDocument:(PDFDocument *)document;
- (PDFPage *)currentPage;
- (BOOL)canGoToFirstPage;
- (BOOL)canGoToLastPage;
- (BOOL)canGoToNextPage;
- (BOOL)canGoToPreviousPage;
- (BOOL)canGoBack;
- (BOOL)canGoForward;
- (void)goToFirstPage:(id)sender;
- (void)goToLastPage:(id)sender;
- (void)goToNextPage:(id)sender;
- (void)goToPreviousPage:(id)sender;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)goToPage:(PDFPage *)page;
- (PDFDestination *)currentDestination;
- (void)goToDestination:(PDFDestination *)destination;
- (void)goToSelection:(PDFSelection *)selection;
- (void)goToRect:(PDFRect)rect onPage:(PDFPage *)page;
- (PDFDisplayMode)displayMode;
- (void)setDisplayMode:(PDFDisplayMode)mode;
- (PDFDisplayDirection)displayDirection;
- (void)setDisplayDirection:(PDFDisplayDirection)direction;
- (BOOL)displaysPageBreaks;
- (void)setDisplaysPageBreaks:(BOOL)value;
- (PDFEdgeInsets)pageBreakMargins;
- (void)setPageBreakMargins:(PDFEdgeInsets)margins;
- (PDFDisplayBox)displayBox;
- (void)setDisplayBox:(PDFDisplayBox)box;
- (BOOL)displaysAsBook;
- (void)setDisplaysAsBook:(BOOL)value;
- (BOOL)displaysRTL;
- (void)setDisplaysRTL:(BOOL)value;
- (NSColor *)backgroundColor;
- (void)setBackgroundColor:(NSColor *)color;
- (PDFInterpolationQuality)interpolationQuality;
- (void)setInterpolationQuality:(PDFInterpolationQuality)quality;
- (BOOL)pageShadowsEnabled;
- (void)enablePageShadows:(BOOL)enabled;
- (id<PDFViewDelegate>)delegate;
- (void)setDelegate:(id<PDFViewDelegate>)delegate;
- (id<PDFPageOverlayViewProvider>)pageOverlayViewProvider;
- (void)setPageOverlayViewProvider:(id<PDFPageOverlayViewProvider>)provider;
- (CGFloat)scaleFactor;
- (void)setScaleFactor:(CGFloat)scale;
- (CGFloat)minScaleFactor;
- (void)setMinScaleFactor:(CGFloat)value;
- (CGFloat)maxScaleFactor;
- (void)setMaxScaleFactor:(CGFloat)value;
- (BOOL)autoScales;
- (void)setAutoScales:(BOOL)value;
- (CGFloat)scaleFactorForSizeToFit;
- (void)zoomIn:(id)sender;
- (BOOL)canZoomIn;
- (void)zoomOut:(id)sender;
- (BOOL)canZoomOut;
- (PDFAreaOfInterest)areaOfInterestForMouse:(NSEvent *)event;
- (PDFAreaOfInterest)areaOfInterestForPoint:(PDFPoint)point;
- (void)setCursorForAreaOfInterest:(PDFAreaOfInterest)area;
- (void)performAction:(PDFAction *)action;
- (PDFSelection *)currentSelection;
- (void)setCurrentSelection:(PDFSelection *)selection;
- (void)setCurrentSelection:(PDFSelection *)selection animate:(BOOL)animate;
- (void)clearSelection;
- (void)selectAll:(id)sender;
- (void)scrollSelectionToVisible:(id)sender;
- (NSArray *)highlightedSelections;
- (void)setHighlightedSelections:(NSArray *)selections;
- (void)drawPage:(PDFPage *)page toContext:(CGContextRef)context;
- (void)drawPagePost:(PDFPage *)page toContext:(CGContextRef)context;
- (void)drawRect:(NSRect)dirtyRect;
- (void)copy:(id)sender;
- (void)printWithInfo:(NSPrintInfo *)printInfo autoRotate:(BOOL)rotate;
- (void)printWithInfo:(NSPrintInfo *)printInfo autoRotate:(BOOL)rotate pageScaling:(PDFPrintScalingMode)scale;
- (PDFPage *)pageForPoint:(PDFPoint)point nearest:(BOOL)nearest;
- (PDFPoint)convertPoint:(PDFPoint)point toPage:(PDFPage *)page;
- (PDFRect)convertRect:(PDFRect)rect toPage:(PDFPage *)page;
- (PDFPoint)convertPoint:(PDFPoint)point fromPage:(PDFPage *)page;
- (PDFRect)convertRect:(PDFRect)rect fromPage:(PDFPage *)page;
- (NSView *)documentView;
- (void)layoutDocumentView;
- (void)annotationsChangedOnPage:(PDFPage *)page;
- (PDFSize)rowSizeForPage:(PDFPage *)page;
- (BOOL)acceptsDraggedFiles;
- (void)setAcceptsDraggedFiles:(BOOL)value;
- (NSArray *)visiblePages;
- (BOOL)enableDataDetectors;
- (void)setEnableDataDetectors:(BOOL)value;
- (BOOL)isInMarkupMode;
- (void)setInMarkupMode:(BOOL)value;
- (void)dealloc;
@property(readonly,getter=isInMarkupMode) BOOL inMarkupMode;
@end

@interface PDFThumbnailView : NSView
- (instancetype)initWithFrame:(NSRect)frame;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (PDFView *)PDFView;
- (void)setPDFView:(PDFView *)view;
- (NSColor *)backgroundColor;
- (void)setBackgroundColor:(NSColor *)color;
- (NSArray *)selectedPages;
- (NSSize)thumbnailSize;
- (void)setThumbnailSize:(NSSize)size;
- (NSUInteger)maximumNumberOfColumns;
- (void)setMaximumNumberOfColumns:(NSUInteger)columns;
- (NSFont *)labelFont;
- (void)setLabelFont:(NSFont *)font;
- (BOOL)allowsDragging;
- (void)setAllowsDragging:(BOOL)value;
- (BOOL)allowsMultipleSelection;
- (void)setAllowsMultipleSelection:(BOOL)value;
- (void)drawRect:(NSRect)dirtyRect;
- (void)encodeWithCoder:(NSCoder *)coder;
- (void)dealloc;
@end
extern PDFDocumentAttribute const PDFDocumentTitleAttribute;
extern PDFDocumentAttribute const PDFDocumentAuthorAttribute;
extern PDFDocumentAttribute const PDFDocumentSubjectAttribute;
extern PDFDocumentAttribute const PDFDocumentCreatorAttribute;
extern PDFDocumentAttribute const PDFDocumentProducerAttribute;
extern PDFDocumentAttribute const PDFDocumentCreationDateAttribute;
extern PDFDocumentAttribute const PDFDocumentModificationDateAttribute;
extern PDFDocumentAttribute const PDFDocumentKeywordsAttribute;
extern PDFDocumentWriteOption const PDFDocumentOwnerPasswordOption;
extern PDFDocumentWriteOption const PDFDocumentUserPasswordOption;
extern PDFDocumentWriteOption const PDFDocumentAccessPermissionsOption;
extern PDFDocumentWriteOption const PDFDocumentBurnInAnnotationsOption;
extern PDFDocumentWriteOption const PDFDocumentSaveTextFromOCROption;
extern PDFDocumentWriteOption const PDFDocumentSaveImagesAsJPEGOption;
extern PDFDocumentWriteOption const PDFDocumentOptimizeImagesForScreenOption;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeText;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeLink;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeFreeText;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeLine;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeSquare;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeCircle;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeHighlight;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeUnderline;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeStrikeOut;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeInk;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeStamp;
extern PDFAnnotationSubtype const PDFAnnotationSubtypePopup;
extern PDFAnnotationSubtype const PDFAnnotationSubtypeWidget;
extern PDFAnnotationKey const PDFAnnotationKeyAppearanceDictionary;
extern PDFAnnotationKey const PDFAnnotationKeyAppearanceState;
extern PDFAnnotationKey const PDFAnnotationKeyBorder;
extern PDFAnnotationKey const PDFAnnotationKeyColor;
extern PDFAnnotationKey const PDFAnnotationKeyContents;
extern PDFAnnotationKey const PDFAnnotationKeyFlags;
extern PDFAnnotationKey const PDFAnnotationKeyDate;
extern PDFAnnotationKey const PDFAnnotationKeyName;
extern PDFAnnotationKey const PDFAnnotationKeyPage;
extern PDFAnnotationKey const PDFAnnotationKeyRect;
extern PDFAnnotationKey const PDFAnnotationKeySubtype;
extern PDFAnnotationKey const PDFAnnotationKeyAction;
extern PDFAnnotationKey const PDFAnnotationKeyBorderStyle;
extern PDFAnnotationKey const PDFAnnotationKeyDestination;
extern PDFBorderKey const PDFBorderKeyLineWidth;
extern PDFBorderKey const PDFBorderKeyStyle;
extern PDFBorderKey const PDFBorderKeyDashPattern;
extern const CGFloat kPDFDestinationUnspecifiedValue;
