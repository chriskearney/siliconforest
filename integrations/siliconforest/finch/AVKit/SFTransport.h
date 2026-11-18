/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
@class AVPlayerView,AVPlayerLayer;
@interface SFTransportView:NSView { AVPlayerView *_playerView;NSUInteger _draws;int _tracking;NSPoint _lastMouse;double _lastActivity;int _pressed; }
- (BOOL)sfIdleHidden;
- (void)setPlayerView:(AVPlayerView *)view;
- (NSUInteger)drawCount;
@end
@interface SFPlayerDrawToken:NSObject { AVPlayerView *_owner; }
@property(assign) AVPlayerView *owner;
@end
void SFUpdatePicturePixelSize(AVPlayerView *view,AVPlayerLayer *layer);
void SFFillOutsidePicture(AVPlayerView *view,AVPlayerLayer *layer,NSRect dirty);
NSRect SFControlsFrame(AVPlayerView *view);
