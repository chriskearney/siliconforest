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
change('    AVPlayer *_fplayer;\n    AVPlayerLayer *_fplayerLayer;','    AVPlayer *_fplayer;\n    AVPlayerLayer *_fplayerLayer;\n    id _sfPeriodic; SFPlayerDrawToken *_sfDrawToken; NSUInteger _sfVideoDraws;')
change('_fcontrols = [[NSView alloc] initWithFrame:', '_fcontrols = [[SFTransportView alloc] initWithFrame:')
a=s.index('        _fplayButton = [[NSButton alloc]');b=s.index('        [self addSubview:_fcontrols];',a)
s=s[:a]+'        [(SFTransportView *)_fcontrols setPlayerView:self];\n'+s[b:]
# (QTP) the controls' frame follows the style: the inline bar, or the floating panel over the picture
change('''    BOOL visible = _fcontrolsStyle != AVPlayerViewControlsStyleNone;
    _fcontrols.hidden = !visible;
    _ffullScreenButton.hidden = !_fshowsFullscreen;''','''    BOOL visible = _fcontrolsStyle != AVPlayerViewControlsStyleNone;
    _fcontrols.hidden = !visible || [(SFTransportView *)_fcontrols sfIdleHidden];
    _fcontrols.frame = SFControlsFrame(self);
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
            if(view){[view _updateControls];[view->_fcontrols setNeedsDisplay:YES];}
        }];
    }
    [self _updatePlayerLayer]; [self _updateControls];''')
change('''    [[NSColor blackColor] set]; NSRectFill(dirtyRect);
}''','''    [[NSColor blackColor] set]; NSRectFill(dirtyRect);
    if(SFDrawPlayerContents(self,_fplayerLayer)) _sfVideoDraws++;
}
- (AVPlayerLayer *)sfPlayerLayer {return _fplayerLayer;}
- (NSUInteger)sfVideoDrawCount {return _sfVideoDraws;}
- (NSUInteger)sfTransportDrawCount {return [(SFTransportView *)_fcontrols drawCount];}''')
p.write_text(s)
