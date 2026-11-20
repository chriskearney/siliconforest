/* Quartz symbols Preview imports. Constants and IKSaveOptions / QuartzFilter follow
   Finch ImageKit/IKConstants.m, ImageKit/IKSaveOptions.m and QuartzFilters/QuartzFilter.m.
   IKImageView2 and IKImageEditPanel are not in Finch yet; this is the image view those
   constants describe (scroll view, zoom, fit) and the edit panel that hosts it. */
#import "sf_min.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#include <dlfcn.h>
#import <math.h>
#import <stdbool.h>

#define SF_EXPORT __attribute__((visibility("default")))

SF_EXPORT NSString *const IKImageCompletedInitialLoadingNotification = @"IKImageCompletedInitialLoadingNotification";
SF_EXPORT NSString *const kIKGeometryChanged = @"kIKGeometryChanged";
SF_EXPORT NSString *const kIKInitialCenter = @"kIKInitialCenter";
SF_EXPORT NSString *const kIKInitialZoomFactor = @"kIKInitialZoomFactor";
SF_EXPORT NSString *const kIKKeepZoomToFitSticky = @"kIKKeepZoomToFitSticky";
SF_EXPORT NSString *const kIKZoomToFitOnStart = @"kIKZoomToFitOnStart";
SF_EXPORT NSString *const kC3DIOSceneSourceTriggerOptionsForRealtimeViewer = @"kC3DIOSceneSourceTriggerOptionsForRealtimeViewer";
/* Finch's IKSaveOptions slider uses 0.8 when the image has no compression quality. */
SF_EXPORT const double IKSaveOptionsDefaultCompressionQuality = 0.8;

static NSString *const kQFilterName = @"Name";
static NSString *const kQFilterType = @"FilterType";
static NSString *const kQFilterData = @"FilterData";

typedef void (*SFColorFilterFn)(CGContextRef c, const float *matrix, const uint8_t *tables, bool linear);
static SFColorFilterFn sf_color_filter(void) {
    static SFColorFilterFn fn;
    static int looked;
    if (!looked) {
        looked = 1;
        fn = (SFColorFilterFn)dlsym(RTLD_DEFAULT, "CGContextSetFinchColorFilter");
    }
    return fn;
}

/* QuartzFilter.m effect_filter: luminance, threshold, tint, gain and lift. */
static BOOL effect_filter(NSDictionary *effect, float matrix[20], BOOL *useMatrix, uint8_t tables[1024], BOOL *useTables) {
    *useMatrix = *useTables = NO;
    if (![effect isKindOfClass:[NSDictionary class]])
        return NO;
    BOOL gray = [effect[@"Luminance"] boolValue];
    NSNumber *threshold = effect[@"Threshold"];
    NSArray *tint = effect[@"Tint"];
    double gain = effect[@"Gain"] ? [effect[@"Gain"] doubleValue] : 1;
    double lift = [effect[@"Lift"] doubleValue];
    if (gray) {
        static const float w[3] = {0.2126f, 0.7152f, 0.0722f};
        float m[20] = {0};
        for (int row = 0; row < 3; row++)
            for (int col = 0; col < 3; col++)
                m[row * 5 + col] = w[col];
        m[18] = 1;
        memcpy(matrix, m, sizeof m);
        *useMatrix = YES;
    }
    double gains[3] = {1, 1, 1};
    if ([tint isKindOfClass:[NSArray class]] && tint.count >= 3)
        for (int i = 0; i < 3; i++)
            gains[i] = [tint[i] doubleValue];
    BOOL anyTable = threshold || gain != 1 || lift != 0 || gains[0] != 1 || gains[1] != 1 || gains[2] != 1;
    if (!anyTable)
        return *useMatrix;
    for (int i = 0; i < 256; i++)
        tables[i] = (uint8_t)i;
    for (int ch = 0; ch < 3; ch++)
        for (int i = 0; i < 256; i++) {
            double v = i / 255.0;
            if (threshold)
                v = v >= [threshold doubleValue] ? 1 : 0;
            v *= gains[ch] * gain;
            v = v + (1 - v) * lift;
            v = fmin(1, fmax(0, v));
            tables[256 * (ch + 1) + i] = (uint8_t)lround(v * 255);
        }
    *useTables = YES;
    return YES;
}

@interface QuartzFilter : NSObject
@end

@implementation QuartzFilter {
    NSDictionary *_properties;
    NSURL *_url;
    id _owner;
}
+ (QuartzFilter *)quartzFilterWithURL:(NSURL *)aURL {
    NSDictionary *p = aURL ? [NSDictionary dictionaryWithContentsOfURL:aURL] : nil;
    if (![p isKindOfClass:[NSDictionary class]])
        return nil;
    QuartzFilter *f = [[[self alloc] _initWithProperties:p] autorelease];
    f->_url = [aURL copy];
    return f;
}
+ (QuartzFilter *)quartzFilterWithProperties:(NSDictionary *)properties {
    if (![properties isKindOfClass:[NSDictionary class]])
        return nil;
    return [[[self alloc] _initWithProperties:properties] autorelease];
}
+ (QuartzFilter *)quartzFilterWithOutputIntents:(NSArray *)outputIntents {
    if (![outputIntents isKindOfClass:[NSArray class]])
        return nil;
    return [self quartzFilterWithProperties:@{kQFilterType : @1, kQFilterData : @{@"OutputIntents" : outputIntents}}];
}
- (instancetype)_initWithProperties:(NSDictionary *)properties {
    if ((self = [super init]))
        _properties = [properties copy];
    return self;
}
- (void)dealloc {
    [_properties release];
    [_url release];
    [super dealloc];
}
- (NSDictionary *)properties { return _properties; }
- (NSURL *)url { return _url; }
- (void)setURL:(NSURL *)url {
    NSURL *old = _url;
    _url = [url copy];
    [old release];
}
- (void)setOwner:(id)owner { _owner = owner; }
- (NSString *)localizedName {
    NSString *name = _properties[kQFilterName];
    if (![name isKindOfClass:[NSString class]])
        name = [[[_url path] lastPathComponent] stringByDeletingPathExtension];
    NSBundle *b = [NSBundle bundleForClass:[QuartzFilter class]];
    return name ? [b localizedStringForKey:name value:name table:@"Filters"] : nil;
}
- (NSDictionary *)contextDictionary { return _properties[kQFilterData]; }
- (BOOL)applyToContext:(CGContextRef)context {
    if (!context)
        return NO;
    float matrix[20];
    uint8_t tables[1024];
    BOOL useMatrix, useTables;
    NSDictionary *data = _properties[kQFilterData];
    if ([data isKindOfClass:[NSDictionary class]] &&
        effect_filter(data[@"FinchColorEffect"], matrix, &useMatrix, tables, &useTables)) {
        SFColorFilterFn fn = sf_color_filter();
        if (fn)
            fn(context, useMatrix ? matrix : NULL, useTables ? tables : NULL, true);
    }
    return YES;
}
- (void)removeFromContext:(CGContextRef)context {
    SFColorFilterFn fn = sf_color_filter();
    if (context && fn)
        fn(context, NULL, NULL, false);
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> %@", [self class], self, [self localizedName]];
}
@end

SF_EXPORT QuartzFilter *QuartzFilterCreateWithOutputIntents(NSArray *outputIntents) {
    return [[QuartzFilter quartzFilterWithOutputIntents:outputIntents] retain];
}

#pragma mark - IKSaveOptions (IKSaveOptions.m)

static BOOL sf_lossy(NSString *type) {
    return [type isEqual:@"public.jpeg"] || [type isEqual:@"public.heic"] || [type isEqual:@"org.webmproject.webp"];
}
static NSArray *sf_offered_types(void) {
    return @[@"public.jpeg", @"public.png", @"public.tiff", @"public.heic", @"com.compuserve.gif", @"com.microsoft.bmp"];
}

@interface NSPopUpButton : NSView
- (instancetype)initWithFrame:(NSRect)frame pullsDown:(BOOL)flag;
- (void)addItemWithTitle:(NSString *)title;
- (id)lastItem;
- (void)selectItemAtIndex:(NSInteger)index;
- (id)selectedItem;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
@end
@interface NSMenuItem : NSObject
@end
@interface NSMenuItem (SFRep)
- (void)setRepresentedObject:(id)object;
- (id)representedObject;
@end
@interface NSSlider : NSView
+ (NSSlider *)sliderWithValue:(double)value minValue:(double)min maxValue:(double)max target:(id)target action:(SEL)action;
- (void)setFrame:(NSRect)frame;
- (double)doubleValue;
- (void)setHidden:(BOOL)hidden;
@end
@interface NSTextField : NSView
+ (NSTextField *)labelWithString:(NSString *)string;
- (void)setFrame:(NSRect)frame;
- (void)setAlignment:(NSInteger)alignment;
- (void)setHidden:(BOOL)hidden;
@end
@interface NSSavePanel : NSObject
- (void)setAccessoryView:(NSView *)view;
@end

@interface IKSaveOptions : NSObject
@property (retain) NSPopUpButton *formatPopup;
@property (retain) NSSlider *qualitySlider;
@property (retain) NSTextField *qualityLabel;
@property (assign) NSSavePanel *savePanel;
@end

@implementation IKSaveOptions {
    NSDictionary *_properties;
    NSString *_type;
    id _delegate;
    NSPopUpButton *_formatPopup;
    NSSlider *_qualitySlider;
    NSTextField *_qualityLabel;
    NSSavePanel *_savePanel;
}
- (instancetype)initWithImageProperties:(NSDictionary *)imageProperties imageUTType:(NSString *)imageUTType {
    if ((self = [super init])) {
        _properties = [imageProperties copy];
        _type = [imageUTType copy];
    }
    return self;
}
- (void)dealloc {
    [_properties release];
    [_type release];
    [_formatPopup release];
    [_qualitySlider release];
    [_qualityLabel release];
    [super dealloc];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSDictionary *)imageProperties { return _properties; }
- (NSString *)imageUTType { return _type; }
- (NSPopUpButton *)formatPopup { return _formatPopup; }
- (void)setFormatPopup:(NSPopUpButton *)popup {
    NSPopUpButton *old = _formatPopup;
    _formatPopup = [popup retain];
    [old release];
}
- (NSSlider *)qualitySlider { return _qualitySlider; }
- (void)setQualitySlider:(NSSlider *)slider {
    NSSlider *old = _qualitySlider;
    _qualitySlider = [slider retain];
    [old release];
}
- (NSTextField *)qualityLabel { return _qualityLabel; }
- (void)setQualityLabel:(NSTextField *)label {
    NSTextField *old = _qualityLabel;
    _qualityLabel = [label retain];
    [old release];
}
- (NSSavePanel *)savePanel { return _savePanel; }
- (void)setSavePanel:(NSSavePanel *)panel { _savePanel = panel; }
- (NSDictionary *)userSelection {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (_type)
        d[@"documentType"] = _type;
    if (_qualitySlider && sf_lossy(_type)) {
        NSMutableDictionary *p = [NSMutableDictionary dictionaryWithDictionary:_properties ?: @{}];
        p[@"kCGImageDestinationLossyCompressionQuality"] = @(_qualitySlider.doubleValue);
        d[@"imageProperties"] = p;
    }
    return d;
}
- (void)_updateQuality {
    BOOL show = sf_lossy(_type);
    _qualitySlider.hidden = !show;
    _qualityLabel.hidden = !show;
}
- (void)_formatChanged:(NSPopUpButton *)sender {
    NSString *t = [[sender selectedItem] representedObject];
    if (![t isKindOfClass:[NSString class]])
        return;
    [_type release];
    _type = [t copy];
    [self _updateQuality];
}
- (NSView *)_optionsView {
    NSView *v = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 362, 64)] autorelease];
    NSTextField *formatLabel = [NSTextField labelWithString:@"Format:"];
    formatLabel.frame = NSMakeRect(8, 36, 100, 20);
    [formatLabel setAlignment:1];
    [v addSubview:formatLabel];
    NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(114, 32, 200, 26) pullsDown:NO] autorelease];
    NSArray *types = sf_offered_types();
    for (NSString *t in types) {
        [popup addItemWithTitle:t];
        [[popup lastItem] setRepresentedObject:t];
    }
    if (_type && [types containsObject:_type])
        [popup selectItemAtIndex:(NSInteger)[types indexOfObject:_type]];
    [popup setTarget:self];
    [popup setAction:@selector(_formatChanged:)];
    [v addSubview:popup];
    self.formatPopup = popup;
    NSTextField *qualityLabel = [NSTextField labelWithString:@"Quality:"];
    qualityLabel.frame = NSMakeRect(8, 8, 100, 20);
    [v addSubview:qualityLabel];
    self.qualityLabel = qualityLabel;
    NSNumber *q = _properties[@"kCGImageDestinationLossyCompressionQuality"];
    double quality = q ? q.doubleValue : IKSaveOptionsDefaultCompressionQuality;
    NSSlider *slider = [NSSlider sliderWithValue:quality minValue:0 maxValue:1 target:nil action:NULL];
    slider.frame = NSMakeRect(114, 8, 200, 20);
    [v addSubview:slider];
    self.qualitySlider = slider;
    [self _updateQuality];
    return v;
}
- (void)addSaveOptionsToView:(NSView *)view {
    NSView *options = [self _optionsView];
    NSRect b = view.bounds;
    options.frame = NSMakeRect(4, NSMaxY(b) - options.frame.size.height - 4, options.frame.size.width, options.frame.size.height);
    [view addSubview:options];
}
- (void)addSaveOptionsAccessoryViewToSavePanel:(NSSavePanel *)savePanel {
    self.savePanel = savePanel;
    [savePanel setAccessoryView:[self _optionsView]];
}
@end

#pragma mark - IKImageView2

@interface IKDocumentView : NSView
@property (retain) NSImage *image;
@property double zoom;
@end
@implementation IKDocumentView {
    NSImage *_image;
    double _zoom;
}
- (void)dealloc {
    [_image release];
    [super dealloc];
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image {
    NSImage *old = _image;
    _image = [image retain];
    [old release];
    [self setNeedsDisplay:YES];
}
- (double)zoom { return _zoom; }
- (void)setZoom:(double)zoom {
    _zoom = zoom > 0 ? zoom : 1;
    [self setNeedsDisplay:YES];
}
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    extern void NSRectFill(NSRect);
    NSRect b = [self bounds];
    id bgCol = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        (id)objc_getClass("NSColor"), @selector(colorWithCalibratedRed:green:blue:alpha:), 0.863, 0.863, 0.878, 1.0);
    [bgCol setFill];
    NSRectFill(b);
    if (!_image)
        return;
    NSSize s = [_image size];
    if (s.width <= 0 || s.height <= 0)
        return;
    /* Use visible clip bounds (superview bounds) if smaller than self bounds so image never clips right/bottom */
    NSRect vis = b;
    id sv = [self respondsToSelector:@selector(superview)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(superview)) : nil;
    if (sv && [sv respondsToSelector:@selector(bounds)]) {
        NSRect svb = ((NSRect (*)(id, SEL))objc_msgSend)(sv, @selector(bounds));
        if (svb.size.width > 40.0 && svb.size.width < vis.size.width) vis.size.width = svb.size.width;
        if (svb.size.height > 40.0 && svb.size.height < vis.size.height) vis.size.height = svb.size.height;
    }
    CGFloat fitX = (vis.size.width > 40.0) ? (vis.size.width - 36.0) / s.width : 1.0;
    CGFloat fitY = (vis.size.height > 40.0) ? (vis.size.height - 36.0) / s.height : 1.0;
    CGFloat effZoom = fitX < fitY ? fitX : fitY;
    if (effZoom > 1.25) effZoom = 1.25;
    if (effZoom < 0.1) effZoom = 0.1;
    CGFloat w = floor(s.width * effZoom);
    CGFloat h = floor(s.height * effZoom);
    CGFloat x = floor((vis.size.width - w) * 0.5);
    CGFloat y = floor((vis.size.height - h) * 0.5);
    /* Subtle macOS Preview image drop shadow + crisp 1px border */
    id shCol = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        (id)objc_getClass("NSColor"), @selector(colorWithCalibratedRed:green:blue:alpha:), 0.0, 0.0, 0.0, 0.12);
    [shCol setFill];
    NSRectFill(NSMakeRect(x - 1.0, y + 2.0, w + 2.0, h + 2.0));
    id brdCol = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        (id)objc_getClass("NSColor"), @selector(colorWithCalibratedRed:green:blue:alpha:), 0.0, 0.0, 0.0, 0.22);
    [brdCol setFill];
    NSRectFill(NSMakeRect(x - 1.0, y - 1.0, w + 2.0, h + 2.0));
    id whCol = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        (id)objc_getClass("NSColor"), @selector(colorWithCalibratedRed:green:blue:alpha:), 1.0, 1.0, 1.0, 1.0);
    [whCol setFill];
    NSRectFill(NSMakeRect(x, y, w, h));
    [_image drawInRect:NSMakeRect(x, y, w, h)];
}
@end

@interface IKImageView2 : NSView {
@public
    NSScrollView *_scrollView;
}
@end

@implementation IKImageView2 {
    NSImage *_image;
    NSDictionary *_properties;
    double _zoomFactor;
    NSPoint _center;
    BOOL _zoomToFit;
    BOOL _keepSticky;
    IKDocumentView *_document;
    id _visionKitDelegate;
    NSUInteger _visionKitInteractionTypes;
    NSString *_currentToolMode;
    NSColor *_backgroundColor;
    double _rotationAngle;
    BOOL _hdrUpdatesPaused;
    NSInteger _hdrFocusMode;
    id _displayState;
    NSMutableDictionary *_overlays;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _zoomFactor = 1;
        _scrollView = [[NSScrollView alloc] initWithFrame:frame];
        [_scrollView setAutoresizingMask:18]; /* width + height sizable */
        [_scrollView setHasVerticalScroller:YES];
        [_scrollView setHasHorizontalScroller:YES];
        _document = [[IKDocumentView alloc] initWithFrame:frame];
        _document.zoom = 1;
        [_scrollView setDocumentView:_document];
        [self addSubview:_scrollView];
        _overlays = [[NSMutableDictionary alloc] init];
    }
    return self;
}
- (void)dealloc {
    [_image release];
    [_properties release];
    [_scrollView release];
    [_document release];
    [_currentToolMode release];
    [_backgroundColor release];
    [_displayState release];
    [_overlays release];
    [super dealloc];
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [_scrollView setFrame:[self bounds]];
    if (_zoomToFit || _keepSticky)
        [self zoomImageToFit:nil];
    else
        [self _applyZoom:_zoomFactor center:_center];
}
- (NSImage *)image { return _image; }
- (NSSize)imageSize { return _image ? [_image size] : NSZeroSize; }
- (double)zoomFactor { return _zoomFactor; }
- (double)getZoomFactor { return _zoomFactor; }
- (double)getMinZoomFactor { return 0.1; }
- (double)getMaxZoomFactor { return 16.0; }
- (double)minZoomFactor { return 0.1; }
- (void)setMinZoomFactor:(double)z { (void)z; }
- (double)maxZoomFactor { return 16.0; }
- (void)setMaxZoomFactor:(double)z { (void)z; }
- (double)minScaleFactor { return 0.1; }
- (void)setMinScaleFactor:(double)z { (void)z; }
- (double)maxScaleFactor { return 16.0; }
- (void)setMaxScaleFactor:(double)z { (void)z; }
- (double)scaleFactor { return _zoomFactor; }
- (void)setScaleFactor:(double)s { [self _applyZoom:s center:_center]; }
- (double)zoomToFitScaleFactor {
    NSSize view = [_scrollView bounds].size;
    NSSize image = _image ? [_image size] : NSMakeSize(640, 360);
    if (image.width <= 0 || image.height <= 0 || view.width <= 32 || view.height <= 32) return 1.0;
    double zx = (view.width - 36.0) / image.width;
    double zy = (view.height - 36.0) / image.height;
    double z = zx < zy ? zx : zy;
    return z > 0.05 ? z : 1.0;
}
- (double)actualSizeScaleFactor { return 1.0; }
- (void)setZoomFactor:(double)z { [self _applyZoom:z center:_center]; }
- (void)setZoomFactor:(double)z centeredAtImagePoint:(NSPoint)pt animate:(BOOL)anim stickyFit:(BOOL)sticky {
    (void)anim;
    _keepSticky = sticky;
    [self _applyZoom:z center:pt];
}
- (NSPoint)centerPoint { return _center; }
- (BOOL)zoomToFitOnStart { return _zoomToFit; }
- (BOOL)keepZoomToFitSticky { return _keepSticky; }
- (BOOL)autoZooms { return _zoomToFit; }
- (void)setAutoZooms:(BOOL)v { _zoomToFit = v; if (v) [self zoomImageToFit:nil]; }
- (BOOL)stickyZoomToFit { return _keepSticky; }
- (void)setStickyZoomToFit:(BOOL)v { _keepSticky = v; }
- (NSScrollView *)scrollView { return _scrollView; }
- (NSScrollView *)documentScrollView { return _scrollView; }
- (id)visionKitDelegate { return _visionKitDelegate; }
- (void)setVisionKitDelegate:(id)d { _visionKitDelegate = d; }
- (NSUInteger)visionKitInteractionTypes { return _visionKitInteractionTypes; }
- (void)setVisionKitInteractionTypes:(NSUInteger)t { _visionKitInteractionTypes = t; }
- (BOOL)hasActiveTextSelection { return NO; }
- (BOOL)isAnimatingTransform { return NO; }
- (BOOL)isZooming { return NO; }
- (BOOL)isRotating { return NO; }
- (BOOL)isDragging { return NO; }
- (BOOL)hasImage { return _image != nil; }
- (BOOL)canZoomIn { return YES; }
- (BOOL)canZoomOut { return YES; }
- (BOOL)canZoomToFit { return YES; }
- (BOOL)canZoomToActualSize { return YES; }
- (BOOL)isZoomedToFit { return _zoomToFit; }
- (BOOL)isZoomedToActualSize { return fabs(_zoomFactor - 1.0) < 0.01; }
- (BOOL)hasSelection { return NO; }
- (NSSize)contentSize { return _image ? [_image size] : NSZeroSize; }
- (NSRect)visibleImageRect { return [self imageRectInView]; }
- (BOOL)HDRUpdatesPaused { return _hdrUpdatesPaused; }
- (void)setHDRUpdatesPaused:(BOOL)v { _hdrUpdatesPaused = v; }
- (NSInteger)hdrFocusMode { return _hdrFocusMode; }
- (void)setHdrFocusMode:(NSInteger)m { _hdrFocusMode = m; }
- (void)updateHDRFocusWithAnimation:(BOOL)anim { (void)anim; }
- (void)updateHDRFocus { }
- (void)beginImageSubjectAnalysisIfNecessary { }
- (void)cancelImageSubjectAnalysis { }
- (BOOL)hasResultsForAnalysisTypes:(NSUInteger)types { (void)types; return NO; }
- (BOOL)isImageSubjectHighlighted { return NO; }
- (BOOL)isSubjectHighlightAvailable { return NO; }
- (BOOL)isSubjectHighlightActive { return NO; }
- (void)setSubjectHighlightActive:(BOOL)v { (void)v; }
- (BOOL)textExistsAtPoint:(NSPoint)p { (void)p; return NO; }
- (BOOL)visualSearchExistsAtPoint:(NSPoint)p { (void)p; return NO; }
- (BOOL)hostAppIsHDRSuppressed { return NO; }
- (void)setMaxHDRGain:(double)g { (void)g; }
- (id)visualSearchInfoButton { return nil; }
- (id)liveTextInteraction { return nil; }
- (id)imageAnalyzer { return nil; }
- (void)setImageAnalyzer:(id)a { (void)a; }
- (id)imageAnalysis { return nil; }
- (void)setImageAnalysis:(id)a { (void)a; }
- (id)displayState { return _displayState; }
- (void)setDisplayState:(id)s { id o = _displayState; _displayState = [s retain]; [o release]; }
- (NSString *)currentToolMode { return _currentToolMode; }
- (void)setCurrentToolMode:(NSString *)m { NSString *o = _currentToolMode; _currentToolMode = [m copy]; [o release]; }
- (NSColor *)backgroundColor { return _backgroundColor; }
- (void)setBackgroundColor:(NSColor *)c { NSColor *o = _backgroundColor; _backgroundColor = [c retain]; [o release]; }
- (double)rotationAngle { return _rotationAngle; }
- (void)setRotationAngle:(double)a { _rotationAngle = a; }
- (void)ik_setRotationAngleCenteredInSafeArea:(double)a { _rotationAngle = a; }
- (void)ik_setRotationAngleWithAnimation:(double)a duration:(double)d { (void)d; _rotationAngle = a; }
- (void)flipImageHorizontal:(id)s { (void)s; }
- (void)flipImageVertical:(id)s { (void)s; }
- (void)setShowControls:(BOOL)v { (void)v; }
- (void)setAllowsMagnification:(BOOL)v { (void)v; }
- (void)setDoubleClickOpensImageEditPanel:(BOOL)v { (void)v; }
- (void)setSupportsDragAndDrop:(BOOL)v { (void)v; }
- (void)setEditable:(BOOL)v { (void)v; }
- (void)setAllowsCutCopyPaste:(BOOL)v { (void)v; }
- (void)setShowsCheckerboardBackground:(BOOL)v { (void)v; }
- (BOOL)showsCheckerboardBackground { return NO; }
- (void)setLoadsSynchronously:(BOOL)v { (void)v; }
- (BOOL)loadsSynchronously { return YES; }
- (void)setAllowsZoomToFit:(BOOL)v { (void)v; }
- (BOOL)allowsZoomToFit { return YES; }
- (void)setSupportsHDR:(BOOL)v { (void)v; }
- (BOOL)supportsHDR { return NO; }
- (void)setHasTransparency:(BOOL)v { (void)v; }
- (BOOL)hasTransparency { return NO; }
- (void)setSelectionRect:(NSRect)r { (void)r; }
- (NSRect)selectionRect { return NSZeroRect; }
- (void)zoomImageToSelection:(id)s { (void)s; }
- (void)scrollToPoint:(NSPoint)p { (void)p; }
- (void)scrollToRect:(NSRect)r { (void)r; }
- (void)centerImage { [self zoomImageToFit:nil]; }
- (id)imageViewLayer { return [self respondsToSelector:@selector(layer)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(layer)) : nil; }
- (NSView *)annotationsView { return _document; }
- (void)setAnnotationsView:(NSView *)v { (void)v; }
- (id)annotationsLayer { return [_document respondsToSelector:@selector(layer)] ? ((id (*)(id, SEL))objc_msgSend)(_document, @selector(layer)) : nil; }
- (void)setAnnotationsLayer:(id)l { (void)l; }
- (id)imageLayer { return [self annotationsLayer]; }
- (id)backgroundLayer { return [self imageViewLayer]; }
- (id)overlayLayer { return [self annotationsLayer]; }
- (void)setImageWithCGImage:(void *)cg imageProperties:(NSDictionary *)props { [self setImage:(id)cg imageProperties:props]; }
- (void)setImageSource:(void *)src imageAtIndex:(NSUInteger)idx displayProperties:(NSDictionary *)props {
    typedef void *(*fn_src_img_t)(void *, size_t, void *);
    static fn_src_img_t f_create = NULL;
    if (!f_create) f_create = (fn_src_img_t)dlsym(RTLD_DEFAULT, "CGImageSourceCreateImageAtIndex");
    void *cg = (src && f_create) ? f_create(src, (size_t)idx, NULL) : NULL;
    [self setImage:(id)cg imageProperties:props];
    if (cg) {
        typedef void (*fn_rel_t)(void *);
        static fn_rel_t f_rel = NULL;
        if (!f_rel) f_rel = (fn_rel_t)dlsym(RTLD_DEFAULT, "CGImageRelease");
        if (f_rel) f_rel(cg);
    }
}
- (void)setAutoresizes:(BOOL)v { (void)v; }
- (BOOL)autoresizes { return NO; }
- (void)setDelegate:(id)d { (void)d; }
- (id)delegate { return nil; }
- (void)setImageCorrection:(id)c { (void)c; }
- (id)imageCorrection { return nil; }
- (NSDictionary *)imageProperties { return _properties; }
- (void)setImageProperties:(NSDictionary *)p { NSDictionary *o = _properties; _properties = [p copy]; [o release]; }
- (void)setRotationAngle:(double)a centerPoint:(NSPoint)pt { (void)pt; _rotationAngle = a; }
- (void)setZoomFactor:(double)z centerPoint:(NSPoint)pt { [self _applyZoom:z center:pt]; }
- (void)magnifyToFitRect:(NSRect)r { (void)r; [self zoomImageToFit:nil]; }
- (void)setMagnification:(double)m centeredAtPoint:(NSPoint)pt { [self _applyZoom:m center:pt]; }
- (void)setMagnificationFilter:(id)f { (void)f; }
- (BOOL)allowPanningInScrollView:(id)sv { (void)sv; return YES; }
- (void)didScrollInScrollView:(id)sv { (void)sv; }
- (void)didBeginScrollInScrollView:(id)sv { (void)sv; }
- (void)didEndScrollInScrollView:(id)sv { (void)sv; }
- (void)resetTextSelection {}
- (void)setAllowsLiveText:(BOOL)v { (void)v; }
- (BOOL)allowsLiveText { return NO; }
- (void)setHasShadow:(BOOL)v { (void)v; }
- (void)setBorderStyle:(NSInteger)s { (void)s; }
- (void)setHideScrollers:(BOOL)v { (void)v; }
- (void)setAnimates:(BOOL)v { (void)v; }
- (void)setHasHorizontalScroller:(BOOL)v { [_scrollView setHasHorizontalScroller:v]; }
- (void)setHasVerticalScroller:(BOOL)v { [_scrollView setHasVerticalScroller:v]; }
- (void)setAutohidesScrollers:(BOOL)v { (void)v; }
- (void)setImageWithURL:(NSURL *)url { [self setImageURL:url imageAtIndex:0 withDisplayProperties:nil]; }
- (void)setImage:(id)img imageProperties:(NSDictionary *)props displayProperties:(NSDictionary *)disp {
    [self setImage:img imageProperties:(disp ?: props)];
}
- (void)setCIImage:(id)ciImg imageProperties:(NSDictionary *)props displayProperties:(NSDictionary *)disp colorSpace:(void *)cs {
    (void)cs;
    void *cg = NULL;
    if (ciImg && [ciImg respondsToSelector:@selector(CGImage)]) {
        cg = ((void *(*)(id, SEL))objc_msgSend)(ciImg, @selector(CGImage));
    }
    if (!cg && ciImg) {
        Class ciCtxCls = objc_lookUpClass("CIContext");
        if (ciCtxCls && [ciCtxCls respondsToSelector:@selector(context)] && [ciImg respondsToSelector:@selector(extent)]) {
            id ctx = ((id (*)(id, SEL))objc_msgSend)((id)ciCtxCls, @selector(context));
            NSRect ext = ((NSRect (*)(id, SEL))objc_msgSend)(ciImg, @selector(extent));
            if (ctx && [ctx respondsToSelector:@selector(createCGImage:fromRect:)]) {
                cg = ((void *(*)(id, SEL, id, NSRect))objc_msgSend)(ctx, @selector(createCGImage:fromRect:), ciImg, ext);
            }
        }
    }
    [self setImage:(id)cg imageProperties:(disp ?: props)];
}
- (void)setOverlay:(id)o forType:(NSString *)t {
    if (!t) return;
    if (o) [_overlays setObject:o forKey:t]; else [_overlays removeObjectForKey:t];
}
- (id)overlayForType:(NSString *)t { return t ? [_overlays objectForKey:t] : nil; }
- (NSRect)imageRectInView {
    NSSize b = [_scrollView bounds].size;
    NSSize s = _image ? [_image size] : NSZeroSize;
    CGFloat w = floor(s.width * _zoomFactor), h = floor(s.height * _zoomFactor);
    CGFloat x = floor((b.width - w) * 0.5), y = floor((b.height - h) * 0.5);
    if (x < 16.0) x = 16.0;
    if (y < 16.0) y = 16.0;
    return NSMakeRect(x, y, w, h);
}
- (NSPoint)convertPointToImage:(NSPoint)p {
    NSRect ir = [self imageRectInView];
    double z = _zoomFactor > 0.001 ? _zoomFactor : 1.0;
    return NSMakePoint((p.x - ir.origin.x) / z, (p.y - ir.origin.y) / z);
}
- (NSPoint)convertPointFromImage:(NSPoint)p {
    NSRect ir = [self imageRectInView];
    return NSMakePoint(ir.origin.x + p.x * _zoomFactor, ir.origin.y + p.y * _zoomFactor);
}
- (NSRect)convertRectToImage:(NSRect)r {
    NSPoint o = [self convertPointToImage:r.origin];
    double z = _zoomFactor > 0.001 ? _zoomFactor : 1.0;
    return NSMakeRect(o.x, o.y, r.size.width / z, r.size.height / z);
}
- (NSRect)convertRectFromImage:(NSRect)r {
    NSPoint o = [self convertPointFromImage:r.origin];
    return NSMakeRect(o.x, o.y, r.size.width * _zoomFactor, r.size.height * _zoomFactor);
}
- (void)_applyZoom:(double)zoom center:(NSPoint)center {
    if (zoom > 0)
        _zoomFactor = zoom;
    _center = center;
    _document.zoom = _zoomFactor;
    NSSize vb = [_scrollView bounds].size;
    if (vb.width < 100.0 || vb.height < 100.0) {
        vb = [self bounds].size;
    }
    if (vb.width < 100.0) vb.width = 580.0;
    if (vb.height < 100.0) vb.height = 340.0;
    [_document setFrame:NSMakeRect(0, 0, vb.width, vb.height)];
    [_document setNeedsDisplay:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:kIKGeometryChanged object:self];
}
- (void)zoomImageToActualSize:(id)sender {
    (void)sender;
    _zoomToFit = NO;
    [self _applyZoom:1.0 center:_center];
}
- (void)zoomIn:(id)sender { (void)sender; [self _applyZoom:_zoomFactor * 1.25 center:_center]; }
- (void)zoomOut:(id)sender { (void)sender; [self _applyZoom:_zoomFactor * 0.8 center:_center]; }
- (void)zoomImageToRect:(NSRect)r { (void)r; [self zoomImageToFit:nil]; }
- (void)zoomImageToFit:(id)sender {
    (void)sender;
    NSSize view = [_scrollView bounds].size;
    NSSize image = _image ? [_image size] : NSMakeSize(1, 1);
    if (image.width <= 0 || image.height <= 0 || view.width <= 32 || view.height <= 32)
        return;
    double zx = (view.width - 36.0) / image.width;
    double zy = (view.height - 36.0) / image.height;
    double zoom = zx < zy ? zx : zy;
    if (zoom > 2.0) zoom = 2.0;
    NSPoint center = NSMakePoint(image.width / 2, image.height / 2);
    [self _applyZoom:zoom center:center];
}
- (void)setImageURL:(NSURL *)url imageAtIndex:(NSInteger)index withDisplayProperties:(NSDictionary *)properties {
    (void)index;
    id img = url ? [((id (*)(id, SEL, id))objc_msgSend)([NSImage alloc], @selector(initWithContentsOfURL:), url) autorelease] : nil;
    [self setImage:img imageProperties:properties];
}
- (void)setImage:(id)imgObj imageProperties:(NSDictionary *)properties {
    NSImage *nsImg = nil;
    if (imgObj && [imgObj isKindOfClass:[NSImage class]]) {
        nsImg = (NSImage *)imgObj;
    } else if (imgObj) {
        typedef size_t (*fn_cg_dim_t)(void *);
        static fn_cg_dim_t f_w, f_h;
        if (!f_w) {
            f_w = (fn_cg_dim_t)dlsym(RTLD_DEFAULT, "CGImageGetWidth");
            f_h = (fn_cg_dim_t)dlsym(RTLD_DEFAULT, "CGImageGetHeight");
        }
        size_t w = f_w ? f_w((void *)imgObj) : 0;
        size_t h = f_h ? f_h((void *)imgObj) : 0;
        if (w > 0 && h > 0) {
            nsImg = [((id (*)(id, SEL, void *, NSSize))objc_msgSend)([NSImage alloc], @selector(initWithCGImage:size:), (void *)imgObj, NSMakeSize((CGFloat)w, (CGFloat)h)) autorelease];
        }
    }
    NSImage *old = _image;
    _image = [nsImg retain];
    [old release];
    [_properties release];
    _properties = [properties copy];
    _document.image = _image;
    NSNumber *zoom = properties[kIKInitialZoomFactor];
    NSValue *center = properties[kIKInitialCenter];
    NSNumber *fit = properties[kIKZoomToFitOnStart];
    NSNumber *sticky = properties[kIKKeepZoomToFitSticky];
    _zoomToFit = fit ? fit.boolValue : YES;
    _keepSticky = sticky ? sticky.boolValue : _zoomToFit;
    NSPoint c = center ? center.pointValue : NSMakePoint(0, 0);
    if (_zoomToFit)
        [self zoomImageToFit:nil];
    else
        [self _applyZoom:zoom ? zoom.doubleValue : (_zoomFactor > 0 ? _zoomFactor : 1) center:c];
    [[NSNotificationCenter defaultCenter] postNotificationName:IKImageCompletedInitialLoadingNotification object:self];
}
- (void)setImage:(NSImage *)image {
    [self setImage:(id)image imageProperties:_properties];
}
@end

@interface IKImageEditPanel : NSPanel
@end
@implementation IKImageEditPanel {
    IKImageView2 *_imageView;
    IKSaveOptions *_saveOptions;
    NSImage *_image;
}
+ (IKImageEditPanel *)sharedPanel {
    static IKImageEditPanel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        panel = [[self alloc] initWithContentRect:NSMakeRect(0, 0, 720, 520)
                                        styleMask:(1 | 2 | 4 | 8)
                                          backing:2
                                            defer:NO];
    });
    return panel;
}
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)flag {
    if ((self = [super initWithContentRect:contentRect styleMask:style backing:backing defer:flag])) {
        _imageView = [[IKImageView2 alloc] initWithFrame:contentRect];
        [self setContentView:_imageView];
    }
    return self;
}
- (void)dealloc {
    [_imageView release];
    [_saveOptions release];
    [_image release];
    [super dealloc];
}
- (IKImageView2 *)imageView { return _imageView; }
- (IKSaveOptions *)saveOptions { return _saveOptions; }
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image {
    NSImage *old = _image;
    _image = [image retain];
    [old release];
    [_imageView setImage:_image imageProperties:nil];
}
- (void)setImage:(NSImage *)image imageProperties:(NSDictionary *)properties {
    NSImage *old = _image;
    _image = [image retain];
    [old release];
    [_imageView setImage:_image imageProperties:properties];
    [_saveOptions release];
    NSString *type = properties[@"kCGImagePropertyUTI"] ?: @"public.jpeg";
    _saveOptions = [[IKSaveOptions alloc] initWithImageProperties:properties imageUTType:type];
}
@end
