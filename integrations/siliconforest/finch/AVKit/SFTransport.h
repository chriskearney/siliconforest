/* SPDX-License-Identifier: MIT */
#import <AppKit/AppKit.h>
@class AVPlayerView,AVPlayerLayer;
@interface SFTransportView:NSView { AVPlayerView *_playerView;NSUInteger _draws;int _tracking;NSPoint _lastMouse;double _lastActivity; }
- (BOOL)sfIdleHidden;
- (void)setPlayerView:(AVPlayerView *)view;
- (NSUInteger)drawCount;
@end
@interface SFPlayerDrawToken:NSObject { AVPlayerView *_owner; }
@property(assign) AVPlayerView *owner;
@end
BOOL SFDrawPlayerContents(AVPlayerView *view,AVPlayerLayer *layer);
NSRect SFControlsFrame(AVPlayerView *view);
