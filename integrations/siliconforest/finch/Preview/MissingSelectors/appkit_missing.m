#include <math.h>
/* Finch bodies for the AppKit symbols SwiftUI imports and the P44 image does not export.
   Sources: NSAccessibilityElement.m, NSAccessibilityConstants.m, NSSwitch.m, NSCell.m
   (classic bezel), NSMenuItem.m, NSWindow.m, AppKitConstants_Generated.m,
   UIFoundation NSTextEncapsulation.m, UIFTextGraphicsContext.m, NSShadow.m,
   NSConstants.m. */
#import "sf_min.h"

#define SF_EXPORT __attribute__((visibility("default")))

SF_EXPORT NSString *const NSAccessibilityIsAccessibilityElementAttribute = @"AXIsElement";
SF_EXPORT NSString *const NSAccessibilityAttributedUserInputLabelsAttribute = @"AXAttributedUserInputLabels";
SF_EXPORT NSString *const NSAccessibilityIdentifierAttribute = @"AXIdentifier";
SF_EXPORT NSString *const NSAccessibilityLayoutChangedNotification = @"AXLayoutChanged";
SF_EXPORT NSString *const NSAccessibilityUIElementsKey = @"AXUIElementsKey";
SF_EXPORT NSString *const NSAdaptiveImageGlyphAttributeName = @"CTAdaptiveImageProvider";
SF_EXPORT NSString *const NSFontFeatureSettingsAttribute = @"NSCTFontFeatureSettingsAttribute";
SF_EXPORT NSString *const NSTextEncapsulationAttributeName = @"NSTextEncapsulation";
SF_EXPORT NSString *const NSWindowWillBeginSheetNotification = @"NSWindowWillBeginSheetNotification";
SF_EXPORT NSString *const NSWindowDidEndSheetNotification = @"NSWindowDidEndSheetNotification";

static NSString *const SFPressAction = @"AXPress";
static NSString *const SFIncrementAction = @"AXIncrement";
static NSString *const SFDecrementAction = @"AXDecrement";
static NSString *const SFConfirmAction = @"AXConfirm";
static NSString *const SFCancelAction = @"AXCancel";
static NSString *const SFShowMenuAction = @"AXShowMenu";
static NSString *const SFPickAction = @"AXPick";
static NSString *const SFRaiseAction = @"AXRaise";
static NSString *const SFShowAlternateUIAction = @"AXShowAlternateUI";
static NSString *const SFShowDefaultUIAction = @"AXShowDefaultUI";
static NSString *const SFDeleteAction = @"AXDelete";
static NSString *const SFButtonRole = @"AXButton";
static NSString *const SFSwitchSubrole = @"AXSwitch";
static NSString *const SFPositionAttribute = @"AXPosition";
static NSString *const SFSizeAttribute = @"AXSize";
static NSString *const SFDescriptionAttribute = @"AXDescription";
static NSString *const SFChildrenAttribute = @"AXChildren";

enum {
    SFEventLeftMouseUp = 2,
    SFEventLeftMouseDragged = 6,
    SFMaskLeftMouseUp = 1u << 2,
    SFMaskLeftMouseDragged = 1u << 6
};

@interface NSWindow : NSObject
- (BOOL)makeFirstResponder:(id)responder;
- (id)nextEventMatchingMask:(NSUInteger)mask;
@end

@interface NSEvent : NSObject
- (NSUInteger)type;
- (NSPoint)locationInWindow;
- (NSString *)charactersIgnoringModifiers;
@end

/* Classic branch of FinchAccentColor / FinchDisabled / FinchDrawBezel (NSCell.m). */
static NSColor *sf_accent(void) {
    return [NSColor colorWithSRGBRed:0.16 green:0.47 blue:0.96 alpha:1];
}
static NSColor *sf_disabled(NSColor *color, BOOL enabled) {
    return enabled ? color : [color colorWithAlphaComponent:[color alphaComponent] * 0.45];
}
static void sf_draw_bezel(NSRect rect, CGFloat radius, NSColor *fill, NSColor *stroke) {
    NSRect r = NSInsetRect(rect, 0.5, 0.5);
    if (r.size.width <= 0 || r.size.height <= 0)
        return;
    radius = MIN(radius, MIN(r.size.width, r.size.height) / 2);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
    if (fill) {
        [fill setFill];
        [p fill];
    }
    if (stroke) {
        [stroke setStroke];
        [p setLineWidth:1];
        [p stroke];
    }
}

#pragma mark - NSMenuItem section headers (NSMenuItem.m)

static const void *sf_section_header_key = &sf_section_header_key;

@interface NSMenuItem : NSObject
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
@end

@implementation NSMenuItem (FinchSectionHeader)
+ (instancetype)sectionHeaderWithTitle:(NSString *)title {
    NSMenuItem *item = [[self alloc] initWithTitle:title ?: @"" action:NULL keyEquivalent:@""];
    objc_setAssociatedObject(item, sf_section_header_key, @YES, OBJC_ASSOCIATION_RETAIN);
    return [item autorelease];
}
- (BOOL)isSectionHeader {
    return objc_getAssociatedObject(self, sf_section_header_key) != nil;
}
- (void)setSectionHeader:(BOOL)flag {
    objc_setAssociatedObject(self, sf_section_header_key, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN);
}
@end

#pragma mark - NSSwitch (NSSwitch.m)

@interface NSSwitch : NSControl
@end
@implementation NSSwitch {
    NSInteger _state;
    BOOL _hasValue, _pressed;
    NSInteger _size;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        _state = [coder containsValueForKey:@"NSState"] ? [coder decodeIntegerForKey:@"NSState"]
                                                        : [[coder decodeObjectForKey:@"NSControlContents"] integerValue];
        _hasValue = [coder containsValueForKey:@"NSState"] || [coder containsValueForKey:@"NSControlContents"];
        _size = [coder decodeIntegerForKey:@"NSControlSize"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    if (_hasValue)
        [coder encodeInteger:_state forKey:@"NSState"];
    [coder encodeInteger:_size forKey:@"NSControlSize"];
}
- (NSInteger)state { return _state; }
- (void)setState:(NSInteger)value {
    _state = value;
    _hasValue = YES;
    [self setNeedsDisplay:YES];
}
- (id)objectValue { return _hasValue ? @(_state) : nil; }
- (void)setObjectValue:(id)value {
    NSInteger n = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    [self setState:n == -1 ? -1 : n != 0];
}
- (NSString *)stringValue { return _hasValue ? [@(_state) stringValue] : @""; }
- (void)setStringValue:(NSString *)s { [self setObjectValue:s]; }
- (NSInteger)integerValue { return _state; }
- (void)setIntegerValue:(NSInteger)n { [self setObjectValue:@(n)]; }
- (int)intValue { return (int)_state; }
- (void)setIntValue:(int)n { [self setObjectValue:@(n)]; }
- (double)doubleValue { return _state; }
- (void)setDoubleValue:(double)n { [self setObjectValue:@(n)]; }
- (float)floatValue { return _state; }
- (void)setFloatValue:(float)n { [self setObjectValue:@(n)]; }
- (NSInteger)controlSize { return _size; }
- (void)setControlSize:(NSInteger)s {
    _size = s;
    [self setNeedsDisplay:YES];
}
- (NSSize)intrinsicContentSize { return NSMakeSize(54, 24); }
- (BOOL)acceptsFirstResponder { return [self isEnabled] && ![self refusesFirstResponder]; }
- (BOOL)isFlipped { return YES; }
- (void)performClick:(id)sender {
    (void)sender;
    [self setState:_state ? 0 : 1];
    [self sendAction:[self action] to:[self target]];
}
- (void)mouseDown:(NSEvent *)event {
    (void)event;
    if (![self isEnabled])
        return;
    NSWindow *window = (NSWindow *)[self window];
    [window makeFirstResponder:self];
    _pressed = YES;
    [self setNeedsDisplay:YES];
    BOOL inside = YES;
    for (;;) {
        NSEvent *next = [window nextEventMatchingMask:SFMaskLeftMouseUp | SFMaskLeftMouseDragged];
        if (!next)
            break;
        NSPoint local = [self convertPoint:[next locationInWindow] fromView:nil];
        inside = NSPointInRect(local, [self bounds]);
        _pressed = inside;
        [self setNeedsDisplay:YES];
        if ([next type] == SFEventLeftMouseUp)
            break;
    }
    _pressed = NO;
    [self setNeedsDisplay:YES];
    if (inside)
        [self performClick:self];
}
- (void)keyDown:(NSEvent *)event {
    if (![self isEnabled])
        return;
    NSString *s = [event charactersIgnoringModifiers];
    if ([s isEqual:@" "] || [s isEqual:@"\r"])
        [self performClick:self];
    else
        [super keyDown:event];
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSRect bounds = [self bounds];
    CGFloat width = MIN(38, bounds.size.width), height = MIN(22, bounds.size.height);
    NSRect track = NSMakeRect(NSMidX(bounds) - width / 2, NSMidY(bounds) - height / 2, width, height);
    NSColor *fill = _state ? sf_accent() : [NSColor colorWithWhite:_pressed ? 0.57 : 0.68 alpha:1];
    sf_draw_bezel(track, height / 2, sf_disabled(fill, [self isEnabled]), nil);
    CGFloat diameter = height - 4;
    NSRect knob = NSMakeRect(_state ? NSMaxX(track) - diameter - 2 : track.origin.x + 2, track.origin.y + 2, diameter, diameter);
    [[NSColor whiteColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return SFButtonRole; }
- (NSString *)accessibilitySubrole { return SFSwitchSubrole; }
- (id)accessibilityValue { return @(_state); }
- (void)setAccessibilityValue:(id)value {
    [self setObjectValue:value];
    [self sendAction:[self action] to:[self target]];
}
- (BOOL)accessibilityPerformPress {
    if (![self isEnabled])
        return NO;
    [self performClick:self];
    return YES;
}
@end

#pragma mark - Rotors (NSAccessibilityElement.m)

@interface NSAccessibilityCustomRotor : NSObject
@end
@implementation NSAccessibilityCustomRotor {
    NSInteger _type;
    NSString *_label;
    id _searchDelegate;
    id _loadDelegate;
}
- (instancetype)initWithLabel:(NSString *)label itemSearchDelegate:(id)delegate {
    if ((self = [super init])) {
        _type = 0; /* NSAccessibilityCustomRotorTypeCustom */
        _label = [label copy];
        _searchDelegate = delegate;
    }
    return self;
}
- (instancetype)initWithRotorType:(NSInteger)type itemSearchDelegate:(id)delegate {
    if ((self = [super init])) {
        _type = type;
        _label = @"";
        _searchDelegate = delegate;
    }
    return self;
}
- (void)dealloc {
    [_label release];
    [super dealloc];
}
- (NSInteger)type { return _type; }
- (void)setType:(NSInteger)type { _type = type; }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)label {
    NSString *old = _label;
    _label = [label copy];
    [old release];
}
- (id)itemSearchDelegate { return _searchDelegate; }
- (void)setItemSearchDelegate:(id)delegate { _searchDelegate = delegate; }
- (id)itemLoadingDelegate { return _loadDelegate; }
- (void)setItemLoadingDelegate:(id)delegate { _loadDelegate = delegate; }
@end

@interface NSAccessibilityCustomRotorItemResult : NSObject
@end
@implementation NSAccessibilityCustomRotorItemResult {
    id _target;
    id _token;
    NSString *_customLabel;
    NSRange _targetRange;
}
- (instancetype)initWithTargetElement:(id)targetElement {
    if ((self = [super init])) {
        _target = targetElement;
        _targetRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}
- (instancetype)initWithItemLoadingToken:(id)token customLabel:(NSString *)customLabel {
    if ((self = [super init])) {
        _token = [token retain];
        _customLabel = [customLabel copy];
        _targetRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}
- (void)dealloc {
    [_token release];
    [_customLabel release];
    [super dealloc];
}
- (id)targetElement { return _target; }
- (id)itemLoadingToken { return _token; }
- (NSString *)customLabel { return _customLabel; }
- (NSRange)targetRange { return _targetRange; }
- (void)setTargetRange:(NSRange)range { _targetRange = range; }
@end

SF_EXPORT
@interface NSAccessibilityRemoteUIElement : NSObject
+ (BOOL)isRemoteUIApp;
@end
@implementation NSAccessibilityRemoteUIElement
+ (BOOL)isRemoteUIApp { return NO; }
@end

#pragma mark - Entry points (NSAccessibilityElement.m)

SF_EXPORT void NSAccessibilityBeginInternalAccessors(void) {}
SF_EXPORT void NSAccessibilityEndInternalAccessors(void) {}

static SEL getter_for_attribute(id element, NSString *attribute) {
    if (![attribute hasPrefix:@"AX"])
        return NULL;
    NSString *base = [attribute substringFromIndex:2];
    if ([attribute isEqualToString:NSAccessibilityIsAccessibilityElementAttribute])
        base = @"Element";
    SEL sel = NSSelectorFromString([@"accessibility" stringByAppendingString:base]);
    if ([element respondsToSelector:sel])
        return sel;
    sel = NSSelectorFromString([@"isAccessibility" stringByAppendingString:base]);
    if ([element respondsToSelector:sel])
        return sel;
    return NULL;
}

static id value_from_getter(id element, NSString *attribute) {
    if ([attribute isEqualToString:SFPositionAttribute] && [element respondsToSelector:@selector(accessibilityFrame)]) {
        NSRect frame = ((NSRect (*)(id, SEL))objc_msgSend)(element, @selector(accessibilityFrame));
        return [NSValue valueWithPoint:frame.origin];
    }
    if ([attribute isEqualToString:SFSizeAttribute] && [element respondsToSelector:@selector(accessibilityFrame)]) {
        NSRect frame = ((NSRect (*)(id, SEL))objc_msgSend)(element, @selector(accessibilityFrame));
        return [NSValue valueWithSize:frame.size];
    }
    if ([attribute isEqualToString:SFDescriptionAttribute] && [element respondsToSelector:@selector(accessibilityLabel)])
        return [element accessibilityLabel];
    SEL getter = getter_for_attribute(element, attribute);
    if (!getter)
        return nil;
    NSMethodSignature *sig = [element methodSignatureForSelector:getter];
    if ([sig numberOfArguments] != 2)
        return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setSelector:getter];
    [inv invokeWithTarget:element];
    const char *t = [sig methodReturnType];
    if (t[0] == '@') {
        __unsafe_unretained id v = nil;
        [inv getReturnValue:&v];
        return v;
    }
    NSUInteger size = [sig methodReturnLength];
    char buf[size ? size : 1];
    memset(buf, 0, sizeof buf);
    [inv getReturnValue:buf];
    switch (t[0]) {
    case 'B':
    case 'c': return @(*(BOOL *)buf);
    case 'q': return @(*(long long *)buf);
    case 'Q': return @(*(unsigned long long *)buf);
    case 'd': return @(*(double *)buf);
    case 'f': return @(*(float *)buf);
    }
    return [NSValue valueWithBytes:buf objCType:t];
}

SF_EXPORT id NSAccessibilityEntryPointValueForAttribute(id element, NSString *attribute) {
    id v = value_from_getter(element, attribute);
    if (!v && [element respondsToSelector:@selector(accessibilityAttributeValue:)])
        return ((id (*)(id, SEL, id))objc_msgSend)(element, @selector(accessibilityAttributeValue:), attribute);
    return v;
}

static const struct {
    NSString *const *action;
    const char *selector;
} sf_actions[] = {
    {&SFPressAction, "accessibilityPerformPress"},
    {&SFIncrementAction, "accessibilityPerformIncrement"},
    {&SFDecrementAction, "accessibilityPerformDecrement"},
    {&SFConfirmAction, "accessibilityPerformConfirm"},
    {&SFCancelAction, "accessibilityPerformCancel"},
    {&SFShowMenuAction, "accessibilityPerformShowMenu"},
    {&SFPickAction, "accessibilityPerformPick"},
    {&SFRaiseAction, "accessibilityPerformRaise"},
    {&SFShowAlternateUIAction, "accessibilityPerformShowAlternateUI"},
    {&SFShowDefaultUIAction, "accessibilityPerformShowDefaultUI"},
    {&SFDeleteAction, "accessibilityPerformDelete"},
};

static BOOL implements(id element, SEL sel) {
    if (![element respondsToSelector:sel])
        return NO;
    return class_getMethodImplementation([element class], sel) != class_getMethodImplementation([NSObject class], sel);
}

SF_EXPORT NSArray *NSAccessibilityEntryPointActionNames(id element) {
    NSMutableArray *names = [NSMutableArray array];
    for (size_t i = 0; i < sizeof sf_actions / sizeof sf_actions[0]; i++)
        if (implements(element, sel_registerName(sf_actions[i].selector)))
            [names addObject:*sf_actions[i].action];
    if (![names count] && [element respondsToSelector:@selector(accessibilityActionNames)])
        return ((id (*)(id, SEL))objc_msgSend)(element, @selector(accessibilityActionNames));
    return [names count] ? names : nil;
}

SF_EXPORT NSString *NSAccessibilityEntryPointActionDescription(id element, NSString *action) {
    if ([element respondsToSelector:@selector(accessibilityActionDescription:)])
        return ((id (*)(id, SEL, id))objc_msgSend)(element, @selector(accessibilityActionDescription:), action);
    return NSAccessibilityActionDescription(action);
}

SF_EXPORT BOOL NSAccessibilityEntryPointPerformAction(id element, NSString *action) {
    for (size_t i = 0; i < sizeof sf_actions / sizeof sf_actions[0]; i++) {
        SEL sel = sel_registerName(sf_actions[i].selector);
        if ([action isEqualToString:*sf_actions[i].action] && [element respondsToSelector:sel])
            return ((BOOL (*)(id, SEL))objc_msgSend)(element, sel);
    }
    if ([element respondsToSelector:@selector(accessibilityPerformAction:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(element, @selector(accessibilityPerformAction:), action);
        return YES;
    }
    return NO;
}

SF_EXPORT BOOL NSUserAccentHasHardwareColor(void) { return NO; }
SF_EXPORT NSString *NSUserAccentColorGetHardwareAccentColorName(void) { return nil; }

#pragma mark - Text classes (UIFoundation)

@interface NSTextEncapsulation : NSObject
@end
@implementation NSTextEncapsulation {
    NSUInteger _scale, _shape, _style, _platterSize;
    CGFloat _lineWeight, _minimumWidth;
    NSObject *_color;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (void)dealloc {
    [_color release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone {
    NSTextEncapsulation *c = [[NSTextEncapsulation allocWithZone:zone] init];
    c->_scale = _scale;
    c->_shape = _shape;
    c->_style = _style;
    c->_platterSize = _platterSize;
    c->_lineWeight = _lineWeight;
    c->_minimumWidth = _minimumWidth;
    c->_color = [_color retain];
    return c;
}
- (BOOL)isEqual:(id)o {
    if (![o isKindOfClass:[NSTextEncapsulation class]])
        return NO;
    NSTextEncapsulation *e = o;
    return e->_scale == _scale && e->_shape == _shape && e->_style == _style && e->_platterSize == _platterSize &&
           e->_lineWeight == _lineWeight && e->_minimumWidth == _minimumWidth &&
           (e->_color == _color || [e->_color isEqual:_color]);
}
- (NSUInteger)hash { return _scale ^ _shape << 2 ^ _style << 4 ^ _platterSize << 6; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:(NSInteger)_scale forKey:@"NSScale"];
    [coder encodeInteger:(NSInteger)_shape forKey:@"NSShape"];
    [coder encodeInteger:(NSInteger)_style forKey:@"NSStyle"];
    [coder encodeInteger:(NSInteger)_platterSize forKey:@"NSPlatterSize"];
    [coder encodeDouble:_lineWeight forKey:@"NSLineWeight"];
    [coder encodeDouble:_minimumWidth forKey:@"NSMinimumWidth"];
    if (_color)
        [coder encodeObject:_color forKey:@"NSColor"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _scale = (NSUInteger)[coder decodeIntegerForKey:@"NSScale"];
        _shape = (NSUInteger)[coder decodeIntegerForKey:@"NSShape"];
        _style = (NSUInteger)[coder decodeIntegerForKey:@"NSStyle"];
        _platterSize = (NSUInteger)[coder decodeIntegerForKey:@"NSPlatterSize"];
        _lineWeight = [coder decodeDoubleForKey:@"NSLineWeight"];
        _minimumWidth = [coder decodeDoubleForKey:@"NSMinimumWidth"];
        _color = [[coder decodeObjectOfClass:[NSObject class] forKey:@"NSColor"] retain];
    }
    return self;
}
- (NSUInteger)scale { return _scale; }
- (void)setScale:(NSUInteger)v { _scale = v; }
- (NSUInteger)shape { return _shape; }
- (void)setShape:(NSUInteger)v { _shape = v; }
- (NSUInteger)style { return _style; }
- (void)setStyle:(NSUInteger)v { _style = v; }
- (NSUInteger)platterSize { return _platterSize; }
- (void)setPlatterSize:(NSUInteger)v { _platterSize = v; }
- (CGFloat)lineWeight { return _lineWeight; }
- (void)setLineWeight:(CGFloat)v { _lineWeight = v; }
- (CGFloat)minimumWidth { return _minimumWidth; }
- (void)setMinimumWidth:(CGFloat)v { _minimumWidth = v; }
- (NSObject *)color { return _color; }
- (void)setColor:(NSObject *)color {
    NSObject *old = _color;
    _color = [color retain];
    [old release];
}
- (void)setPlatformColor:(NSObject *)color { [self setColor:color]; }
@end

static Class sf_provider_class;
static Class sf_context_class;
static __thread id sf_current_text_context;

@interface _NSStandardTextGraphicsContextProvider : NSObject
@end
@implementation _NSStandardTextGraphicsContextProvider
+ (id)graphicsContextForApplicationFrameworkContext:(id)context { return context; }
@end

@interface NSTextGraphicsContextProvider : NSObject
@end
@implementation NSTextGraphicsContextProvider
+ (Class)textGraphicsContextProviderClass {
    return sf_provider_class ?: [_NSStandardTextGraphicsContextProvider class];
}
+ (void)setTextGraphicsContextProviderClass:(Class)cls { sf_provider_class = cls; }
+ (BOOL)textGraphicsContextProviderClassRespondsToColorQuery {
    return [[self textGraphicsContextProviderClass] respondsToSelector:@selector(colorClassForApplicationFrameworkContext:)];
}
+ (Class)__defaultColorClass { return objc_getClass("NSColor"); }
+ (Class)textGraphicsContextClass { return sf_context_class; }
+ (void)setTextGraphicsContextClass:(Class)cls { sf_context_class = cls; }
+ (void)setCurrentTextGraphicsContext:(id)context duringBlock:(void (^)(void))block {
    id saved = sf_current_text_context;
    sf_current_text_context = context;
    @try {
        if (block)
            block();
    } @finally {
        sf_current_text_context = saved;
    }
}
@end

@interface NSAdaptiveImageGlyph : NSObject
@end
@implementation NSAdaptiveImageGlyph {
    NSData *_content;
    NSString *_identifier, *_description;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (id)contentType {
    Class t = objc_getClass("UTType");
    return t ? ((id (*)(id, SEL, id))objc_msgSend)(t, @selector(typeWithIdentifier:), @"public.heic") : nil;
}
- (instancetype)initWithImageContent:(NSData *)content {
    if (![content length]) {
        [self release];
        return nil;
    }
    if ((self = [super init])) {
        _content = [content copy];
        _identifier = [[[NSUUID UUID] UUIDString] copy];
        _description = @"";
    }
    return self;
}
- (instancetype)initWithCTAdaptiveImageGlyph:(id)glyph {
    NSData *d = [glyph respondsToSelector:@selector(imageContent)]
                    ? ((id (*)(id, SEL))objc_msgSend)(glyph, @selector(imageContent))
                    : nil;
    return [self initWithImageContent:d ?: [NSData data]];
}
- (void)dealloc {
    [_content release];
    [_identifier release];
    [_description release];
    [super dealloc];
}
- (NSData *)imageContent { return _content; }
- (NSString *)contentIdentifier { return _identifier; }
- (NSString *)contentDescription { return _description; }
- (void)setContentDescription:(NSString *)description {
    NSString *old = _description;
    _description = [description copy];
    [old release];
}
- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_content forKey:@"NSImageContent"]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithImageContent:[coder decodeObjectOfClass:[NSData class] forKey:@"NSImageContent"]];
}
@end

@interface NSStringDrawingContext : NSObject
@end
@implementation NSStringDrawingContext {
    CGFloat _minimumScaleFactor, _actualScaleFactor;
    NSRect _totalBounds;
    CGFloat _baselineOffset, _firstBaselineOffset, _scaledLineHeight, _scaledBaselineOffset;
    BOOL _wrapsForTruncationMode, _wantsBaselineOffset, _wantsScaledLineHeight, _wantsScaledBaselineOffset;
    BOOL _cachesLayout, _wantsNumberOfLineFragments, _hasTruncatedRanges;
    NSInteger _maximumNumberOfLines, _numberOfLineFragments;
    NSUInteger _activeRenderers;
    id _layout;
    id _linkTextAttributesProvider;
}
- (void)dealloc {
    [_layout release];
    [_linkTextAttributesProvider release];
    [super dealloc];
}
- (CGFloat)minimumScaleFactor { return _minimumScaleFactor; }
- (void)setMinimumScaleFactor:(CGFloat)f { _minimumScaleFactor = f; }
- (CGFloat)actualScaleFactor { return _actualScaleFactor; }
- (NSRect)totalBounds { return _totalBounds; }
- (CGFloat)baselineOffset { return _baselineOffset; }
- (void)setBaselineOffset:(CGFloat)v { _baselineOffset = v; }
- (CGFloat)firstBaselineOffset { return _firstBaselineOffset; }
- (void)setFirstBaselineOffset:(CGFloat)v { _firstBaselineOffset = v; }
- (CGFloat)scaledLineHeight { return _scaledLineHeight; }
- (void)setScaledLineHeight:(CGFloat)v { _scaledLineHeight = v; }
- (CGFloat)scaledBaselineOffset { return _scaledBaselineOffset; }
- (void)setScaledBaselineOffset:(CGFloat)v { _scaledBaselineOffset = v; }
- (BOOL)wrapsForTruncationMode { return _wrapsForTruncationMode; }
- (void)setWrapsForTruncationMode:(BOOL)v { _wrapsForTruncationMode = v; }
- (BOOL)wantsBaselineOffset { return _wantsBaselineOffset; }
- (void)setWantsBaselineOffset:(BOOL)v { _wantsBaselineOffset = v; }
- (BOOL)wantsScaledLineHeight { return _wantsScaledLineHeight; }
- (void)setWantsScaledLineHeight:(BOOL)v { _wantsScaledLineHeight = v; }
- (BOOL)wantsScaledBaselineOffset { return _wantsScaledBaselineOffset; }
- (void)setWantsScaledBaselineOffset:(BOOL)v { _wantsScaledBaselineOffset = v; }
- (BOOL)cachesLayout { return _cachesLayout; }
- (void)setCachesLayout:(BOOL)v { _cachesLayout = v; }
- (NSInteger)maximumNumberOfLines { return _maximumNumberOfLines; }
- (void)setMaximumNumberOfLines:(NSInteger)v { _maximumNumberOfLines = v; }
- (BOOL)wantsNumberOfLineFragments { return _wantsNumberOfLineFragments; }
- (void)setWantsNumberOfLineFragments:(BOOL)v { _wantsNumberOfLineFragments = v; }
- (NSUInteger)activeRenderers { return _activeRenderers; }
- (void)setActiveRenderers:(NSUInteger)v { _activeRenderers = v; }
- (id)layout { return _layout; }
- (void)setLayout:(id)v {
    [_layout autorelease];
    _layout = [v retain];
}
- (NSInteger)numberOfLineFragments { return _numberOfLineFragments; }
- (BOOL)hasTruncatedRanges { return _hasTruncatedRanges; }
- (id)linkTextAttributesProvider { return _linkTextAttributesProvider; }
- (void)setLinkTextAttributesProvider:(id)v {
    [_linkTextAttributesProvider autorelease];
    _linkTextAttributesProvider = [v copy];
}
@end

static char kSFClipsToBoundsKey;

@implementation NSView (SFClipsToBounds)
- (BOOL)clipsToBounds {
    NSNumber *n = objc_getAssociatedObject(self, &kSFClipsToBoundsKey);
    return n ? [n boolValue] : NO;
}
- (void)setClipsToBounds:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFClipsToBoundsKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([self respondsToSelector:@selector(layer)]) {
        id layer = ((id (*)(id, SEL))objc_msgSend)(self, @selector(layer));
        if (layer && [layer respondsToSelector:@selector(setMasksToBounds:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, @selector(setMasksToBounds:), flag);
        }
    }
}
@end

@interface NSColor (SFColorSpaceCompat)
+ (id)colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (id)colorWithCalibratedWhite:(CGFloat)w alpha:(CGFloat)a;
@end

@implementation NSColor (SFColorSpaceCompat)
+ (id)colorWithColorSpace:(id)space components:(const CGFloat *)components count:(NSInteger)numberOfComponents {
    (void)space;
    if (!components || numberOfComponents <= 0) {
        return [self colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
    }
    if (numberOfComponents == 1) {
        return [self colorWithCalibratedWhite:components[0] alpha:1];
    }
    if (numberOfComponents == 2) {
        return [self colorWithCalibratedWhite:components[0] alpha:components[1]];
    }
    CGFloat r = components[0];
    CGFloat g = components[1];
    CGFloat b = components[2];
    CGFloat a = numberOfComponents >= 4 ? components[3] : 1.0;
    return [self colorWithCalibratedRed:r green:g blue:b alpha:a];
}
@end

static char kSFLineBreakStrategyKey;
static char kSFAllowsTighteningKey;
static char kSFUsesDefaultHyphenationKey;

@interface NSParagraphStyle : NSObject
@end
@interface NSMutableParagraphStyle : NSParagraphStyle
@end

@implementation NSParagraphStyle (SFParagraphCompat)
- (NSUInteger)lineBreakStrategy {
    NSNumber *n = objc_getAssociatedObject(self, &kSFLineBreakStrategyKey);
    return n ? [n unsignedIntegerValue] : 0;
}
- (BOOL)allowsDefaultTighteningForTruncation {
    NSNumber *n = objc_getAssociatedObject(self, &kSFAllowsTighteningKey);
    return n ? [n boolValue] : NO;
}
- (BOOL)usesDefaultHyphenation {
    NSNumber *n = objc_getAssociatedObject(self, &kSFUsesDefaultHyphenationKey);
    return n ? [n boolValue] : NO;
}
@end

@implementation NSMutableParagraphStyle (SFParagraphCompat)
- (void)setLineBreakStrategy:(NSUInteger)strategy {
    objc_setAssociatedObject(self, &kSFLineBreakStrategyKey, @(strategy), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)setAllowsDefaultTighteningForTruncation:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFAllowsTighteningKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)setUsesDefaultHyphenation:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFUsesDefaultHyphenationKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* Adapted from Finch userland/AppKit/AppKitPrivate.m (SPDX-License-Identifier: MIT OR Apache-2.0) */
typedef struct {
    CGFloat top, left, bottom, right;
} SFEdgeInsets;

typedef struct {
    CGFloat firstTextBaseline;
    CGFloat lastTextBaseline;
} SFFinchBaselineOffset;

@interface _SFFinchGeometryObserver : NSObject {
@public
    __unsafe_unretained NSView *_view;
    void (^_block)(NSView *);
}
@end

static NSMutableArray *sf_geometry_observers;

@implementation _SFFinchGeometryObserver
- (void)dealloc {
    [sf_geometry_observers removeObject:self];
    [_block release];
    [super dealloc];
}
@end

@implementation NSView (SFFinchPrivateSPI)
- (id)_observerForChangesInGeometryInWindow:(void (^)(NSView *))block {
    if (!sf_geometry_observers)
        sf_geometry_observers = [[NSMutableArray alloc] init];
    _SFFinchGeometryObserver *o = [[[_SFFinchGeometryObserver alloc] init] autorelease];
    o->_view = self;
    o->_block = [block copy];
    [sf_geometry_observers addObject:o];
    return o;
}
- (void)_updateLayerGeometryFromView {}
- (void)_updateLayerShadowFromView {}
- (void)_updateLayerShadowColorFromView {}
- (SFEdgeInsets)computedSafeAreaInsets {
    SFEdgeInsets z = {0, 0, 0, 0};
    if ([self respondsToSelector:@selector(safeAreaInsets)]) {
        return ((SFEdgeInsets (*)(id, SEL))objc_msgSend)(self, @selector(safeAreaInsets));
    }
    return z;
}
- (id)_nextResponderForEvent:(id)event {
    (void)event;
    if ([self respondsToSelector:@selector(nextResponder)]) {
        return ((id (*)(id, SEL))objc_msgSend)(self, @selector(nextResponder));
    }
    return nil;
}
- (void)measureMin:(CGSize *)min max:(CGSize *)max ideal:(CGSize *)ideal stretchingPriority:(float)priority {
    NSSize intrinsic = {-1, -1};
    if ([self respondsToSelector:@selector(intrinsicContentSize)])
        intrinsic = ((NSSize (*)(id, SEL))objc_msgSend)(self, @selector(intrinsicContentSize));
    NSSize fit = {0, 0};
    if ([self respondsToSelector:@selector(fittingSize)])
        fit = ((NSSize (*)(id, SEL))objc_msgSend)(self, @selector(fittingSize));
    CGFloat lo[2], hi[2], idv[2];
    for (int axis = 0; axis < 2; axis++) {
        CGFloat v = axis ? intrinsic.height : intrinsic.width;
        if (v < 0) {
            CGFloat f = axis ? fit.height : fit.width;
            lo[axis] = f; idv[axis] = f; hi[axis] = 1e9;
        } else {
            idv[axis] = v;
            lo[axis] = v;
            hi[axis] = priority > 500 ? 1e9 : v;
        }
    }
    if (min) *min = CGSizeMake(lo[0], lo[1]);
    if (max) *max = CGSizeMake(hi[0], hi[1]);
    if (ideal) *ideal = CGSizeMake(idv[0], idv[1]);
}
- (void)measureMin:(CGSize *)min max:(CGSize *)max ideal:(CGSize *)ideal {
    [self measureMin:min max:max ideal:ideal stretchingPriority:250.0f];
}
static char sf_hosts_engine_key;
- (void)_setHostsLayoutEngine:(BOOL)flag {
    objc_setAssociatedObject(self, &sf_hosts_engine_key, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN);
}
- (BOOL)_hostsLayoutEngine {
    return objc_getAssociatedObject(self, &sf_hosts_engine_key) != nil;
}
@end

static char sf_override_values_key, sf_override_handlers_key;

@implementation NSObject (SFFinchAccessibilityOverrides)
- (BOOL)_accessibilitySetOverrideValue:(id)value forAttribute:(NSString *)attribute {
    NSMutableDictionary *d = objc_getAssociatedObject(self, &sf_override_values_key);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &sf_override_values_key, d, OBJC_ASSOCIATION_RETAIN);
    }
    if (value) [d setObject:value forKey:attribute];
    else [d removeObjectForKey:attribute];
    return YES;
}
- (BOOL)_accessibilitySetOverrideHandler:(id (^)(void))handler forAttribute:(NSString *)attribute {
    NSMutableDictionary *d = objc_getAssociatedObject(self, &sf_override_handlers_key);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &sf_override_handlers_key, d, OBJC_ASSOCIATION_RETAIN);
    }
    if (handler) [d setObject:[[handler copy] autorelease] forKey:attribute];
    else [d removeObjectForKey:attribute];
    return YES;
}
@end

@interface NSApplication : NSObject
@end
@implementation NSApplication (SFFinchPrivateSPI)
- (BOOL)_shouldLoadMainNibNamed:(NSString *)name { (void)name; return YES; }
- (BOOL)_shouldLoadMainStoryboardNamed:(NSString *)name { (void)name; return YES; }
@end

@interface NSAppearance : NSObject
@end
@implementation NSAppearance (SFFinchPrivateSPI)
- (id)appearanceByApplyingTintColor:(id)tintColor { (void)tintColor; return self; }
@end

@interface NSGestureRecognizer : NSObject
@end
@implementation NSGestureRecognizer (SFFinchPrivateSPI)
- (void)_updateForActiveEvents {}
- (BOOL)_hasUnmetFailureRequirements { return NO; }
@end

__attribute__((visibility("default")))
@interface _NSConstraintBasedLayoutHostingView : NSView {
    BOOL _hasAddedConstraints;
    NSView *_hosted;
}
- (instancetype)initWithHostedView:(NSView *)view;
- (NSView *)hostedView;
- (void)setHostedView:(NSView *)view;
@end

@implementation _NSConstraintBasedLayoutHostingView
+ (BOOL)requiresConstraintBasedLayout { return YES; }
- (instancetype)initWithHostedView:(NSView *)view {
    NSRect frame = view ? ((NSRect (*)(id, SEL))objc_msgSend)(view, @selector(frame)) : NSMakeRect(0, 0, 0, 0);
    if ((self = [super initWithFrame:frame])) {
        [self setHostedView:view];
    }
    return self;
}
- (void)dealloc {
    [_hosted release];
    [super dealloc];
}
- (NSView *)hostedView { return _hosted; }
- (void)setHostedView:(NSView *)view {
    if (view == _hosted) return;
    if (_hosted) ((void (*)(id, SEL))objc_msgSend)(_hosted, @selector(removeFromSuperview));
    [_hosted release];
    _hosted = [view retain];
    _hasAddedConstraints = NO;
    if (view) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(addSubview:), view);
    }
}
- (void)layout {
    if (_hosted) {
        NSRect b = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
        ((void (*)(id, SEL, NSRect))objc_msgSend)(_hosted, @selector(setFrame:), b);
    }
}
- (CGSize)_layoutSizeThatFits:(CGSize)fits fixedAxes:(unsigned long long)axes {
    if (!_hosted) return CGSizeMake(0, 0);
    NSSize intrinsic = {-1, -1};
    if ([_hosted respondsToSelector:@selector(intrinsicContentSize)])
        intrinsic = ((NSSize (*)(id, SEL))objc_msgSend)(_hosted, @selector(intrinsicContentSize));
    NSSize fit = {0, 0};
    if ([_hosted respondsToSelector:@selector(fittingSize)])
        fit = ((NSSize (*)(id, SEL))objc_msgSend)(_hosted, @selector(fittingSize));
    CGSize s = CGSizeMake(intrinsic.width >= 0 ? intrinsic.width : fit.width,
                          intrinsic.height >= 0 ? intrinsic.height : fit.height);
    if (axes & 1) s.width = fits.width;
    if (axes & 2) s.height = fits.height;
    return s;
}
- (CGSize)sizeThatFits:(CGSize)fits { return [self _layoutSizeThatFits:fits fixedAxes:0]; }
- (void)sizeToFit {
    CGSize s = [self sizeThatFits:CGSizeMake(0, 0)];
    ((void (*)(id, SEL, NSSize))objc_msgSend)(self, @selector(setFrameSize:), NSMakeSize(s.width, s.height));
}
- (BOOL)_layoutHeightDependsOnWidth { return NO; }
- (NSSize)intrinsicContentSize {
    if (_hosted && [_hosted respondsToSelector:@selector(intrinsicContentSize)])
        return ((NSSize (*)(id, SEL))objc_msgSend)(_hosted, @selector(intrinsicContentSize));
    return NSMakeSize(-1, -1);
}
- (void)_setFrameWithAlignmentRect:(CGRect)rect {
    ((void (*)(id, SEL, NSRect))objc_msgSend)(self, @selector(setFrame:), NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height));
}
- (SFFinchBaselineOffset)_baselineOffsetsAtSize:(CGSize)size {
    (void)size;
    SFFinchBaselineOffset b = {0, 0};
    return b;
}
- (void)_intrinsicContentSizeInvalidatedForChildView:(NSView *)view { (void)view; }
- (void)_layoutMetricsInvalidatedForHostedView {}
- (void)_informContainerThatSubviewsNeedUpdateConstraints {}
- (void)constraintsDidChangeInEngine:(id)engine { (void)engine; }
@end

static char kSFPreferredContentSizeKey;
@interface NSViewController : NSObject
@end
@implementation NSViewController (SFPreferredContentSize)
- (NSSize)preferredContentSize {
    NSValue *v = objc_getAssociatedObject(self, &kSFPreferredContentSizeKey);
    return v ? [v sizeValue] : NSMakeSize(0, 0);
}
- (void)setPreferredContentSize:(NSSize)size {
    objc_setAssociatedObject(self, &kSFPreferredContentSizeKey, [NSValue valueWithSize:size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char kSFFlippedKey;
@implementation NSView (SFFlippedCompat)
- (void)setFlipped:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFFlippedKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static void sf_pdfview_enable_annotation_kit(id self, SEL _cmd) {
    (void)self; (void)_cmd;
}

__attribute__((constructor))
static void sf_register_pdfview_annotation_kit(void) {
    Class pdfView = objc_getClass("PDFView");
    if (pdfView) {
        Class meta = object_getClass((id)pdfView);
        if (meta && !class_respondsToSelector(meta, sel_registerName("EnableAnnotationKit"))) {
            class_addMethod(meta, sel_registerName("EnableAnnotationKit"), (IMP)sf_pdfview_enable_annotation_kit, "v@:");
        }
    }
}

static char kSFAdditionalSafeAreaKey;
@implementation NSView (SFSafeAreaLayoutGuide)
- (id)safeAreaLayoutGuide { return self; }
- (id)layoutMarginsGuide { return self; }
- (NSRect)safeAreaRect {
    return ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
}
- (SFEdgeInsets)additionalSafeAreaInsets {
    NSValue *v = objc_getAssociatedObject(self, &kSFAdditionalSafeAreaKey);
    SFEdgeInsets z = {0, 0, 0, 0};
    if (v && [v respondsToSelector:@selector(getValue:)]) {
        [v getValue:&z];
    }
    return z;
}
- (void)setAdditionalSafeAreaInsets:(SFEdgeInsets)insets {
    NSValue *v = [NSValue valueWithBytes:&insets objCType:@encode(SFEdgeInsets)];
    objc_setAssociatedObject(self, &kSFAdditionalSafeAreaKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char kSFSplitViewKey, kSFSplitItemsKey, kSFSplitVCViewKey, kSFSplitVCTitleKey, kSFSplitVCMinSidebarKey;

@interface NSSplitViewController : NSViewController
@end

@implementation NSSplitViewController (SFPreviewSplitVC)
- (instancetype)initWithCoder:(NSCoder *)coder {
    (void)coder;
    if ((self = [super init])) {
        NSMutableArray *items = [NSMutableArray array];
        objc_setAssociatedObject(self, &kSFSplitItemsKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return self;
}
- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
    (void)nibName; (void)bundle;
    if ((self = [super init])) {
        NSMutableArray *items = [NSMutableArray array];
        objc_setAssociatedObject(self, &kSFSplitItemsKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return self;
}
- (void)_sfSyncSplitSubviews {
    id sv = [self splitView];
    if (!sv) return;
    if ([sv respondsToSelector:@selector(setVertical:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(sv, @selector(setVertical:), YES);
    }
    NSArray *items = [self splitViewItems];
    for (id item in items) {
        id vc = [item respondsToSelector:@selector(viewController)] ? ((id (*)(id, SEL))objc_msgSend)(item, @selector(viewController)) : nil;
        NSView *v = (vc && [vc respondsToSelector:@selector(view)]) ? ((id (*)(id, SEL))objc_msgSend)(vc, @selector(view)) : nil;
        if (v && [v superview] != sv) {
            if ([sv respondsToSelector:@selector(addSubview:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(sv, @selector(addSubview:), v);
            }
        }
    }
    if ([sv respondsToSelector:@selector(adjustSubviews)]) {
        ((void (*)(id, SEL))objc_msgSend)(sv, @selector(adjustSubviews));
    }
}
- (id)splitView {
    id sv = objc_getAssociatedObject(self, &kSFSplitViewKey);
    if (!sv) {
        Class cls = objc_getClass("NSSplitView");
        if (cls) {
            sv = [((id (*)(id, SEL, NSRect))objc_msgSend)([cls alloc], @selector(initWithFrame:), NSMakeRect(0, 0, 1000, 760)) autorelease];
            if ([sv respondsToSelector:@selector(setVertical:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(sv, @selector(setVertical:), YES);
            }
            objc_setAssociatedObject(self, &kSFSplitViewKey, sv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return sv;
}
- (void)setSplitView:(id)sv {
    objc_setAssociatedObject(self, &kSFSplitViewKey, sv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (sv && [sv respondsToSelector:@selector(setVertical:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(sv, @selector(setVertical:), YES);
    }
    [self _sfSyncSplitSubviews];
}
- (id)view {
    id v = objc_getAssociatedObject(self, &kSFSplitVCViewKey);
    if (!v) v = [self splitView];
    return v;
}
- (void)setView:(id)v {
    objc_setAssociatedObject(self, &kSFSplitVCViewKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (v && [v isKindOfClass:objc_getClass("NSSplitView")]) {
        objc_setAssociatedObject(self, &kSFSplitViewKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self _sfSyncSplitSubviews];
    }
}
- (NSArray *)splitViewItems {
    NSMutableArray *items = objc_getAssociatedObject(self, &kSFSplitItemsKey);
    if (!items) {
        items = [NSMutableArray array];
        objc_setAssociatedObject(self, &kSFSplitItemsKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return items;
}
- (void)setSplitViewItems:(NSArray *)items {
    NSMutableArray *m = items ? [NSMutableArray arrayWithArray:items] : [NSMutableArray array];
    objc_setAssociatedObject(self, &kSFSplitItemsKey, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _sfSyncSplitSubviews];
}
- (void)addSplitViewItem:(id)item {
    if (!item) return;
    NSMutableArray *items = (NSMutableArray *)[self splitViewItems];
    [items addObject:item];
    [self _sfSyncSplitSubviews];
}
- (void)insertSplitViewItem:(id)item atIndex:(NSInteger)idx {
    if (!item) return;
    NSMutableArray *items = (NSMutableArray *)[self splitViewItems];
    if (idx < 0) idx = 0;
    if ((NSUInteger)idx > [items count]) idx = (NSInteger)[items count];
    [items insertObject:item atIndex:(NSUInteger)idx];
    [self _sfSyncSplitSubviews];
}
- (void)removeSplitViewItem:(id)item {
    if (!item) return;
    NSMutableArray *items = (NSMutableArray *)[self splitViewItems];
    id vc = [item respondsToSelector:@selector(viewController)] ? ((id (*)(id, SEL))objc_msgSend)(item, @selector(viewController)) : nil;
    NSView *v = (vc && [vc respondsToSelector:@selector(view)]) ? ((id (*)(id, SEL))objc_msgSend)(vc, @selector(view)) : nil;
    if (v && [v superview] == [self splitView]) [v removeFromSuperview];
    [items removeObject:item];
}
- (id)splitViewItemForViewController:(id)vc {
    for (id item in [self splitViewItems]) {
        if ([item respondsToSelector:@selector(viewController)]) {
            id ivc = ((id (*)(id, SEL))objc_msgSend)(item, @selector(viewController));
            if (ivc == vc) return item;
        }
    }
    return nil;
}
- (NSString *)title { return objc_getAssociatedObject(self, &kSFSplitVCTitleKey); }
- (void)setTitle:(NSString *)t { objc_setAssociatedObject(self, &kSFSplitVCTitleKey, t, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (CGFloat)minimumThicknessForInlineSidebars {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSplitVCMinSidebarKey);
    return n ? [n doubleValue] : 0;
}
- (void)setMinimumThicknessForInlineSidebars:(CGFloat)v {
    objc_setAssociatedObject(self, &kSFSplitVCMinSidebarKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)viewDidLoad {}
- (void)viewWillAppear {}
- (void)viewDidAppear {}
- (void)viewWillDisappear {}
- (void)viewDidDisappear {}
- (void)loadView { (void)[self view]; }
- (BOOL)isViewLoaded { return objc_getAssociatedObject(self, &kSFSplitVCViewKey) != nil || objc_getAssociatedObject(self, &kSFSplitViewKey) != nil; }
@end

/* Fix NSWindowController -window + NSWindow(contentViewController:) + layoutIfNeeded for SwiftUI & Preview. */
static char kSFWindowContentVCKey;
static IMP g_orig_nswc_window_imp = NULL;

@interface NSWindowController : NSObject
- (id)window;
- (NSString *)windowNibPath;
- (void)loadWindow;
@end

static id sf_nswc_window(id self, SEL _cmd) {
    id win = g_orig_nswc_window_imp ? ((id (*)(id, SEL))g_orig_nswc_window_imp)(self, _cmd) : nil;
    if (!win) {
        Class baseCls = objc_getClass("NSWindowController");
        IMP baseLoad = baseCls ? class_getMethodImplementation(baseCls, @selector(loadWindow)) : NULL;
        IMP selfLoad = class_getMethodImplementation(object_getClass(self), @selector(loadWindow));
        if (selfLoad && selfLoad != baseLoad) {
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(loadWindow));
            if (g_orig_nswc_window_imp) {
                win = ((id (*)(id, SEL))g_orig_nswc_window_imp)(self, _cmd);
            }
        }
    }
    return win;
}

__attribute__((constructor))
static void sf_patch_nswindowcontroller_window(void) {
    Class cls = objc_getClass("NSWindowController");
    if (cls) {
        Method m = class_getInstanceMethod(cls, @selector(window));
        if (m) {
            g_orig_nswc_window_imp = method_setImplementation(m, (IMP)sf_nswc_window);
        }
    }
}

@interface NSWindow (SFWindowDecls)
- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSUInteger)mask backing:(NSUInteger)backing defer:(BOOL)flag;
- (void)setContentSize:(NSSize)size;
- (void)setContentView:(id)view;
@end

@implementation NSWindow (SFContentViewController)
- (id)contentViewController {
    return objc_getAssociatedObject(self, &kSFWindowContentVCKey);
}
- (void)setContentViewController:(id)controller {
    objc_setAssociatedObject(self, &kSFWindowContentVCKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!controller) return;
    id view = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(view));
    if (view) {
        NSRect frame = ((NSRect (*)(id, SEL))objc_msgSend)(view, @selector(frame));
        if (frame.size.width > 0 && frame.size.height > 0) {
            [self setContentSize:frame.size];
        }
        [self setContentView:view];
    }
}
- (instancetype)initWithContentViewController:(id)controller {
    id view = controller ? ((id (*)(id, SEL))objc_msgSend)(controller, @selector(view)) : nil;
    NSRect rect = view ? ((NSRect (*)(id, SEL))objc_msgSend)(view, @selector(frame)) : NSMakeRect(0, 0, 0, 0);
    if ((rect.size.width <= 0 || rect.size.height <= 0) && controller && [controller respondsToSelector:@selector(preferredContentSize)]) {
        rect.size = ((NSSize (*)(id, SEL))objc_msgSend)(controller, @selector(preferredContentSize));
    }
    if ((rect.size.width <= 0 || rect.size.height <= 0) && view && [view respondsToSelector:@selector(fittingSize)]) {
        rect.size = ((NSSize (*)(id, SEL))objc_msgSend)(view, @selector(fittingSize));
    }
    if (rect.size.width <= 0 || rect.size.height <= 0) {
        rect.size = NSMakeSize(400, 300);
    }
    rect.origin = NSMakePoint(0, 0);
    /* Titled(1) | Closable(2) | Miniaturizable(4) | Resizable(8) = 15; BackingStoreBuffered = 2 */
    self = [self initWithContentRect:rect styleMask:15 backing:2 defer:NO];
    if (self) {
        [self setContentViewController:controller];
    }
    return self;
}
- (void)layoutIfNeeded {}
@end

@implementation NSWindow (SFWindowWithContentVC)
+ (instancetype)windowWithContentViewController:(id)controller {
    return [[[self alloc] initWithContentViewController:controller] autorelease];
}
@end

static char kSFSVIVCKey, kSFSVIBehaviorKey, kSFSVICollapsedKey, kSFSVICanCollapseKey;
static char kSFSVIHoldingKey, kSFSVIMinKey, kSFSVIMaxKey, kSFSVIAutoMaxKey, kSFSVIPrefFracKey;
static char kSFSVIFullHeightKey, kSFSVITitlebarSepKey, kSFSVISpringKey, kSFSVICollapseBehaviorKey;

@interface NSSplitViewItem : NSObject
@end

@implementation NSSplitViewItem (SFPreviewSplitItem)
+ (instancetype)splitViewItemWithViewController:(id)viewController {
    id item = [[[self alloc] init] autorelease];
    [item setViewController:viewController];
    [item setHoldingPriority:250.0f];
    [item setMinimumThickness:-1.0];
    [item setMaximumThickness:-1.0];
    [item setPreferredThicknessFraction:-1.0];
    return item;
}
+ (instancetype)sidebarWithViewController:(id)viewController {
    id item = [self splitViewItemWithViewController:viewController];
    objc_setAssociatedObject(item, &kSFSVIBehaviorKey, @(1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [item setCanCollapse:YES];
    [item setHoldingPriority:260.0f];
    return item;
}
+ (instancetype)contentListWithViewController:(id)viewController {
    id item = [self splitViewItemWithViewController:viewController];
    objc_setAssociatedObject(item, &kSFSVIBehaviorKey, @(2), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [item setHoldingPriority:260.0f];
    return item;
}
+ (instancetype)inspectorWithViewController:(id)viewController {
    id item = [self splitViewItemWithViewController:viewController];
    objc_setAssociatedObject(item, &kSFSVIBehaviorKey, @(3), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [item setCanCollapse:YES];
    return item;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    (void)coder;
    return [self init];
}
- (id)viewController { return objc_getAssociatedObject(self, &kSFSVIVCKey); }
- (void)setViewController:(id)vc { objc_setAssociatedObject(self, &kSFSVIVCKey, vc, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSInteger)behavior { return [objc_getAssociatedObject(self, &kSFSVIBehaviorKey) integerValue]; }
- (BOOL)isCollapsed { return [objc_getAssociatedObject(self, &kSFSVICollapsedKey) boolValue]; }
- (void)setCollapsed:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFSVICollapsedKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id vc = [self viewController];
    if (vc && [vc respondsToSelector:@selector(view)]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(vc, @selector(view));
        if (v && [v respondsToSelector:@selector(setHidden:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(v, @selector(setHidden:), flag);
        }
    }
}
- (BOOL)canCollapse { return [objc_getAssociatedObject(self, &kSFSVICanCollapseKey) boolValue]; }
- (void)setCanCollapse:(BOOL)flag { objc_setAssociatedObject(self, &kSFSVICanCollapseKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (float)holdingPriority {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVIHoldingKey);
    return n ? [n floatValue] : 250.0f;
}
- (void)setHoldingPriority:(float)p { objc_setAssociatedObject(self, &kSFSVIHoldingKey, @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)minimumThickness {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVIMinKey);
    return n ? [n doubleValue] : -1.0;
}
- (void)setMinimumThickness:(CGFloat)v { objc_setAssociatedObject(self, &kSFSVIMinKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)maximumThickness {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVIMaxKey);
    return n ? [n doubleValue] : -1.0;
}
- (void)setMaximumThickness:(CGFloat)v { objc_setAssociatedObject(self, &kSFSVIMaxKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)automaticMaximumThickness {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVIAutoMaxKey);
    return n ? [n doubleValue] : -1.0;
}
- (void)setAutomaticMaximumThickness:(CGFloat)v { objc_setAssociatedObject(self, &kSFSVIAutoMaxKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)preferredThicknessFraction {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVIPrefFracKey);
    return n ? [n doubleValue] : -1.0;
}
- (void)setPreferredThicknessFraction:(CGFloat)v { objc_setAssociatedObject(self, &kSFSVIPrefFracKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)allowsFullHeightLayout { return [objc_getAssociatedObject(self, &kSFSVIFullHeightKey) boolValue]; }
- (void)setAllowsFullHeightLayout:(BOOL)flag { objc_setAssociatedObject(self, &kSFSVIFullHeightKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSInteger)titlebarSeparatorStyle { return [objc_getAssociatedObject(self, &kSFSVITitlebarSepKey) integerValue]; }
- (void)setTitlebarSeparatorStyle:(NSInteger)s { objc_setAssociatedObject(self, &kSFSVITitlebarSepKey, @(s), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isSpringLoaded { return [objc_getAssociatedObject(self, &kSFSVISpringKey) boolValue]; }
- (void)setSpringLoaded:(BOOL)flag { objc_setAssociatedObject(self, &kSFSVISpringKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSInteger)collapseBehavior { return [objc_getAssociatedObject(self, &kSFSVICollapseBehaviorKey) integerValue]; }
- (void)setCollapseBehavior:(NSInteger)b { objc_setAssociatedObject(self, &kSFSVICollapseBehaviorKey, @(b), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

/* Batch real methods for the remaining AppKit.sf-missing classes */
static char kSFAccViewKey, kSFAccHiddenKey, kSFAccInsetsKey, kSFAccEdgeStyleKey;
static char kSFSVITopAccKey, kSFSVIBotAccKey;

@interface NSSplitViewItemAccessoryViewController : NSObject
@end
@implementation NSSplitViewItemAccessoryViewController (SFPreviewAccVC)
- (instancetype)initWithNibName:(NSString *)nib bundle:(NSBundle *)b {
    (void)nib; (void)b;
    return [self init];
}
- (instancetype)initWithCoder:(NSCoder *)coder { (void)coder; return [self init]; }
- (id)view { return objc_getAssociatedObject(self, &kSFAccViewKey); }
- (void)setView:(id)v { objc_setAssociatedObject(self, &kSFAccViewKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isViewLoaded { return [self view] != nil; }
- (void)loadView {}
- (BOOL)isHidden { return [objc_getAssociatedObject(self, &kSFAccHiddenKey) boolValue]; }
- (void)setHidden:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFAccHiddenKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id v = [self view];
    if (v && [v respondsToSelector:@selector(setHidden:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(v, @selector(setHidden:), flag);
}
- (BOOL)automaticallyAppliesContentInsets {
    NSNumber *n = objc_getAssociatedObject(self, &kSFAccInsetsKey);
    return n ? [n boolValue] : YES;
}
- (void)setAutomaticallyAppliesContentInsets:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFAccInsetsKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)preferredScrollEdgeEffectStyle { return objc_getAssociatedObject(self, &kSFAccEdgeStyleKey); }
- (void)setPreferredScrollEdgeEffectStyle:(id)s { objc_setAssociatedObject(self, &kSFAccEdgeStyleKey, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)viewWillAppear {}
- (void)viewDidAppear {}
- (void)viewWillDisappear {}
- (void)viewDidDisappear {}
@end

@implementation NSSplitViewItem (SFPreviewAccessoryArrays)
- (NSArray *)topAlignedAccessoryViewControllers {
    NSMutableArray *a = objc_getAssociatedObject(self, &kSFSVITopAccKey);
    if (!a) { a = [NSMutableArray array]; objc_setAssociatedObject(self, &kSFSVITopAccKey, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return a;
}
- (void)setTopAlignedAccessoryViewControllers:(NSArray *)arr {
    objc_setAssociatedObject(self, &kSFSVITopAccKey, arr ? [NSMutableArray arrayWithArray:arr] : [NSMutableArray array], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)addTopAlignedAccessoryViewController:(id)vc {
    if (vc) [(NSMutableArray *)[self topAlignedAccessoryViewControllers] addObject:vc];
}
- (void)insertTopAlignedAccessoryViewController:(id)vc atIndex:(NSInteger)idx {
    if (!vc) return;
    NSMutableArray *a = (NSMutableArray *)[self topAlignedAccessoryViewControllers];
    if (idx < 0) idx = 0;
    if ((NSUInteger)idx > [a count]) idx = (NSInteger)[a count];
    [a insertObject:vc atIndex:(NSUInteger)idx];
}
- (void)removeTopAlignedAccessoryViewControllerAtIndex:(NSInteger)idx {
    NSMutableArray *a = (NSMutableArray *)[self topAlignedAccessoryViewControllers];
    if (idx >= 0 && (NSUInteger)idx < [a count]) [a removeObjectAtIndex:(NSUInteger)idx];
}
- (NSArray *)bottomAlignedAccessoryViewControllers {
    NSMutableArray *a = objc_getAssociatedObject(self, &kSFSVIBotAccKey);
    if (!a) { a = [NSMutableArray array]; objc_setAssociatedObject(self, &kSFSVIBotAccKey, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return a;
}
- (void)setBottomAlignedAccessoryViewControllers:(NSArray *)arr {
    objc_setAssociatedObject(self, &kSFSVIBotAccKey, arr ? [NSMutableArray arrayWithArray:arr] : [NSMutableArray array], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)addBottomAlignedAccessoryViewController:(id)vc {
    if (vc) [(NSMutableArray *)[self bottomAlignedAccessoryViewControllers] addObject:vc];
}
@end

@interface NSScrollEdgeEffectStyle : NSObject
@end
@implementation NSScrollEdgeEffectStyle (SFStyles)
+ (instancetype)automaticStyle { static id s; if (!s) s = [[self alloc] init]; return s; }
+ (instancetype)softStyle { static id s; if (!s) s = [[self alloc] init]; return s; }
+ (instancetype)hardStyle { static id s; if (!s) s = [[self alloc] init]; return s; }
@end

@interface NSBindingSelectionMarker : NSObject
@end
@implementation NSBindingSelectionMarker (SFMarkers)
+ (instancetype)multipleValuesSelectionMarker { static id s; if (!s) s = [[self alloc] init]; return s; }
+ (instancetype)noSelectionMarker { static id s; if (!s) s = [[self alloc] init]; return s; }
+ (instancetype)notApplicableSelectionMarker { static id s; if (!s) s = [[self alloc] init]; return s; }
@end

@interface NSTouchDevice : NSObject
@end
@implementation NSTouchDevice (SFDevices)
+ (NSArray *)touchDevices { return [NSArray array]; }
@end

static char kSFBarBgReqKey, kSFAutoSafeAreaKey;
@implementation NSSplitViewItemAccessoryViewController (SFBarBg)
- (void)_setBarBackgroundRequirement:(NSInteger)req {
    objc_setAssociatedObject(self, &kSFBarBgReqKey, @(req), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSInteger)_barBackgroundRequirement {
    return [objc_getAssociatedObject(self, &kSFBarBgReqKey) integerValue];
}
@end

@implementation NSSplitViewItem (SFRemoveBotAcc)
- (void)removeBottomAlignedAccessoryViewControllerAtIndex:(NSInteger)idx {
    NSMutableArray *a = (NSMutableArray *)[self bottomAlignedAccessoryViewControllers];
    if (idx >= 0 && (NSUInteger)idx < [a count]) [a removeObjectAtIndex:(NSUInteger)idx];
}
@end

@implementation NSView (SFAutoSafeArea)
- (BOOL)automaticallyAdjustsSafeAreaInsets {
    NSNumber *n = objc_getAssociatedObject(self, &kSFAutoSafeAreaKey);
    return n ? [n boolValue] : YES;
}
- (void)setAutomaticallyAdjustsSafeAreaInsets:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFAutoSafeAreaKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char kSFSVIAutoSafeAreaKey, kSFSVICollapseResizeKey;
@implementation NSSplitViewItem (SFSafeAreaAndResize)
- (BOOL)automaticallyAdjustsSafeAreaInsets {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVIAutoSafeAreaKey);
    return n ? [n boolValue] : YES;
}
- (void)setAutomaticallyAdjustsSafeAreaInsets:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFSVIAutoSafeAreaKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)canCollapseFromWindowResize {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVICollapseResizeKey);
    return n ? [n boolValue] : YES;
}
- (void)setCanCollapseFromWindowResize:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFSVICollapseResizeKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

/* Complete NSAccessibility storage category on NSObject for Preview.app & SwiftUI */
static char kSFA11yDictKey;
static NSMutableDictionary *sf_a11y_dict(id obj, BOOL create) {
    NSMutableDictionary *d = objc_getAssociatedObject(obj, &kSFA11yDictKey);
    if (!d && create) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(obj, &kSFA11yDictKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}

@implementation NSObject (SFAccessibilityCompat)
- (void)setAccessibilityValueDescription:(NSString *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"valDesc"]; else [d removeObjectForKey:@"valDesc"];
}
- (NSString *)accessibilityValueDescription { return [sf_a11y_dict(self, NO) objectForKey:@"valDesc"]; }
- (void)setAccessibilityDescriptions:(NSArray *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"descs"]; else [d removeObjectForKey:@"descs"];
}
- (void)setAccessibilityIdentifier:(NSString *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"ident"]; else [d removeObjectForKey:@"ident"];
}
- (NSString *)accessibilityIdentifier { return [sf_a11y_dict(self, NO) objectForKey:@"ident"]; }
- (void)setAccessibilityIdentifiers:(NSArray *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"idents"]; else [d removeObjectForKey:@"idents"];
}
- (void)setAccessibilityLabel:(NSString *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"label"]; else [d removeObjectForKey:@"label"];
}
- (NSString *)accessibilityLabel { return [sf_a11y_dict(self, NO) objectForKey:@"label"]; }
- (void)setAccessibilityRole:(NSString *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"role"]; else [d removeObjectForKey:@"role"];
}
- (NSString *)accessibilityRole { return [sf_a11y_dict(self, NO) objectForKey:@"role"]; }
- (void)setAccessibilityRoleDescription:(NSString *)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"roleDesc"]; else [d removeObjectForKey:@"roleDesc"];
}
- (NSString *)accessibilityRoleDescription { return [sf_a11y_dict(self, NO) objectForKey:@"roleDesc"]; }
- (void)setAccessibilityValue:(id)v {
    NSMutableDictionary *d = sf_a11y_dict(self, YES);
    if (v) [d setObject:v forKey:@"val"]; else [d removeObjectForKey:@"val"];
}
- (id)accessibilityValue { return [sf_a11y_dict(self, NO) objectForKey:@"val"]; }
- (NSString *)accessibilitySubrole { return [sf_a11y_dict(self, NO) objectForKey:@"subrole"]; }
- (NSArray *)accessibilityChildren {
    if ([self respondsToSelector:@selector(segmentCount)]) {
        NSInteger n = ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(segmentCount));
        if (n > 0) {
            NSMutableDictionary *d = sf_a11y_dict(self, YES);
            NSMutableArray *arr = [d objectForKey:@"segChildren"];
            if (!arr || (NSInteger)[arr count] != n) {
                arr = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
                for (NSInteger i = 0; i < n; i++) {
                    [arr addObject:[[[NSObject alloc] init] autorelease]];
                }
                [d setObject:arr forKey:@"segChildren"];
            }
            return arr;
        }
    }
    return nil;
}
- (NSString *)accessibilityEmbeddedImageDescription { return nil; }
- (BOOL)isAccessibilityElement { return YES; }
- (BOOL)isAccessibilityEnabled { return YES; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)sel { (void)sel; return YES; }
@end

@interface NSImage (SFPrivateSymbol)
+ (id)imageWithSystemSymbolName:(NSString *)name accessibilityDescription:(NSString *)desc;
@end
@implementation NSImage (SFPrivateSymbol)
+ (id)imageWithPrivateSystemSymbolName:(NSString *)name accessibilityDescription:(NSString *)desc {
    id r = nil;
    if ([self respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
        r = [self imageWithSystemSymbolName:name accessibilityDescription:desc];
    }
    if (getenv("SF_UI_AUDIT")) {
        fprintf(stderr, "SF_IMG_PRIV name='%s' -> %s\n", name ? [name UTF8String] : "(null)", r ? "OK" : "NIL");
    }
    return r;
}
@end

@interface NSWorkspace : NSObject
@end
@implementation NSWorkspace (SFContrast)
- (BOOL)accessibilityDisplayShouldIncreaseContrast { return NO; }
@end

@interface NSMenuItem (SFImportInit)
- (instancetype)initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)key;
- (void)setHidden:(BOOL)flag;
@end

@implementation NSMenuItem (SFStandardImport)
+ (instancetype)standardImportFromDeviceMenuItem {
    NSMenuItem *item = [[[self alloc] initWithTitle:@"Import from Device" action:NULL keyEquivalent:@""] autorelease];
    if ([item respondsToSelector:@selector(setHidden:)]) [item setHidden:YES];
    return item;
}
@end

static char kSFWindowSubtitleKey;
@implementation NSWindow (SFSubtitle)
- (NSString *)subtitle {
    NSString *s = objc_getAssociatedObject(self, &kSFWindowSubtitleKey);
    return s ? s : @"";
}
- (void)setSubtitle:(NSString *)subtitle {
    objc_setAssociatedObject(self, &kSFWindowSubtitleKey, subtitle, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

static char kSFBtnImgScaleKey, kSFBtnHugsKey, kSFBtnTintKey, kSFBtnSymCfgKey, kSFBtnBezelColorKey;
@interface NSButton : NSControl
@end
@implementation NSButton (SFModernButtonProps)
- (NSUInteger)imageScaling { return [objc_getAssociatedObject(self, &kSFBtnImgScaleKey) unsignedIntegerValue]; }
- (void)setImageScaling:(NSUInteger)s { objc_setAssociatedObject(self, &kSFBtnImgScaleKey, @(s), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)imageHugsTitle { return [objc_getAssociatedObject(self, &kSFBtnHugsKey) boolValue]; }
- (void)setImageHugsTitle:(BOOL)f { objc_setAssociatedObject(self, &kSFBtnHugsKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)contentTintColor { return objc_getAssociatedObject(self, &kSFBtnTintKey); }
- (void)setContentTintColor:(id)c { objc_setAssociatedObject(self, &kSFBtnTintKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)symbolConfiguration { return objc_getAssociatedObject(self, &kSFBtnSymCfgKey); }
- (void)setSymbolConfiguration:(id)c { objc_setAssociatedObject(self, &kSFBtnSymCfgKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)bezelColor { return objc_getAssociatedObject(self, &kSFBtnBezelColorKey); }
- (void)setBezelColor:(id)c { objc_setAssociatedObject(self, &kSFBtnBezelColorKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

static char kSFCtrlSendMaskKey, kSFCtrlSingleLineKey, kSFCtrlLineBreakKey;
@implementation NSControl (SFControlCompat)
- (NSInteger)sendActionOn:(NSUInteger)mask {
    NSNumber *prev = objc_getAssociatedObject(self, &kSFCtrlSendMaskKey);
    objc_setAssociatedObject(self, &kSFCtrlSendMaskKey, @(mask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([self respondsToSelector:@selector(cell)]) {
        id cell = ((id (*)(id, SEL))objc_msgSend)(self, @selector(cell));
        if (cell && [cell respondsToSelector:@selector(sendActionOn:)]) {
            return ((NSInteger (*)(id, SEL, NSUInteger))objc_msgSend)(cell, @selector(sendActionOn:), mask);
        }
    }
    return prev ? [prev integerValue] : 0;
}
- (BOOL)usesSingleLineMode { return [objc_getAssociatedObject(self, &kSFCtrlSingleLineKey) boolValue]; }
- (void)setUsesSingleLineMode:(BOOL)f { objc_setAssociatedObject(self, &kSFCtrlSingleLineKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSUInteger)lineBreakMode { return [objc_getAssociatedObject(self, &kSFCtrlLineBreakKey) unsignedIntegerValue]; }
- (void)setLineBreakMode:(NSUInteger)m { objc_setAssociatedObject(self, &kSFCtrlLineBreakKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

static char kSFPUBUsesItemKey, kSFPUBAltersStateKey, kSFPUBArrowPosKey, kSFPUBPrefEdgeKey;
@interface NSPopUpButtonCell : NSObject
@end
@implementation NSPopUpButtonCell (SFPopUpCellCompat)
- (BOOL)usesItemFromMenu {
    NSNumber *n = objc_getAssociatedObject(self, &kSFPUBUsesItemKey);
    return n ? [n boolValue] : YES;
}
- (void)setUsesItemFromMenu:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFPUBUsesItemKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)altersStateOfSelectedItem {
    NSNumber *n = objc_getAssociatedObject(self, &kSFPUBAltersStateKey);
    return n ? [n boolValue] : YES;
}
- (void)setAltersStateOfSelectedItem:(BOOL)flag {
    objc_setAssociatedObject(self, &kSFPUBAltersStateKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSUInteger)arrowPosition {
    NSNumber *n = objc_getAssociatedObject(self, &kSFPUBArrowPosKey);
    return n ? [n unsignedIntegerValue] : 2;
}
- (void)setArrowPosition:(NSUInteger)p {
    objc_setAssociatedObject(self, &kSFPUBArrowPosKey, @(p), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSUInteger)preferredEdge {
    return [objc_getAssociatedObject(self, &kSFPUBPrefEdgeKey) unsignedIntegerValue];
}
- (void)setPreferredEdge:(NSUInteger)e {
    objc_setAssociatedObject(self, &kSFPUBPrefEdgeKey, @(e), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char kSFPUBMenuItemKey;
@implementation NSPopUpButtonCell (SFMenuItemCompat)
- (id)menuItem { return objc_getAssociatedObject(self, &kSFPUBMenuItemKey); }
- (void)setMenuItem:(id)item { objc_setAssociatedObject(self, &kSFPUBMenuItemKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

static char kSFPDFViewDictKey;
static NSMutableDictionary *sf_pdfview_props(id self) {
    NSMutableDictionary *d = objc_getAssociatedObject(self, &kSFPDFViewDictKey);
    if (!d) {
        d = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &kSFPDFViewDictKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return d;
}
static void sf_pdfview_set_bool(id self, SEL _cmd, BOOL v) {
    NSString *k = NSStringFromSelector(_cmd);
    [sf_pdfview_props(self) setObject:@(v) forKey:k];
}
static BOOL sf_pdfview_get_bool(id self, SEL _cmd) {
    NSString *k = [NSString stringWithFormat:@"set%c%@:", toupper(sel_getName(_cmd)[0]), [NSString stringWithUTF8String:sel_getName(_cmd) + 1]];
    return [[sf_pdfview_props(self) objectForKey:k] boolValue];
}
static void sf_pdfview_set_obj(id self, SEL _cmd, id v) {
    NSString *k = NSStringFromSelector(_cmd);
    if (v) [sf_pdfview_props(self) setObject:v forKey:k];
    else [sf_pdfview_props(self) removeObjectForKey:k];
}
static id sf_pdfview_get_obj(id self, SEL _cmd) {
    NSString *k = [NSString stringWithFormat:@"set%c%@:", toupper(sel_getName(_cmd)[0]), [NSString stringWithUTF8String:sel_getName(_cmd) + 1]];
    return [sf_pdfview_props(self) objectForKey:k];
}

__attribute__((constructor))
static void sf_register_pdfview_modern_methods(void) {
    Class pdfView = objc_getClass("PDFView");
    if (!pdfView) return;
    const char *boolPairs[][2] = {
        {"formDetectionEnabled", "setFormDetectionEnabled:"},
        {"inMarkupMode", "setInMarkupMode:"},
        {"enableDataDetectors", "setEnableDataDetectors:"},
        {"displaysRTL", "setDisplaysRTL:"},
        {"showsScrollIndicators", "setShowsScrollIndicators:"},
        {"displaysLinks", "setDisplaysLinks:"},
        {"displaysPageLabels", "setDisplaysPageLabels:"},
        {"pageShadowsEnabled", "enablePageShadows:"},
        {"acceptsDraggedFiles", "setAcceptsDraggedFiles:"},
    };
    for (size_t i = 0; i < sizeof(boolPairs)/sizeof(boolPairs[0]); i++) {
        SEL g = sel_registerName(boolPairs[i][0]);
        SEL s = sel_registerName(boolPairs[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_bool, "B@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_bool, "v@:B");
    }
    const char *objPairs[][2] = {
        {"akController", "setAkController:"},
        {"AKController", "setAKController:"},
        {"PDFAKControllerDelegate", "setPDFAKControllerDelegate:"},
    };
    for (size_t i = 0; i < sizeof(objPairs)/sizeof(objPairs[0]); i++) {
        SEL g = sel_registerName(objPairs[i][0]);
        SEL s = sel_registerName(objPairs[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_obj, "@@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_obj, "v@:@");
    }
}

static SFEdgeInsets sf_pdfview_get_insets(id self, SEL _cmd) {
    NSString *k = [NSString stringWithFormat:@"set%c%@:", toupper(sel_getName(_cmd)[0]), [NSString stringWithUTF8String:sel_getName(_cmd) + 1]];
    NSValue *v = [sf_pdfview_props(self) objectForKey:k];
    SFEdgeInsets z = {0, 0, 0, 0};
    if (v && [v respondsToSelector:@selector(getValue:)]) [v getValue:&z];
    return z;
}
static void sf_pdfview_set_insets(id self, SEL _cmd, SFEdgeInsets ins) {
    NSString *k = NSStringFromSelector(_cmd);
    NSValue *v = [NSValue valueWithBytes:&ins objCType:@encode(SFEdgeInsets)];
    [sf_pdfview_props(self) setObject:v forKey:k];
}
static double sf_pdfview_get_double(id self, SEL _cmd) {
    NSString *k = [NSString stringWithFormat:@"set%c%@:", toupper(sel_getName(_cmd)[0]), [NSString stringWithUTF8String:sel_getName(_cmd) + 1]];
    NSNumber *n = [sf_pdfview_props(self) objectForKey:k];
    return n ? [n doubleValue] : 0.0;
}
static void sf_pdfview_set_double(id self, SEL _cmd, double d) {
    [sf_pdfview_props(self) setObject:@(d) forKey:NSStringFromSelector(_cmd)];
}
static NSInteger sf_pdfview_get_int(id self, SEL _cmd) {
    NSString *k = [NSString stringWithFormat:@"set%c%@:", toupper(sel_getName(_cmd)[0]), [NSString stringWithUTF8String:sel_getName(_cmd) + 1]];
    NSNumber *n = [sf_pdfview_props(self) objectForKey:k];
    return n ? [n integerValue] : 0;
}
static void sf_pdfview_set_int(id self, SEL _cmd, NSInteger i) {
    [sf_pdfview_props(self) setObject:@(i) forKey:NSStringFromSelector(_cmd)];
}

__attribute__((constructor))
static void sf_register_pdfview_layout_methods(void) {
    Class pdfView = objc_getClass("PDFView");
    if (!pdfView) return;
    const char *insetsPairs[][2] = {
        {"documentMargins", "setDocumentMargins:"},
        {"pageBreakMargins", "setPageBreakMargins:"},
    };
    for (size_t i = 0; i < sizeof(insetsPairs)/sizeof(insetsPairs[0]); i++) {
        SEL g = sel_registerName(insetsPairs[i][0]);
        SEL s = sel_registerName(insetsPairs[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_insets, "{NSEdgeInsets=dddd}@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_insets, "v@:{NSEdgeInsets=dddd}");
    }
    const char *dblPairs[][2] = {
        {"gutterWidth", "setGutterWidth:"},
        {"minScaleFactor", "setMinScaleFactor:"},
        {"maxScaleFactor", "setMaxScaleFactor:"},
    };
    for (size_t i = 0; i < sizeof(dblPairs)/sizeof(dblPairs[0]); i++) {
        SEL g = sel_registerName(dblPairs[i][0]);
        SEL s = sel_registerName(dblPairs[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_double, "d@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_double, "v@:d");
    }
    const char *intPairs[][2] = {
        {"displayDirection", "setDisplayDirection:"},
        {"interpolationQuality", "setInterpolationQuality:"},
        {"displaysPageBreaks", "setDisplaysPageBreaks:"},
    };
    for (size_t i = 0; i < sizeof(intPairs)/sizeof(intPairs[0]); i++) {
        SEL g = sel_registerName(intPairs[i][0]);
        SEL s = sel_registerName(intPairs[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_int, "q@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_int, "v@:q");
    }
}

@interface SFPDFLayoutProxy : NSObject {
    id _pdfView;
}
- (instancetype)initWithPDFView:(id)v;
@end
@implementation SFPDFLayoutProxy
- (instancetype)initWithPDFView:(id)v {
    if ((self = [super init])) { _pdfView = v; }
    return self;
}
- (NSSize)contentSizeWithCurrentPage:(id)page {
    id p = page;
    if (!p && _pdfView && [_pdfView respondsToSelector:@selector(currentPage)]) {
        p = ((id (*)(id, SEL))objc_msgSend)(_pdfView, @selector(currentPage));
    }
    if (!p && _pdfView && [_pdfView respondsToSelector:@selector(document)]) {
        id doc = ((id (*)(id, SEL))objc_msgSend)(_pdfView, @selector(document));
        if (doc && [doc respondsToSelector:@selector(pageCount)] && ((NSUInteger (*)(id, SEL))objc_msgSend)(doc, @selector(pageCount)) > 0) {
            p = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(doc, @selector(pageAtIndex:), 0);
        }
    }
    NSSize sz = NSMakeSize(612.0, 792.0);
    if (p && [p respondsToSelector:@selector(boundsForBox:)]) {
        NSRect b = ((NSRect (*)(id, SEL, NSInteger))objc_msgSend)(p, @selector(boundsForBox:), 1);
        if (b.size.width > 1.0 && b.size.height > 1.0) sz = b.size;
    }
    CGFloat sc = (_pdfView && [_pdfView respondsToSelector:@selector(scaleFactor)]) ? ((CGFloat (*)(id, SEL))objc_msgSend)(_pdfView, @selector(scaleFactor)) : 1.0;
    if (sc <= 0.1 || sc > 20.0) sc = 1.0;
    return NSMakeSize(sz.width * sc, sz.height * sc);
}
@end
static char kSFPDFLayoutProxyKey;
static id sf_pdfview_pdflayout(id self, SEL _cmd) {
    (void)_cmd;
    id l = objc_getAssociatedObject(self, &kSFPDFLayoutProxyKey);
    if (!l) {
        l = [[[SFPDFLayoutProxy alloc] initWithPDFView:self] autorelease];
        objc_setAssociatedObject(self, &kSFPDFLayoutProxyKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return l;
}
__attribute__((constructor))
static void sf_register_pdfview_layout_obj(void) {
    Class pdfView = objc_getClass("PDFView");
    if (pdfView && !class_respondsToSelector(pdfView, sel_registerName("PDFLayout"))) {
        class_addMethod(pdfView, sel_registerName("PDFLayout"), (IMP)sf_pdfview_pdflayout, "@@:");
    }
}

static double sf_pdfview_autoscale_size(id self, SEL _cmd, NSSize sz) {
    (void)_cmd;
    NSRect b = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
    if (sz.width <= 0 || sz.height <= 0 || b.size.width <= 0 || b.size.height <= 0) return 1.0;
    double sx = b.size.width / sz.width;
    double sy = b.size.height / sz.height;
    double s = sx < sy ? sx : sy;
    if (s < 0.25) s = 0.25;
    if (s > 4.0) s = 4.0;
    return s;
}
static double sf_pdfview_autoscale_page(id self, SEL _cmd, id page) {
    (void)_cmd;
    if (!page || ![page respondsToSelector:@selector(boundsForBox:)]) return 1.0;
    NSRect pb = ((NSRect (*)(id, SEL, NSInteger))objc_msgSend)(page, @selector(boundsForBox:), 0);
    return sf_pdfview_autoscale_size(self, _cmd, pb.size);
}
static double sf_pdfview_scale_to_fit(id self, SEL _cmd) {
    id page = [self respondsToSelector:@selector(currentPage)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(currentPage)) : nil;
    return sf_pdfview_autoscale_page(self, _cmd, page);
}
static id sf_pdfview_document_view(id self, SEL _cmd) {
    (void)_cmd;
    return self;
}

__attribute__((constructor))
static void sf_register_pdfview_scale_methods(void) {
    Class pdfView = objc_getClass("PDFView");
    if (!pdfView) return;
    if (!class_respondsToSelector(pdfView, sel_registerName("autoScaleFactorForPageWithSize:")))
        class_addMethod(pdfView, sel_registerName("autoScaleFactorForPageWithSize:"), (IMP)sf_pdfview_autoscale_size, "d@:{CGSize=dd}");
    if (!class_respondsToSelector(pdfView, sel_registerName("autoScaleFactorForPage:")))
        class_addMethod(pdfView, sel_registerName("autoScaleFactorForPage:"), (IMP)sf_pdfview_autoscale_page, "d@:@");
    if (!class_respondsToSelector(pdfView, sel_registerName("scaleFactorForSizeToFit")))
        class_addMethod(pdfView, sel_registerName("scaleFactorForSizeToFit"), (IMP)sf_pdfview_scale_to_fit, "d@:");
    if (!class_respondsToSelector(pdfView, sel_registerName("documentView")))
        class_addMethod(pdfView, sel_registerName("documentView"), (IMP)sf_pdfview_document_view, "@@:");
}

static void sf_pdfview_noop(id self, SEL _cmd) { (void)self; (void)_cmd; }

__attribute__((constructor))
static void sf_register_pdfview_tile_methods(void) {
    Class pdfView = objc_getClass("PDFView");
    if (!pdfView) return;
    const char *moreBools[][2] = {
        {"enableTileUpdates", "setEnableTileUpdates:"},
        {"shouldAntiAlias", "setShouldAntiAlias:"},
        {"usesPageLabels", "setUsesPageLabels:"},
        {"displaysAsBook", "setDisplaysAsBook:"},
        {"enablePageShadows", "setEnablePageShadows:"},
        {"automaticallyAdjustsContentInsets", "setAutomaticallyAdjustsContentInsets:"},
        {"allowsDragging", "setAllowsDragging:"},
        {"isUsingPageViewController", "usePageViewController:withViewOptions:"},
    };
    for (size_t i = 0; i < sizeof(moreBools)/sizeof(moreBools[0]); i++) {
        SEL g = sel_registerName(moreBools[i][0]);
        SEL s = sel_registerName(moreBools[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_bool, "B@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_bool, "v@:B");
    }
    const char *moreDbls[][2] = {
        {"greekingThreshold", "setGreekingThreshold:"},
    };
    for (size_t i = 0; i < sizeof(moreDbls)/sizeof(moreDbls[0]); i++) {
        SEL g = sel_registerName(moreDbls[i][0]);
        SEL s = sel_registerName(moreDbls[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_double, "d@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_double, "v@:d");
    }
    const char *noops[] = {
        "layoutDocumentView", "forceTileUpdate", "updateScrollView", "clearSelection",
        "annotationsChangedOnPage:", "goToFirstPage:", "goToLastPage:", "goToNextPage:", "goToPreviousPage:"
    };
    for (size_t i = 0; i < sizeof(noops)/sizeof(noops[0]); i++) {
        SEL s = sel_registerName(noops[i]);
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_noop, "v@:@");
    }
}

__attribute__((constructor))
static void sf_register_pdfview_enable_methods(void) {
    Class pdfView = objc_getClass("PDFView");
    if (!pdfView) return;
    const char *enables[] = {
        "enableSwipeGestures:", "enablePageShadows:", "setEnableTileUpdates:",
        "setEnableDataDetectors:", "setEnablePageShadows:", "enableBackgroundImages:",
        "setEnablesMarquee:", "setDrawsBackground:", "setAutomaticallyAdjustsContentInsets:",
        "setPageShadowsEnabled:", "setDisplaysPageBreaks:", "setDisplaysAsBook:",
        "setAllowsDragging:", "setInMarkupMode:", "setFormDetectionEnabled:"
    };
    for (size_t i = 0; i < sizeof(enables)/sizeof(enables[0]); i++) {
        SEL s = sel_registerName(enables[i]);
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_bool, "v@:B");
    }
}

__attribute__((constructor))
static void sf_register_pdfview_appearance_methods(void) {
    Class pdfView = objc_getClass("PDFView");
    if (!pdfView) return;
    const char *pairs[][2] = {
        {"allowsDarkAppearanceContent", "setAllowsDarkAppearanceContent:"},
        {"allowsUndo", "setAllowsUndo:"},
        {"enableRemotePreviews", "setEnableRemotePreviews:"},
        {"pageOverlayViewProvider", "setPageOverlayViewProvider:"},
        {"displaysShadows", "setDisplaysShadows:"},
    };
    for (size_t i = 0; i < sizeof(pairs)/sizeof(pairs[0]); i++) {
        SEL g = sel_registerName(pairs[i][0]);
        SEL s = sel_registerName(pairs[i][1]);
        if (!class_respondsToSelector(pdfView, g)) class_addMethod(pdfView, g, (IMP)sf_pdfview_get_bool, "B@:");
        if (!class_respondsToSelector(pdfView, s)) class_addMethod(pdfView, s, (IMP)sf_pdfview_set_bool, "v@:B");
    }
}

static id sf_pdfdoc_empty_array(id self, SEL _cmd) { (void)self; (void)_cmd; return [NSArray array]; }
static id sf_pdfdoc_nil(id self, SEL _cmd) { (void)self; (void)_cmd; return nil; }
static BOOL sf_pdfdoc_no(id self, SEL _cmd) { (void)self; (void)_cmd; return NO; }
static BOOL sf_pdfdoc_yes(id self, SEL _cmd) { (void)self; (void)_cmd; return YES; }

__attribute__((constructor))
static void sf_register_pdfdocument_methods(void) {
    Class pdfDoc = objc_getClass("PDFDocument");
    if (!pdfDoc) return;
    const char *arrGetters[] = { "bookmarkedPages", "pageLabels" };
    for (size_t i = 0; i < sizeof(arrGetters)/sizeof(arrGetters[0]); i++) {
        SEL s = sel_registerName(arrGetters[i]);
        if (!class_respondsToSelector(pdfDoc, s)) class_addMethod(pdfDoc, s, (IMP)sf_pdfdoc_empty_array, "@@:");
    }
    const char *nilGetters[] = { "akDocumentAdapter", "akController", "AKController", "outlineRoot", "permissionsStatus" };
    for (size_t i = 0; i < sizeof(nilGetters)/sizeof(nilGetters[0]); i++) {
        SEL s = sel_registerName(nilGetters[i]);
        if (!class_respondsToSelector(pdfDoc, s)) class_addMethod(pdfDoc, s, (IMP)sf_pdfdoc_nil, "@@:");
    }
    const char *noGetters[] = { "isEncrypted", "isLocked", "allowsFormFieldEntry", "allowsCommenting", "allowsDocumentAssembly", "allowsDocumentChanges", "hasHighLatencyDataProvider" };
    for (size_t i = 0; i < sizeof(noGetters)/sizeof(noGetters[0]); i++) {
        SEL s = sel_registerName(noGetters[i]);
        if (!class_respondsToSelector(pdfDoc, s)) class_addMethod(pdfDoc, s, (IMP)sf_pdfdoc_no, "B@:");
    }
    const char *yesGetters[] = { "allowsPrinting", "allowsCopying", "allowsContentAccessibility" };
    for (size_t i = 0; i < sizeof(yesGetters)/sizeof(yesGetters[0]); i++) {
        SEL s = sel_registerName(yesGetters[i]);
        if (!class_respondsToSelector(pdfDoc, s)) class_addMethod(pdfDoc, s, (IMP)sf_pdfdoc_yes, "B@:");
    }
    const char *objSetters[] = { "setBookmarkedPages:", "setAkController:", "setAKController:", "setBookmarked:atPageIndex:" };
    for (size_t i = 0; i < sizeof(objSetters)/sizeof(objSetters[0]); i++) {
        SEL s = sel_registerName(objSetters[i]);
        if (!class_respondsToSelector(pdfDoc, s)) class_addMethod(pdfDoc, s, (IMP)sf_pdfview_noop, "v@:@");
    }
}

static void sf_pdfview_set_doc_wait(id self, SEL _cmd, id doc, double waitDuration) {
    (void)_cmd; (void)waitDuration;
    if ([self respondsToSelector:@selector(setDocument:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setDocument:), doc);
    }
}

__attribute__((constructor))
static void sf_register_pdfview_setdoc_wait(void) {
    Class pdfView = objc_getClass("PDFView");
    if (pdfView && !class_respondsToSelector(pdfView, sel_registerName("setDocument:waitDuration:"))) {
        class_addMethod(pdfView, sel_registerName("setDocument:waitDuration:"), (IMP)sf_pdfview_set_doc_wait, "v@:@d");
    }
}

__attribute__((constructor))
static void sf_register_pdfdocument_ak_delegate(void) {
    Class pdfDoc = objc_getClass("PDFDocument");
    if (!pdfDoc) return;
    SEL s = sel_registerName("setPDFAKControllerDelegate:");
    SEL g = sel_registerName("PDFAKControllerDelegate");
    if (!class_respondsToSelector(pdfDoc, s)) class_addMethod(pdfDoc, s, (IMP)sf_pdfview_set_obj, "v@:@");
    if (!class_respondsToSelector(pdfDoc, g)) class_addMethod(pdfDoc, g, (IMP)sf_pdfview_get_obj, "@@:");
}

/* Built-in macOS NSToolbar standard item identifiers handled before delegate lookup */
static IMP g_orig_toolbar_item_for_id = NULL;

static BOOL sf_is_builtin_toolbar_id(NSString *ident) {
    if (!ident) return NO;
    if ([ident rangeOfString:@"TrackingSeparator"].location != NSNotFound) return YES;
    if ([ident hasPrefix:@"NSToolbarToggle"] || [ident hasPrefix:@"NSToolbarSidebar"] || [ident hasPrefix:@"NSToolbarInspector"] || [ident hasPrefix:@"NSToolbarCloudSharing"] || [ident hasPrefix:@"NSToolbarWritingTools"] || [ident hasPrefix:@"NSToolbarPrimarySidebar"] || [ident hasPrefix:@"NSToolbarSupplementarySidebar"]) return YES;
    static NSArray *builtins;
    if (!builtins) {
        builtins = [@[
            @"NSToolbarToggleSidebarItemIdentifier",
            @"NSToolbarToggleInspectorItemIdentifier",
            @"NSToolbarSidebarTrackingSeparatorItemIdentifier",
            @"NSToolbarInspectorTrackingSeparatorItemIdentifier",
            @"NSToolbarPrimarySidebarTrackingSeparatorItemIdentifier",
            @"NSToolbarSupplementarySidebarTrackingSeparatorItemIdentifier",
            @"NSToolbarCloudSharingItemIdentifier",
            @"NSToolbarWritingToolsItemIdentifier",
        ] retain];
    }
    return [builtins containsObject:ident];
}

static id sf_toolbar_item_for_id(id self, SEL _cmd, NSString *ident, BOOL willInsert) {
        if (sf_is_builtin_toolbar_id(ident)) {
        Class cls = objc_getClass("NSToolbarItem");
        if (cls) {
            return [((id (*)(id, SEL, id))objc_msgSend)([cls alloc], @selector(initWithItemIdentifier:), ident) autorelease];
        }
        return nil;
    }
    return g_orig_toolbar_item_for_id ? ((id (*)(id, SEL, id, BOOL))g_orig_toolbar_item_for_id)(self, _cmd, ident, willInsert) : nil;
}

__attribute__((constructor))
static void sf_patch_toolbar_builtin_items(void) {
    Class cls = objc_getClass("NSToolbar");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel_registerName("_itemForItemIdentifier:willBeInsertedIntoToolbar:"));
    if (m) {
        g_orig_toolbar_item_for_id = method_setImplementation(m, (IMP)sf_toolbar_item_for_id);
    }
}

static char kSFCVSingleColKey, kSFCVPinHeadersKey, kSFCVPinFootersKey, kSFCVEstItemSizeKey;
@interface NSCollectionViewFlowLayout : NSObject
@end
@implementation NSCollectionViewFlowLayout (SFPreviewSidebarLayout)
- (BOOL)_singleColumnOrRow { return [objc_getAssociatedObject(self, &kSFCVSingleColKey) boolValue]; }
- (void)_setSingleColumnOrRow:(BOOL)f { objc_setAssociatedObject(self, &kSFCVSingleColKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)sectionHeadersPinToVisibleBounds { return [objc_getAssociatedObject(self, &kSFCVPinHeadersKey) boolValue]; }
- (void)setSectionHeadersPinToVisibleBounds:(BOOL)f { objc_setAssociatedObject(self, &kSFCVPinHeadersKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)sectionFootersPinToVisibleBounds { return [objc_getAssociatedObject(self, &kSFCVPinFootersKey) boolValue]; }
- (void)setSectionFootersPinToVisibleBounds:(BOOL)f { objc_setAssociatedObject(self, &kSFCVPinFootersKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSSize)estimatedItemSize {
    NSValue *v = objc_getAssociatedObject(self, &kSFCVEstItemSizeKey);
    return v ? [v sizeValue] : NSMakeSize(0, 0);
}
- (void)setEstimatedItemSize:(NSSize)sz {
    objc_setAssociatedObject(self, &kSFCVEstItemSizeKey, [NSValue valueWithSize:sz], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static char kSFCVCollapseSecKey;
@implementation NSCollectionViewFlowLayout (SFMoreFlowProps)
- (BOOL)_collapsesSectionsToFirstItem { return [objc_getAssociatedObject(self, &kSFCVCollapseSecKey) boolValue]; }
- (void)_setCollapsesSectionsToFirstItem:(BOOL)f { objc_setAssociatedObject(self, &kSFCVCollapseSecKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)collapseSectionAtIndex:(NSUInteger)idx { (void)idx; }
- (void)expandSectionAtIndex:(NSUInteger)idx { (void)idx; }
- (BOOL)sectionAtIndexIsCollapsed:(NSUInteger)idx { (void)idx; return NO; }
@end



static char kSFCVSectionDropKey, kSFCVDropGapsKey, kSFCVCollapseBtnKey;
@interface NSCollectionView : NSView
@end
@implementation NSCollectionView (SFPreviewSidebarCV)
- (BOOL)allowsSectionDrop { return [objc_getAssociatedObject(self, &kSFCVSectionDropKey) boolValue]; }
- (void)setAllowsSectionDrop:(BOOL)f { objc_setAssociatedObject(self, &kSFCVSectionDropKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)_opensDropInsertionGaps { return [objc_getAssociatedObject(self, &kSFCVDropGapsKey) boolValue]; }
- (void)_setOpensDropInsertionGaps:(BOOL)f { objc_setAssociatedObject(self, &kSFCVDropGapsKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (id)sectionCollapseButton { return objc_getAssociatedObject(self, &kSFCVCollapseBtnKey); }
- (void)setSectionCollapseButton:(id)b { objc_setAssociatedObject(self, &kSFCVCollapseBtnKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)setDraggingSourceOperationMask:(NSUInteger)mask forLocal:(BOOL)isLocal { (void)mask; (void)isLocal; }
- (void)willTransitionFromLayout:(id)oldL toLayout:(id)newL { (void)oldL; (void)newL; }
- (void)didTransitionFromLayout:(id)oldL toLayout:(id)newL { (void)oldL; (void)newL; }
@end

static char kSFSVLegacyKey, kSFSVPageHKey, kSFSVPageVKey, kSFSVAllowMagKey, kSFSVInsetsKey, kSFSVAutoInsetsKey, kSFSVScInsetsKey, kSFSVMagKey;
@implementation NSScrollView (SFPreviewScrollCompat)
- (void)_setAllowsContentUnderLegacyScrollers:(BOOL)f { objc_setAssociatedObject(self, &kSFSVLegacyKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)_wantsPageAlignedHorizontalAxis { return [objc_getAssociatedObject(self, &kSFSVPageHKey) boolValue]; }
- (void)_setWantsPageAlignedHorizontalAxis:(BOOL)f { objc_setAssociatedObject(self, &kSFSVPageHKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)_wantsPageAlignedVerticalAxis { return [objc_getAssociatedObject(self, &kSFSVPageVKey) boolValue]; }
- (void)_setWantsPageAlignedVerticalAxis:(BOOL)f { objc_setAssociatedObject(self, &kSFSVPageVKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)allowsMagnification { return [objc_getAssociatedObject(self, &kSFSVAllowMagKey) boolValue]; }
- (void)setAllowsMagnification:(BOOL)f { objc_setAssociatedObject(self, &kSFSVAllowMagKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)magnification {
    NSNumber *n = objc_getAssociatedObject(self, &kSFSVMagKey);
    return n ? [n doubleValue] : 1.0;
}
- (void)setMagnification:(CGFloat)m { objc_setAssociatedObject(self, &kSFSVMagKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)minMagnification { return 0.1; }
- (void)setMinMagnification:(CGFloat)m { (void)m; }
- (CGFloat)maxMagnification { return 16.0; }
- (void)setMaxMagnification:(CGFloat)m { (void)m; }
- (void)setMagnification:(CGFloat)m centeredAtPoint:(NSPoint)pt { (void)pt; [self setMagnification:m]; }
- (void)magnifyToFitRect:(NSRect)r { (void)r; }
- (SFEdgeInsets)contentInsets {
    NSData *d = objc_getAssociatedObject(self, &kSFSVInsetsKey);
    SFEdgeInsets e = {0, 0, 0, 0};
    if (d && [d length] == sizeof(e)) memcpy(&e, [d bytes], sizeof(e));
    return e;
}
- (void)setContentInsets:(SFEdgeInsets)e {
    objc_setAssociatedObject(self, &kSFSVInsetsKey, [NSData dataWithBytes:&e length:sizeof(e)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)automaticallyAdjustsContentInsets { return [objc_getAssociatedObject(self, &kSFSVAutoInsetsKey) boolValue]; }
- (void)setAutomaticallyAdjustsContentInsets:(BOOL)v { objc_setAssociatedObject(self, &kSFSVAutoInsetsKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (SFEdgeInsets)scrollerInsets {
    NSData *d = objc_getAssociatedObject(self, &kSFSVScInsetsKey);
    SFEdgeInsets e = {0, 0, 0, 0};
    if (d && [d length] == sizeof(e)) memcpy(&e, [d bytes], sizeof(e));
    return e;
}
- (void)setScrollerInsets:(SFEdgeInsets)e {
    objc_setAssociatedObject(self, &kSFSVScInsetsKey, [NSData dataWithBytes:&e length:sizeof(e)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (NSInteger)horizontalScrollElasticity { return 0; }
- (void)setHorizontalScrollElasticity:(NSInteger)e { (void)e; }
- (NSInteger)verticalScrollElasticity { return 0; }
- (void)setVerticalScrollElasticity:(NSInteger)e { (void)e; }
- (BOOL)usesPredominantAxisScrolling { return NO; }
- (void)setUsesPredominantAxisScrolling:(BOOL)v { (void)v; }
- (NSInteger)findBarPosition { return 1; }
- (void)setFindBarPosition:(NSInteger)p { (void)p; }
@end

static SFEdgeInsets sf_sv_get_contentInsets(id self, SEL _cmd) {
    (void)_cmd;
    NSData *d = objc_getAssociatedObject(self, &kSFSVInsetsKey);
    SFEdgeInsets e = {0, 0, 0, 0};
    if (d && [d length] == sizeof(e)) memcpy(&e, [d bytes], sizeof(e));
    return e;
}
static void sf_sv_set_contentInsets(id self, SEL _cmd, SFEdgeInsets e) {
    (void)_cmd;
    objc_setAssociatedObject(self, &kSFSVInsetsKey, [NSData dataWithBytes:&e length:sizeof(e)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static SFEdgeInsets sf_sv_get_scrollerInsets(id self, SEL _cmd) {
    (void)_cmd;
    NSData *d = objc_getAssociatedObject(self, &kSFSVScInsetsKey);
    SFEdgeInsets e = {0, 0, 0, 0};
    if (d && [d length] == sizeof(e)) memcpy(&e, [d bytes], sizeof(e));
    return e;
}
static void sf_sv_set_scrollerInsets(id self, SEL _cmd, SFEdgeInsets e) {
    (void)_cmd;
    objc_setAssociatedObject(self, &kSFSVScInsetsKey, [NSData dataWithBytes:&e length:sizeof(e)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL sf_sv_get_autoInsets(id self, SEL _cmd) { (void)_cmd; return [objc_getAssociatedObject(self, &kSFSVAutoInsetsKey) boolValue]; }
static void sf_sv_set_autoInsets(id self, SEL _cmd, BOOL v) { (void)_cmd; objc_setAssociatedObject(self, &kSFSVAutoInsetsKey, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static CGFloat sf_sv_get_mag(id self, SEL _cmd) { (void)_cmd; NSNumber *n = objc_getAssociatedObject(self, &kSFSVMagKey); return n ? [n doubleValue] : 1.0; }
static void sf_sv_set_mag(id self, SEL _cmd, CGFloat m) { (void)_cmd; objc_setAssociatedObject(self, &kSFSVMagKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static CGFloat sf_sv_get_minMag(id self, SEL _cmd) { (void)self; (void)_cmd; return 0.1; }
static CGFloat sf_sv_get_maxMag(id self, SEL _cmd) { (void)self; (void)_cmd; return 16.0; }
static void sf_sv_noop_dbl(id self, SEL _cmd, CGFloat v) { (void)self; (void)_cmd; (void)v; }
static NSInteger sf_sv_ret0(id self, SEL _cmd) { (void)self; (void)_cmd; return 0; }
static void sf_sv_noop_int(id self, SEL _cmd, NSInteger v) { (void)self; (void)_cmd; (void)v; }
static BOOL sf_sv_retNO(id self, SEL _cmd) { (void)self; (void)_cmd; return NO; }
static void sf_sv_noop_bool(id self, SEL _cmd, BOOL v) { (void)self; (void)_cmd; (void)v; }
static void sf_sv_set_mag_pt(id self, SEL _cmd, CGFloat m, NSPoint pt) { (void)pt; sf_sv_set_mag(self, _cmd, m); }
static void sf_sv_mag_rect(id self, SEL _cmd, NSRect r) { (void)self; (void)_cmd; (void)r; }

__attribute__((constructor))
static void sf_install_scrollview_modern_methods(void) {
    Class sv = objc_getClass("NSScrollView");
    if (!sv) return;
    if (!class_respondsToSelector(sv, @selector(contentInsets)))
        class_addMethod(sv, @selector(contentInsets), (IMP)sf_sv_get_contentInsets, "{NSEdgeInsets=dddd}@:");
    if (!class_respondsToSelector(sv, @selector(setContentInsets:)))
        class_addMethod(sv, @selector(setContentInsets:), (IMP)sf_sv_set_contentInsets, "v@:{NSEdgeInsets=dddd}");
    if (!class_respondsToSelector(sv, @selector(scrollerInsets)))
        class_addMethod(sv, @selector(scrollerInsets), (IMP)sf_sv_get_scrollerInsets, "{NSEdgeInsets=dddd}@:");
    if (!class_respondsToSelector(sv, @selector(setScrollerInsets:)))
        class_addMethod(sv, @selector(setScrollerInsets:), (IMP)sf_sv_set_scrollerInsets, "v@:{NSEdgeInsets=dddd}");
    if (!class_respondsToSelector(sv, @selector(automaticallyAdjustsContentInsets)))
        class_addMethod(sv, @selector(automaticallyAdjustsContentInsets), (IMP)sf_sv_get_autoInsets, "B@:");
    if (!class_respondsToSelector(sv, @selector(setAutomaticallyAdjustsContentInsets:)))
        class_addMethod(sv, @selector(setAutomaticallyAdjustsContentInsets:), (IMP)sf_sv_set_autoInsets, "v@:B");
    if (!class_respondsToSelector(sv, @selector(magnification)))
        class_addMethod(sv, @selector(magnification), (IMP)sf_sv_get_mag, "d@:");
    if (!class_respondsToSelector(sv, @selector(setMagnification:)))
        class_addMethod(sv, @selector(setMagnification:), (IMP)sf_sv_set_mag, "v@:d");
    if (!class_respondsToSelector(sv, @selector(minMagnification)))
        class_addMethod(sv, @selector(minMagnification), (IMP)sf_sv_get_minMag, "d@:");
    if (!class_respondsToSelector(sv, @selector(setMinMagnification:)))
        class_addMethod(sv, @selector(setMinMagnification:), (IMP)sf_sv_noop_dbl, "v@:d");
    if (!class_respondsToSelector(sv, @selector(maxMagnification)))
        class_addMethod(sv, @selector(maxMagnification), (IMP)sf_sv_get_maxMag, "d@:");
    if (!class_respondsToSelector(sv, @selector(setMaxMagnification:)))
        class_addMethod(sv, @selector(setMaxMagnification:), (IMP)sf_sv_noop_dbl, "v@:d");
    if (!class_respondsToSelector(sv, @selector(setMagnification:centeredAtPoint:)))
        class_addMethod(sv, @selector(setMagnification:centeredAtPoint:), (IMP)sf_sv_set_mag_pt, "v@:d{CGPoint=dd}");
    if (!class_respondsToSelector(sv, @selector(magnifyToFitRect:)))
        class_addMethod(sv, @selector(magnifyToFitRect:), (IMP)sf_sv_mag_rect, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}");
    if (!class_respondsToSelector(sv, @selector(horizontalScrollElasticity)))
        class_addMethod(sv, @selector(horizontalScrollElasticity), (IMP)sf_sv_ret0, "q@:");
    if (!class_respondsToSelector(sv, @selector(setHorizontalScrollElasticity:)))
        class_addMethod(sv, @selector(setHorizontalScrollElasticity:), (IMP)sf_sv_noop_int, "v@:q");
    if (!class_respondsToSelector(sv, @selector(verticalScrollElasticity)))
        class_addMethod(sv, @selector(verticalScrollElasticity), (IMP)sf_sv_ret0, "q@:");
    if (!class_respondsToSelector(sv, @selector(setVerticalScrollElasticity:)))
        class_addMethod(sv, @selector(setVerticalScrollElasticity:), (IMP)sf_sv_noop_int, "v@:q");
    if (!class_respondsToSelector(sv, @selector(usesPredominantAxisScrolling)))
        class_addMethod(sv, @selector(usesPredominantAxisScrolling), (IMP)sf_sv_retNO, "B@:");
    if (!class_respondsToSelector(sv, @selector(setUsesPredominantAxisScrolling:)))
        class_addMethod(sv, @selector(setUsesPredominantAxisScrolling:), (IMP)sf_sv_noop_bool, "v@:B");
    if (!class_respondsToSelector(sv, @selector(findBarPosition)))
        class_addMethod(sv, @selector(findBarPosition), (IMP)sf_sv_ret0, "q@:");
    if (!class_respondsToSelector(sv, @selector(setFindBarPosition:)))
        class_addMethod(sv, @selector(setFindBarPosition:), (IMP)sf_sv_noop_int, "v@:q");
}

static char kSFSpRevealKey;
@interface NSSplitView : NSView
@end
@implementation NSSplitView (SFPreviewSplitCompat)
- (void)setHoldingPriority:(float)prio forSubviewAtIndex:(NSInteger)idx { (void)prio; (void)idx; }
- (NSInteger)_indexOfDividerForLocation:(NSPoint)loc andReturnFrame:(NSRect *)r {
    (void)loc;
    if (r) *r = NSZeroRect;
    return NSNotFound;
}
- (void)setRevealsOnEdgeHoverInFullscreen:(BOOL)f { objc_setAssociatedObject(self, &kSFSpRevealKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

static char kSFSegDistKey;
@interface NSSegmentedControl : NSControl
@end
@implementation NSSegmentedControl (SFPreviewSegCompat)
- (NSInteger)segmentDistribution { return [objc_getAssociatedObject(self, &kSFSegDistKey) integerValue]; }
- (void)setSegmentDistribution:(NSInteger)d { objc_setAssociatedObject(self, &kSFSegDistKey, @(d), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)setAlternateImage:(id)img forSegment:(NSInteger)seg { (void)img; (void)seg; }
- (BOOL)_wantsMenuIndicatorForSegment:(NSInteger)seg { (void)seg; return NO; }
- (NSRect)_rectForSegment:(NSInteger)seg inFrame:(NSRect)f { (void)seg; return f; }
- (void)_performClick:(id)sender onSegment:(NSInteger)seg ignoreMenus:(BOOL)ig { (void)sender; (void)seg; (void)ig; }
@end

@interface NSSegmentedCell : NSObject
@end
@implementation NSSegmentedCell (SFPreviewSegCellCompat)
- (NSInteger)segmentDistribution { return [objc_getAssociatedObject(self, &kSFSegDistKey) integerValue]; }
- (void)setSegmentDistribution:(NSInteger)d { objc_setAssociatedObject(self, &kSFSegDistKey, @(d), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)setAlternateImage:(id)img forSegment:(NSInteger)seg { (void)img; (void)seg; }
- (BOOL)_wantsMenuIndicatorForSegment:(NSInteger)seg { (void)seg; return NO; }
- (NSRect)_rectForSegment:(NSInteger)seg inFrame:(NSRect)f { (void)seg; return f; }
- (void)_performClick:(id)sender onSegment:(NSInteger)seg ignoreMenus:(BOOL)ig { (void)sender; (void)seg; (void)ig; }
@end

static char kSFTBNavKey;
@interface NSToolbarItem : NSObject
@end
@implementation NSToolbarItem (SFPreviewToolbarCompat)
- (BOOL)isNavigational { return [objc_getAssociatedObject(self, &kSFTBNavKey) boolValue]; }
- (void)setNavigational:(BOOL)f { objc_setAssociatedObject(self, &kSFTBNavKey, @(f), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

@implementation NSWindow (SFPreviewWindowCompat)
- (void)_disableFullScreenAutohiding {}
- (void)_enableFullScreenAutohiding {}
- (BOOL)_fullScreenTileFillsScreen { return NO; }
- (id)_windowForToolbar { return self; }
- (void)setAutomaticallyAdjustWindowPosition:(BOOL)f { (void)f; }
@end

@implementation NSApplication (SFPreviewAppCompat)
- (void)enumerateWindowsWithOptions:(NSUInteger)opts usingBlock:(void (^)(NSWindow *w, BOOL *stop))blk {
    (void)opts;
    if (!blk) return;
    NSArray *ws = nil;
    if ([self respondsToSelector:@selector(windows)]) ws = [self performSelector:@selector(windows)];
    BOOL stop = NO;
    for (NSWindow *w in ws) {
        blk(w, &stop);
        if (stop) break;
    }
}
- (BOOL)_hasForceCapableTouchDevice { return NO; }
- (BOOL)_inSendAction { return NO; }
- (void)_windowsDidShow {}
@end

@interface NSResponder : NSObject
@end
@implementation NSResponder (SFPreviewResponderCompat)
- (void)_encodeObjectIntoRestorableState:(id)obj forKey:(NSString *)key { (void)obj; (void)key; }
- (id)suggestedTouchBarIdentifier { return nil; }
- (id)groupTouchBar { return nil; }
- (void)setGroupTouchBar:(id)tb { (void)tb; }
@end

@interface NSTableView : NSView
@end
@implementation NSTableView (SFPreviewTableCompat)
- (void)setAllowsTypeSelect:(BOOL)f { (void)f; }
@end

@interface NSTextField : NSControl
@end
@implementation NSTextField (SFPreviewTFCompat)
- (id)textContentType { return nil; }
- (void)setTextContentType:(id)t { (void)t; }
- (void)setAutomaticTextCompletionEnabled:(BOOL)f { (void)f; }
@end

@interface NSImageView : NSControl
@end
@implementation NSImageView (SFPreviewIVCompat)
- (void)setPreferredDynamicRange:(NSInteger)r { (void)r; }
- (void)setAvailableHeadroom:(CGFloat)h { (void)h; }
@end

@implementation NSViewController (SFPreviewVCCompat)
- (void)presentViewControllerAsSheet:(NSViewController *)vc { (void)vc; }
- (void)dismissController:(id)sender { (void)sender; }
@end

@implementation NSView (SFPreviewViewCompat)
- (void)_setRowAlignmentsOptions:(id)o { (void)o; }
- (void)setPreferredDynamicRange:(NSInteger)r { (void)r; }
- (void)setAvailableHeadroom:(CGFloat)h { (void)h; }
@end

@interface NSFont : NSObject
+ (id)systemFontOfSize:(CGFloat)sz;
@end
@implementation NSFont (SFPreviewFontCompat)
+ (id)preferredFontForTextStyle:(NSString *)style addingSymbolicTraits:(uint32_t)traits {
    (void)style; (void)traits;
    return [self systemFontOfSize:13.0];
}
@end

@interface NSWindowController (SFPreviewWCCompat)
@end
@implementation NSWindowController (SFPreviewWCCompat)
- (void)setShouldCloseWithWindow:(BOOL)f { (void)f; }
@end

@implementation NSNumberFormatter (SFPreviewNFCompat)
- (void)setUsesGroupingSeparator:(BOOL)f { (void)f; }
- (void)setRoundingIncrement:(id)n { (void)n; }
- (void)setRoundingMode:(NSUInteger)m { (void)m; }
- (void)setFormatterBehavior:(NSUInteger)b { (void)b; }
- (void)setFormattingContext:(NSInteger)c { (void)c; }
- (void)setPartialStringValidationEnabled:(BOOL)f { (void)f; }
@end

@implementation NSDateFormatter (SFPreviewDFCompat)
- (void)setDoesRelativeDateFormatting:(BOOL)f { (void)f; }
@end

static id sf_pdfv_docScrollView(id self, SEL _cmd) {
    (void)_cmd;
    if ([self respondsToSelector:@selector(enclosingScrollView)]) {
        return ((id (*)(id, SEL))objc_msgSend)(self, @selector(enclosingScrollView));
    }
    return nil;
}
static void sf_pdfv_redrawTiles(id self, SEL _cmd) {
    (void)_cmd;
    if ([self respondsToSelector:@selector(setNeedsDisplay:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setNeedsDisplay:), YES);
    }
}
static void sf_pdfv_noopBool(id self, SEL _cmd, BOOL f) { (void)self; (void)_cmd; (void)f; }
static void sf_pdfv_noopId(id self, SEL _cmd, id o) { (void)self; (void)_cmd; (void)o; }
static void sf_pdfv_noopVoid(id self, SEL _cmd) { (void)self; (void)_cmd; }
static void sf_pdfv_noopIntId(id self, SEL _cmd, NSInteger i, id o) { (void)self; (void)_cmd; (void)i; (void)o; }
static BOOL sf_pdfv_retNO(id self, SEL _cmd) { (void)self; (void)_cmd; return NO; }
static CGFloat sf_pdfv_retOne(id self, SEL _cmd) { (void)self; (void)_cmd; return 1.0; }
static CGFloat sf_pdfv_thumbAspect(id self, SEL _cmd, id p) { (void)self; (void)_cmd; (void)p; return 0.77; }
static id sf_pdfv_viewForPage(id self, SEL _cmd, id p) { (void)_cmd; (void)p; return self; }
static void sf_pdfv_drawPage(id self, SEL _cmd, id page, NSRect r, void *ctx) {
    (void)self; (void)_cmd; (void)r;
    if (page && [page respondsToSelector:@selector(drawWithBox:toContext:)]) {
        ((void (*)(id, SEL, NSInteger, void *))objc_msgSend)(page, @selector(drawWithBox:toContext:), 1, ctx);
    }
}
static void sf_pdfv_genThumb(id self, SEL _cmd, id page, NSSize sz, void (^cb)(id)) {
    (void)self; (void)_cmd; (void)page; (void)sz;
    if (cb) cb(nil);
}
static void sf_pdfp_drawThumb(id self, SEL _cmd, NSInteger box, void *ctx, BOOL thumb) {
    (void)_cmd; (void)thumb;
    if ([self respondsToSelector:@selector(drawWithBox:toContext:)]) {
        ((void (*)(id, SEL, NSInteger, void *))objc_msgSend)(self, @selector(drawWithBox:toContext:), box, ctx);
    }
}
static id sf_pdfd_firstPage(id self, SEL _cmd) {
    (void)_cmd;
    if ([self respondsToSelector:@selector(pageCount)] && ((NSUInteger (*)(id, SEL))objc_msgSend)(self, @selector(pageCount)) > 0) {
        return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(self, @selector(pageAtIndex:), 0);
    }
    return nil;
}
static id sf_pdfd_lastPage(id self, SEL _cmd) {
    (void)_cmd;
    if ([self respondsToSelector:@selector(pageCount)]) {
        NSUInteger c = ((NSUInteger (*)(id, SEL))objc_msgSend)(self, @selector(pageCount));
        if (c > 0) return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(self, @selector(pageAtIndex:), c - 1);
    }
    return nil;
}
static id sf_pdfd_retNil(id self, SEL _cmd) { (void)self; (void)_cmd; return nil; }
static id sf_pdfd_findOcc(id self, SEL _cmd, id s, id p, NSUInteger o) { (void)self; (void)_cmd; (void)s; (void)p; (void)o; return @[]; }
static void sf_pdfd_asyncFind(id self, SEL _cmd, id ss, NSUInteger o, id d, id q) { (void)self; (void)_cmd; (void)ss; (void)o; (void)d; (void)q; }

__attribute__((constructor))
static void sf_install_more_pdfkit_compat(void) {
    Class pdfv = objc_lookUpClass("PDFView");
    if (pdfv) {
        class_addMethod(pdfv, @selector(documentScrollView), (IMP)sf_pdfv_docScrollView, "@@:");
        class_addMethod(pdfv, @selector(redrawTiles), (IMP)sf_pdfv_redrawTiles, "v@:");
        class_addMethod(pdfv, @selector(set_wantsFormFieldDetection:), (IMP)sf_pdfv_noopBool, "v@:B");
        class_addMethod(pdfv, @selector(setInFormFillingMode:), (IMP)sf_pdfv_noopBool, "v@:B");
        class_addMethod(pdfv, @selector(setEnableRemotePreviews:), (IMP)sf_pdfv_noopBool, "v@:B");
        class_addMethod(pdfv, @selector(autoZooms), (IMP)sf_pdfv_retNO, "B@:");
        class_addMethod(pdfv, @selector(setAutoZooms:), (IMP)sf_pdfv_noopBool, "v@:B");
        class_addMethod(pdfv, @selector(stickyZoomToFit), (IMP)sf_pdfv_retNO, "B@:");
        class_addMethod(pdfv, @selector(setStickyZoomToFit:), (IMP)sf_pdfv_noopBool, "v@:B");
        class_addMethod(pdfv, @selector(zoomToFitScaleFactor), (IMP)sf_pdfv_retOne, "d@:");
        class_addMethod(pdfv, @selector(viewForPage:), (IMP)sf_pdfv_viewForPage, "@@:@");
        class_addMethod(pdfv, @selector(drawPage:inRect:context:), (IMP)sf_pdfv_drawPage, "v@:@{CGRect={CGPoint=dd}{CGSize=dd}}^v");
        class_addMethod(pdfv, @selector(setFocusedOccurrenceIndex:inPage:), (IMP)sf_pdfv_noopIntId, "v@:q@");
        class_addMethod(pdfv, @selector(setHighlightedOccurrences:), (IMP)sf_pdfv_noopId, "v@:@");
        class_addMethod(pdfv, @selector(supportsFormFill), (IMP)sf_pdfv_retNO, "B@:");
        class_addMethod(pdfv, @selector(updateBookmarksInPDFDocument), (IMP)sf_pdfv_noopVoid, "v@:");
        class_addMethod(pdfv, @selector(thumbnailAspectRatioForPage:), (IMP)sf_pdfv_thumbAspect, "d@:@");
        class_addMethod(pdfv, @selector(generateThumbnailForPage:maxSize:completionBlock:), (IMP)sf_pdfv_genThumb, "v@:@{CGSize=dd}@?");
    }
    Class pdfp = objc_lookUpClass("PDFPage");
    if (pdfp) {
        class_addMethod(pdfp, @selector(setBookmarked:), (IMP)sf_pdfv_noopBool, "v@:B");
        class_addMethod(pdfp, @selector(drawWithBox:inContext:isThumbnail:), (IMP)sf_pdfp_drawThumb, "v@:q^vB");
    }
    Class pdfd = objc_lookUpClass("PDFDocument");
    if (pdfd) {
        class_addMethod(pdfd, @selector(firstPage), (IMP)sf_pdfd_firstPage, "@@:");
        class_addMethod(pdfd, @selector(lastPage), (IMP)sf_pdfd_lastPage, "@@:");
        class_addMethod(pdfd, @selector(userPassword), (IMP)sf_pdfd_retNil, "@@:");
        class_addMethod(pdfd, @selector(selectionForAll), (IMP)sf_pdfd_retNil, "@@:");
        class_addMethod(pdfd, @selector(findOccurrencesOfString:inPage:withOptions:), (IMP)sf_pdfd_findOcc, "@@:@@Q");
        class_addMethod(pdfd, @selector(asyncFindStrings:withOptions:withDelegate:onQueue:), (IMP)sf_pdfd_asyncFind, "v@:@Q@@");
    }
}

@implementation NSCollectionView (SFPreviewBGColor)
- (void)setBackgroundColor:(id)c {
    if (c && [c respondsToSelector:@selector(alphaComponent)]) {
        CGFloat a = ((CGFloat (*)(id, SEL))objc_msgSend)(c, @selector(alphaComponent));
        if (a < 0.05) {
            /* Replace clearColor with macOS Light Mode opaque sidebar surface so SHM window never punches transparent holes */
            c = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
                (id)objc_getClass("NSColor"), @selector(colorWithCalibratedRed:green:blue:alpha:),
                0.933, 0.933, 0.945, 1.0);
        }
    }
    if ([self respondsToSelector:@selector(setBackgroundColors:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setBackgroundColors:), c ? @[c] : @[]);
    }
}
- (id)backgroundColor {
    if ([self respondsToSelector:@selector(backgroundColors)]) {
        NSArray *cs = ((id (*)(id, SEL))objc_msgSend)(self, @selector(backgroundColors));
        return [cs firstObject];
    }
    return nil;
}
@end

static char kSFCVRowAlignKey;
@implementation NSCollectionViewFlowLayout (SFPreviewRowAlign)
- (void)_setRowAlignmentsOptions:(id)opts { objc_setAssociatedObject(self, &kSFCVRowAlignKey, opts, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)_rowAlignmentsOptions { return objc_getAssociatedObject(self, &kSFCVRowAlignKey); }
- (NSRect)_frameForSectionAtIndex:(NSUInteger)idx { (void)idx; return NSZeroRect; }
@end

@interface NSClipView : NSView
- (id)documentView;
- (NSRect)documentRect;
@end
@implementation NSClipView (SFPreviewClipCompat)
- (NSRect)constrainBoundsRect:(NSRect)proposedBounds {
    if ([self respondsToSelector:@selector(documentRect)]) {
        NSRect doc = [self documentRect];
        if (doc.size.width > 0 && doc.size.height > 0) {
            if (proposedBounds.origin.x + proposedBounds.size.width > doc.origin.x + doc.size.width)
                proposedBounds.origin.x = doc.origin.x + doc.size.width - proposedBounds.size.width;
            if (proposedBounds.origin.x < doc.origin.x)
                proposedBounds.origin.x = doc.origin.x;
            if (proposedBounds.origin.y + proposedBounds.size.height > doc.origin.y + doc.size.height)
                proposedBounds.origin.y = doc.origin.y + doc.size.height - proposedBounds.size.height;
            if (proposedBounds.origin.y < doc.origin.y)
                proposedBounds.origin.y = doc.origin.y;
        }
    }
    return proposedBounds;
}
- (NSPoint)constrainedScrollToPoint:(NSPoint)pt {
    NSRect b = [self bounds];
    b.origin = pt;
    return [self constrainBoundsRect:b].origin;
}
@end

@implementation NSMutableParagraphStyle (SFPreviewCoreTextCompat)
- (void)setHorizontalAlignment:(NSInteger)a { (void)a; }
- (void)setFullyJustified:(BOOL)f { (void)f; }
- (void)setSpansAllLines:(BOOL)f { (void)f; }
- (void)setSecondaryLineBreakMode:(NSInteger)m { (void)m; }
- (void)setCompositionLanguage:(NSInteger)l { (void)l; }
@end

@implementation NSAttributedString (SFPreviewCoreTextCompat)
- (BOOL)isEmptyOrTerminatedByParagraphSeparator {
    NSString *s = [self string];
    if (!s || [s length] == 0) return YES;
    unichar c = [s characterAtIndex:[s length] - 1];
    return (c == '\n' || c == '\r' || c == 0x2029);
}
@end

@implementation NSSplitViewController (SFPreviewSplitDelegate)
- (void)splitViewWillResizeSubviews:(NSNotification *)n { (void)n; }
- (void)splitViewDidResizeSubviews:(NSNotification *)n { (void)n; }
- (BOOL)splitView:(id)sv canCollapseSubview:(NSView *)sub { (void)sv; (void)sub; return NO; }
- (BOOL)splitView:(id)sv shouldCollapseSubview:(NSView *)sub forDoubleClickOnDividerAtIndex:(NSInteger)i { (void)sv; (void)sub; (void)i; return NO; }
- (BOOL)splitView:(id)sv shouldAdjustSizeOfSubview:(NSView *)sub { (void)sv; (void)sub; return YES; }
- (BOOL)splitView:(id)sv shouldHideDividerAtIndex:(NSInteger)i { (void)sv; (void)i; return NO; }
- (NSRect)splitView:(id)sv effectiveRect:(NSRect)pr forDrawnRect:(NSRect)dr ofDividerAtIndex:(NSInteger)i { (void)sv; (void)dr; (void)i; return pr; }
- (NSRect)splitView:(id)sv additionalEffectiveRectOfDividerAtIndex:(NSInteger)i { (void)sv; (void)i; return NSZeroRect; }
@end

static char kSFWinIdentKey;
@implementation NSWindow (SFPreviewIdent)
- (NSString *)identifier { return objc_getAssociatedObject(self, &kSFWinIdentKey); }
- (void)setIdentifier:(NSString *)ident { objc_setAssociatedObject(self, &kSFWinIdentKey, ident, OBJC_ASSOCIATION_COPY_NONATOMIC); }
@end

@interface NSDocument : NSObject
@end
@implementation NSDocument (SFPreviewDocWindowsDidShow)
- (void)_windowsDidShow {}
@end

static id sf_pdfp_imageOfSize(id self, SEL _cmd, NSSize sz, NSInteger box, id opts) {
    (void)_cmd; (void)opts;
    if ([self respondsToSelector:@selector(thumbnailOfSize:forBox:)]) {
        return ((id (*)(id, SEL, NSSize, NSInteger))objc_msgSend)(self, @selector(thumbnailOfSize:forBox:), sz, box);
    }
    Class imgCls = objc_lookUpClass("NSImage");
    if (!imgCls) return nil;
    if (sz.width <= 0) sz.width = 128;
    if (sz.height <= 0) sz.height = 166;
    id img = [((id (*)(id, SEL, NSSize))objc_msgSend)([imgCls alloc], @selector(initWithSize:), sz) autorelease];
    return img;
}
__attribute__((constructor))
static void sf_install_pdfpage_imageOfSize(void) {
    Class pdfp = objc_lookUpClass("PDFPage");
    if (pdfp) {
        class_addMethod(pdfp, @selector(imageOfSize:forBox:withOptions:), (IMP)sf_pdfp_imageOfSize, "@@:{CGSize=dd}q@");
    }
}

#include <pthread.h>
static pthread_mutex_t g_sf_pdf_draw_lock;
static pthread_once_t g_sf_pdf_draw_once = PTHREAD_ONCE_INIT;
static void (*g_orig_pdfp_draw)(id, SEL, NSInteger, void *) = NULL;
static void sf_pdf_draw_lock_init(void) {
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&g_sf_pdf_draw_lock, &a);
    pthread_mutexattr_destroy(&a);
}
static void sf_pdfp_draw_serialized(id self, SEL _cmd, NSInteger box, void *ctx) {
    pthread_once(&g_sf_pdf_draw_once, sf_pdf_draw_lock_init);
    pthread_mutex_lock(&g_sf_pdf_draw_lock);
    if (g_orig_pdfp_draw) g_orig_pdfp_draw(self, _cmd, box, ctx);
    pthread_mutex_unlock(&g_sf_pdf_draw_lock);
}
__attribute__((constructor))
static void sf_install_pdfpage_draw_lock(void) {
    Class pdfp = objc_lookUpClass("PDFPage");
    if (!pdfp) return;
    Method m = class_getInstanceMethod(pdfp, @selector(drawWithBox:toContext:));
    if (m) g_orig_pdfp_draw = (void (*)(id, SEL, NSInteger, void *))method_setImplementation(m, (IMP)sf_pdfp_draw_serialized);
}

static char kSFImgA11yDescKey, kSFImgAlignRectKey, kSFImgCapInsetsKey, kSFImgResizeModeKey;
@implementation NSImage (SFPreviewA11yAndCompat)
- (NSString *)accessibilityDescription { return objc_getAssociatedObject(self, &kSFImgA11yDescKey); }
- (void)setAccessibilityDescription:(NSString *)desc { objc_setAssociatedObject(self, &kSFImgA11yDescKey, desc, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (id)imageWithSymbolConfiguration:(id)cfg { (void)cfg; return self; }
- (CGFloat)recommendedLayerContentsScale:(CGFloat)preferredScale { return preferredScale > 0 ? preferredScale : 2.0; }
- (id)layerContentsForContentsScale:(CGFloat)scale { (void)scale; return self; }
- (NSRect)alignmentRect {
    NSValue *v = objc_getAssociatedObject(self, &kSFImgAlignRectKey);
    if (v) return [v rectValue];
    NSSize sz = [self respondsToSelector:@selector(size)] ? ((NSSize (*)(id, SEL))objc_msgSend)(self, @selector(size)) : NSZeroSize;
    return NSMakeRect(0, 0, sz.width, sz.height);
}
- (void)setAlignmentRect:(NSRect)r { objc_setAssociatedObject(self, &kSFImgAlignRectKey, [NSValue valueWithRect:r], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSInteger)resizingMode { return [objc_getAssociatedObject(self, &kSFImgResizeModeKey) integerValue]; }
- (void)setResizingMode:(NSInteger)m { objc_setAssociatedObject(self, &kSFImgResizeModeKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

@implementation NSImage (SFSwiftUIImageCompat)
- (NSString *)_defaultAccessibilityDescription { return [self accessibilityDescription]; }
- (id)symbolConfiguration { return nil; }
- (BOOL)matchesOnMultipleResolution { return NO; }
- (void)setMatchesOnMultipleResolution:(BOOL)f { (void)f; }
@end

/* Ensure [view setWantsLayer:YES] immediately creates a backing CALayer so SwiftUI's view.layer! never traps on nil */
static void (*g_orig_setWantsLayer)(id, SEL, BOOL) = NULL;
static void sf_nsview_setWantsLayer(id self, SEL _cmd, BOOL flag) {
    if (g_orig_setWantsLayer) g_orig_setWantsLayer(self, _cmd, flag);
    if (flag && [self respondsToSelector:@selector(layer)] && [self respondsToSelector:@selector(setLayer:)]) {
        id l = ((id (*)(id, SEL))objc_msgSend)(self, @selector(layer));
        if (!l) {
            if ([self respondsToSelector:@selector(makeBackingLayer)]) {
                l = ((id (*)(id, SEL))objc_msgSend)(self, @selector(makeBackingLayer));
            }
            if (!l) {
                Class ca = objc_lookUpClass("CALayer");
                if (ca) l = ((id (*)(id, SEL))objc_msgSend)((id)ca, @selector(layer));
            }
            if (l) ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setLayer:), l);
        }
    }
}
__attribute__((constructor))
static void sf_install_setWantsLayer_fix(void) {
    Class c = objc_lookUpClass("NSView");
    if (!c) return;
    Method m = class_getInstanceMethod(c, @selector(setWantsLayer:));
    if (m) g_orig_setWantsLayer = (void (*)(id, SEL, BOOL))method_setImplementation(m, (IMP)sf_nsview_setWantsLayer);
}


#include <dlfcn.h>
typedef void (*sf_cg_ctx_fn)(void *);
typedef void (*sf_cg_rect_fn)(void *, NSRect);
typedef void (*sf_cg_img_fn)(void *, NSRect, void *);
typedef void (*sf_cg_col_fn)(void *, void *);
typedef void (*sf_cg_f1_fn)(void *, CGFloat);
typedef void (*sf_cg_f2_fn)(void *, CGFloat, CGFloat);
typedef struct { CGFloat a, b, c, d, tx, ty; } SF_CGAffineTransform;
typedef void (*sf_cg_ctm_fn)(void *, SF_CGAffineTransform);

static void (*g_orig_drawLayerContext)(id, SEL) = NULL;
static void sf_add_rounded_rect(void *port, NSRect r, CGFloat rad,
                                void (*fn_begin)(void *), void (*fn_move)(void *, CGFloat, CGFloat),
                                void (*fn_line)(void *, CGFloat, CGFloat), void (*fn_close)(void *)) {
    if (rad <= 0.5) return;
    if (rad > r.size.width * 0.5) rad = r.size.width * 0.5;
    if (rad > r.size.height * 0.5) rad = r.size.height * 0.5;
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = r.origin.x + r.size.width, y1 = r.origin.y + r.size.height;
    fn_begin(port);
    const int steps = 8;
    /* 4 corners clockwise */
    CGFloat cx[4] = { x1 - rad, x1 - rad, x0 + rad, x0 + rad };
    CGFloat cy[4] = { y0 + rad, y1 - rad, y1 - rad, y0 + rad };
    CGFloat a0[4] = { -1.5707963, 0.0, 1.5707963, 3.14159265 };
    int first = 1;
    for (int c = 0; c < 4; c++) {
        for (int s = 0; s <= steps; s++) {
            double ang = a0[c] + (1.5707963 * s) / steps;
            CGFloat px = cx[c] + rad * cos(ang);
            CGFloat py = cy[c] + rad * sin(ang);
            if (first) { fn_move(port, px, py); first = 0; }
            else fn_line(port, px, py);
        }
    }
    fn_close(port);
}

static void sf_nsview_drawLayerContext(id self, SEL _cmd) {
    if (g_orig_drawLayerContext) g_orig_drawLayerContext(self, _cmd);
    if (![self respondsToSelector:@selector(layer)] || ![self respondsToSelector:@selector(window)]) return;
    id layer = ((id (*)(id, SEL))objc_msgSend)(self, @selector(layer));
    id win = ((id (*)(id, SEL))objc_msgSend)(self, @selector(window));
    if (!layer || !win) return;
    Ivar lcIv = class_getInstanceVariable(objc_getClass("NSView"), "_layerContext");
    if (lcIv && object_getIvar(self, lcIv) != nil) return;
    if ([layer respondsToSelector:@selector(isHidden)] && ((BOOL (*)(id, SEL))objc_msgSend)(layer, @selector(isHidden))) return;

    const char *lcls = object_getClassName(layer);
    BOOL isBacking = (lcls && strcmp(lcls, "NSViewBackingLayer") == 0);
    BOOL isCGDrawing = (lcls && strstr(lcls, "CGDrawingLayer") != NULL);
    BOOL isCustomLayer = (lcls && strcmp(lcls, "CALayer") != 0 && !isBacking);

    id contents = [layer respondsToSelector:@selector(contents)] ? ((id (*)(id, SEL))objc_msgSend)(layer, @selector(contents)) : nil;
    /* Never fill default NSViewBackingLayer backgroundColor (covers SwiftUI sibling views like page numbers & button labels) */
    void *bg = (!isBacking && [layer respondsToSelector:@selector(backgroundColor)]) ? ((void *(*)(id, SEL))objc_msgSend)(layer, @selector(backgroundColor)) : NULL;
    if (!contents && !bg && !isCustomLayer) return;

    id wc = [win respondsToSelector:@selector(graphicsContext)] ? ((id (*)(id, SEL))objc_msgSend)(win, @selector(graphicsContext)) : nil;
    if (!wc || ![wc respondsToSelector:@selector(graphicsPort)]) return;
    void *port = ((void *(*)(id, SEL))objc_msgSend)(wc, @selector(graphicsPort));
    if (!port) return;

    static sf_cg_ctx_fn fn_save, fn_restore, fn_resetclip, fn_begin, fn_close, fn_fillpath;
    static sf_cg_rect_fn fn_clip, fn_fill;
    static sf_cg_img_fn fn_drawimg;
    static sf_cg_col_fn fn_setfill;
    static sf_cg_f1_fn fn_alpha;
    static sf_cg_f2_fn fn_trans, fn_scale, fn_move, fn_line;
    static sf_cg_ctm_fn fn_setctm;
    static int resolved = 0;
    if (!resolved) {
        resolved = 1;
        fn_save = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextSaveGState");
        fn_restore = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextRestoreGState");
        fn_resetclip = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextResetClip");
        fn_begin = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextBeginPath");
        fn_close = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextClosePath");
        fn_fillpath = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextFillPath");
        fn_clip = (sf_cg_rect_fn)dlsym(RTLD_DEFAULT, "CGContextClipToRect");
        fn_fill = (sf_cg_rect_fn)dlsym(RTLD_DEFAULT, "CGContextFillRect");
        fn_drawimg = (sf_cg_img_fn)dlsym(RTLD_DEFAULT, "CGContextDrawImage");
        fn_setfill = (sf_cg_col_fn)dlsym(RTLD_DEFAULT, "CGContextSetFillColorWithColor");
        fn_alpha = (sf_cg_f1_fn)dlsym(RTLD_DEFAULT, "CGContextSetAlpha");
        fn_trans = (sf_cg_f2_fn)dlsym(RTLD_DEFAULT, "CGContextTranslateCTM");
        fn_scale = (sf_cg_f2_fn)dlsym(RTLD_DEFAULT, "CGContextScaleCTM");
        fn_move = (sf_cg_f2_fn)dlsym(RTLD_DEFAULT, "CGContextMoveToPoint");
        fn_line = (sf_cg_f2_fn)dlsym(RTLD_DEFAULT, "CGContextAddLineToPoint");
        fn_setctm = (sf_cg_ctm_fn)dlsym(RTLD_DEFAULT, "CGContextSetCTM");
    }
    if (!fn_save || !fn_restore || !fn_drawimg) return;
    NSRect bounds = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
    NSRect vis = [self respondsToSelector:@selector(visibleRect)] ? ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(visibleRect)) : bounds;
    if (NSIsEmptyRect(vis)) return;
    if ([win respondsToSelector:@selector(_addDamage:)] && [self respondsToSelector:@selector(convertRect:toView:)]) {
        NSRect dmg = ((NSRect (*)(id, SEL, NSRect, id))objc_msgSend)(self, @selector(convertRect:toView:), vis, nil);
        ((void (*)(id, SEL, NSRect))objc_msgSend)(win, @selector(_addDamage:), dmg);
    }
    fn_save(port);
    if (fn_resetclip) fn_resetclip(port);
    if (fn_setctm && [self respondsToSelector:@selector(transformToWindow)]) {
        SF_CGAffineTransform xform = ((SF_CGAffineTransform (*)(id, SEL))objc_msgSend)(self, @selector(transformToWindow));
        fn_setctm(port, xform);
    }
    if (fn_clip) fn_clip(port, vis);
    float op = [layer respondsToSelector:@selector(opacity)] ? ((float (*)(id, SEL))objc_msgSend)(layer, @selector(opacity)) : 1.0f;
    if (op < 0.999f && fn_alpha) fn_alpha(port, op);

    if (getenv("SF_DUMP_VIEWS") && bounds.size.width > 115 && bounds.size.width < 125 && bounds.size.height > 12 && bounds.size.height < 18) {
        fprintf(stderr, "SF_120x15_LAYER view=%s layer=%s bg=%p contents=%p\n", object_getClassName(self), lcls ? lcls : "nil", bg, (void*)contents);
    }
    if (bg && fn_setfill && fn_fill) {
        const char *vcls = object_getClassName(self);
        if (vcls && strstr(vcls, "_NSShapeHitTestingView") != NULL &&
            bounds.size.width > 140.0 && bounds.size.width < 200.0 && bounds.size.height > 125.0) {
            /* macOS Preview subtle grey rounded highlight wrapping the thumbnail cleanly with breathing room above the page number */
            typedef void (*sf_rgba_f)(void *, CGFloat, CGFloat, CGFloat, CGFloat);
            typedef void (*sf_lw_f)(void *, CGFloat);
            static sf_rgba_f f_fr, f_sr; static sf_lw_f f_lw; static sf_cg_ctx_fn f_sp;
            if (!f_fr) {
                f_fr = (sf_rgba_f)dlsym(RTLD_DEFAULT, "CGContextSetRGBFillColor");
                f_sr = (sf_rgba_f)dlsym(RTLD_DEFAULT, "CGContextSetRGBStrokeColor");
                f_lw = (sf_lw_f)dlsym(RTLD_DEFAULT, "CGContextSetLineWidth");
                f_sp = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextStrokePath");
            }
            /* Clear full selection view bounds to sidebar surface first so no heavy blue bleed remains */
            NSRect pill = NSMakeRect(bounds.origin.x + 1.0, bounds.origin.y + 1.0,
                                     bounds.size.width - 2.0, bounds.size.height - 2.0);
            if (f_fr && fn_fill && fn_begin && fn_move && fn_line && fn_close && fn_fillpath) {
                f_fr(port, 0.933, 0.933, 0.945, 1.0);
                fn_fill(port, bounds);
                /* Subtle macOS Preview grey rounded highlight wrapping thumbnail + page number cleanly */
                f_fr(port, 0.847, 0.855, 0.875, 1.0);
                sf_add_rounded_rect(port, pill, 8.0, fn_begin, fn_move, fn_line, fn_close);
                fn_fillpath(port);
                if (f_sr && f_lw && f_sp) {
                    f_sr(port, 0.0, 0.0, 0.0, 0.09);
                    f_lw(port, 1.0);
                    sf_add_rounded_rect(port, NSMakeRect(pill.origin.x + 0.5, pill.origin.y + 0.5, pill.size.width - 1.0, pill.size.height - 1.0),
                                        8.0, fn_begin, fn_move, fn_line, fn_close);
                    f_sp(port);
                }
            }
        } else {
            CGFloat rad = [layer respondsToSelector:@selector(cornerRadius)] ? ((CGFloat (*)(id, SEL))objc_msgSend)(layer, @selector(cornerRadius)) : 0.0;
            fn_setfill(port, bg);
            if (rad > 0.5 && fn_begin && fn_move && fn_line && fn_close && fn_fillpath) {
                sf_add_rounded_rect(port, bounds, rad, fn_begin, fn_move, fn_line, fn_close);
                fn_fillpath(port);
            } else {
                fn_fill(port, bounds);
            }
        }
    }

    Class o2img = objc_lookUpClass("O2Image");
    if (isCGDrawing && [layer respondsToSelector:@selector(drawInContext:)]) {
        /* Restore window CTM, then use [self lockFocus] so [NSView focusView] is self (flipped=YES!)
         * which NSStringDrawer / NSLayoutManager relies on for crisp, unclipped SwiftUI Text baselines! */
        fn_restore(port);
        /* Give sidebar page numbers (small CGDrawingViews at y>=125) clean 3pt clearance below the thumbnail highlight */
        NSRect cgFrame = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(frame));
        if (cgFrame.origin.y >= 125.0 && cgFrame.size.width <= 30.0 && cgFrame.size.height <= 18.0 && cgFrame.origin.y < 130.0) {
            cgFrame.origin.y = 131.0;
            ((void (*)(id, SEL, NSRect))objc_msgSend)(self, @selector(setFrame:), cgFrame);
        }
        if ([self respondsToSelector:@selector(lockFocusIfCanDraw)] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(lockFocusIfCanDraw))) {
            id curGC = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSGraphicsContext"), @selector(currentContext));
            void *curPort = (curGC && [curGC respondsToSelector:@selector(graphicsPort)]) ?
                ((void *(*)(id, SEL))objc_msgSend)(curGC, @selector(graphicsPort)) : port;
            ((void (*)(id, SEL, void *))objc_msgSend)(layer, @selector(drawInContext:), curPort);
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(unlockFocus));
        }
        return;
    } else if (contents && o2img && [contents isKindOfClass:o2img]) {
        BOOL flipped = [self respondsToSelector:@selector(isFlipped)] ? ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isFlipped)) : NO;
        fn_save(port);
        if (flipped && fn_trans && fn_scale) {
            fn_trans(port, 0, NSMaxY(bounds) + NSMinY(bounds));
            fn_scale(port, 1.0, -1.0);
        }
        fn_drawimg(port, bounds, (void *)contents);
        fn_restore(port);
        if (lcls && strstr(lcls, "ImageLayer") != NULL && bounds.size.width > 40.0 && bounds.size.height > 40.0) {
            typedef void (*sf_rgba_f)(void *, CGFloat, CGFloat, CGFloat, CGFloat);
            typedef void (*sf_lw_f)(void *, CGFloat);
            typedef void (*sf_sr_f)(void *, NSRect);
            static sf_rgba_f f_sr; static sf_lw_f f_lw; static sf_sr_f f_srect;
            if (!f_sr) {
                f_sr = (sf_rgba_f)dlsym(RTLD_DEFAULT, "CGContextSetRGBStrokeColor");
                f_lw = (sf_lw_f)dlsym(RTLD_DEFAULT, "CGContextSetLineWidth");
                f_srect = (sf_sr_f)dlsym(RTLD_DEFAULT, "CGContextStrokeRect");
            }
            if (f_sr && f_lw && f_srect) {
                fn_save(port);
                f_sr(port, 0.0, 0.0, 0.0, 0.14);
                f_lw(port, 1.0);
                f_srect(port, NSMakeRect(bounds.origin.x + 0.5, bounds.origin.y + 0.5, bounds.size.width - 1.0, bounds.size.height - 1.0));
                fn_restore(port);
            }
        }
    } else if (isCustomLayer && [layer respondsToSelector:@selector(drawInContext:)]) {
        fn_save(port);
        ((void (*)(id, SEL, void *))objc_msgSend)(layer, @selector(drawInContext:), port);
        fn_restore(port);
    }
    fn_restore(port);
}
__attribute__((constructor))
static void sf_install_cpu_layer_draw(void) {
    Class c = objc_lookUpClass("NSView");
    if (!c) return;
    Method m = class_getInstanceMethod(c, @selector(_drawLayerContext));
    if (m) g_orig_drawLayerContext = (void (*)(id, SEL))method_setImplementation(m, (IMP)sf_nsview_drawLayerContext);
}

static void sf_dump_layer(id l, int depth) {
    if (!l || depth > 8) return;
    NSRect f = [l respondsToSelector:@selector(frame)] ? ((NSRect (*)(id, SEL))objc_msgSend)(l, @selector(frame)) : NSZeroRect;
    id c = [l respondsToSelector:@selector(contents)] ? ((id (*)(id, SEL))objc_msgSend)(l, @selector(contents)) : nil;
    NSArray *subs = [l respondsToSelector:@selector(sublayers)] ? ((id (*)(id, SEL))objc_msgSend)(l, @selector(sublayers)) : nil;
    fprintf(stderr, "%*sL %s f=(%.0f,%.0f %.0fx%.0f) contents=%s subs=%lu\n",
            depth * 2, "", object_getClassName(l), f.origin.x, f.origin.y, f.size.width, f.size.height,
            c ? object_getClassName(c) : "nil", (unsigned long)[subs count]);
    for (id sl in subs) sf_dump_layer(sl, depth + 1);
}
static void sf_dump_view(id v, int depth) {
    if (!v || depth > 12) return;
    NSRect f = [v respondsToSelector:@selector(frame)] ? ((NSRect (*)(id, SEL))objc_msgSend)(v, @selector(frame)) : NSZeroRect;
    BOOL h = [v respondsToSelector:@selector(isHidden)] ? ((BOOL (*)(id, SEL))objc_msgSend)(v, @selector(isHidden)) : NO;
    id l = [v respondsToSelector:@selector(layer)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(layer)) : nil;
    id c = (l && [l respondsToSelector:@selector(contents)]) ? ((id (*)(id, SEL))objc_msgSend)(l, @selector(contents)) : nil;
    NSArray *lsubs = (l && [l respondsToSelector:@selector(sublayers)]) ? ((id (*)(id, SEL))objc_msgSend)(l, @selector(sublayers)) : nil;
    if (strcmp(object_getClassName(v), "PVPDFView") == 0) {
        id doc = [v respondsToSelector:@selector(document)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(document)) : nil;
        NSUInteger pc = (doc && [doc respondsToSelector:@selector(pageCount)]) ? ((NSUInteger (*)(id, SEL))objc_msgSend)(doc, @selector(pageCount)) : 0;
        CGFloat sc = [v respondsToSelector:@selector(scaleFactor)] ? ((CGFloat (*)(id, SEL))objc_msgSend)(v, @selector(scaleFactor)) : -1;
        NSInteger dm = [v respondsToSelector:@selector(displayMode)] ? ((NSInteger (*)(id, SEL))objc_msgSend)(v, @selector(displayMode)) : -1;
        id bg = [v respondsToSelector:@selector(backgroundColor)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(backgroundColor)) : nil;
        fprintf(stderr, "  >>> PVPDFView doc=%p pages=%lu scale=%.3f mode=%ld bg=%s\n", (void*)doc, (unsigned long)pc, sc, (long)dm, bg ? [[bg description] UTF8String] : "nil");
    }
    fprintf(stderr, "%*sV %s f=(%.0f,%.0f %.0fx%.0f) hid=%d layer=%s(c=%s,ls=%lu)\n",
            depth * 2, "", object_getClassName(v), f.origin.x, f.origin.y, f.size.width, f.size.height, (int)h,
            l ? object_getClassName(l) : "nil", c ? object_getClassName(c) : "nil", (unsigned long)[lsubs count]);
    NSArray *subs = [v respondsToSelector:@selector(subviews)] ? ((id (*)(id, SEL))objc_msgSend)(v, @selector(subviews)) : nil;
    if (strstr(object_getClassName(v), "SidebarView") != NULL && l) sf_dump_layer(l, depth + 1);
    for (id sv in subs) sf_dump_view(sv, depth + 1);
}
__attribute__((constructor))
static void sf_install_view_dumper(void) {
    if (!getenv("SF_DUMP_VIEWS")) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2500000000LL)), dispatch_get_main_queue(), ^{
        id app = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSApplication"), @selector(sharedApplication));
        NSArray *ws = [app respondsToSelector:@selector(windows)] ? ((id (*)(id, SEL))objc_msgSend)(app, @selector(windows)) : nil;
        fprintf(stderr, "=== SF_DUMP_VIEWS windows=%lu ===\n", (unsigned long)[ws count]);
        for (id w in ws) {
            NSRect wf = [w respondsToSelector:@selector(frame)] ? ((NSRect (*)(id, SEL))objc_msgSend)(w, @selector(frame)) : NSZeroRect;
            NSString *t = [w respondsToSelector:@selector(title)] ? ((id (*)(id, SEL))objc_msgSend)(w, @selector(title)) : nil;
            fprintf(stderr, "WIN %s title='%s' f=(%.0f,%.0f %.0fx%.0f)\n",
                    object_getClassName(w), t ? [t UTF8String] : "", wf.origin.x, wf.origin.y, wf.size.width, wf.size.height);
            id cv = [w respondsToSelector:@selector(contentView)] ? ((id (*)(id, SEL))objc_msgSend)(w, @selector(contentView)) : nil;
            if (cv) sf_dump_view(cv, 1);
            /* Inspect PVPDFView if present */
            Class pvCls = objc_lookUpClass("PVPDFView");
            if (pvCls) {
                IMP pvDraw = class_getMethodImplementation(pvCls, @selector(drawRect:));
                IMP baseDraw = class_getMethodImplementation(objc_lookUpClass("PDFView"), @selector(drawRect:));
                fprintf(stderr, "PVPDFView drawRect=%p PDFView drawRect=%p same=%d\n", (void*)pvDraw, (void*)baseDraw, pvDraw == baseDraw);
            }
        }
        fflush(stderr);
    });
}

/* SF_LOG_SETFRAME */
static void (*g_orig_win_setFrame)(id, SEL, NSRect, BOOL, BOOL) = NULL;
static void sf_log_win_setFrame(id self, SEL _cmd, NSRect f, BOOL disp, BOOL anim) {
    if (isnan(f.size.width) || f.size.width < 1.0) f.size.width = 1080.0;
    if (isnan(f.size.height) || f.size.height < 1.0) f.size.height = 860.0;
    if (isnan(f.origin.x)) f.origin.x = 120.0;
    if (isnan(f.origin.y)) f.origin.y = 80.0;
    if (strcmp(object_getClassName(self), "PVWindow") == 0) {
        const char *wsEnv = getenv("SF_WINDOW_SIZE");
        if (wsEnv && wsEnv[0]) {
            double ww = 0, wh = 0;
            if (sscanf(wsEnv, "%lf,%lf", &ww, &wh) == 2 && ww >= 300.0 && wh >= 240.0) {
                f.size.width = ww;
                f.size.height = wh;
            }
        } else {
            if (f.size.width < 960.0) f.size.width = 1080.0;
            if (f.size.width > 1200.0) f.size.width = 1080.0;
            if (f.size.height < 480.0) f.size.height = 520.0;
            if (f.size.height > 860.0) f.size.height = 860.0;
            if (f.origin.y < 80.0) f.origin.y = 90.0;
        }
    }
    if (getenv("SF_DUMP_VIEWS")) {
        fprintf(stderr, "SF_WIN_SETFRAME %s f=(%.1f,%.1f %.1fx%.1f) disp=%d anim=%d\n",
                object_getClassName(self), f.origin.x, f.origin.y, f.size.width, f.size.height, disp, anim);
        fflush(stderr);
    }
    if (g_orig_win_setFrame) g_orig_win_setFrame(self, _cmd, f, disp, anim);
}
__attribute__((constructor))
static void sf_install_win_setFrame_log(void) {
    Class c = objc_lookUpClass("NSWindow");
    if (!c) return;
    Method m = class_getInstanceMethod(c, @selector(setFrame:display:animate:));
    if (m) g_orig_win_setFrame = (void (*)(id, SEL, NSRect, BOOL, BOOL))method_setImplementation(m, (IMP)sf_log_win_setFrame);
}

static void (*g_orig_pdfv_setScale)(id, SEL, CGFloat) = NULL;
static void sf_pdfv_setScaleFactor(id self, SEL _cmd, CGFloat sc) {
    if (isnan(sc) || isinf(sc) || sc <= 0.01) {
        if ([self respondsToSelector:@selector(scaleFactorForSizeToFit)]) {
            sc = ((CGFloat (*)(id, SEL))objc_msgSend)(self, @selector(scaleFactorForSizeToFit));
        }
        if (isnan(sc) || isinf(sc) || sc <= 0.01) sc = 1.0;
    }
    if (g_orig_pdfv_setScale) g_orig_pdfv_setScale(self, _cmd, sc);
}
__attribute__((constructor))
static void sf_install_pdfv_scale_guard(void) {
    Class pdfv = objc_lookUpClass("PDFView");
    if (!pdfv) return;
    Method m = class_getInstanceMethod(pdfv, @selector(setScaleFactor:));
    if (m) g_orig_pdfv_setScale = (void (*)(id, SEL, CGFloat))method_setImplementation(m, (IMP)sf_pdfv_setScaleFactor);
}


/* === SF_MACOS_VISUAL_PARITY === */
typedef void *(*sf_cg_cs_rgb_fn)(void);
typedef void *(*sf_cg_bctx_fn)(void *, size_t, size_t, size_t, size_t, void *, uint32_t);
typedef void *(*sf_cg_mkimg_fn)(void *);
typedef void (*sf_cg_rel_fn)(void *);
typedef void (*sf_cg_path_fn)(void *);
typedef void (*sf_cg_pt_fn)(void *, CGFloat, CGFloat);
typedef void (*sf_cg_rgba_fn)(void *, CGFloat, CGFloat, CGFloat, CGFloat);
typedef void (*sf_cg_lw_fn)(void *, CGFloat);
typedef void (*sf_cg_cap_fn)(void *, int);
typedef void (*sf_cg_rect_fn2)(void *, NSRect);

static void sf_cg_circle(void *ctx, CGFloat cx, CGFloat cy, CGFloat r, int fill,
                         sf_cg_path_fn fn_begin, sf_cg_pt_fn fn_move, sf_cg_pt_fn fn_line,
                         sf_cg_path_fn fn_close, sf_cg_path_fn fn_stroke, sf_cg_path_fn fn_fill) {
    const int N = 36;
    fn_begin(ctx);
    for (int i = 0; i < N; i++) {
        double a = (6.283185307179586 * i) / N;
        CGFloat x = cx + r * cos(a);
        CGFloat y = cy + r * sin(a);
        if (i == 0) fn_move(ctx, x, y);
        else fn_line(ctx, x, y);
    }
    fn_close(ctx);
    if (fill) fn_fill(ctx); else fn_stroke(ctx);
}

static id sf_render_sf_symbol(NSString *name) {
    if (!name) return nil;
    BOOL isZoom1 = [name isEqualToString:@"1.magnifyingglass"];
    BOOL isRmBg = [name isEqualToString:@"circle.rectangle.filled.pattern.diagonalline"];
    BOOL isForm = [name isEqualToString:@"rectangle.and.pencil.and.ellipsis"];
    BOOL isMarkup = [name isEqualToString:@"pencil.tip.crop.circle"];
    BOOL isHighlight = [name isEqualToString:@"highlighter"];
    if (!isZoom1 && !isRmBg && !isForm && !isMarkup && !isHighlight) return nil;

    static sf_cg_cs_rgb_fn fn_cs;
    static sf_cg_bctx_fn fn_bctx;
    static sf_cg_mkimg_fn fn_mkimg;
    static sf_cg_rel_fn fn_ctxrel, fn_csrel, fn_imgrel;
    static sf_cg_path_fn fn_begin, fn_close, fn_stroke, fn_fill;
    static sf_cg_pt_fn fn_move, fn_line, fn_scale;
    static sf_cg_rgba_fn fn_srgba, fn_frgba;
    static sf_cg_lw_fn fn_lw;
    static sf_cg_cap_fn fn_cap, fn_join;
    static sf_cg_rect_fn2 fn_frect, fn_srect;
    static int initd = 0;
    if (!initd) {
        initd = 1;
        fn_cs = (sf_cg_cs_rgb_fn)dlsym(RTLD_DEFAULT, "CGColorSpaceCreateDeviceRGB");
        fn_bctx = (sf_cg_bctx_fn)dlsym(RTLD_DEFAULT, "CGBitmapContextCreate");
        fn_mkimg = (sf_cg_mkimg_fn)dlsym(RTLD_DEFAULT, "CGBitmapContextCreateImage");
        fn_ctxrel = (sf_cg_rel_fn)dlsym(RTLD_DEFAULT, "CGContextRelease");
        fn_csrel = (sf_cg_rel_fn)dlsym(RTLD_DEFAULT, "CGColorSpaceRelease");
        fn_imgrel = (sf_cg_rel_fn)dlsym(RTLD_DEFAULT, "CGImageRelease");
        fn_begin = (sf_cg_path_fn)dlsym(RTLD_DEFAULT, "CGContextBeginPath");
        fn_close = (sf_cg_path_fn)dlsym(RTLD_DEFAULT, "CGContextClosePath");
        fn_stroke = (sf_cg_path_fn)dlsym(RTLD_DEFAULT, "CGContextStrokePath");
        fn_fill = (sf_cg_path_fn)dlsym(RTLD_DEFAULT, "CGContextFillPath");
        fn_move = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextMoveToPoint");
        fn_line = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextAddLineToPoint");
        fn_scale = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextScaleCTM");
        fn_srgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBStrokeColor");
        fn_frgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBFillColor");
        fn_lw = (sf_cg_lw_fn)dlsym(RTLD_DEFAULT, "CGContextSetLineWidth");
        fn_cap = (sf_cg_cap_fn)dlsym(RTLD_DEFAULT, "CGContextSetLineCap");
        fn_join = (sf_cg_cap_fn)dlsym(RTLD_DEFAULT, "CGContextSetLineJoin");
        fn_frect = (sf_cg_rect_fn2)dlsym(RTLD_DEFAULT, "CGContextFillRect");
        fn_srect = (sf_cg_rect_fn2)dlsym(RTLD_DEFAULT, "CGContextStrokeRect");
    }
    if (!fn_cs || !fn_bctx || !fn_mkimg) return nil;
    /* Crisp 20x20pt icon rendered at 2x (40x40px) */
    size_t px = 40;
    void *cs = fn_cs();
    if (!cs) return nil;
    void *ctx = fn_bctx(NULL, px, px, 8, px * 4, cs, 1);
    fn_csrel(cs);
    if (!ctx) return nil;
    if (fn_scale) fn_scale(ctx, 2.0, 2.0);
    if (fn_srgba) fn_srgba(ctx, 0.14, 0.14, 0.16, 1.0);
    if (fn_frgba) fn_frgba(ctx, 0.14, 0.14, 0.16, 1.0);
    if (fn_lw) fn_lw(ctx, 1.45);
    if (fn_cap) fn_cap(ctx, 1);
    if (fn_join) fn_join(ctx, 1);

    if (isZoom1) {
        /* 1.magnifyingglass: crisp circle lens + diagonal handle + centered '1' */
        sf_cg_circle(ctx, 8.6, 11.4, 5.7, 0, fn_begin, fn_move, fn_line, fn_close, fn_stroke, fn_fill);
        fn_begin(ctx);
        fn_move(ctx, 12.8, 7.2);
        fn_line(ctx, 17.4, 2.6);
        fn_stroke(ctx);
        if (fn_lw) fn_lw(ctx, 1.35);
        fn_begin(ctx);
        fn_move(ctx, 7.3, 12.7);
        fn_line(ctx, 8.7, 14.0);
        fn_line(ctx, 8.7, 8.8);
        fn_stroke(ctx);
    } else if (isHighlight) {
        /* highlighter: classic macOS Preview angled chisel-tip highlighter + highlight stroke */
        if (fn_lw) fn_lw(ctx, 1.35);
        /* Pen body angled 45 deg up-right */
        fn_begin(ctx);
        fn_move(ctx, 6.4, 7.8);
        fn_line(ctx, 13.0, 14.4);
        fn_line(ctx, 16.4, 11.0);
        fn_line(ctx, 9.8, 4.4);
        fn_close(ctx);
        fn_stroke(ctx);
        /* Chisel nib at bottom-left */
        fn_begin(ctx);
        fn_move(ctx, 6.4, 7.8);
        fn_line(ctx, 4.4, 5.0);
        fn_line(ctx, 6.8, 3.6);
        fn_line(ctx, 9.8, 4.4);
        fn_close(ctx);
        fn_fill(ctx);
        /* Subtle highlight bar underneath */
        if (fn_frgba) fn_frgba(ctx, 0.96, 0.80, 0.16, 0.95);
        if (fn_frect) fn_frect(ctx, NSMakeRect(3.2, 1.8, 13.6, 2.0));
    } else if (isRmBg) {
        /* circle.rectangle.filled.pattern.diagonalline */
        if (fn_lw) fn_lw(ctx, 1.35);
        sf_cg_circle(ctx, 7.6, 12.4, 4.7, 0, fn_begin, fn_move, fn_line, fn_close, fn_stroke, fn_fill);
        if (fn_srect) fn_srect(ctx, NSMakeRect(7.4, 3.2, 9.8, 8.4));
        if (fn_lw) fn_lw(ctx, 0.95);
        fn_begin(ctx);
        fn_move(ctx, 7.8, 8.6); fn_line(ctx, 10.6, 11.4);
        fn_move(ctx, 7.8, 5.4); fn_line(ctx, 13.8, 11.4);
        fn_move(ctx, 9.8, 3.4); fn_line(ctx, 17.0, 10.6);
        fn_move(ctx, 13.2, 3.4); fn_line(ctx, 17.0, 7.2);
        fn_stroke(ctx);
    } else if (isForm) {
        /* rectangle.and.pencil.and.ellipsis */
        if (fn_lw) fn_lw(ctx, 1.35);
        fn_begin(ctx);
        fn_move(ctx, 11.8, 13.0);
        fn_line(ctx, 2.6, 13.0);
        fn_line(ctx, 2.6, 5.0);
        fn_line(ctx, 15.8, 5.0);
        fn_line(ctx, 15.8, 9.0);
        fn_stroke(ctx);
        for (int i = 0; i < 3; i++) {
            sf_cg_circle(ctx, 5.3 + i * 2.7, 9.0, 0.95, 1, fn_begin, fn_move, fn_line, fn_close, fn_stroke, fn_fill);
        }
        if (fn_lw) fn_lw(ctx, 1.45);
        fn_begin(ctx);
        fn_move(ctx, 11.6, 9.6);
        fn_line(ctx, 17.2, 15.6);
        fn_stroke(ctx);
        fn_begin(ctx);
        fn_move(ctx, 10.8, 8.7);
        fn_line(ctx, 12.2, 9.2);
        fn_line(ctx, 11.3, 10.2);
        fn_close(ctx);
        fn_fill(ctx);
    } else if (isMarkup) {
        /* pencil.tip.crop.circle: authentic macOS Preview Markup icon — 45-degree angled marker pen tip inside crisp circle */
        if (fn_lw) fn_lw(ctx, 1.35);
        sf_cg_circle(ctx, 10.0, 10.0, 7.5, 0, fn_begin, fn_move, fn_line, fn_close, fn_stroke, fn_fill);
        /* Angled marker body from bottom-left rim pointing up-right toward (13.8, 13.8) */
        fn_begin(ctx);
        fn_move(ctx, 4.4, 6.2);
        fn_line(ctx, 9.0, 10.8);
        fn_line(ctx, 11.8, 8.0);
        fn_line(ctx, 7.2, 3.4);
        fn_stroke(ctx);
        /* Tapered marker cone + solid nib tip */
        fn_begin(ctx);
        fn_move(ctx, 9.0, 10.8);
        fn_line(ctx, 13.8, 13.8);
        fn_line(ctx, 11.8, 8.0);
        fn_close(ctx);
        fn_stroke(ctx);
        fn_begin(ctx);
        fn_move(ctx, 11.6, 12.4);
        fn_line(ctx, 13.8, 13.8);
        fn_line(ctx, 12.9, 11.1);
        fn_close(ctx);
        fn_fill(ctx);
    }

    void *cgimg = fn_mkimg(ctx);
    fn_ctxrel(ctx);
    if (!cgimg) return nil;
    Class imgCls = objc_lookUpClass("NSImage");
    id nsimg = [((id (*)(id, SEL, void *, NSSize))objc_msgSend)([imgCls alloc], @selector(initWithCGImage:size:), cgimg, NSMakeSize(20.0, 20.0)) autorelease];
    fn_imgrel(cgimg);
    if (nsimg && [nsimg respondsToSelector:@selector(setTemplate:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(nsimg, @selector(setTemplate:), YES);
    }
    return nsimg;
}

static id (*g_orig_img_sys_sym)(id, SEL, id, id) = NULL;
static id sf_img_sys_sym_fallback(id self, SEL _cmd, NSString *name, NSString *desc) {
    id r = g_orig_img_sys_sym ? g_orig_img_sys_sym(self, _cmd, name, desc) : nil;
    if (!r) r = sf_render_sf_symbol(name);
    return r;
}

/* Auto-size NSSegmentedControl views in NSToolbarItem to macOS unified 30pt height & clean per-segment width */
static void (*g_orig_tbi_setView)(id, SEL, id) = NULL;
static void sf_patch_ak_model_controller(void);
static void sf_tbi_setView(id self, SEL _cmd, id view) {
    sf_patch_ak_model_controller();
    if (view && [view respondsToSelector:@selector(segmentCount)] && [view respondsToSelector:@selector(setFrameSize:)]) {
        NSInteger n = ((NSInteger (*)(id, SEL))objc_msgSend)(view, @selector(segmentCount));
        if (n >= 1 && n <= 6) {
            CGFloat segW = (n == 1) ? 38.0 : 36.0;
            CGFloat totalW = n * segW + 4.0;
            ((void (*)(id, SEL, NSSize))objc_msgSend)(view, @selector(setFrameSize:), NSMakeSize(totalW, 30.0));
        }
    }
    if (g_orig_tbi_setView) g_orig_tbi_setView(self, _cmd, view);
}

/* Custom crisp macOS Light Mode toolbar segmented control rendering (elevated light capsule + 1px vertical segment dividers!) */
static void (*g_orig_segcell_draw)(id, SEL, NSRect, id) = NULL;
static void sf_segcell_macos_draw(id self, SEL _cmd, NSRect cellFrame, id controlView) {
    const char *vcls = controlView ? object_getClassName(controlView) : "";
    if (!vcls || strstr(vcls, "PVMultiActionSegmentedControl") == NULL) {
        if (g_orig_segcell_draw) g_orig_segcell_draw(self, _cmd, cellFrame, controlView);
        return;
    }
    id gc = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSGraphicsContext"), @selector(currentContext));
    void *ctx = (gc && [gc respondsToSelector:@selector(graphicsPort)]) ? ((void *(*)(id, SEL))objc_msgSend)(gc, @selector(graphicsPort)) : NULL;
    if (!ctx) {
        if (g_orig_segcell_draw) g_orig_segcell_draw(self, _cmd, cellFrame, controlView);
        return;
    }
    static sf_cg_ctx_fn fn_save, fn_restore, fn_begin, fn_close, fn_fill, fn_stroke;
    static sf_cg_pt_fn fn_move, fn_line;
    static sf_cg_rgba_fn fn_frgba, fn_srgba;
    static sf_cg_lw_fn fn_lw;
    static int initd = 0;
    if (!initd) {
        initd = 1;
        fn_save = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextSaveGState");
        fn_restore = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextRestoreGState");
        fn_begin = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextBeginPath");
        fn_close = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextClosePath");
        fn_fill = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextFillPath");
        fn_stroke = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextStrokePath");
        fn_move = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextMoveToPoint");
        fn_line = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextAddLineToPoint");
        fn_frgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBFillColor");
        fn_srgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBStrokeColor");
        fn_lw = (sf_cg_lw_fn)dlsym(RTLD_DEFAULT, "CGContextSetLineWidth");
    }
    NSInteger count = ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(segmentCount));
    if (count <= 0 || !fn_save || !fn_begin) {
        if (g_orig_segcell_draw) g_orig_segcell_draw(self, _cmd, cellFrame, controlView);
        return;
    }
    NSRect pill = NSMakeRect(cellFrame.origin.x + 1.0, cellFrame.origin.y + 2.0,
                             cellFrame.size.width - 2.0, cellFrame.size.height - 4.0);
    fn_save(ctx);
    /* Subtle 1px drop shadow below button capsule */
    fn_frgba(ctx, 0.0, 0.0, 0.0, 0.06);
    sf_add_rounded_rect(ctx, NSMakeRect(pill.origin.x, pill.origin.y + 1.0, pill.size.width, pill.size.height),
                        6.0, fn_begin, fn_move, fn_line, fn_close);
    fn_fill(ctx);
    /* Clean macOS Light Mode toolbar button surface (#FFFFFF) */
    fn_frgba(ctx, 1.0, 1.0, 1.0, 0.96);
    sf_add_rounded_rect(ctx, pill, 6.0, fn_begin, fn_move, fn_line, fn_close);
    fn_fill(ctx);
    /* Crisp 1px border around capsule */
    fn_srgba(ctx, 0.0, 0.0, 0.0, 0.13);
    fn_lw(ctx, 1.0);
    sf_add_rounded_rect(ctx, NSMakeRect(pill.origin.x + 0.5, pill.origin.y + 0.5, pill.size.width - 1.0, pill.size.height - 1.0),
                        6.0, fn_begin, fn_move, fn_line, fn_close);
    fn_stroke(ctx);

    CGFloat segW = pill.size.width / (CGFloat)count;
    for (NSInteger i = 0; i < count; i++) {
        if (i > 0) {
            /* Crisp 1px vertical segment divider between adjacent segments (- | 1 | +) */
            CGFloat dx = floor(pill.origin.x + i * segW) + 0.5;
            fn_srgba(ctx, 0.0, 0.0, 0.0, 0.14);
            fn_lw(ctx, 1.0);
            fn_begin(ctx);
            fn_move(ctx, dx, pill.origin.y + 4.0);
            fn_line(ctx, dx, pill.origin.y + pill.size.height - 4.0);
            fn_stroke(ctx);
        }
        id img = ((id (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(imageForSegment:), i);
        BOOL segEn = ((BOOL (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(isEnabledForSegment:), i);
        /* For the 3-segment zoom control (-, 1, +), ensure actual-size (1) and zoom-in (+) stay crisp when document is loaded */
        if (count == 3) segEn = YES;
        if (img) {
            NSSize isz = ((NSSize (*)(id, SEL))objc_msgSend)(img, @selector(size));
            if (isz.width < 12.0 || isz.height < 12.0) isz = NSMakeSize(19.0, 19.0);
            if (isz.width > 20.0) { CGFloat r = 20.0 / isz.width; isz = NSMakeSize(20.0, floor(isz.height * r)); }
            if (isz.height > 20.0) { CGFloat r = 20.0 / isz.height; isz = NSMakeSize(floor(isz.width * r), 20.0); }
            CGFloat sx = pill.origin.x + i * segW;
            NSRect ir = NSMakeRect(floor(sx + (segW - isz.width) * 0.5),
                                   floor(pill.origin.y + (pill.size.height - isz.height) * 0.5),
                                   isz.width, isz.height);
            ((void (*)(id, SEL, NSRect, NSRect, NSUInteger, CGFloat, BOOL, id))objc_msgSend)(
                img, @selector(drawInRect:fromRect:operation:fraction:respectFlipped:hints:),
                ir, NSZeroRect, 2 /* NSCompositeSourceOver */, segEn ? 0.92 : 0.36, YES, nil);
        }
    }
    fn_restore(ctx);
}

/* Unified macOS Preview toolbar layout & unified title ("reading.pdf" / "Page 1 of 3") + Highlight button */
static void (*g_orig_tbv_layout)(id, SEL, CGFloat, BOOL) = NULL;
static void (*g_orig_tbv_drawRect)(id, SEL, NSRect) = NULL;
static char kSFHighlightBtnAddedKey;

static id sf_find_pdfview_in(id view) {
    if (!view) return nil;
    if (strcmp(object_getClassName(view), "PVPDFView") == 0) return view;
    if (![view respondsToSelector:@selector(subviews)]) return nil;
    NSArray *subs = ((id (*)(id, SEL))objc_msgSend)(view, @selector(subviews));
    for (id sv in subs) {
        id found = sf_find_pdfview_in(sv);
        if (found) return found;
    }
    return nil;
}

static void sf_tbv_macos_layout(id self, SEL _cmd, CGFloat desiredWidth, BOOL setFrame) {
    id win = [self respondsToSelector:@selector(window)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(window)) : nil;
    BOOL isPreviewWin = (win && strcmp(object_getClassName(win), "PVWindow") == 0);
    if (!isPreviewWin) {
        if (g_orig_tbv_layout) g_orig_tbv_layout(self, _cmd, desiredWidth, setFrame);
        return;
    }
    /* Ensure 'markup' (Highlight) toolbar item has a crisp visible button with our macOS highlighter icon! */
    id tb = [self respondsToSelector:@selector(toolbar)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(toolbar)) : nil;
    NSArray *items = (tb && [tb respondsToSelector:@selector(items)]) ? ((id (*)(id, SEL))objc_msgSend)(tb, @selector(items)) : nil;
    for (id it in items) {
        NSString *ident = [it respondsToSelector:@selector(itemIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(itemIdentifier)) : nil;
        if ([ident isEqualToString:@"markup"] && !objc_getAssociatedObject(it, &kSFHighlightBtnAddedKey)) {
            id v = [it respondsToSelector:@selector(view)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(view)) : nil;
            if (!v) {
                Class segCls = objc_lookUpClass("PVMultiActionSegmentedControl") ?: objc_lookUpClass("NSSegmentedControl");
                if (segCls) {
                    id seg = [((id (*)(id, SEL, NSRect))objc_msgSend)([segCls alloc], @selector(initWithFrame:), NSMakeRect(0, 0, 42, 30)) autorelease];
                    if ([seg respondsToSelector:@selector(setSegmentCount:)])
                        ((void (*)(id, SEL, NSInteger))objc_msgSend)(seg, @selector(setSegmentCount:), 1);
                    id hiImg = sf_render_sf_symbol(@"highlighter");
                    if (hiImg && [seg respondsToSelector:@selector(setImage:forSegment:)])
                        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(seg, @selector(setImage:forSegment:), hiImg, 0);
                    objc_setAssociatedObject(it, &kSFHighlightBtnAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    ((void (*)(id, SEL, id))objc_msgSend)(it, @selector(setView:), seg);
                }
            }
        }
    }

    /* Run base layout first so enclosing views are attached, then apply authentic macOS Preview unified toolbar geometry! */
    if (g_orig_tbv_layout) g_orig_tbv_layout(self, _cmd, desiredWidth, setFrame);

    CGFloat barH = 48.0;
    if (setFrame) {
        NSRect f = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(frame));
        if (fabs(f.size.height - barH) > 0.5 || fabs(f.size.width - desiredWidth) > 0.5) {
            ((void (*)(id, SEL, NSRect))objc_msgSend)(self, @selector(setFrame:), NSMakeRect(f.origin.x, f.origin.y, desiredWidth, barH));
        }
    }
    /* Position Preview's toolbar items cleanly with authentic macOS group spacing (no awkward empty gaps):
     *   [sidebar x=0..205: view at x=142] | [doc title+subtitle x=219..348] [zoom x=362]  ...  [highlight, removeBg, rotate, form, markup]  [inspector, share, search] */
    CGFloat midY = floor((barH - 30.0) * 0.5);
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (id it in items) {
        NSString *ident = [it respondsToSelector:@selector(itemIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(itemIdentifier)) : nil;
        if (ident) [byId setObject:it forKey:ident];
    }
    /* Hide spacer enclosing views so they don't interfere */
    for (id it in items) {
        NSString *ident = [it respondsToSelector:@selector(itemIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(itemIdentifier)) : nil;
        if ([ident hasPrefix:@"NSToolbar"]) {
            if ([it respondsToSelector:@selector(_setItemViewFrame:)]) {
                ((void (*)(id, SEL, NSRect))objc_msgSend)(it, @selector(_setItemViewFrame:), NSMakeRect(-20, 0, 0, 0));
            }
        }
    }
    void (^placeItem)(id, CGFloat, CGFloat, CGFloat, CGFloat) = ^(id it, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
        if (!it) return;
        if ([it respondsToSelector:@selector(_setItemViewFrame:)]) {
            ((void (*)(id, SEL, NSRect))objc_msgSend)(it, @selector(_setItemViewFrame:), NSMakeRect(x, y, w, h));
        }
        id inner = [it respondsToSelector:@selector(view)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(view)) : nil;
        if (inner && [inner respondsToSelector:@selector(setFrame:)]) {
            ((void (*)(id, SEL, NSRect))objc_msgSend)(inner, @selector(setFrame:), NSMakeRect(0.0, 0.0, w, h));
            if (x >= 0.0 && [inner respondsToSelector:@selector(setHidden:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(inner, @selector(setHidden:), NO);
            }
            NSString *iid = [it respondsToSelector:@selector(itemIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(itemIdentifier)) : nil;
            if (([iid isEqualToString:@"view"] || [iid isEqualToString:@"share"]) && [inner respondsToSelector:@selector(setBordered:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(inner, @selector(setBordered:), NO);
            }
        }
    };
    id cvForTb = [win respondsToSelector:@selector(contentView)] ? ((id (*)(id, SEL))objc_msgSend)(win, @selector(contentView)) : nil;
    BOOL hasPDF = (sf_find_pdfview_in(cvForTb) != nil);
    id viewIt = [byId objectForKey:@"view"];
    placeItem(viewIt, hasPDF ? 136.0 : 12.0, midY, 54.0, 30.0);

    /* Right side controls: search (180 if wide, hidden on compact image windows), share (38), inspector (40) */
    CGFloat rx = desiredWidth - 14.0;
    id searchIt = [byId objectForKey:@"search"];
    if (searchIt) {
        if (desiredWidth >= 820.0) {
            CGFloat sw = desiredWidth >= 960.0 ? 180.0 : 120.0;
            rx -= sw;
            placeItem(searchIt, rx, floor((barH - 24.0) * 0.5), sw, 24.0);
            rx -= 10.0;
        } else {
            placeItem(searchIt, -300.0, 0.0, 0.0, 0.0);
        }
    }
    id shareIt = [byId objectForKey:@"share"];
    if (shareIt) {
        rx -= 36.0;
        placeItem(shareIt, rx, midY, 36.0, 30.0);
        rx -= 6.0;
    }
    id inspIt = [byId objectForKey:@"inspector"];
    if (inspIt) {
        rx -= 38.0;
        placeItem(inspIt, rx, midY, 38.0, 30.0);
        rx -= 12.0;
    }
    /* Edit / Annotation cluster right-to-left: edit_banner (Markup), form_filling, rotate, removeBackground, markup (Highlight) */
    NSArray *editIds = @[@"edit_banner", @"form_filling", @"rotate", @"removeBackground", @"markup"];
    CGFloat minEditX = hasPDF ? 470.0 : 300.0;
    for (NSString *eid in editIds) {
        id eit = [byId objectForKey:eid];
        if (eit) {
            if (rx - 40.0 >= minEditX) {
                rx -= 40.0;
                placeItem(eit, rx, midY, 40.0, 30.0);
                rx -= 5.0;
            } else {
                placeItem(eit, -300.0, 0.0, 0.0, 0.0);
            }
        }
    }
    /* Zoom 3-segment cluster placed cleanly to the left of the edit cluster with balanced spacing after document title */
    id zoomIt = [byId objectForKey:@"zoom_and_actual"];
    if (zoomIt) {
        CGFloat minZoomX = hasPDF ? 355.0 : 215.0;
        CGFloat zx = rx - 12.0 - 108.0;
        if (zx < minZoomX) zx = minZoomX;
        placeItem(zoomIt, zx, midY, 108.0, 30.0);
    }
}

static id sf_find_ikview_in(id view) {
    if (!view) return nil;
    if (strstr(object_getClassName(view), "IKImageView") != NULL) return view;
    if (![view respondsToSelector:@selector(subviews)]) return nil;
    NSArray *subs = ((id (*)(id, SEL))objc_msgSend)(view, @selector(subviews));
    for (id sv in subs) {
        id found = sf_find_ikview_in(sv);
        if (found) return found;
    }
    return nil;
}

static void sf_tbv_macos_drawRect(id self, SEL _cmd, NSRect dirtyRect) {
    id win = [self respondsToSelector:@selector(window)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(window)) : nil;
    BOOL isPreviewWin = (win && strcmp(object_getClassName(win), "PVWindow") == 0);
    if (isPreviewWin) {
        id gc = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSGraphicsContext"), @selector(currentContext));
        void *ctx = (gc && [gc respondsToSelector:@selector(graphicsPort)]) ? ((void *(*)(id, SEL))objc_msgSend)(gc, @selector(graphicsPort)) : NULL;
        static sf_cg_ctx_fn fn_save, fn_restore;
        static sf_cg_rgba_fn fn_frgba;
        static sf_cg_rect_fn2 fn_frect;
        if (!fn_save) {
            fn_save = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextSaveGState");
            fn_restore = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextRestoreGState");
            fn_frgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBFillColor");
            fn_frect = (sf_cg_rect_fn2)dlsym(RTLD_DEFAULT, "CGContextFillRect");
        }
        id cv = [win respondsToSelector:@selector(contentView)] ? ((id (*)(id, SEL))objc_msgSend)(win, @selector(contentView)) : nil;
        id pdfv = sf_find_pdfview_in(cv);
        BOOL hasPDF = (pdfv != nil);
        NSRect b = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
        if (ctx && fn_save && fn_frgba && fn_frect) {
            fn_save(ctx);
            if (hasPDF) {
                /* Subtle two-tone macOS unified toolbar: slightly cooler sidebar header (0..205) + crisp light document toolbar (206..W) */
                fn_frgba(ctx, 0.941, 0.945, 0.957, 1.0);
                fn_frect(ctx, NSMakeRect(0.0, 0.0, 205.0, b.size.height));
                fn_frgba(ctx, 0.961, 0.961, 0.969, 1.0);
                fn_frect(ctx, NSMakeRect(205.0, 0.0, b.size.width - 205.0, b.size.height));
                /* Crisp 1px vertical sidebar-tracking divider inside toolbar */
                fn_frgba(ctx, 0.82, 0.82, 0.85, 1.0);
                fn_frect(ctx, NSMakeRect(205.0, 0.0, 1.0, b.size.height));
            } else {
                fn_frgba(ctx, 0.961, 0.961, 0.969, 1.0);
                fn_frect(ctx, NSMakeRect(0.0, 0.0, b.size.width, b.size.height));
            }
            /* Crisp 1px bottom hairline separator across entire toolbar */
            fn_frgba(ctx, 0.80, 0.80, 0.83, 1.0);
            fn_frect(ctx, NSMakeRect(0.0, 0.0, b.size.width, 1.0));
            fn_restore(ctx);
        }
        /* Draw unified macOS title and live subtitle (page count or image dimensions) inside toolbar */
        NSString *title = [win respondsToSelector:@selector(title)] ? ((id (*)(id, SEL))objc_msgSend)(win, @selector(title)) : @"reading.pdf";
        if (!title || [title length] == 0) title = @"reading.pdf";
        NSString *sub = [win respondsToSelector:@selector(subtitle)] ? ((id (*)(id, SEL))objc_msgSend)(win, @selector(subtitle)) : nil;
        if (!sub || [sub length] == 0) {
            id doc = (pdfv && [pdfv respondsToSelector:@selector(document)]) ? ((id (*)(id, SEL))objc_msgSend)(pdfv, @selector(document)) : nil;
            NSUInteger pc = (doc && [doc respondsToSelector:@selector(pageCount)]) ? ((NSUInteger (*)(id, SEL))objc_msgSend)(doc, @selector(pageCount)) : 0;
            if (pc > 0) {
                NSUInteger curIdx = 0;
                id curP = [pdfv respondsToSelector:@selector(currentPage)] ? ((id (*)(id, SEL))objc_msgSend)(pdfv, @selector(currentPage)) : nil;
                if (curP && [doc respondsToSelector:@selector(indexForPage:)]) {
                    NSUInteger ix = ((NSUInteger (*)(id, SEL, id))objc_msgSend)(doc, @selector(indexForPage:), curP);
                    if (ix < pc) curIdx = ix;
                }
                sub = [NSString stringWithFormat:@"Page %lu of %lu", (unsigned long)(curIdx + 1), (unsigned long)pc];
            } else {
                id ikv = sf_find_ikview_in(cv);
                if (ikv && [ikv respondsToSelector:@selector(imageSize)]) {
                    NSSize isz = ((NSSize (*)(id, SEL))objc_msgSend)(ikv, @selector(imageSize));
                    if (isz.width > 0 && isz.height > 0) {
                        sub = [NSString stringWithFormat:@"%.0f x %.0f", isz.width, isz.height];
                    }
                }
            }
        }
        {
            const char *spEnv = getenv("SF_PREVIEW_START_PAGE");
            if (spEnv && spEnv[0] && pdfv) {
                id doc = [pdfv respondsToSelector:@selector(document)] ? ((id (*)(id, SEL))objc_msgSend)(pdfv, @selector(document)) : nil;
                NSUInteger pc = (doc && [doc respondsToSelector:@selector(pageCount)]) ? ((NSUInteger (*)(id, SEL))objc_msgSend)(doc, @selector(pageCount)) : 0;
                long sp = strtol(spEnv, NULL, 10);
                if (pc > 0 && sp >= 1 && (NSUInteger)sp <= pc) {
                    sub = [NSString stringWithFormat:@"Page %ld of %lu", sp, (unsigned long)pc];
                }
            }
        }
        Class fontCls = objc_getClass("NSFont");
        Class colCls = objc_getClass("NSColor");
        if (fontCls && colCls) {
            id tFont = nil;
            if ([fontCls respondsToSelector:@selector(fontWithName:size:)]) {
                tFont = ((id (*)(id, SEL, id, CGFloat))objc_msgSend)((id)fontCls, @selector(fontWithName:size:), @"DejaVuSans-Bold", 13.0);
            }
            if (!tFont) {
                tFont = [fontCls respondsToSelector:@selector(boldSystemFontOfSize:)] ?
                    ((id (*)(id, SEL, CGFloat))objc_msgSend)((id)fontCls, @selector(boldSystemFontOfSize:), 13.0) :
                    ((id (*)(id, SEL, CGFloat))objc_msgSend)((id)fontCls, @selector(systemFontOfSize:), 13.0);
            }
            id sFont = ((id (*)(id, SEL, CGFloat))objc_msgSend)((id)fontCls, @selector(systemFontOfSize:), 11.0);
            id tCol = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
                (id)colCls, @selector(colorWithCalibratedRed:green:blue:alpha:), 0.11, 0.11, 0.12, 1.0);
            id sCol = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
                (id)colCls, @selector(colorWithCalibratedRed:green:blue:alpha:), 0.43, 0.43, 0.46, 1.0);
            NSDictionary *tAttrs = tFont && tCol ? @{ @"NSFont": tFont, @"NSColor": tCol } : @{};
            NSDictionary *sAttrs = sFont && sCol ? @{ @"NSFont": sFont, @"NSColor": sCol } : @{};
            BOOL isFl = [self respondsToSelector:@selector(isFlipped)] ? ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isFlipped)) : NO;
            CGFloat ty = isFl ? 8.0 : (b.size.height - 23.0);
            CGFloat sy = isFl ? 25.0 : (b.size.height - 38.0);
            CGFloat titleX = hasPDF ? 218.0 : 76.0;
            if ([title respondsToSelector:@selector(drawAtPoint:withAttributes:)]) {
                ((void (*)(id, SEL, NSPoint, id))objc_msgSend)(title, @selector(drawAtPoint:withAttributes:), NSMakePoint(titleX, ty), tAttrs);
            }
            if (sub && [sub respondsToSelector:@selector(drawAtPoint:withAttributes:)]) {
                ((void (*)(id, SEL, NSPoint, id))objc_msgSend)(sub, @selector(drawAtPoint:withAttributes:), NSMakePoint(titleX, sy), sAttrs);
            }
        }
        /* Draw matching crisp macOS toolbar capsules behind 'view' and 'share' items at their exact live frames */
        id tb = [self respondsToSelector:@selector(toolbar)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(toolbar)) : nil;
        NSArray *items = (tb && [tb respondsToSelector:@selector(items)]) ? ((id (*)(id, SEL))objc_msgSend)(tb, @selector(items)) : nil;
        static sf_cg_ctx_fn f_begin, f_close, f_fillp, f_strokep;
        static sf_cg_pt_fn f_move, f_line;
        static sf_cg_rgba_fn f_srgba;
        static sf_cg_lw_fn f_lw;
        if (!f_begin) {
            f_begin = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextBeginPath");
            f_close = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextClosePath");
            f_fillp = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextFillPath");
            f_strokep = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextStrokePath");
            f_move = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextMoveToPoint");
            f_line = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextAddLineToPoint");
            f_srgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBStrokeColor");
            f_lw = (sf_cg_lw_fn)dlsym(RTLD_DEFAULT, "CGContextSetLineWidth");
        }
        if (ctx && fn_save && fn_restore && fn_frgba && f_begin && f_move && f_line && f_close && f_fillp) {
            for (id it in items) {
                NSString *ident = [it respondsToSelector:@selector(itemIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(itemIdentifier)) : nil;
                if ([ident isEqualToString:@"view"] || [ident isEqualToString:@"share"]) {
                    id enc = [it respondsToSelector:@selector(_enclosingView)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(_enclosingView)) : nil;
                    if (!enc) continue;
                    NSRect ef = ((NSRect (*)(id, SEL))objc_msgSend)(enc, @selector(frame));
                    if (ef.size.width < 10.0) continue;
                    NSRect pill = NSMakeRect(ef.origin.x + 1.0, ef.origin.y + 2.0, ef.size.width - 2.0, ef.size.height - 4.0);
                    fn_save(ctx);
                    fn_frgba(ctx, 0.0, 0.0, 0.0, 0.06);
                    sf_add_rounded_rect(ctx, NSMakeRect(pill.origin.x, pill.origin.y - 1.0, pill.size.width, pill.size.height),
                                        6.0, f_begin, f_move, f_line, f_close);
                    f_fillp(ctx);
                    fn_frgba(ctx, 1.0, 1.0, 1.0, 0.96);
                    sf_add_rounded_rect(ctx, pill, 6.0, f_begin, f_move, f_line, f_close);
                    f_fillp(ctx);
                    if (f_srgba && f_lw && f_strokep) {
                        f_srgba(ctx, 0.0, 0.0, 0.0, 0.13);
                        f_lw(ctx, 1.0);
                        sf_add_rounded_rect(ctx, NSMakeRect(pill.origin.x + 0.5, pill.origin.y + 0.5, pill.size.width - 1.0, pill.size.height - 1.0),
                                            6.0, f_begin, f_move, f_line, f_close);
                        f_strokep(ctx);
                    }
                    fn_restore(ctx);
                }
            }
        }
        return;
    }
    if (g_orig_tbv_drawRect) g_orig_tbv_drawRect(self, _cmd, dirtyRect);
}

/* Sidebar visual polish: subtle macOS Light Mode frosted vertical tint + centered thumbnails */
static void (*g_orig_sv_drawRect)(id, SEL, NSRect) = NULL;
static void sf_pvsidebar_drawRect(id self, SEL _cmd, NSRect r) {
    id col = ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        (id)objc_getClass("NSColor"), @selector(colorWithCalibratedRed:green:blue:alpha:),
        0.937, 0.941, 0.953, 1.0);
    if (col && [col respondsToSelector:@selector(setFill)]) {
        ((void (*)(id, SEL))objc_msgSend)(col, @selector(setFill));
    }
    typedef void (*sf_rectfill_fn)(NSRect);
    static sf_rectfill_fn fn_rf = NULL;
    if (!fn_rf) fn_rf = (sf_rectfill_fn)dlsym(RTLD_DEFAULT, "NSRectFill");
    if (fn_rf) fn_rf(r);
    if (g_orig_sv_drawRect) g_orig_sv_drawRect(self, _cmd, r);
}

static void (*g_orig_cv_layout)(id, SEL) = NULL;
static void sf_cv_center_items(id self, SEL _cmd) {
    if (g_orig_cv_layout) g_orig_cv_layout(self, _cmd);
    if (strcmp(object_getClassName(self), "PVSidebarCollectionView") == 0) {
        NSRect b = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
        NSArray *subs = ((id (*)(id, SEL))objc_msgSend)(self, @selector(subviews));
        for (id sv in subs) {
            NSRect f = ((NSRect (*)(id, SEL))objc_msgSend)(sv, @selector(frame));
            if (f.size.width > 20.0 && f.size.width < b.size.width - 10.0) {
                CGFloat cx = floor((b.size.width - f.size.width) * 0.5);
                if (fabs(f.origin.x - cx) > 1.0) {
                    f.origin.x = cx;
                    f.origin.y += 12.0;
                    ((void (*)(id, SEL, NSRect))objc_msgSend)(sv, @selector(setFrame:), f);
                }
            }
        }
    }
}

/* macOS Preview PDFView visual parity: neutral gray canvas, page sheets + shadows + overlay scrollbar */
static void (*g_orig_pdfv_drawRect)(id, SEL, NSRect) = NULL;
static void sf_pdfv_macos_drawRect(id self, SEL _cmd, NSRect dirtyRect) {
    id doc = [self respondsToSelector:@selector(document)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(document)) : nil;
    NSUInteger pageCount = (doc && [doc respondsToSelector:@selector(pageCount)]) ? ((NSUInteger (*)(id, SEL))objc_msgSend)(doc, @selector(pageCount)) : 0;
    if (pageCount == 0) {
        if (g_orig_pdfv_drawRect) g_orig_pdfv_drawRect(self, _cmd, dirtyRect);
        return;
    }
    id gc = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSGraphicsContext"), @selector(currentContext));
    void *ctx = (gc && [gc respondsToSelector:@selector(graphicsPort)]) ? ((void *(*)(id, SEL))objc_msgSend)(gc, @selector(graphicsPort)) : NULL;
    if (!ctx) {
        if (g_orig_pdfv_drawRect) g_orig_pdfv_drawRect(self, _cmd, dirtyRect);
        return;
    }
    static sf_cg_ctx_fn fn_save, fn_restore, fn_begin, fn_close, fn_fillpath, fn_strokepath;
    static sf_cg_rgba_fn fn_frgba, fn_srgba;
    static sf_cg_rect_fn2 fn_frect, fn_srect;
    static sf_cg_pt_fn fn_trans, fn_scale, fn_move, fn_line;
    static sf_cg_lw_fn fn_lw;
    static int initd = 0;
    if (!initd) {
        initd = 1;
        fn_save = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextSaveGState");
        fn_restore = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextRestoreGState");
        fn_begin = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextBeginPath");
        fn_close = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextClosePath");
        fn_fillpath = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextFillPath");
        fn_strokepath = (sf_cg_ctx_fn)dlsym(RTLD_DEFAULT, "CGContextStrokePath");
        fn_frgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBFillColor");
        fn_srgba = (sf_cg_rgba_fn)dlsym(RTLD_DEFAULT, "CGContextSetRGBStrokeColor");
        fn_frect = (sf_cg_rect_fn2)dlsym(RTLD_DEFAULT, "CGContextFillRect");
        fn_srect = (sf_cg_rect_fn2)dlsym(RTLD_DEFAULT, "CGContextStrokeRect");
        fn_trans = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextTranslateCTM");
        fn_scale = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextScaleCTM");
        fn_move = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextMoveToPoint");
        fn_line = (sf_cg_pt_fn)dlsym(RTLD_DEFAULT, "CGContextAddLineToPoint");
        fn_lw = (sf_cg_lw_fn)dlsym(RTLD_DEFAULT, "CGContextSetLineWidth");
    }
    if (!fn_save || !fn_restore || !fn_frgba || !fn_frect) {
        if (g_orig_pdfv_drawRect) g_orig_pdfv_drawRect(self, _cmd, dirtyRect);
        return;
    }
    NSRect vbounds = ((NSRect (*)(id, SEL))objc_msgSend)(self, @selector(bounds));
    fn_save(ctx);
    fn_frgba(ctx, 0.863, 0.863, 0.878, 1.0);
    fn_frect(ctx, dirtyRect);
    /* Crisp 1px vertical separator along left edge + 1px top toolbar hairline */
    fn_frgba(ctx, 0.78, 0.78, 0.80, 1.0);
    fn_frect(ctx, NSMakeRect(0.0, 0.0, 1.0, vbounds.size.height));
    fn_frect(ctx, NSMakeRect(0.0, vbounds.size.height - 1.0, vbounds.size.width, 1.0));
    fn_restore(ctx);

    NSInteger box = [self respondsToSelector:@selector(displayBox)] ? ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(displayBox)) : 1;
    NSInteger mode = [self respondsToSelector:@selector(displayMode)] ? ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(displayMode)) : 1;
    CGFloat padX = 40.0;
    CGFloat padTop = 24.0;
    CGFloat pageGap = 20.0;
    CGFloat scale = [self respondsToSelector:@selector(scaleFactor)] ? ((CGFloat (*)(id, SEL))objc_msgSend)(self, @selector(scaleFactor)) : 1.0;
    if (isnan(scale) || isinf(scale) || scale <= 0.05) scale = 1.0;
    id p0 = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(doc, @selector(pageAtIndex:), 0);
    NSRect p0b = (p0 && [p0 respondsToSelector:@selector(boundsForBox:)]) ? ((NSRect (*)(id, SEL, NSInteger))objc_msgSend)(p0, @selector(boundsForBox:), box) : NSMakeRect(0, 0, 612, 792);
    CGFloat maxFitW = (vbounds.size.width > padX * 2.0 + 40.0) ? (vbounds.size.width - padX * 2.0) : vbounds.size.width;
    if (p0b.size.width > 1.0 && p0b.size.width * scale > maxFitW) {
        scale = maxFitW / p0b.size.width;
    }
    const char *fitEnv = getenv("SF_PREVIEW_FIT_PAGE");
    if (fitEnv && fitEnv[0] == '1' && p0b.size.height > 1.0) {
        CGFloat maxFitH = (vbounds.size.height > padTop * 2.0 + 40.0) ? (vbounds.size.height - padTop * 2.0) : vbounds.size.height;
        CGFloat sh = maxFitH / p0b.size.height;
        if (sh < scale) scale = sh;
    }

    NSUInteger first = 0, last = pageCount;
    if (mode == 0 && [self respondsToSelector:@selector(currentPage)]) {
        id cur = ((id (*)(id, SEL))objc_msgSend)(self, @selector(currentPage));
        NSUInteger idx = (cur && [doc respondsToSelector:@selector(indexForPage:)]) ? ((NSUInteger (*)(id, SEL, id))objc_msgSend)(doc, @selector(indexForPage:), cur) : 0;
        if (idx < pageCount) { first = idx; last = idx + 1; }
    }
    const char *spEnv = getenv("SF_PREVIEW_START_PAGE");
    if (spEnv && spEnv[0]) {
        long sp = strtol(spEnv, NULL, 10);
        if (sp >= 1 && (NSUInteger)sp <= pageCount) {
            first = (NSUInteger)(sp - 1);
            last = pageCount;
        }
    }

    CGFloat totalDocH = padTop * 2.0 + (CGFloat)pageCount * (floor(p0b.size.height * scale) + pageGap);
    CGFloat top = NSMaxY(vbounds) - padTop;
    for (NSUInteger i = first; i < last; i++) {
        id page = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(doc, @selector(pageAtIndex:), i);
        if (!page) continue;
        NSRect pb = ((NSRect (*)(id, SEL, NSInteger))objc_msgSend)(page, @selector(boundsForBox:), box);
        if (pb.size.width <= 0 || pb.size.height <= 0) continue;
        CGFloat pw = floor(pb.size.width * scale);
        CGFloat ph = floor(pb.size.height * scale);
        CGFloat px = floor(NSMinX(vbounds) + (vbounds.size.width - 14.0 - pw) * 0.5);
        CGFloat py = floor(top - ph);
        if (py + ph >= NSMinY(dirtyRect) - 10.0 && py <= NSMaxY(dirtyRect) + 10.0) {
            fn_save(ctx);
            fn_frgba(ctx, 0.0, 0.0, 0.0, 0.045);
            fn_frect(ctx, NSMakeRect(px - 2.0, py - 5.0, pw + 4.0, ph + 5.0));
            fn_frgba(ctx, 0.0, 0.0, 0.0, 0.075);
            fn_frect(ctx, NSMakeRect(px - 1.0, py - 3.0, pw + 2.0, ph + 3.0));
            fn_frgba(ctx, 0.0, 0.0, 0.0, 0.10);
            fn_frect(ctx, NSMakeRect(px, py - 1.5, pw, ph + 1.5));
            fn_frgba(ctx, 1.0, 1.0, 1.0, 1.0);
            fn_frect(ctx, NSMakeRect(px, py, pw, ph));
            fn_restore(ctx);

            fn_save(ctx);
            fn_trans(ctx, px, py);
            fn_scale(ctx, scale, scale);
            fn_trans(ctx, -pb.origin.x, -pb.origin.y);
            ((void (*)(id, SEL, NSInteger, void *))objc_msgSend)(page, @selector(drawWithBox:toContext:), box, ctx);
            fn_restore(ctx);

            if (fn_srgba && fn_srect && fn_lw) {
                fn_save(ctx);
                fn_srgba(ctx, 0.0, 0.0, 0.0, 0.16);
                fn_lw(ctx, 1.0);
                fn_srect(ctx, NSMakeRect(px + 0.5, py + 0.5, pw - 1.0, ph - 1.0));
                fn_restore(ctx);
            }
        }
        top = py - pageGap;
    }

    /* Authentic macOS Light Mode overlay scrollbar along right edge of document canvas when content overflows vertically */
    if (totalDocH > vbounds.size.height + 4.0 && fn_begin && fn_move && fn_line && fn_close && fn_fillpath) {
        CGFloat trackInset = 6.0;
        CGFloat trackH = vbounds.size.height - trackInset * 2.0;
        CGFloat frac = vbounds.size.height / totalDocH;
        if (frac < 0.12) frac = 0.12;
        if (frac > 0.90) frac = 0.90;
        CGFloat thumbH = floor(trackH * frac);
        if (thumbH < 40.0) thumbH = 40.0;
        CGFloat thumbW = 7.0;
        CGFloat thumbX = NSMaxX(vbounds) - thumbW - 4.0;
        CGFloat scrollFrac = (pageCount > 1) ? ((CGFloat)first / (CGFloat)(pageCount - 1)) : 0.0;
        CGFloat thumbY = NSMaxY(vbounds) - trackInset - thumbH - floor((trackH - thumbH) * scrollFrac);
        NSRect thumb = NSMakeRect(thumbX, thumbY, thumbW, thumbH);
        fn_save(ctx);
        /* Subtle translucent track slot */
        fn_frgba(ctx, 0.0, 0.0, 0.0, 0.04);
        fn_frect(ctx, NSMakeRect(NSMaxX(vbounds) - 14.0, 0.0, 14.0, vbounds.size.height - 1.0));
        fn_frgba(ctx, 0.0, 0.0, 0.0, 0.08);
        fn_frect(ctx, NSMakeRect(NSMaxX(vbounds) - 14.0, 0.0, 1.0, vbounds.size.height - 1.0));
        /* Rounded macOS overlay scrollbar thumb */
        fn_frgba(ctx, 0.0, 0.0, 0.0, 0.36);
        sf_add_rounded_rect(ctx, thumb, 3.5, fn_begin, fn_move, fn_line, fn_close);
        fn_fillpath(ctx);
        if (fn_srgba && fn_lw && fn_strokepath) {
            fn_srgba(ctx, 1.0, 1.0, 1.0, 0.35);
            fn_lw(ctx, 1.0);
            sf_add_rounded_rect(ctx, NSMakeRect(thumb.origin.x - 0.5, thumb.origin.y - 0.5, thumb.size.width + 1.0, thumb.size.height + 1.0),
                                4.0, fn_begin, fn_move, fn_line, fn_close);
            fn_strokepath(ctx);
        }
        fn_restore(ctx);
    }
}

__attribute__((constructor))
static void sf_install_macos_visual_parity(void) {
    Class imgCls = objc_lookUpClass("NSImage");
    if (imgCls) {
        Method m = class_getClassMethod(imgCls, @selector(imageWithSystemSymbolName:accessibilityDescription:));
        if (m) g_orig_img_sys_sym = (id (*)(id, SEL, id, id))method_setImplementation(m, (IMP)sf_img_sys_sym_fallback);
    }
    Class tbiCls = objc_lookUpClass("NSToolbarItem");
    if (tbiCls) {
        Method m = class_getInstanceMethod(tbiCls, @selector(setView:));
        if (m) g_orig_tbi_setView = (void (*)(id, SEL, id))method_setImplementation(m, (IMP)sf_tbi_setView);
    }
    Class segCellCls = objc_lookUpClass("NSSegmentedCell");
    if (segCellCls) {
        Method m = class_getInstanceMethod(segCellCls, @selector(drawWithFrame:inView:));
        if (m) g_orig_segcell_draw = (void (*)(id, SEL, NSRect, id))method_setImplementation(m, (IMP)sf_segcell_macos_draw);
    }
    Class tbvCls = objc_lookUpClass("NSToolbarView");
    if (tbvCls) {
        Method m1 = class_getInstanceMethod(tbvCls, @selector(layoutViewsWithWidth:setFrame:));
        if (m1) g_orig_tbv_layout = (void (*)(id, SEL, CGFloat, BOOL))method_setImplementation(m1, (IMP)sf_tbv_macos_layout);
        Method m2 = class_getInstanceMethod(tbvCls, @selector(drawRect:));
        if (m2) g_orig_tbv_drawRect = (void (*)(id, SEL, NSRect))method_setImplementation(m2, (IMP)sf_tbv_macos_drawRect);
    }
    Class cvCls = objc_lookUpClass("NSCollectionView");
    if (cvCls) {
        Method m = class_getInstanceMethod(cvCls, @selector(_finchLayOutItems));
        if (m) g_orig_cv_layout = (void (*)(id, SEL))method_setImplementation(m, (IMP)sf_cv_center_items);
    }
    Class pdfvCls = objc_lookUpClass("PDFView");
    if (pdfvCls) {
        Method m = class_getInstanceMethod(pdfvCls, @selector(drawRect:));
        if (m) g_orig_pdfv_drawRect = (void (*)(id, SEL, NSRect))method_setImplementation(m, (IMP)sf_pdfv_macos_drawRect);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        Class pvsb = objc_lookUpClass("PVSidebarView");
        if (pvsb) {
            Method m = class_getInstanceMethod(pvsb, @selector(drawRect:));
            if (m) g_orig_sv_drawRect = (void (*)(id, SEL, NSRect))method_setImplementation(m, (IMP)sf_pvsidebar_drawRect);
        }
    });
}

/* Fix SwiftUI Text (CGDrawingLayer -> NSAttributedString drawWithRect:options:context:) vertical baseline offset
 * when OpenSwiftUI draws into a flipped NSGraphicsContext with no focusView (opts includes NSStringDrawingUsesLineFragmentOrigin). */
static void (*g_orig_as_draw_ctx)(id, SEL, NSRect, NSUInteger, id) = NULL;
static void sf_as_draw_with_rect_ctx(id self, SEL _cmd, NSRect r, NSUInteger opts, id ctx) {
    id gc = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSGraphicsContext"), @selector(currentContext));
    BOOL fl = (gc && [gc respondsToSelector:@selector(isFlipped)]) ? ((BOOL (*)(id, SEL))objc_msgSend)(gc, @selector(isFlipped)) : NO;
    id fv = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSView"), @selector(focusView));
    if (fl && !fv && (opts & 1) && r.size.height > 4.0) {
        CGFloat shift = 8.0;
        if ([self respondsToSelector:@selector(length)] && ((NSUInteger (*)(id, SEL))objc_msgSend)(self, @selector(length)) > 0 &&
            [self respondsToSelector:@selector(attribute:atIndex:effectiveRange:)]) {
            id font = ((id (*)(id, SEL, id, NSUInteger, void *))objc_msgSend)(
                self, @selector(attribute:atIndex:effectiveRange:), @"NSFont", 0, NULL);
            if (font && [font respondsToSelector:@selector(ascender)]) {
                CGFloat asc = ((CGFloat (*)(id, SEL))objc_msgSend)(font, @selector(ascender));
                CGFloat desc = [font respondsToSelector:@selector(descender)] ? fabs(((CGFloat (*)(id, SEL))objc_msgSend)(font, @selector(descender))) : 3.0;
                if (asc > 4.0 && asc < 40.0) {
                    /* Center glyphs inside r.size.height without clipping either ascenders or descenders */
                    shift = floor((asc + desc) * 0.50);
                    if (shift > r.size.height * 0.45) shift = floor(r.size.height * 0.45);
                }
            }
        }
        r.origin.y -= shift;
    }
    if (g_orig_as_draw_ctx) g_orig_as_draw_ctx(self, _cmd, r, opts, ctx);
}

/* Prevent Finch invisible mouse/tooltip tracking views (_FinchMouseRegion.RegionView) from triggering opaque-ancestor
 * background repaints over SwiftUI selection pills behind them. */
static void (*g_orig_view_did_move_win)(id, SEL) = NULL;
static void sf_view_did_move_win(id self, SEL _cmd) {
    if (g_orig_view_did_move_win) g_orig_view_did_move_win(self, _cmd);
    const char *cn = object_getClassName(self);
    if (cn && (strstr(cn, "_FinchMouseRegion") != NULL)) {
        if ([self respondsToSelector:@selector(setHidden:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setHidden:), YES);
        }
    }
}

static void sf_akmc_setPageModelControllers(id self, SEL _cmd, id pages) {
    (void)_cmd;
    NSArray *arr = [pages isKindOfClass:[NSArray class]] ? (NSArray *)pages : @[];
    if ([self respondsToSelector:sel_registerName("sfSetPageModelControllers:")]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("sfSetPageModelControllers:"), arr);
    }
}

static id sf_ak_toolbarButtonItem(id self, SEL _cmd, NSUInteger type, NSUInteger style) {
    (void)self; (void)_cmd; (void)type; (void)style;
    Class viewCls = objc_lookUpClass("NSView");
    Class segCls = objc_lookUpClass("NSSegmentedControl");
    if (!viewCls || !segCls) return nil;
    id wrap = [((id (*)(id, SEL, NSRect))objc_msgSend)([viewCls alloc], @selector(initWithFrame:), NSMakeRect(0, 0, 60, 28)) autorelease];
    id seg = [((id (*)(id, SEL, NSRect))objc_msgSend)([segCls alloc], @selector(initWithFrame:), NSMakeRect(0, 0, 60, 28)) autorelease];
    if (seg) {
        if ([seg respondsToSelector:@selector(setSegmentCount:)])
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(seg, @selector(setSegmentCount:), 1);
        id img = sf_render_sf_symbol(@"highlighter");
        if (img && [seg respondsToSelector:@selector(setImage:forSegment:)])
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(seg, @selector(setImage:forSegment:), img, 0);
        if ([seg respondsToSelector:@selector(setWidth:forSegment:)])
            ((void (*)(id, SEL, CGFloat, NSInteger))objc_msgSend)(seg, @selector(setWidth:forSegment:), 34.0, 0);
        if ([seg respondsToSelector:@selector(setEnabled:forSegment:)])
            ((void (*)(id, SEL, BOOL, NSInteger))objc_msgSend)(seg, @selector(setEnabled:forSegment:), YES, 0);
        if (wrap && [wrap respondsToSelector:@selector(addSubview:)])
            ((void (*)(id, SEL, id))objc_msgSend)(wrap, @selector(addSubview:), seg);
    }
    if (getenv("SF_LOG_EXC")) {
        NSArray *subs = [wrap respondsToSelector:@selector(subviews)] ? ((id (*)(id, SEL))objc_msgSend)(wrap, @selector(subviews)) : nil;
        id fo = [subs respondsToSelector:@selector(firstObject)] ? ((id (*)(id, SEL))objc_msgSend)(subs, @selector(firstObject)) : nil;
        fprintf(stderr, "SF_AK_TB type=%lu wrap=%p subs=%lu fo=%s isSeg=%d\n",
                (unsigned long)type, (void *)wrap, (unsigned long)[subs count],
                fo ? object_getClassName(fo) : "nil", (int)[fo isKindOfClass:segCls]);
        fflush(stderr);
    }
    return wrap;
}

static void sf_patch_ak_model_controller(void) {
    static int s_done = 0;
    if (s_done) return;
    Class akmc = objc_lookUpClass("AKModelController");
    Class akc = objc_lookUpClass("AKController");
    if (akmc && !class_respondsToSelector(akmc, sel_registerName("setPageModelControllers:"))) {
        class_addMethod(akmc, sel_registerName("setPageModelControllers:"), (IMP)sf_akmc_setPageModelControllers, "v@:@");
    }
    if (akc) {
        class_replaceMethod(akc, sel_registerName("toolbarButtonItemOfType:style:"), (IMP)sf_ak_toolbarButtonItem, "@@:QQ");
        s_done = 1;
    }
}

static id (*g_orig_exc_create)(id, SEL, id, id, id) = NULL;
static id sf_exc_create_log(id self, SEL _cmd, id nm, id rs, id ui) {
    if (getenv("SF_LOG_EXC")) {
        fprintf(stderr, "SF_NS_EXCEPTION_NEW name=%s reason=%s\n", nm ? [[nm description] UTF8String] : "?", rs ? [[rs description] UTF8String] : "?");
        fflush(stderr);
    }
    return g_orig_exc_create ? g_orig_exc_create(self, _cmd, nm, rs, ui) : nil;
}

static void (*g_orig_exc_raise)(id, SEL) = NULL;
static void sf_exc_raise_log(id self, SEL _cmd) {
    if (getenv("SF_LOG_EXC")) {
        NSString *nm = [self respondsToSelector:@selector(name)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(name)) : @"?";
        NSString *rs = [self respondsToSelector:@selector(reason)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(reason)) : @"?";
        fprintf(stderr, "SF_NS_EXCEPTION name=%s reason=%s\n", nm ? [nm UTF8String] : "?", rs ? [rs UTF8String] : "?");
        fflush(stderr);
    }
    if (g_orig_exc_raise) g_orig_exc_raise(self, _cmd);
}

__attribute__((constructor))
static void sf_install_swiftui_text_baseline_fix(void) {
    Class as = objc_lookUpClass("NSAttributedString");
    if (as) {
        Method m = class_getInstanceMethod(as, @selector(drawWithRect:options:context:));
        if (m) g_orig_as_draw_ctx = (void (*)(id, SEL, NSRect, NSUInteger, id))method_setImplementation(m, (IMP)sf_as_draw_with_rect_ctx);
    }
    Class v = objc_lookUpClass("NSView");
    if (v) {
        Method m = class_getInstanceMethod(v, @selector(viewDidMoveToWindow));
        if (m) g_orig_view_did_move_win = (void (*)(id, SEL))method_setImplementation(m, (IMP)sf_view_did_move_win);
    }
    sf_patch_ak_model_controller();
    dispatch_async(dispatch_get_main_queue(), ^{ sf_patch_ak_model_controller(); });
    Class ex = objc_lookUpClass("NSException");
    if (ex) {
        Method m = class_getInstanceMethod(ex, @selector(raise));
        if (m) g_orig_exc_raise = (void (*)(id, SEL))method_setImplementation(m, (IMP)sf_exc_raise_log);
        Method cm = class_getClassMethod(ex, @selector(exceptionWithName:reason:userInfo:));
        if (cm) g_orig_exc_create = (id (*)(id, SEL, id, id, id))method_setImplementation(cm, (IMP)sf_exc_create_log);
    }
}
