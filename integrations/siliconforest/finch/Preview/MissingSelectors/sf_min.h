/* Minimal declarations so Finch bodies compile against the cross SDK.
   Superclasses are the ones the reexported AppKit defines. No @implementation. */
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

typedef NSString *SFAttributeName;
typedef NSString *SFActionName;

@class NSEvent;

@interface NSView : NSObject
- (instancetype)initWithFrame:(NSRect)frame;
- (NSRect)bounds;
- (NSRect)frame;
- (void)setFrame:(NSRect)frame;
- (void)addSubview:(NSView *)view;
- (void)setAutoresizingMask:(NSUInteger)mask;
- (id)window;
- (BOOL)isFlipped;
- (BOOL)isEnabled;
- (void)setNeedsDisplay:(BOOL)flag;
- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)view;
- (BOOL)mouse:(NSPoint)point inRect:(NSRect)rect;
- (void)drawRect:(NSRect)dirty;
- (void)keyDown:(NSEvent *)event;
@end

@interface NSControl : NSView
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
- (BOOL)refusesFirstResponder;
- (SEL)action;
- (id)target;
- (BOOL)sendAction:(SEL)action to:(id)target;
@end

@interface NSColor : NSObject
+ (NSColor *)whiteColor;
+ (NSColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (NSColor *)colorWithSRGBRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
- (void)setFill;
- (void)setStroke;
- (CGFloat)alphaComponent;
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;
@end

@interface NSBezierPath : NSObject
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius yRadius:(CGFloat)yRadius;
- (void)fill;
- (void)stroke;
- (void)setLineWidth:(CGFloat)width;
@end

@interface NSScrollView : NSView
- (void)setDocumentView:(NSView *)view;
- (void)setHasVerticalScroller:(BOOL)flag;
- (void)setHasHorizontalScroller:(BOOL)flag;
- (NSView *)documentView;
- (NSView *)contentView;
@end

@interface NSImage : NSObject
- (NSSize)size;
- (void)drawInRect:(NSRect)rect;
@end

@interface NSPanel : NSView
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)flag;
- (NSView *)contentView;
- (void)setContentView:(NSView *)view;
@end

extern NSString *NSAccessibilityActionDescription(NSString *action);
