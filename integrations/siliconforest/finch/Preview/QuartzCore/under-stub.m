/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Link-time stand-in for @loader_path/QuartzCore.sf-under.
 * Runtime still binds that install name to the system QuartzCore. The stub only
 * exists so the linker can see the superclass symbols this overlay subclasses. */
#import <Foundation/Foundation.h>

__attribute__((visibility("default")))
@interface CALayer : NSObject
@end
@implementation CALayer
@end

__attribute__((visibility("default")))
@interface CAPropertyAnimation : NSObject
@end
@implementation CAPropertyAnimation
@end

__attribute__((visibility("default")))
@interface CABasicAnimation : NSObject
@end
@implementation CABasicAnimation
@end
