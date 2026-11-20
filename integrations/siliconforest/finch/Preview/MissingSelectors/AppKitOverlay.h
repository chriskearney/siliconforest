#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, NSCompositingOperation) {
    NSCompositingOperationClear = 0,
    NSCompositingOperationCopy = 1,
    NSCompositingOperationSourceOver = 2,
    NSCompositingOperationSourceIn = 3,
    NSCompositingOperationSourceOut = 4,
    NSCompositingOperationSourceAtop = 5,
    NSCompositingOperationDestinationOver = 6,
    NSCompositingOperationDestinationIn = 7,
    NSCompositingOperationDestinationOut = 8,
    NSCompositingOperationDestinationAtop = 9,
    NSCompositingOperationXOR = 10,
    NSCompositingOperationPlusDarker = 11,
    NSCompositingOperationHighlight = 12,
    NSCompositingOperationPlusLighter = 13
};

/* The C entry point exported by AppKit.sf-under. The Swift overlay replaces the
   argv type; this declaration keeps the linker symbol and a distinct Swift name. */
/* char ** matches the Swift argv type. The asm name is the C entry point. */
extern int sf_NSApplicationMain(int argc, char **argv) __asm__("_NSApplicationMain");
extern void NSRectFillUsingOperation(CGRect rect, NSCompositingOperation operation);

@interface NSMenuItem : NSObject
+ (NSMenuItem *)sectionHeaderWithTitle:(NSString *)title;
@end

@interface NSGraphicsContext : NSObject
+ (NSGraphicsContext *)currentContext;
@end
