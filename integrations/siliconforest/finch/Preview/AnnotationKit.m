/* SPDX-License-Identifier: MIT */
/* Original SiliconForest reader implementation; native metadata supplies only
 * interface names/types. This is not Apple's editor or archive implementation. */
#import "AnnotationKit.h"
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSEvent.h>
#import <math.h>

#define SF_AK_DEFINE(n) NSString *const n = @#n;
SF_AK_CONSTANTS(SF_AK_DEFINE)
#undef SF_AK_DEFINE

/* Keep the entire error graph alive through unwinding independently of the
 * baseline Foundation exception constructor's metadata ownership. */
@interface SFAnnotationUnsupportedException : NSException
- (instancetype)initWithOperation:(NSString *)operation;
@end
@implementation SFAnnotationUnsupportedException {
    NSString *_sfReason;
    NSDictionary *_sfErrorInfo, *_sfInfo;
    NSError *_sfError;
}
- (instancetype)initWithOperation:(NSString *)operation {
    if ((self=[super initWithName:@"SFAnnotationUnsupportedOperation" reason:@"" userInfo:nil])) {
        _sfReason=[NSString stringWithFormat:@"AnnotationKit reader does not implement %@.",operation];
        _sfErrorInfo=@{NSLocalizedDescriptionKey:_sfReason};
        _sfError=[NSError errorWithDomain:@"org.siliconforest.AnnotationKit.Unsupported" code:1 userInfo:_sfErrorInfo];
        _sfInfo=@{NSUnderlyingErrorKey:_sfError};
    }
    return self;
}
- (NSString *)reason { return _sfReason; }
- (NSDictionary *)userInfo { return _sfInfo; }
@end
static void unsupported(NSString *operation)
{
    @throw [[SFAnnotationUnsupportedException alloc] initWithOperation:operation];
}
static void changed(AKAnnotation *annotation)
{
    annotation.isEdited = YES;
    annotation.modificationDate = [NSDate date];
    [[NSNotificationCenter defaultCenter] postNotificationName:AKAnnotationPropertiesChangedNotification
                                                      object:annotation userInfo:@{AKAnnotationChangeObjectKey:annotation}];
}
@implementation AKAnnotation
- (instancetype)init
{
    if ((self = [super init])) {
        _UUID = [[NSProcessInfo processInfo] globallyUniqueString];
        _originalModelBaseScaleFactor = 1; _originalExifOrientation = 1;
        _modificationDate = [NSDate date];
    }
    return self;
}
- (NSString *)displayName { return NSStringFromClass([self class]); }
- (CGRect)drawingBounds { return CGRectZero; }
- (CGRect)integralDrawingBounds { return CGRectIntegral(self.drawingBounds); }
- (CGRect)hitTestBounds { return self.drawingBounds; }
- (void)translateBy:(CGPoint)delta { unsupported(@"translation of a geometry-free annotation"); }
- (NSData *)dataRepresentation { unsupported(@"Apple annotation serialization"); return nil; }
+ (BOOL)supportsSecureCoding { return NO; }
- (instancetype)initWithCoder:(NSCoder *)coder { unsupported(@"Apple annotation decoding"); return nil; }
- (void)encodeWithCoder:(NSCoder *)coder { unsupported(@"Apple annotation encoding"); }
@end
@implementation AKStrokedAnnotation
- (instancetype)init { if ((self = [super init])) { _strokeWidth=1; _strokeColor=[NSColor blackColor]; } return self; }
@end
@implementation AKShapeAnnotation
@end
@implementation AKArrowAnnotation
- (CGRect)drawingBounds {
    double w = MAX(self.strokeWidth, 1);
    return CGRectInset(CGRectMake(MIN(_startPoint.x,_endPoint.x), MIN(_startPoint.y,_endPoint.y),
                                  fabs(_endPoint.x-_startPoint.x),fabs(_endPoint.y-_startPoint.y)), -w/2,-w/2);
}
- (void)translateBy:(CGPoint)d {
    _startPoint.x+=d.x; _startPoint.y+=d.y; _endPoint.x+=d.x; _endPoint.y+=d.y;
    _midPoint.x+=d.x; _midPoint.y+=d.y; changed(self);
}
@end
@implementation AKArrowShapeAnnotation
@end
#define SF_AK_RECT_GEOMETRY \
- (CGRect)drawingBounds { return self.rectangle; } \
- (void)translateBy:(CGPoint)d { CGRect r=self.rectangle; r.origin.x+=d.x; r.origin.y+=d.y; self.rectangle=r; changed(self); }
@implementation AKRectangularShapeAnnotation
SF_AK_RECT_GEOMETRY
@end
@implementation AKThoughtBubbleAnnotation
- (void)translateBy:(CGPoint)d { [super translateBy:d]; _pointyBitPoint.x+=d.x; _pointyBitPoint.y+=d.y; }
@end
@implementation AKBorderMaskAnnotation
SF_AK_RECT_GEOMETRY
@end
@implementation AKImageAnnotation
SF_AK_RECT_GEOMETRY
@end
@implementation AKNoteAnnotation
SF_AK_RECT_GEOMETRY
@end

@implementation AKPageModelController {
    NSArray *_annotations;
    NSMutableSet *_selection;
}
- (instancetype)init {
    if ((self=[super init])) { _annotations=@[]; _selection=[NSMutableSet set]; }
    return self;
}
- (NSArray *)annotations { return _annotations; }
- (NSSet *)selectedAnnotations { return [_selection copy]; }
- (void)sfSetAnnotations:(NSArray *)annotations {
    if (!annotations) [NSException raise:NSInvalidArgumentException format:@"Annotations cannot be nil."];
    for (id a in annotations)
        if (![a isKindOfClass:[AKAnnotation class]])
            [NSException raise:NSInvalidArgumentException format:@"Expected AKAnnotation."];
    _annotations=[annotations copy];
    [_selection intersectSet:[NSSet setWithArray:_annotations]];
    [[NSNotificationCenter defaultCenter] postNotificationName:AKAnnotationsAddedOrRemovedNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:AKSelectionChangedNotification object:self];
}
- (void)selectAnnotationsAtIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend {
    if (indexes.count && indexes.lastIndex >= _annotations.count)
        [NSException raise:NSRangeException format:@"Annotation selection outside page."];
    if (!extend) [_selection removeAllObjects];
    NSUInteger i=[indexes firstIndex];
    while (i!=NSNotFound) { [_selection addObject:_annotations[i]]; i=[indexes indexGreaterThanIndex:i]; }
    [[NSNotificationCenter defaultCenter] postNotificationName:AKSelectionChangedNotification object:self];
}
- (id)archivableRepresentation { unsupported(@"Apple page archive encoding"); return nil; }
- (instancetype)initWithArchivableRepresentation:(id)representation { unsupported(@"Apple page archive decoding"); return nil; }
@end
@implementation AKModelController { NSArray *_pages; }
- (instancetype)init { if ((self=[super init])) _pages=@[]; return self; }
- (NSArray *)pageModelControllers { return _pages; }
- (void)sfSetPageModelControllers:(NSArray *)pages {
    if (!pages) [NSException raise:NSInvalidArgumentException format:@"Pages cannot be nil."];
    for (id p in pages) if (![p isKindOfClass:[AKPageModelController class]])
        [NSException raise:NSInvalidArgumentException format:@"Expected AKPageModelController."];
    _pages=[pages copy];
}
- (AKPageModelController *)pageModelControllerForPage:(NSUInteger)index { return index<_pages.count ? _pages[index] : nil; }
- (AKPageModelController *)pageModelControllerForAnnotation:(AKAnnotation *)annotation {
    for (AKPageModelController *p in _pages) if ([p.annotations containsObject:annotation]) return p;
    return nil;
}
- (id)allSelectedAnnotations {
    NSMutableSet *selection=[NSMutableSet set];
    for (AKPageModelController *p in _pages) [selection unionSet:p.selectedAnnotations];
    return [selection copy];
}
@end
@implementation AKToolController { NSUInteger _toolMode; }
- (instancetype)initWithController:(AKController *)controller {
    if ((self=[super init])) _controller=controller;
    return self;
}
/* Mode zero is this provider's reader selection mode; other tool enums are
 * intentionally unimplemented rather than guessed from native constants. */
- (NSUInteger)defaultToolMode { return 0; }
- (BOOL)isInDefaultMode { return _toolMode==0; }
- (NSUInteger)toolMode { return _toolMode; }
- (void)setToolMode:(NSUInteger)mode { if (mode!=0) unsupported(@"annotation editing tools"); _toolMode=mode; }
- (BOOL)isOptionKeyPressed { return ([NSEvent modifierFlags] & NSAlternateKeyMask)!=0; }
@end

static void setColor(CGContextRef ctx, NSColor *color, BOOL stroke) {
    NSColor *rgb=[color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    if (!rgb) unsupported(@"non-RGB annotation color conversion");
    CGFloat r,g,b,a; [rgb getRed:&r green:&g blue:&b alpha:&a];
    if (stroke) CGContextSetRGBStrokeColor(ctx,r,g,b,a); else CGContextSetRGBFillColor(ctx,r,g,b,a);
}
static void render(AKAnnotation *a, CGContextRef ctx) {
    if (!a || !ctx) [NSException raise:NSInvalidArgumentException format:@"Annotation/context required."];
    /* Refuse shapes whose visual semantics are not implemented. Do not render a
     * thought bubble, image, note, rotated shape, or arrowhead as a plain box. */
    if ([a class]==[AKRectangularShapeAnnotation class]) {
        AKRectangularShapeAnnotation *r=(id)a;
        if (r.rotationAngle || r.hasShadow || r.isDashed) unsupported(@"rotated/shadow/dashed rectangles");
        if (r.fillColor) { setColor(ctx,r.fillColor,NO); CGContextFillRect(ctx,r.rectangle); }
        if (r.strokeColor && r.strokeWidth>0) { setColor(ctx,r.strokeColor,YES); CGContextSetLineWidth(ctx,r.strokeWidth); CGContextStrokeRect(ctx,r.rectangle); }
    } else if ([a class]==[AKBorderMaskAnnotation class]) {
        AKBorderMaskAnnotation *r=(id)a;
        if (!r.fillColor) unsupported(@"border mask without fill color");
        setColor(ctx,r.fillColor,NO); CGContextFillRect(ctx,r.rectangle);
    } else unsupported([NSString stringWithFormat:@"rendering %@",NSStringFromClass([a class])]);
}
@interface SFAnnotationReaderOverlay : NSView
@property(weak) AKController *controller;
@property NSUInteger pageIndex;
@end
@implementation SFAnnotationReaderOverlay
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; } /* Input stays with document view. */
- (void)drawRect:(NSRect)dirty {
    AKController *c=self.controller;
    AKPageModelController *p=[c.modelController pageModelControllerForPage:_pageIndex];
    if (!p.annotations.count) return;
    id<SFAnnotationReaderDelegate> d=c.delegate;
    if (![d respondsToSelector:@selector(convertPoint:fromModelToOverlayWithPageIndex:forAnnotationController:)])
        unsupported(@"overlay rendering without model-to-view coordinates");
    /* Bounds computed from actual delegate conversions. General rotated/sheared
     * overlays require a future path transformer, not guessed coordinates. */
    for (AKAnnotation *a in p.annotations) {
        if ([a class]!=[AKRectangularShapeAnnotation class] && [a class]!=[AKBorderMaskAnnotation class])
            unsupported(@"overlay shape rendering");
        CGRect rect=[a drawingBounds];
        CGPoint o=[d convertPoint:rect.origin fromModelToOverlayWithPageIndex:_pageIndex forAnnotationController:c];
        CGPoint x=[d convertPoint:CGPointMake(CGRectGetMaxX(rect),CGRectGetMinY(rect)) fromModelToOverlayWithPageIndex:_pageIndex forAnnotationController:c];
        CGPoint y=[d convertPoint:CGPointMake(CGRectGetMinX(rect),CGRectGetMaxY(rect)) fromModelToOverlayWithPageIndex:_pageIndex forAnnotationController:c];
        if (fabs(x.y-o.y)>1e-6 || fabs(y.x-o.x)>1e-6) unsupported(@"sheared/rotated overlay coordinates");
        CGContextRef ctx=[[NSGraphicsContext currentContext] graphicsPort];
        CGContextSaveGState(ctx);
        @try {
            CGContextTranslateCTM(ctx,o.x,o.y);
            CGContextScaleCTM(ctx,rect.size.width ? (x.x-o.x)/rect.size.width : 1,
                                  rect.size.height ? (y.y-o.y)/rect.size.height : 1);
            CGContextTranslateCTM(ctx,-rect.origin.x,-rect.origin.y);
            render(a,ctx);
        } @finally { CGContextRestoreGState(ctx); }
    }
}
@end

@implementation AKController {
    AKModelController *_modelController;
    AKToolController *_toolController;
    NSMutableDictionary *_overlays;
    BOOL _tornDown;
}
+ (instancetype)controllerWithDelegate:(id)d { return [[self alloc] initWithDelegate:d]; }
- (instancetype)init { return [self initWithDelegate:nil]; }
- (instancetype)initWithDelegate:(id)d {
    if ((self=[super init])) { _delegate=d; _modelController=[AKModelController new];
        _toolController=[[AKToolController alloc] initWithController:self]; _overlays=[NSMutableDictionary dictionary];
        _maxHDRGain=1; _availableHeadroom=1; }
    return self;
}
+ (double)defaultMaxHDRGain { return 1; } /* This renderer is SDR only. */
- (AKModelController *)modelController { return _modelController; }
- (AKToolController *)toolController { return _toolController; }
- (NSUInteger)toolMode { return _toolController.toolMode; }
- (void)setToolMode:(NSUInteger)m { _toolController.toolMode=m; }
- (void)resetToDefaultToolMode { self.toolMode=_toolController.defaultToolMode; }
- (BOOL)allEditingDisabled { return YES; }
- (BOOL)annotationEditingEnabled { return NO; }
- (BOOL)formFillingEnabled { return NO; }
- (BOOL)supportsFormFill { return NO; }
- (BOOL)supportsImageDescriptionEditing { return NO; }
- (NSString *)modifiedImageDescription { return nil; }
- (NSString *)suggestedTouchBarIdentifier { return nil; }
- (BOOL)isOverlayViewLoadedAtIndex:(NSUInteger)i { return _overlays[@(i)]!=nil; }
- (NSView *)overlayViewAtIndex:(NSUInteger)i { return _overlays[@(i)]; }
- (void)prepareOverlayAtIndex:(NSUInteger)i {
    if (_tornDown) [NSException raise:NSInternalInconsistencyException format:@"Annotation controller torn down."];
    if ([self isOverlayViewLoadedAtIndex:i]) return;
    if (![_delegate respondsToSelector:@selector(maxPageRectWithPageIndex:forAnnotationController:)])
        unsupported(@"overlay creation without document bounds delegate");
    CGRect rect=[_delegate maxPageRectWithPageIndex:i forAnnotationController:self];
    SFAnnotationReaderOverlay *v=[[SFAnnotationReaderOverlay alloc] initWithFrame:rect];
    v.controller=self; v.pageIndex=i; _overlays[@(i)]=v;
}
- (void)updateOverlayViewAtIndex:(NSUInteger)i { [[self overlayViewAtIndex:i] setNeedsDisplay:YES]; }
- (void)relinquishOverlayAtIndex:(NSUInteger)i { [[self overlayViewAtIndex:i] removeFromSuperview]; [_overlays removeObjectForKey:@(i)]; }
- (void)teardown {
    if (_tornDown) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:AKControllerWillTeardownNotification object:self];
    for (NSView *v in [_overlays allValues]) [v removeFromSuperview];
    [_overlays removeAllObjects]; _delegate=nil; _overlayInteractionDelegate=nil; _tornDown=YES;
}
- (void)commitEditing {
    for (AKPageModelController *p in _modelController.pageModelControllers)
        for (AKAnnotation *a in p.annotations) if (a.isEditingText) unsupported(@"text edit commit");
    /* A reader has no pending editor, so there is no commit to perform. */
}
- (NSInteger)currentExifOrientationForPageAtIndex:(NSUInteger)i {
    unsupported(@"EXIF orientation lookup without image metadata provider"); return 0;
}
- (double)currentModelBaseScaleFactorForPageAtIndex:(NSUInteger)i {
    if ([_delegate respondsToSelector:@selector(modelBaseScaleFactorOfPageAtIndex:forAnnotationController:)])
        return [_delegate modelBaseScaleFactorOfPageAtIndex:i forAnnotationController:self];
    unsupported(@"scale lookup without document scale delegate"); return 0;
}
- (CGRect)contentAlignedRectForRect:(CGRect)rect onPageAtIndex:(NSUInteger)i {
    if (![_delegate respondsToSelector:@selector(maxPageRectWithPageIndex:forAnnotationController:)])
        unsupported(@"content alignment without document bounds");
    return CGRectIntersection(rect,[_delegate maxPageRectWithPageIndex:i forAnnotationController:self]);
}
+ (void)renderAnnotation:(AKAnnotation *)a inContext:(CGContextRef)ctx {
    if (!a || !ctx) [NSException raise:NSInvalidArgumentException format:@"Annotation/context required."];
    CGContextSaveGState(ctx); @try { render(a,ctx); } @finally { CGContextRestoreGState(ctx); }
}
- (void)renderAnnotation:(AKAnnotation *)a inContext:(CGContextRef)ctx { [[self class] renderAnnotation:a inContext:ctx]; }
- (void)selectAll:(id)sender {
    AKPageModelController *p=[_modelController pageModelControllerForPage:_currentPageIndex];
    [p selectAnnotationsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,p.annotations.count)] byExtendingSelection:NO];
}
- (BOOL)validateSelectAll:(id)sender { return [[_modelController pageModelControllerForPage:_currentPageIndex] annotations].count>0; }
#define SF_AK_REJECT_ACTION(n) - (void)n:(id)sender { unsupported(@#n); }
SF_AK_REJECT_ACTION(copy) SF_AK_REJECT_ACTION(cut) SF_AK_REJECT_ACTION(paste)
SF_AK_REJECT_ACTION(delete) SF_AK_REJECT_ACTION(duplicate) SF_AK_REJECT_ACTION(undo)
SF_AK_REJECT_ACTION(redo) SF_AK_REJECT_ACTION(performActionForSender)
#define SF_AK_INVALID(n) - (BOOL)n:(id)sender { return NO; }
SF_AK_INVALID(validateCopy) SF_AK_INVALID(validateCut) SF_AK_INVALID(validatePaste)
SF_AK_INVALID(validateDelete) SF_AK_INVALID(validateDuplicate) SF_AK_INVALID(validateSender)
- (id)toolbarButtonItemOfType:(NSUInteger)t style:(NSUInteger)s { return nil; } /* No editor toolbar provided. */
- (id)signaturesMenu { return nil; }
- (id)groupTouchBarItemWithIdentifier:(id)i { return nil; }
- (BOOL)isInDFRAction { return NO; }
- (void)beginLogging:(id)c documentType:(id)t { NSLog(@"AnnotationKit telemetry unavailable; no recording started."); }
- (void)endLogging { NSLog(@"AnnotationKit telemetry unavailable; no recording exists."); }
- (void)addPopupToAnnotation:(id)a openPopup:(BOOL)o { unsupported(@"annotation popups"); }
@end
