/* SPDX-License-Identifier: MIT */
#if __has_feature(modules)
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import <AppKit/NSViewController.h>

/* Original rendering bridge, not a declaration of Apple's private PaperKit. */
void SFPaperDisplay(NSViewController *controller, NSURL *url, BOOL readOnly);
