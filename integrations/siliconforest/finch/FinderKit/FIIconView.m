/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>

@interface FIIconView : NSView
@property (nonatomic, retain) NSImage *iconImage;
@property (nonatomic, copy) NSString *titleStr;
@property (nonatomic, copy) NSString *subtitleStr;
@property (nonatomic) NSSize iconImageSize;
@property (nonatomic) CGFloat titleFontSize;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, getter=isTitleEnabled) BOOL titleEnabled;
@property (nonatomic, getter=isSubtitleEnabled) BOOL subtitleEnabled;
@property (nonatomic, getter=isTitleOnBottom) BOOL titleOnBottom;
@property (nonatomic, retain) NSColor *titleFontColor;
@property (nonatomic, retain) NSColor *subtitleFontColor;
- (NSRect)iconFrame;
- (NSRect)titleFrame;
@end

@implementation FIIconView
- (void)initCommon
{
    _iconImageSize = NSMakeSize(32, 32);
    _titleOnBottom = YES;
    _titleEnabled = YES;
    _titleFontSize = 12;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) [self initCommon];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) [self initCommon];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setIconImage:(NSImage *)image { _iconImage = image; [self setNeedsDisplay:YES]; }
- (void)setTitleStr:(NSString *)title { _titleStr = [title copy]; [self setNeedsDisplay:YES]; }
- (void)setSubtitleStr:(NSString *)subtitle { _subtitleStr = [subtitle copy]; [self setNeedsDisplay:YES]; }
- (void)setIconImageSize:(NSSize)size { _iconImageSize = size; [self setNeedsDisplay:YES]; }
- (void)setTitleFontSize:(CGFloat)size { _titleFontSize = MAX(1, size); [self setNeedsDisplay:YES]; }
- (void)setSelected:(BOOL)selected { _selected = selected; [self setNeedsDisplay:YES]; }
- (void)setTitleEnabled:(BOOL)enabled { _titleEnabled = enabled; [self setNeedsDisplay:YES]; }
- (void)setSubtitleEnabled:(BOOL)enabled { _subtitleEnabled = enabled; [self setNeedsDisplay:YES]; }
- (void)setTitleOnBottom:(BOOL)bottom { _titleOnBottom = bottom; [self setNeedsDisplay:YES]; }
- (void)setTitleFontColor:(NSColor *)color { _titleFontColor = color; [self setNeedsDisplay:YES]; }
- (void)setSubtitleFontColor:(NSColor *)color { _subtitleFontColor = color; [self setNeedsDisplay:YES]; }

- (NSRect)iconFrame
{
    NSRect bounds = [self bounds];
    CGFloat width = MIN(NSWidth(bounds), MAX(0, _iconImageSize.width));
    CGFloat height = MIN(NSHeight(bounds), MAX(0, _iconImageSize.height));
    CGFloat x = _titleOnBottom ? NSMidX(bounds) - width / 2 : NSMinX(bounds);
    CGFloat y = _titleOnBottom ? NSMinY(bounds) : NSMidY(bounds) - height / 2;
    return NSMakeRect(x, y, width, height);
}

- (NSRect)titleFrame
{
    NSRect bounds = [self bounds];
    NSRect icon = [self iconFrame];
    if (_titleOnBottom)
        return NSMakeRect(NSMinX(bounds), NSMaxY(icon), NSWidth(bounds), MAX(0, NSMaxY(bounds) - NSMaxY(icon)));
    return NSMakeRect(NSMaxX(icon), NSMinY(bounds), MAX(0, NSMaxX(bounds) - NSMaxX(icon)), NSHeight(bounds));
}

- (NSView *)hitTestInIcon:(NSPoint)point { return NSPointInRect(point, [self iconFrame]) ? self : nil; }
- (NSView *)hitTestInText:(NSPoint)point
{
    return (_titleEnabled || _subtitleEnabled) && NSPointInRect(point, [self titleFrame]) ? self : nil;
}
- (NSView *)hitTestInIconOrText:(NSPoint)point { return [self hitTestInIcon:point] ?: [self hitTestInText:point]; }

- (void)drawRect:(NSRect)dirtyRect
{
    if (_selected) {
        [[NSColor selectedControlColor] setFill];
        NSRectFill(NSIntersectionRect(dirtyRect, [self bounds]));
    }
    [_iconImage drawInRect:[self iconFrame] fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
    NSRect text = [self titleFrame];
    CGFloat lineHeight = _titleFontSize + 3;
    NSFont *font = [NSFont systemFontOfSize:_titleFontSize];
    if (_titleEnabled) {
        [_titleStr drawInRect:NSMakeRect(NSMinX(text), NSMinY(text), NSWidth(text), MIN(lineHeight, NSHeight(text)))
               withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: _titleFontColor ?: [NSColor controlTextColor]}];
        text.origin.y += lineHeight;
        text.size.height -= lineHeight;
    }
    if (_subtitleEnabled && NSHeight(text) > 0)
        [_subtitleStr drawInRect:text withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: _subtitleFontColor ?: [NSColor secondaryLabelColor]}];
}
@end
