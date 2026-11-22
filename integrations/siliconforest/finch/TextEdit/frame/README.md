# TextEdit's AppKit frame

TextEdit 1.20 draws a page rule with `CGRect.frame(withWidth:using:)`.
That Swift method is not in the AppKit overlay Preview uses. Dyld looks
for it in the AppKit image TextEdit loaded, so a side library cannot
satisfy the bind.

`FrameRect.S` is that method. It reorders the registers from the Swift
method calling convention onto `NSFrameRectWithWidthUsingOperation`, which
`AppKit.sf-under` already exports. `DocumentSymbols.m` is the document
attribute and document type constants TextEdit also binds there.
`TextKitStubs.m` is empty `NSTextContentStorage`, `NSTextLayoutManager`,
and `NSTextRange` classes so those binds resolve. TextEdit leaves the
`UsesTextLayoutManagerFor*` defaults unset, and `boolForKey:` is false, so
it stays on `NSLayoutManager`.

`build.sh` links these as an AppKit front that reexports a copy of the
dock overlay. The copy's install name is `@loader_path/AppKit.sf-base`.
The front's install name is `AppKit.sf-textedit`, not `AppKit.sf-additions`
and not AppKit's own path, so dyld does not fold it onto the dock overlay
or the system image.

The front is found through `DYLD_FRAMEWORK_PATH` ahead of the dock
overlay, and only for TextEdit. The dock overlay and the Apple bundles
are not modified. Objects and the built front are not committed.
`build.sh` reads `CC`, `LD`, `SDK`, `LIBSYSTEM`, `OBJC`, `FOUNDATION`, `CF`, `BASE`, and `OUT`.

`ExceptionLog.m` prints an exception AppKit catches. `SpellCheckerAdd.m`
replaces the spelling getters and setters that only raise.
`DocumentRead.m` reads RTF through `NSRichTextReader`. That reader drops
`\trowd`, so each real row is rewritten to one paragraph joined by `\u9`
before the parse. The same tab stops are stroked as a navy grid from
every `NSTextView` `drawRect:` and from `drawGlyphsForGlyphRange:atPoint:`.
A line fragment with no height still takes the paragraph's line height.
The file on disk keeps `\trowd`. `LayoutAdd.m`
fills the layout, scroll, and text-view selectors TextEdit calls, and,
when `SF_TE_PLACE=1`, puts the first three document windows on a grid.
That grid is read by the compositor only while `window_position=on`,
and only before a window's first buffer. `TextKitStubs.m` also forces
the TextKit 2 defaults off, including a value inherited from the global
domain.

The Recap front in `../recap` supplies the two test classes TextEdit
binds and reexports the dock's Recap library under a different install
name. It is staged ahead of the p44 prefix. The p44 file is not modified.
