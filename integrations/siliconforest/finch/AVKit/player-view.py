#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Keep Finch's AVKit model, add our drawn controls and real layer CPU fallback."""
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
def change(old,new):
 global s
 assert s.count(old)==1,old[:100]
 s=s.replace(old,new)
change('#import <QuartzCore/QuartzCore.h>','#import <QuartzCore/QuartzCore.h>\n#import "SFTransport.h"')
change('    AVPlayer *_fplayer;\n    AVPlayerLayer *_fplayerLayer;','    AVPlayer *_fplayer;\n    AVPlayerLayer *_fplayerLayer;\n    id _sfPeriodic; SFPlayerDrawToken *_sfDrawToken; NSUInteger _sfVideoDraws; BOOL _sfQuiet;')
change('_fcontrols = [[NSView alloc] initWithFrame:', '_fcontrols = [[SFTransportView alloc] initWithFrame:')
a=s.index('        _fplayButton = [[NSButton alloc]');b=s.index('        [self addSubview:_fcontrols];',a)
s=s[:a]+'        [(SFTransportView *)_fcontrols setPlayerView:self];\n'+s[b:]
# (QTP) the controls' frame follows the style: the inline bar, or the floating panel over the picture
change('''    BOOL visible = _fcontrolsStyle != AVPlayerViewControlsStyleNone;
    _fcontrols.hidden = !visible;
    _ffullScreenButton.hidden = !_fshowsFullscreen;''','''    BOOL visible = _fcontrolsStyle != AVPlayerViewControlsStyleNone;
    _fcontrols.hidden = !visible || [(SFTransportView *)_fcontrols sfIdleHidden];
    if (!NSEqualRects(_fcontrols.frame, SFControlsFrame(self))) _fcontrols.frame = SFControlsFrame(self);
    SFUpdatePicturePixelSize(self, _fplayerLayer);
    _fcontrols.autoresizingMask = _fcontrolsStyle == AVPlayerViewControlsStyleFloating ? (NSViewMinXMargin | NSViewMaxXMargin | NSViewMaxYMargin) : (NSViewWidthSizable | NSViewMaxYMargin);
    _ffullScreenButton.hidden = !_fshowsFullscreen || _fcontrolsStyle == AVPlayerViewControlsStyleFloating;''')
change('    _fcontrols.frame = NSMakeRect(0, 0, NSWidth(self.bounds), 38);','    _fcontrols.frame = SFControlsFrame(self);')
change('''    [_fplayer release]; [_fplayerLayer release];''','''    _sfDrawToken.owner=nil;
    if(_sfPeriodic) [_fplayer removeTimeObserver:_sfPeriodic];
    [_sfDrawToken release];
    [_fplayer release]; [_fplayerLayer release];''')
change('''    [_fplayer release]; _fplayer = [player retain];
    [self _updatePlayerLayer]; [self _updateControls];''','''    _sfDrawToken.owner=nil;
    if(_sfPeriodic) [_fplayer removeTimeObserver:_sfPeriodic];
    _sfPeriodic=nil;[_sfDrawToken release];_sfDrawToken=nil;
    [_fplayer release]; _fplayer = [player retain];
    if(player){
        _sfDrawToken=[SFPlayerDrawToken new];_sfDrawToken.owner=self;
        SFPlayerDrawToken *token=_sfDrawToken;
        _sfPeriodic=[player addPeriodicTimeObserverForInterval:CMTimeMake(1,30) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){
            (void)time;AVPlayerView *view=token.owner;
            /* (QTP2) the clock does not redraw the view: a new picture does (AppKit redraws a view whose hosted layer's
               contents changed, the controls with it); twice per picture, out of step, was 52 window commits a second.
               Paused, the controls are drawn again here. */
            if(view){view->_sfQuiet=YES;[view _updateControls];view->_sfQuiet=NO;if(view->_fplayer.rate==0)[view->_fcontrols setNeedsDisplay:YES];}
        }];
    }
    [self _updatePlayerLayer]; [self _updateControls];''')
change('''    [[NSColor blackColor] set]; NSRectFill(dirtyRect);
}''','''    /* (QTP2) the window's first drawing has the first picture: the layer is asked for it now, not at its next tick
       (a window showed black for 0.03-0.3 s when it opened) */
    if(![_fplayerLayer contents] && _fplayer.currentItem.status == AVPlayerItemStatusReadyToPlay && [_fplayerLayer respondsToSelector:@selector(_finchShowFrame)]){
        SFUpdatePicturePixelSize(self, _fplayerLayer);
        [_fplayerLayer performSelector:@selector(_finchShowFrame)];
    }
    SFFillOutsidePicture(self, _fplayerLayer, dirtyRect);
    /* (QTP2) the picture itself is the hosted player layer's contents, drawn by AppKit over this (once: it was drawn
       here as well, a second full-size resampling per picture) */
    if([_fplayerLayer contents]) _sfVideoDraws++;
}
- (AVPlayerLayer *)sfPlayerLayer {return _fplayerLayer;}
- (NSUInteger)sfVideoDrawCount {return _sfVideoDraws;}
- (NSUInteger)sfTransportDrawCount {return [(SFTransportView *)_fcontrols drawCount];}''')
change('''    _fplayButton.title = _fplayer.rate == 0 ? @"Play" : @"Pause";
    [self setNeedsDisplay:YES];''','''    _fplayButton.title = _fplayer.rate == 0 ? @"Play" : @"Pause";
    if (!_sfQuiet) [self setNeedsDisplay:YES];''')
p.write_text(s)
