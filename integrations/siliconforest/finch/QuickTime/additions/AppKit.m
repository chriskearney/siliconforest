/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * AppKit names QuickTime Player binds that SiliconForest's AppKit (15 November) lacks. */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stddef.h>
#include "absent.h"

/* Bindings are named by the property they bind: documented values. */
#if !defined(SF_OMIT_NSEnabledBinding) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0340 */
SF_EXPORT NSString *const NSEnabledBinding = @"enabled";
#endif
#if !defined(SF_OMIT_NSHiddenBinding) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0340 */
SF_EXPORT NSString *const NSHiddenBinding = @"hidden";
#endif
#if !defined(SF_OMIT_NSTitleBinding) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0340 */
SF_EXPORT NSString *const NSTitleBinding = @"title";
#endif
#if !defined(SF_OMIT_NSToolTipBinding) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0340 */
SF_EXPORT NSString *const NSToolTipBinding = @"toolTip";
#endif

/* Text styles are opaque keys for +[NSFont preferredFontForTextStyle:options:]. The values
 * are the ones UIKit and CoreText share; believed correct, not verified against macOS. */
#if !defined(SF_OMIT_NSFontTextStyle) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0340 */
SF_EXPORT NSString *const NSFontTextStyleLargeTitle = @"UICTFontTextStyleTitle0";
SF_EXPORT NSString *const NSFontTextStyleTitle1 = @"UICTFontTextStyleTitle1";
SF_EXPORT NSString *const NSFontTextStyleTitle3 = @"UICTFontTextStyleTitle3";
SF_EXPORT NSString *const NSFontTextStyleCaption1 = @"UICTFontTextStyleCaption1";
#endif

/* Private names. A notification nobody posts here, an image our AppKit has no drawing for
 * (imageNamed: answers nil), and the name of a menu AppKit would manage. Values inferred. */
#ifndef SF_OMIT_NSWindowWillOrderOnScreenNotification
SF_EXPORT NSString *const NSWindowWillOrderOnScreenNotification = @"NSWindowWillOrderOnScreenNotification";
#endif
#ifndef SF_OMIT_NSImageNameToolbarBookmarks
SF_EXPORT NSString *const NSImageNameToolbarBookmarks = @"NSToolbarBookmarks";
#endif
#ifndef SF_OMIT_NSRecentDocumentsMenuName
SF_EXPORT NSString *const NSRecentDocumentsMenuName = @"NSRecentDocumentsMenu";
#endif

/* A click recogniser in the manner of this AppKit's other recognisers: it keeps its
 * configuration and recognises nothing. */
#if !defined(SF_OMIT_NSClickGestureRecognizer) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0340 */
@interface NSGestureRecognizer : NSObject
@end
SF_EXPORT
@interface NSClickGestureRecognizer : NSGestureRecognizer {
    NSUInteger _sfButtonMask;
    NSInteger _sfClicks, _sfTouches;
}
@end
@implementation NSClickGestureRecognizer
- (void)sfDefaults {
    SF_ABSENT("NSClickGestureRecognizer keeps its configuration but recognises no clicks");
    _sfButtonMask = 1;
    _sfClicks = 1;
    _sfTouches = 1;
}
- (id)init {
    if ((self = [super init])) [self sfDefaults];
    return self;
}
- (id)initWithTarget:(id)target action:(SEL)action {
    struct objc_super sup = {self, [NSGestureRecognizer class]};
    self = ((id (*)(struct objc_super *, SEL, id, SEL))objc_msgSendSuper)(&sup, _cmd, target, action);
    if (self) [self sfDefaults];
    return self;
}
- (id)initWithCoder:(NSCoder *)coder {
    struct objc_super sup = {self, [NSGestureRecognizer class]};
    self = ((id (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, coder);
    if (self) [self sfDefaults];
    return self;
}
- (NSUInteger)buttonMask { return _sfButtonMask; }
- (void)setButtonMask:(NSUInteger)mask { _sfButtonMask = mask; }
- (NSInteger)numberOfClicksRequired { return _sfClicks; }
- (void)setNumberOfClicksRequired:(NSInteger)n { _sfClicks = n; }
- (NSInteger)numberOfTouchesRequired { return _sfTouches; }
- (void)setNumberOfTouchesRequired:(NSInteger)n { _sfTouches = n; }
@end
#endif

/* QuickTime Player extends AppKit's private About-panel class with a category that reads
 * two of its instance variables by offset. The offsets belong to the class, so they can
 * only be right if AppKit's class has those variables. At load:
 *   copyrightView       our class's copyrightView if it has one, else its legalTextField
 *                       (the same field under Cocotron's name);
 *   _optionsDictionary  our class's if it has one. If not, there is nothing honest to point
 *                       at: the offset stays 0 and using the About panel will fail. This is
 *                       said at load. The fix is two instance variables in AppKit. */
#if !defined(SF_OMIT_NSSystemInfoPanel_ivars) && !defined(SF_MOVED) /* in AppKit: cocoa patch 0364 (with the class's own variables the
   offsets below resolve to them; this stays for an AppKit without them) */
SF_EXPORT ptrdiff_t SFAboutCopyrightViewOffset __asm__("_OBJC_IVAR_$_NSSystemInfoPanel.copyrightView") = 0;
SF_EXPORT ptrdiff_t SFAboutOptionsDictionaryOffset __asm__("_OBJC_IVAR_$_NSSystemInfoPanel._optionsDictionary") = 0;
__attribute__((constructor)) static void SFResolveAboutPanelOffsets(void) {
    Class panel = objc_getClass("NSSystemInfoPanel");
    Ivar copyright = panel ? class_getInstanceVariable(panel, "copyrightView") : NULL;
    if (!copyright && panel) copyright = class_getInstanceVariable(panel, "legalTextField");
    Ivar options = panel ? class_getInstanceVariable(panel, "_optionsDictionary") : NULL;
    if (copyright) SFAboutCopyrightViewOffset = ivar_getOffset(copyright);
    if (options) SFAboutOptionsDictionaryOffset = ivar_getOffset(options);
    if (!copyright || !options)
        fputs("SiliconForest: AppKit's About panel class lacks the instance variables QuickTime Player reads "
              "(copyrightView, _optionsDictionary); its About panel will not work\n", stderr);
}
#endif
