/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
 *
 * Link-time stand-ins only. An additions library re-exports the system's own image of the
 * same framework, which the launcher's preparation step links beside it as
 * "<Name>.sf-under". When the additions subclass a class of that image, the linker needs a
 * library with that install name that exports the class: this file, compiled with SF_STANDIN
 * naming the framework. It is never shipped and never loaded. */
#import <Foundation/Foundation.h>
#define SF_EXPORT __attribute__((visibility("default")))
#if SF_STANDIN == 1 /* AppKit */
SF_EXPORT @interface NSGestureRecognizer : NSObject @end
@implementation NSGestureRecognizer @end
#elif SF_STANDIN == 2 /* QuartzCore */
SF_EXPORT @interface CAAnimation : NSObject @end
@implementation CAAnimation @end
SF_EXPORT @interface CAPropertyAnimation : CAAnimation @end
@implementation CAPropertyAnimation @end
SF_EXPORT @interface CALayer : NSObject @end
@implementation CALayer @end
#elif SF_STANDIN == 3 /* AVFoundation */
SF_EXPORT @interface AVAsset : NSObject @end
@implementation AVAsset @end
SF_EXPORT @interface AVCaptureOutput : NSObject @end
@implementation AVCaptureOutput @end
SF_EXPORT @interface AVAssetReaderOutput : NSObject @end
@implementation AVAssetReaderOutput @end
#elif SF_STANDIN == 4 /* Foundation */
SF_EXPORT @interface NSScriptObjectSpecifier : NSObject @end
@implementation NSScriptObjectSpecifier @end
#elif SF_STANDIN == 5 /* AppKit by its public path, for symbols re-exported from it */
SF_EXPORT @interface NSFileWrapper : NSObject @end
@implementation NSFileWrapper @end
#else
const char SFStandInHasNoSymbols = 0;
#endif
