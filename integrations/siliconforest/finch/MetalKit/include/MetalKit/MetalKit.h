/* SPDX-License-Identifier: MIT */
#ifndef SF_METALKIT_H
#define SF_METALKIT_H
#import <AppKit/NSView.h>
#import <QuartzCore/CAMetalLayer.h>

@class MTKView, MTLRenderPassDescriptor, MTL4RenderPassDescriptor;
@protocol MTLDevice, MTLTexture, MTLResidencySet;
typedef NSUInteger MTLPixelFormat;
typedef NSUInteger MTLTextureUsage;
typedef NSUInteger MTLStorageMode;
typedef struct MTLClearColor { double red, green, blue, alpha; } MTLClearColor;
static inline MTLClearColor MTLClearColorMake(double red, double green, double blue, double alpha) {
    return (MTLClearColor){ red, green, blue, alpha };
}

enum { MTLTextureUsageRenderTarget = 4, MTLStorageModePrivate = 2, MTLPixelFormatInvalid = 0 };

@protocol MTKViewDelegate <NSObject>
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(MTKView *)view;
@end

@interface MTKView : NSView
- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device;
- (void)updateDrawableSize;
@property(nonatomic, weak) id<MTKViewDelegate> delegate;
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic) CGSize drawableSize;
@property(nonatomic, readonly) id<CAMetalDrawable> currentDrawable;
@property(nonatomic) NSInteger preferredFramesPerSecond;
@property(nonatomic, getter=isPaused) BOOL paused;
- (void)draw;
@end

#endif
