/* SPDX-License-Identifier: MIT */
/* Our transport shapes and CPU fallback; they consume actual AVPlayerLayer
 * contents. No system image catalogue or fictitious playback service.
 *
 * Two looks (QTP, 18 November): the inline style is the bar under the picture; the floating style (the one
 * QuickTime Player asks for) is a rounded translucent panel over the bottom of the picture, drawn here from
 * shapes: volume, skip back and forward 15 s, play/pause, full screen, and a scrubber between the elapsed and
 * remaining time. The picture then fills the whole view. */
#import <AVKit/AVKit.h>
#import "SFTransport.h"
#include <math.h>
#include <objc/message.h>
@interface AVPlayerView(SFTransportActions)
- (void)_togglePlayback:(id)sender;
@end
@implementation SFPlayerDrawToken
@synthesize owner=_owner;
@end

#define SF_HUD_HEIGHT 66.0
#define SF_HUD_MAX_WIDTH 480.0
#define SF_HUD_BOTTOM 18.0
#define SF_SKIP_SECONDS 15.0

NSRect SFControlsFrame(AVPlayerView *view){
 NSRect b=view.bounds;
 if(view.controlsStyle==AVPlayerViewControlsStyleFloating){
  CGFloat w=MIN(SF_HUD_MAX_WIDTH,NSWidth(b)-32);if(w<200)w=MIN(200,NSWidth(b));
  return NSMakeRect(floor(NSMidX(b)-w/2),NSMinY(b)+SF_HUD_BOTTOM,w,SF_HUD_HEIGHT);
 }
 return NSMakeRect(0,0,NSWidth(b),38);
}

static NSString *SFTimeText(double seconds){
 if(!isfinite(seconds)||seconds<0)seconds=0;
 long total=(long)floor(seconds+.5);long h=total/3600,m=(total/60)%60,s=total%60;
 return h?[NSString stringWithFormat:@"%ld:%02ld:%02ld",h,m,s]:[NSString stringWithFormat:@"%ld:%02ld",m,s];
}

/* the floating panel's parts, in the panel's coordinates */
typedef struct { NSRect volumeIcon,volume,back,play,forward,fullScreen,scrubber,elapsed,remaining; } SFHudLayout;
static SFHudLayout SFHud(NSRect b){
 SFHudLayout l;CGFloat top=NSMaxY(b)-24,mid=NSMidX(b);
 l.volumeIcon=NSMakeRect(14,top-8,16,16);
 l.volume=NSMakeRect(36,top-6,72,12);
 l.back=NSMakeRect(mid-62,top-11,30,22);
 l.play=NSMakeRect(mid-13,top-13,26,26);
 l.forward=NSMakeRect(mid+32,top-11,30,22);
 l.fullScreen=NSMakeRect(NSMaxX(b)-34,top-9,18,18);
 l.elapsed=NSMakeRect(10,10,52,14);
 l.remaining=NSMakeRect(NSMaxX(b)-62,10,52,14);
 l.scrubber=NSMakeRect(66,13,NSWidth(b)-132,8);
 return l;
}

static void SFTriangle(NSPoint a,NSPoint b,NSPoint c){NSBezierPath *p=[NSBezierPath bezierPath];[p moveToPoint:a];[p lineToPoint:b];[p lineToPoint:c];[p closePath];[p fill];}

@implementation SFTransportView
- (void)setPlayerView:(AVPlayerView *)view {_playerView=view;}
- (NSUInteger)drawCount{return _draws;}
- (BOOL)isFloating{return _playerView.controlsStyle==AVPlayerViewControlsStyleFloating;}
- (double)duration{double d=CMTimeGetSeconds(_playerView.player.currentItem.duration);return isfinite(d)&&d>0?d:0;}
- (double)current{double t=CMTimeGetSeconds(_playerView.player.currentTime);return isfinite(t)?t:0;}
- (void)drawRect:(NSRect)dirty {
 (void)dirty;_draws++;
 if([self isFloating]){[self drawFloating];return;}
 [[NSColor colorWithCalibratedWhite:.12 alpha:1] set];NSRectFill(self.bounds);
 [[NSColor whiteColor] set];
 if(_playerView.player.rate==0){NSBezierPath *play=[NSBezierPath bezierPath];[play moveToPoint:NSMakePoint(15,9)];[play lineToPoint:NSMakePoint(15,29)];[play lineToPoint:NSMakePoint(32,19)];[play closePath];[play fill];}
 else {NSRectFill(NSMakeRect(15,9,5,20));NSRectFill(NSMakeRect(25,9,5,20));}
 CGFloat width=NSWidth(self.bounds)-70;if(width<1)return;
 [[NSColor colorWithCalibratedWhite:.35 alpha:1] set];NSRectFill(NSMakeRect(50,16,width,6));
 double duration=CMTimeGetSeconds(_playerView.player.currentItem.duration),time=CMTimeGetSeconds(_playerView.player.currentTime);
 double fraction=isfinite(duration)&&duration>0&&isfinite(time)?MAX(0,MIN(1,time/duration)):0;
 [[NSColor colorWithCalibratedRed:.2 green:.65 blue:1 alpha:1] set];NSRectFill(NSMakeRect(50,16,width*fraction,6));
}
- (void)drawFloating {
 NSRect b=self.bounds;SFHudLayout l=SFHud(b);
 [[NSColor colorWithCalibratedWhite:.08 alpha:.72] set];
 [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b,.5,.5) xRadius:14 yRadius:14] fill];
 [[NSColor colorWithCalibratedWhite:1 alpha:.12] set];
 NSBezierPath *edge=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b,.5,.5) xRadius:14 yRadius:14];[edge setLineWidth:1];[edge stroke];
 NSColor *ink=[NSColor colorWithCalibratedWhite:1 alpha:.92];[ink set];
 /* volume: a speaker and a slider */
 NSRect s=l.volumeIcon;NSRectFill(NSMakeRect(NSMinX(s),NSMidY(s)-3,4,6));
 SFTriangle(NSMakePoint(NSMinX(s)+3,NSMidY(s)),NSMakePoint(NSMinX(s)+10,NSMaxY(s)-1),NSMakePoint(NSMinX(s)+10,NSMinY(s)+1));
 float volume=_playerView.player.isMuted?0:_playerView.player.volume;
 NSRect track=NSMakeRect(NSMinX(l.volume),NSMidY(l.volume)-1.5,NSWidth(l.volume),3);
 [[NSColor colorWithCalibratedWhite:1 alpha:.28] set];[[NSBezierPath bezierPathWithRoundedRect:track xRadius:1.5 yRadius:1.5] fill];
 [ink set];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(track),NSMinY(track),NSWidth(track)*MAX(0,MIN(1,volume)),3) xRadius:1.5 yRadius:1.5] fill];
 [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(track)+NSWidth(track)*MAX(0,MIN(1,volume))-5,NSMidY(track)-5,10,10)] fill];
 /* skip back and forward: two triangles each */
 NSRect k=l.back;CGFloat cy=NSMidY(k);
 SFTriangle(NSMakePoint(NSMinX(k),cy),NSMakePoint(NSMidX(k),cy+8),NSMakePoint(NSMidX(k),cy-8));
 SFTriangle(NSMakePoint(NSMidX(k),cy),NSMakePoint(NSMaxX(k),cy+8),NSMakePoint(NSMaxX(k),cy-8));
 k=l.forward;cy=NSMidY(k);
 SFTriangle(NSMakePoint(NSMaxX(k),cy),NSMakePoint(NSMidX(k),cy+8),NSMakePoint(NSMidX(k),cy-8));
 SFTriangle(NSMakePoint(NSMidX(k),cy),NSMakePoint(NSMinX(k),cy+8),NSMakePoint(NSMinX(k),cy-8));
 /* play or pause */
 NSRect p=l.play;
 if(_playerView.player.rate==0)SFTriangle(NSMakePoint(NSMinX(p)+5,NSMaxY(p)-2),NSMakePoint(NSMinX(p)+5,NSMinY(p)+2),NSMakePoint(NSMaxX(p)-1,NSMidY(p)));
 else{NSRectFill(NSMakeRect(NSMinX(p)+5,NSMinY(p)+3,6,NSHeight(p)-6));NSRectFill(NSMakeRect(NSMaxX(p)-11,NSMinY(p)+3,6,NSHeight(p)-6));}
 /* full screen: two corner marks */
 NSRect f=l.fullScreen;NSBezierPath *corners=[NSBezierPath bezierPath];[corners setLineWidth:2];
 [corners moveToPoint:NSMakePoint(NSMinX(f),NSMaxY(f)-6)];[corners lineToPoint:NSMakePoint(NSMinX(f),NSMaxY(f))];[corners lineToPoint:NSMakePoint(NSMinX(f)+6,NSMaxY(f))];
 [corners moveToPoint:NSMakePoint(NSMaxX(f)-6,NSMinY(f))];[corners lineToPoint:NSMakePoint(NSMaxX(f),NSMinY(f))];[corners lineToPoint:NSMakePoint(NSMaxX(f),NSMinY(f)+6)];
 [corners stroke];
 /* the scrubber between the elapsed and the remaining time */
 double duration=[self duration],time=MIN([self current],duration?duration:[self current]);
 double fraction=duration>0?MAX(0,MIN(1,time/duration)):0;
 NSRect bar=NSMakeRect(NSMinX(l.scrubber),NSMidY(l.scrubber)-2,NSWidth(l.scrubber),4);
 [[NSColor colorWithCalibratedWhite:1 alpha:.28] set];[[NSBezierPath bezierPathWithRoundedRect:bar xRadius:2 yRadius:2] fill];
 [ink set];[[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMinX(bar),NSMinY(bar),NSWidth(bar)*fraction,4) xRadius:2 yRadius:2] fill];
 NSDictionary *font=@{NSFontAttributeName:[NSFont boldSystemFontOfSize:11],NSForegroundColorAttributeName:ink};
 [SFTimeText(time) drawInRect:l.elapsed withAttributes:font];
 NSString *left=[@"-" stringByAppendingString:SFTimeText(duration-time)];
 NSSize size=[left sizeWithAttributes:font];
 [left drawAtPoint:NSMakePoint(NSMaxX(l.remaining)-size.width,NSMinY(l.remaining)) withAttributes:font];
}
- (void)seekToFraction:(double)fraction {
 double duration=[self duration];if(duration<=0)return;
 [_playerView.player seekToTime:CMTimeMakeWithSeconds(MAX(0,MIN(1,fraction))*duration,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
 [self setNeedsDisplay:YES];
}
- (void)trackFloating:(NSPoint)point began:(BOOL)began {
 SFHudLayout l=SFHud(self.bounds);
 if(began)_tracking=0;
 if(began&&NSPointInRect(point,NSInsetRect(l.scrubber,-4,-8)))_tracking=1;
 if(began&&NSPointInRect(point,NSInsetRect(l.volume,-6,-8)))_tracking=2;
 if(_tracking==1){[self seekToFraction:(point.x-NSMinX(l.scrubber))/NSWidth(l.scrubber)];return;}
 if(_tracking==2){
  float volume=(float)MAX(0,MIN(1,(point.x-NSMinX(l.volume))/NSWidth(l.volume)));
  [_playerView.player setMuted:NO];[_playerView.player setVolume:volume];[self setNeedsDisplay:YES];return;
 }
 /* (QTP2) the buttons act when the button is released over them, as buttons do: full screen toggled on the press
    changed the window under the held button, and the desk took the release at the window's new top edge as the end
    of a resize (the window came back 50 points taller) */
 if(began)_pressed=[self buttonAt:point];
}
- (int)buttonAt:(NSPoint)point {
 SFHudLayout l=SFHud(self.bounds);
 if(NSPointInRect(point,NSInsetRect(l.play,-6,-6)))return 1;
 if(NSPointInRect(point,NSInsetRect(l.back,-4,-6)))return 2;
 if(NSPointInRect(point,NSInsetRect(l.forward,-4,-6)))return 3;
 if(NSPointInRect(point,NSInsetRect(l.volumeIcon,-4,-4)))return 4;
 if(NSPointInRect(point,NSInsetRect(l.fullScreen,-6,-6)))return 5;
 return 0;
}
- (void)pressButton:(int)button {
 if(button==1){[_playerView _togglePlayback:self];[self setHidden:NO];[self display];return;}   /* (drawn at once: paused, nothing else redraws the panel) */
 if(button==2||button==3){
  double to=[self current]+(button==2?-SF_SKIP_SECONDS:SF_SKIP_SECONDS),duration=[self duration];
  if(duration>0)[_playerView.player seekToTime:CMTimeMakeWithSeconds(MAX(0,MIN(duration,to)),600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
  [self setNeedsDisplay:YES];return;
 }
 if(button==4){[_playerView.player setMuted:![_playerView.player isMuted]];[self setNeedsDisplay:YES];return;}
 if(button==5){[[self window] toggleFullScreen:self];return;}
}
- (void)mouseDown:(NSEvent *)event {
 NSPoint point=[self convertPoint:[event locationInWindow] fromView:nil];
 if([self isFloating]){[self trackFloating:point began:YES];return;}
 if(point.x<42){[_playerView _togglePlayback:self];return;}
 CGFloat width=NSWidth(self.bounds)-70;double duration=CMTimeGetSeconds(_playerView.player.currentItem.duration);
 if(width>0&&isfinite(duration)&&duration>0&&point.x>=50&&point.x<=50+width){double fraction=(point.x-50)/width;[_playerView.player seekToTime:CMTimeMakeWithSeconds(fraction*duration,600)];[self setNeedsDisplay:YES];}
}
- (void)mouseDragged:(NSEvent *)event {
 if([self isFloating])[self trackFloating:[self convertPoint:[event locationInWindow] fromView:nil] began:NO];
}
- (void)mouseUp:(NSEvent *)event {
 int pressed=_pressed;
 _tracking=0;_pressed=0;
 if(pressed&&[self isFloating]&&[self buttonAt:[self convertPoint:[event locationInWindow] fromView:nil]]==pressed)[self pressButton:pressed];
}
/* the floating panel goes while a movie plays and the pointer has not moved for 3 s, and comes back when it moves
   (asked at every picture the player view shows; while paused it stays) */
- (BOOL)sfIdleHidden {
 if(![self isFloating]||![self window])return NO;
 double now=[NSDate timeIntervalSinceReferenceDate];
 NSPoint mouse=[NSEvent mouseLocation];   /* (the desk's pointer, as the display last reported it) */
 if(!_lastActivity||!NSEqualPoints(mouse,_lastMouse)){_lastMouse=mouse;_lastActivity=now;}
 /* (held as long as a press or drag on it lasts: the release is the window's for the view at the press) */
 if(_playerView.player.rate==0||_tracking||_pressed){_lastActivity=now;return NO;}
 return now-_lastActivity>3.0;
}
@end
/* (QTP2) The picture is drawn by AppKit, as the contents of the player layer the view hosts (without OpenGL it draws a
 * hosted layer into the window itself). The view tells the layer the size in device pixels the picture takes there
 * (the video gravity's rectangle in the view, at the window's scale), so the player makes each picture at that size:
 * drawn at its own size on whole pixels it is copied, not resampled (two pictures a second at 1080p before). Where
 * the rectangle is centred the picture's size keeps the parity of the view's, so that its edges stay on whole pixels. */
@interface AVPlayerLayer(SFDisplayPixelSize)
- (void)sfSetDisplayPixelSize:(CGSize)size;
@end
/* (QTP2) the view's own drawing: black where the picture is not (the picture is drawn over it). Black under the
 * whole picture was a second full-window fill per picture; the bars reach one point into the picture's rectangle so
 * that no pixel at its edges is left as the last frame had it. */
void SFFillOutsidePicture(AVPlayerView *view,AVPlayerLayer *layer,NSRect dirty){
 [[NSColor blackColor] set];
 CGImageRef image=(CGImageRef)[layer contents];NSRect b=view.bounds;
 double iw=image?CGImageGetWidth(image):0,ih=image?CGImageGetHeight(image):0;
 if(iw<=0||ih<=0||![view.videoGravity isEqualToString:AVLayerVideoGravityResizeAspect]){NSRectFill(dirty);return;}
 double s=MIN(NSWidth(b)/iw,NSHeight(b)/ih);
 NSRect inner=NSInsetRect(NSMakeRect(NSMidX(b)-iw*s/2,NSMidY(b)-ih*s/2,iw*s,ih*s),1,1);
 if(NSIsEmptyRect(inner)){NSRectFill(dirty);return;}
 NSRect bars[4]={NSMakeRect(NSMinX(b),NSMinY(b),NSWidth(b),NSMinY(inner)-NSMinY(b)),NSMakeRect(NSMinX(b),NSMaxY(inner),NSWidth(b),NSMaxY(b)-NSMaxY(inner)),
  NSMakeRect(NSMinX(b),NSMinY(inner),NSMinX(inner)-NSMinX(b),NSHeight(inner)),NSMakeRect(NSMaxX(inner),NSMinY(inner),NSMaxX(b)-NSMaxX(inner),NSHeight(inner))};
 for(int i=0;i<4;i++){NSRect r=NSIntersectionRect(bars[i],dirty);if(!NSIsEmptyRect(r))NSRectFill(r);}
}
void SFUpdatePicturePixelSize(AVPlayerView *view,AVPlayerLayer *layer){
 if(![layer respondsToSelector:@selector(sfSetDisplayPixelSize:)])return;
 CGSize p=view.player.currentItem.presentationSize;NSRect b=view.bounds;CGFloat scale=view.window?[view.window backingScaleFactor]:0;
 if(scale<=0||p.width<=0||p.height<=0||NSWidth(b)<=0||NSHeight(b)<=0){[layer sfSetDisplayPixelSize:CGSizeZero];return;}
 /* (the window's own pixels per point along each axis where AppKit says them: its backing store is whole pixels over
    whole points, 1.5003 or 1.5005 rather than 1.5 at 150 %) */
 CGFloat sx=scale,sy=scale;
 if([view.window respondsToSelector:@selector(_backingPixelsPerPoint)]){
  NSSize f=((NSSize (*)(id,SEL))objc_msgSend)(view.window,@selector(_backingPixelsPerPoint));
  if(f.width>0&&f.height>0){sx=f.width;sy=f.height;}
 }
 double bw=round(NSWidth(b)*sx),bh=round(NSHeight(b)*sy),w=bw,h=bh;
 NSString *gravity=view.videoGravity;
 if(![gravity isEqualToString:AVLayerVideoGravityResize]){
  BOOL fill=[gravity isEqualToString:AVLayerVideoGravityResizeAspectFill];
  /* fit: the picture spans the view's width when the view is the narrower (fill: when it is the wider) */
  if((bw/bh>p.width/p.height)!=fill){h=bh;w=round(bh*p.width/p.height);if(((long)(bw-w))&1)w+=fill?1:-1;}
  else{w=bw;h=round(bw*p.height/p.width);if(((long)(bh-h))&1)h+=fill?1:-1;}
 }
 [layer sfSetDisplayPixelSize:CGSizeMake(MAX(w,1),MAX(h,1))];
}
