/* SPDX-License-Identifier: MIT */
/* Original reader model. Names/types from owner-authorized runtime metadata;
 * no Apple implementation, archive format, assets, or private headers used. */
#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <CoreGraphics/CoreGraphics.h>

#define SF_AK_CONSTANTS(X) \
 X(AKAnnotationChangeObjectKey) X(AKAnnotationPropertiesChangedNotification) \
 X(AKAnnotationsAddedOrRemovedNotification) X(AKControllerSuggestedTouchBarItemChanged) \
 X(AKControllerWillTeardownNotification) X(AKSelectionChangedNotification) \
 X(AKStatisticsDocumentTypeImage) X(AKStatisticsDocumentTypePDF) \
 X(AKTouchBarItemIdentifierHighlights) X(AKTouchBarItemIdentifierMain)
#define SF_AK_DECLARE(n) extern NSString *const n;
SF_AK_CONSTANTS(SF_AK_DECLARE)
#undef SF_AK_DECLARE

@interface AKAnnotation : NSObject
@property(copy, readonly) NSString *UUID;
@property(readonly) NSString *displayName;
@property(copy) NSString *author, *textContentType, *customPlaceholderText;
@property(strong) NSDate *modificationDate;
@property(weak) AKAnnotation *parentAnnotation, *childAnnotation;
@property BOOL isEdited, isEditingText, textIsClipped, editingDisabled, isDetectedSignature;
@property BOOL shouldUseAppearanceOverride, shouldObserveEdits, isBeingCopied;
@property BOOL textIsFixedWidth, textIsFixedHeight, shouldUsePlaceholderText;
@property BOOL editsDisableAppearanceOverride, isTranslating, isDraggingHandle, isFormField;
@property NSUInteger formContentType;
@property NSInteger akSerializationVersion, akSerializationPlatform, originalExifOrientation;
@property double originalModelBaseScaleFactor;
@property CGRect initialDrawingBoundsForAppearanceOverride;
@property(readonly) CGRect drawingBounds, integralDrawingBounds, hitTestBounds;
- (void)translateBy:(CGPoint)delta;
- (NSData *)dataRepresentation;
+ (BOOL)supportsSecureCoding;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
@end
@interface AKStrokedAnnotation : AKAnnotation
@property double strokeWidth;
@property(copy) NSColor *strokeColor;
@property(strong) NSColor *strokeColorHDR, *strokeColorSDR;
@property(getter=isDashed) BOOL dashed;
@property NSInteger brushStyle;
@property BOOL hasShadow;
@end
@interface AKShapeAnnotation : AKStrokedAnnotation
@property(copy) NSColor *fillColor;
@property(strong) NSColor *fillColorHDR, *fillColorSDR;
@end
@interface AKArrowAnnotation : AKShapeAnnotation
@property CGPoint startPoint, endPoint, midPoint;
@property NSUInteger arrowHeadStyle;
@end
@interface AKArrowShapeAnnotation : AKArrowAnnotation
@property double arrowLineWidth, arrowHeadWidth, arrowHeadLength;
@end
@interface AKRectangularShapeAnnotation : AKShapeAnnotation
@property CGRect rectangle;
@property double rotationAngle;
@property(getter=isHighlighted) BOOL highlighted;
@property(strong) NSColor *highlightColor;
@end
@interface AKThoughtBubbleAnnotation : AKRectangularShapeAnnotation
@property CGPoint pointyBitPoint;
@end
@interface AKBorderMaskAnnotation : AKAnnotation
@property CGRect rectangle;
@property(copy) NSColor *fillColor;
@property(strong) NSColor *fillColorHDR, *fillColorSDR;
@end
@interface AKImageAnnotation : AKAnnotation
@property CGRect rectangle;
@property(strong) NSImage *image;
@property BOOL hasShadow, verticallyFlipped, horizontallyFlipped;
@property double rotationAngle;
@end
@interface AKNoteAnnotation : AKAnnotation
@property CGRect rectangle;
@property(copy) NSString *contents;
@property(copy) NSColor *fillColor;
@property(strong) NSColor *fillColorHDR, *fillColorSDR;
@end

@interface AKPageModelController : NSObject
@property(weak) id representedObject;
@property(readonly) NSArray *annotations;
@property(readonly) NSSet *selectedAnnotations;
@property CGRect appliedCropRect;
/* Original explicit model API: no claim to decode Apple's archive format. */
- (void)sfSetAnnotations:(NSArray *)annotations;
- (void)selectAnnotationsAtIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
- (id)archivableRepresentation;
- (instancetype)initWithArchivableRepresentation:(id)representation;
@end
@interface AKModelController : NSObject
@property(readonly) NSArray *pageModelControllers;
- (void)sfSetPageModelControllers:(NSArray *)pages;
- (AKPageModelController *)pageModelControllerForPage:(NSUInteger)index;
- (AKPageModelController *)pageModelControllerForAnnotation:(AKAnnotation *)annotation;
- (id)allSelectedAnnotations;
@end
@class AKController;
@interface AKToolController : NSObject
@property(weak) AKController *controller;
@property BOOL allInkEnabled, pencilInkEnabled, suppressSuggestedTouchBarChange;
@property NSUInteger toolMode;
@property(readonly) BOOL isInDefaultMode;
- (instancetype)initWithController:(AKController *)controller;
- (NSUInteger)defaultToolMode;
- (BOOL)isOptionKeyPressed;
@end
@protocol SFAnnotationReaderDelegate <NSObject>
@optional
- (CGRect)maxPageRectWithPageIndex:(NSUInteger)index forAnnotationController:(AKController *)controller;
- (CGPoint)convertPoint:(CGPoint)point fromModelToOverlayWithPageIndex:(NSUInteger)index forAnnotationController:(AKController *)controller;
- (CGPoint)convertPoint:(CGPoint)point fromOverlayToModelWithPageIndex:(NSUInteger)index forAnnotationController:(AKController *)controller;
- (double)modelBaseScaleFactorOfPageAtIndex:(NSUInteger)index forAnnotationController:(AKController *)controller;
- (void)placeAuxiliaryView:(NSView *)view forAnnotationController:(AKController *)controller;
- (void)removeAuxiliaryView:(NSView *)view forAnnotationController:(AKController *)controller;
@end
@interface AKController : NSObject
@property(weak) id<SFAnnotationReaderDelegate> delegate;
@property(weak) id overlayInteractionDelegate;
@property(copy) NSString *author;
@property(strong) id dfrController;
@property(readonly) AKModelController *modelController;
@property(readonly) AKToolController *toolController;
@property NSUInteger currentPageIndex, toolMode;
@property double maxHDRGain, availableHeadroom;
@property BOOL overlayShouldPixelate;
@property(readonly) BOOL allEditingDisabled, annotationEditingEnabled, formFillingEnabled;
@property(readonly) NSString *modifiedImageDescription, *suggestedTouchBarIdentifier;
+ (instancetype)controllerWithDelegate:(id)delegate;
- (instancetype)initWithDelegate:(id)delegate;
+ (double)defaultMaxHDRGain;
- (BOOL)supportsFormFill;
- (BOOL)supportsImageDescriptionEditing;
- (void)prepareOverlayAtIndex:(NSUInteger)index;
- (NSView *)overlayViewAtIndex:(NSUInteger)index;
- (BOOL)isOverlayViewLoadedAtIndex:(NSUInteger)index;
- (void)updateOverlayViewAtIndex:(NSUInteger)index;
- (void)relinquishOverlayAtIndex:(NSUInteger)index;
- (void)teardown;
- (void)commitEditing;
- (void)resetToDefaultToolMode;
- (NSInteger)currentExifOrientationForPageAtIndex:(NSUInteger)index;
- (double)currentModelBaseScaleFactorForPageAtIndex:(NSUInteger)index;
- (CGRect)contentAlignedRectForRect:(CGRect)rect onPageAtIndex:(NSUInteger)index;
+ (void)renderAnnotation:(AKAnnotation *)annotation inContext:(CGContextRef)context;
- (void)renderAnnotation:(AKAnnotation *)annotation inContext:(CGContextRef)context;
- (void)selectAll:(id)sender;
- (BOOL)validateSelectAll:(id)sender;
- (BOOL)validateCopy:(id)sender;
- (BOOL)validateCut:(id)sender;
- (BOOL)validatePaste:(id)sender;
- (BOOL)validateDelete:(id)sender;
- (BOOL)validateDuplicate:(id)sender;
- (BOOL)validateSender:(id)sender;
- (void)copy:(id)sender;
- (void)cut:(id)sender;
- (void)paste:(id)sender;
- (void)delete:(id)sender;
- (void)duplicate:(id)sender;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)performActionForSender:(id)sender;
- (id)toolbarButtonItemOfType:(NSUInteger)type style:(NSUInteger)style;
- (id)signaturesMenu;
- (id)groupTouchBarItemWithIdentifier:(id)identifier;
- (BOOL)isInDFRAction;
- (void)beginLogging:(id)context documentType:(id)type;
- (void)endLogging;
- (void)addPopupToAnnotation:(id)annotation openPopup:(BOOL)open;
@end
