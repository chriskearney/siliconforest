# SPDX-License-Identifier: MIT
# Our changes to upstream's frameworks, as patches against the pinned SiliconForest tree
# (./patches, one topic each, paths from the tree's root) and the arm64 builds made from the
# patched sources with upstream's own recipes.
#
#   0001  tip cherry-pick (upstream 71a9d0b0, part): NSFontWeight constants, NSImageSymbolConfiguration
#   0002  AppKit: NSSharingServicePicker
#   0003  AuthenticationServices: the browser side of ASWebAuthenticationSession
#   0004  WindowServer: server-side decorations (xdg-decoration), scale (wp_fractional_scale +
#         wp_viewporter, or the output's whole scale), size limits
#   0005  AppKit: no title bar inside a compositor-drawn frame, backing stores at the scale,
#         zoomed and miniaturised state from the compositor's frame
#   0006  Onyx2D: glyphs rasterised at the device scale (text was point-size bitmaps on a scaled surface)
#   0011  AppKit: the layout API (intrinsic and fitting sizes, alignment rectangles, baselines,
#         compression resistance, -layout/-updateConstraints), intrinsic sizes used by the solver
#   0012  AppKit: control geometry and drawing as macOS 26 has them (measured), the macOS 15 look
#         kept behind the SFControlLook default
#   0013  Onyx2D: the PNG encoder writes straight alpha and reads "default" byte order as the
#         rest of Onyx2D does (pictures of a bitmap context had red and blue exchanged)
#   0015  AppKit: NSPopUpView built its array with +init then +alloc (every pop-up button crashed)
#   0016  AppKit: discarding the events before one event tested that event's own type and removed
#         every earlier event (a tracking loop's periodic timer threw away mouse and key events)
#   0017  AppKit: popups (menus, lists, tool tips) for a compositor that places them: one tracking loop
#         for menus, submenus, pop-up and pull-down buttons and combo boxes, with the keyboard
#   0018  WindowServer: a popup's anchor and kind in its positioner (flip, slide), where the compositor
#         put it reported back, a held button kept across the surfaces of an open menu
#   0019  tip cherry-pick: NSStackView, NSAccessibilityElement (files as at upstream c713d8fb)
#   0020  AppKit: names applications built against the macOS 26 SDK import (first user: Apple's
#         Terminal.app, docs/roadmap/issues/SF-Y-terminal-app.md): constants, accessibility helpers,
#         gesture recognizers, NSTextFinder, private classes that answer nothing to what they lack
#   0021  AppKit: faults found with Terminal.app: an undeclared variadic call in nib loading, a nil
#         window title, exceptions from run-loop callouts reported instead of ending the program,
#         nib objects replaced before they were collected, +removeFrameUsingName:, NSViewController
#         without a nib, NSPathControl's delegate; an application's own fonts (ATSApplicationFontsPath)
#         registered for the process; a nib window without a maximum size has none (it was 0 by 0)
#   0022  WindowServer: SF_WS_DUMP_DIR writes the picture a window presents (a diagnostic where the
#         compositor has no screen capture)
#   0023  CoreText: Menlo, Monaco, SF Mono and any family whose name says it is fixed-pitch resolve to
#         an installed fixed-pitch face (a terminal measured its cells from the proportional
#         default); the fixed-pitch UI font comes from the registry; CTFontDrawGlyphsWithAdvances
#         and CTFontShouldAntiAlias (private, imported by Terminal.app)
#   0024  AppKit: +[NSFont fontWithName:size:] asks CoreText for a name no installed face carries;
#         a selection naming rows the content does not have selects nothing (it ended the program);
#         a binding whose key is missing is reported once and does not stop the change that
#         notified it; a font archived without a size has the system font size (labels were dots)
#   0025  CoreGraphics: the context getters for anti-aliasing and font smoothing and the private
#         CGS/CPS window-server calls Terminal.app imports (answers of a Wayland client)
#   0026  Onyx2D: -copyBitsInRect:toPoint:gState: for the bitmap context (-[NSView scrollRect:by:]
#         raised "only defined for abstract class": Terminal.app scrolls its text this way)
#   0027  AppKit: the constraint solves asked for inside one resize cascade are done once, at its end
#         (every view holding constraints had the whole tree solved twice per resized view: 388
#         solves, 4.8 s, while Terminal.app's preferences nib was decoded)
#   0028  AppKit: the application's main menu as a strip, the first row of each titled window that is
#         not a panel, where the compositor draws the frames (the desktop has no global menu bar):
#         the application's own NSMenu in a horizontal NSMenuView, each title's menu an ordinary
#         popup; pointer and keyboard (Control-F2, arrows); counted as frame, not content. Menu rows
#         are measured once and only the rows whose highlight changed are drawn again
#         (0028 also: on such a desktop an application ends when its last window is closed, as it
#         could not be reached again; SFQuitsWithLastWindow=NO keeps it)
#   0029  AppKit: more faults found with Terminal.app: removing the selected NSTabViewItem selected
#         item -1 (closing a window ended the program); -[NSAttributedString URLAtIndex:effectiveRange:];
#         a nib's toolbar kept no items (visibility classes; emptied when its delegate was
#         connected); -[NSWorkspace typeOfFile:error:] answers the type the application declares
#   0030  WindowServer: a window of a program without a bundle identifier gets the program's name as
#         its app id
#   0031  AppKit: the content bindings of a pop-up button (content, contentObjects, contentValues,
#         selectedObject): arrays of objects were taken for titles; the bound selection is applied
#         again when the content arrives after it
#   0032  AppKit: the size of an unbounded one-style string is remembered (a measurement is a pass of
#         the whole text system: 5 ms on the M1, and Terminal.app made 1384 at launch); a title up to
#         an eighth too wide for its place is drawn narrower instead of cut with an ellipsis
#   0033  AppKit: scrollers in the macOS 26 look (no arrow buttons, a rounded bar); SFControlLook=15
#         keeps the old one
#   0034  CoreText: one graphics font per installed face (a fontconfig search and a FreeType face per
#         CTFont: Terminal.app makes a CTFont for each line it draws); a directory registered through
#         CTFontManagerRegisterFontsForURL goes through fontconfig's cache of that directory; a named
#         instance of a variable font is drawn as that instance (its Bold was drawn as Regular)
#   0035  AppKit: glyph advances from the metrics table (FT_Get_Advance) instead of loading each
#         glyph's outline; an application's fonts registered as their directory (cached by fontconfig,
#         instead of three scans of each file at every launch); the main menu is not archived when
#         there is no menu transport
#   0036  WindowServer: a flush that finds every frame busy is presented when the compositor releases
#         one (it waited up to 100 ms on the main thread and was then dropped); SF_WS_TIMING=1 prints
#         the wall time of each commit and release; kWSWindowTakeToplevel: the tabs of a window share
#         one toplevel (two records exchange their identities)
#   0037  Onyx2D: one font per name (each was a fontconfig match, the whole file read and a FreeType
#         face opened: AppKit makes an NSFont by name for every string it measures)
#   0038  AppKit: more found with Terminal.app: +[NSCountedSet setWithCapacity:] (its check for running
#         processes when it quits), -[NSTextField setLineBreakMode:], a family's plain Bold and Italic
#         for -convertFont:toHaveTrait: (not the first face with the trait: Heavy, Light Italic)
#   0039  AppKit: window tabs (NSWindowTabGroup, NSWindowTab, addTabbedWindow:ordered:, Show Next/Previous
#         Tab, Move Tab to New Window, Merge All Windows) as one toplevel per group, with a tab bar under
#         the menu strip; structure from Finch's NSWindowTabbing.m (MIT OR Apache-2.0, commit 2d9b1bb)
#   0040  AppKit: -getRectsBeingDrawn: answers the rect that is drawn (Onyx2D clips to one rectangle, so
#         the views behind fill all of it: Terminal filled only the dirty rows and the rows between kept
#         the window's grey); dirty rects far apart are drawn one at a time; dirty rects are whole
#         device pixels (at 150% a rect of whole points left a seam of the grey at each row edge)
#   0041  AppKit: a window starts opaque, as on macOS (Terminal turns a window with a translucent profile
#         clear only when -setOpaque:NO changes that), and its background is copied, not drawn over
#         what the backing store held; a window without NSTitledWindowMask (a sheet, an alert) has no
#         title bar and no room for one, a sheet a hairline border, and the WindowServer is told a
#         sheet's parent; the offscreen window of an image's cache does not take the current context
#         while a view draws (Terminal's profile list drew into it after the first thumbnail)
#   0042  Onyx2D: PNG entries of an .icns (ic07 to ic14, all a current application icon has), upstream's
#         change at the tip (29bc3a57 "Onyx2D: PNG icons in ICNS"): Terminal's icon read as nothing
#   0043  WindowServer: a window's parent (kWSWindowSetParent, xdg_toplevel.set_parent): the compositor
#         keeps a sheet over its parent and centres it there
#   0044  AppKit: alerts laid out as on macOS 26 (metrics after Finch's NSAlert.m, MIT OR Apache-2.0):
#         420 points wide, the application's icon, the message bold and wrapped, buttons sized to their
#         titles; NSRunAlertPanel and NSBeginAlertSheet are NSAlert (they were a panel that put the
#         message in its title bar); Return, Escape and Command-D buttons; the application's icon is
#         its bundle's from the start and is what NSApplicationIcon names
#   0045  AppKit: a space that opens a layout fragment is a place to wrap (lines broke inside words
#         and began with a space after a kerning pair had ended a fragment)
#   0046  AppKit: the NIBArchive reader's -decodeFloatForKey: answers a float as NSCoder declares it (it
#         answered a double: every caller read 0, so a nib's column widths and row heights were 0);
#         labels a little too wide for a nib laid out for macOS's system font are drawn narrower when
#         they clip too, and their descenders are not cut; a shortcut typed with Shift shows as macOS
#         shows it (Shift-Command-[ for Command-{); a menu's shadow layers are rings round the panel,
#         not eight fills of its whole area
#   0047  AppKit: a control's bound value goes to the model when it sends its action (a click changes
#         the cell, which no key-value observation of the control hears), and a controller's
#         selection proxy sets a value on each selected object: Terminal's preference checkboxes now
#         change the profile and persist
#   0048  AppKit: NSTextFinder with a find bar (search field, previous/next, Done, replace row), taken
#         from Finch's NSTextFinder.m (MIT OR Apache-2.0, notice in the file): Terminal's Command-F,
#         Find Next/Previous, Use Selection for Find (the finder before had no bar and beeped); the bar
#         takes the find actions while its field has the keys; a Command key that no menu took inserts
#         no text (Command-G typed a "g")
#   0049  AppKit: a font name's PostScript name (a fontconfig listing of every installed face) and the
#         fallback font for a character are remembered: a menu opened in about 390 ms once the CJK fonts
#         were installed, now about 195 ms
#   0050  AppKit: tab views as on macOS 26 (rounded segments, the selected one white, a faint rounded
#         pane with a hairline) instead of raised grey bevels, on which a disabled label vanished
#   0051  AppKit: drawn once: a menu that opens and a tab that is switched to were drawn twice; the
#         window's menu strip laid out its titles again whenever the content under it was drawn (at
#         150% the content's top edge falls inside a pixel row of the strip); the strip stays in full
#         screen; a tab bar redraws when a tab's title changes; an empty Services menu shows a
#         disabled "No Services Apply" as on macOS (it opened as nothing)
#   0052  AppKit: full screen through the compositor (xdg_toplevel set/unset_fullscreen, the window's
#         state follows the compositor's, will/did notifications and delegate calls, the menu item
#         says Enter or Exit Full Screen); Command-= is Command-+ (Bigger); a key equivalent validates
#         the item it matches, not every menu; a title set again unchanged is no message and no redraw;
#         a configure that a later one overtook is not applied (a drag resized the window once per
#         pointer step, each a new backing store and a whole drawing, and fell behind)
#   0053  CoreText: the line made for an attributed string is kept for the same text and attributes
#         (a terminal lays out every row of every frame); the CTFont made for an NSFont is kept
#   0055  AppKit: the save and open panels drawn by AppKit (name, folder, the folder's items, the
#         application's accessory view, Cancel and Save/Open), macOS's API for them
#         (-beginSheetModalForWindow:completionHandler:, -setNameFieldStringValue:, -directoryURL ...):
#         they were left to the display, which had none (Export Text As, Export Settings, Open)
#   0056  AppKit: printing saves a PDF (there are no printers: the print panel says so and offers
#         Save as PDF, the operation draws its pages into a PDF context);
#         -runOperationModalForWindow:delegate:didRunSelector:contextInfo:; a help book that is asked
#         for says that help is not available (the alert of -showHelp:) instead of raising
#   0057  AppKit: -getRectsBeingDrawn: and -needsToDrawRect: asked outside a display (a view drawn
#         into an image by calling -drawRect:, Terminal's profile thumbnails) answer the whole view
#   0058  WindowServer: a window AppKit brings to the front (kWSWindowOrder: Command-`, the Window
#         menu) is raised and focused by the compositor through xdg_activation_v1; SF_WS_TIMING
#         also logs each configure (the time from a configure to the frame of its size)
#   0059  AppKit: found walking Terminal's menus: a table column can be hidden (-isHidden,
#         -setHidden:; Terminal's inspector); a cell keeps an object value that cannot be copied
#         (its process list); the font bindings of a cell (fontBold, fontItalic, fontName, fontSize);
#         a foreground "colour" that is not one draws black instead of raising in every redraw;
#         a binding's value transformer named by a class nobody registered is an instance of that
#         class, and a table column's bindings go through it (the inspector's process names and
#         colours); an empty key equivalent of a button matches nothing (Shift alone opened the
#         inspector's pull-down)
#   0054  Onyx2D: a filled rectangle, a straight stroke along an axis and a stroked outline whose
#         sides are straight (a rectangle, a rounded rectangle: its arcs alone go through the edge
#         rasterizer) are covered directly, a row at a time; the rasterizer's winding buffer (2 MB at
#         the screen's width) is kept for the next context instead of a fresh calloc per context
#         (a window gets one at every size)
#   0100..0106: Apple's Activity Monitor (docs/roadmap/issues/SF-AA-activity-monitor.md, GitHub issue 53;
#   regenerated by ./patches/mkpatches-0100.sh)
#   0100  AppKit: names Activity Monitor imports (NSSearchToolbarItem, NSWorkspaceDidWakeNotification, the
#         compositional layout's description objects kept as data, +[NSColor colorNamed:], ...); the search
#         field sends its action while typing
#   0101  AppKit: view-based NSTableView/NSOutlineView (cell views, row views, the archived cell-view nibs,
#         reuse), hidden table columns, the header's sort indicator; a header click asks the delegate
#         -tableView:shouldSelectTableColumn: (a row click no longer does); a table row view is the top of its
#         own layouts
#   0102  CoreGraphics: CGSEventIsAppUnresponsive, CGSRegisterNotifyProc
#   0103  AppKit: without EGL a layer-backed view is drawn as an ordinary view (no layer context through CGL)
#   0104  AppKit: NIBArchive booleans the right way round (value type 4 is false, 5 true: every BOOL a nib
#         carried was read inverted), a cell's three line-break bits, custom views' constraints and
#         identifier, a constrained label re-measured when its string's length changes, bindings apply a
#         change made off the main thread on the main thread, the menu strip on full-size-content windows
#   0105  AppKit: an application's named colours from its Assets.car (Finch's catalog reader, MIT OR Apache-2.0)
#   0106  AppKit: what the corrected booleans handed to Auto Layout (Terminal's Preferences and Inspector panes
#         overlapped, a label cut at the left edge): a nib's standard-space constraints (NSSymbolicConstant
#         NSSpace: 20 points to the superview's edge, 8 between siblings; they were 0), the content hugging and
#         compression resistance priorities a nib archives, NSMatrix's intrinsic size from its cells (it was
#         10000 by 10000); a table header as wide as its clip view where no vertical scroller takes room (the
#         last column's title was under an empty corner); SF_LAYOUT_TRACE=1 prints each layout's constraints
#         and frames
#   0107  AppKit: what Activity Monitor showed wrongly or slowly. Our own drawings for the few system symbol
#         images asked for (info.circle, ellipsis.circle, xmark.octagon, magnifyingglass, arrow.forward.circle.fill: SF Symbols are
#         Apple's font and not copied); a toolbar item's view centred in its item, the toolbar with a margin
#         above and below (an icon-only toolbar's views were pushed 4 points up and cut); a hidden menu takes no
#         title in the window's menu strip; an image cell's image is its object value (an image set to nil
#         showed the nib's placeholder, the application's icon, on every process); a table keeps its columns'
#         widths unless its column autoresizing style says otherwise, and its header draws an empty header
#         right of the last column; a view-based table reloads the rows shown in place (the cell's own view is
#         given back to it) and draws only what changed; a dirty view scrolled out of sight is not drawn; a
#         system catalog colour is resolved once per appearance; SF_CA_TRACE is read once (it was a getenv per
#         -setFrame:); a pop-up (not pull-down) menu with items has one selected (Activity Monitor's Send Signal
#         sent signal 0). Activity Monitor's own CPU: docs/roadmap/issues/SF-AA-activity-monitor.md, Performance
#   0108  AppKit: NSMenuItem's object getters (title, attributed title, key equivalent, image, represented
#         object) answer retained and autoreleased, as macOS's atomic properties do. With libFoundation's
#         CFAutorelease fix (terminal-app/build-foundation.nix, 14 November evening) strings are freed when
#         their pool ends; Terminal keeps a removed item's key equivalent (macOS's one-letter strings are
#         tagged pointers, never freed) and ended in -[NSMenuItem initWithTitle:...] without this
#   0109  CoreGraphics (ImageIO re-exports it): CGImageSourceCreateThumbnailAtIndex (oriented, scaled to
#         kCGImageSourceThumbnailMaxPixelSize) and image metadata (tags by path, made, copied, set, read,
#         removed; a source's EXIF and TIFF properties as exif:/tiff: tags), for Finch's Contacts and
#         MediaAccessibility (runs/m1-coord/requests-for-CLAUDE.md)
#   0110  AppKit: the modern NSCollectionView from Finch (MIT OR Apache-2.0; data source, registered items, flow
#         and grid layouts, selection, the older content/prototype form; NSCollectionView.m, NSCollectionViewLayout.m,
#         notices kept): an item with nothing registered comes from a nib or class of the identifier's name, as
#         on macOS; NSViewController -isViewLoaded; SF_CV_TRACE=1 prints each layout pass. Activity Monitor's
#         Window > CPU Usage and CPU History open (they ended the application or did not open). Needs
#         libFoundation's NSIndexPath: AppKit is built against ../terminal-app/build-foundation.nix (below)
#   0111  AppKit: images of an application's asset catalog for +[NSImage imageNamed:] (Finch's CoreUI bitmap,
#         deepmap2 and LZFSE/LZVN/zip decoding and rendition choice; libcompression and zlib looked up at run
#         time) and Finch's symbol glyphs (about 150 names drawn in code, with .fill/.circle/.slash/.badge) after
#         our own five (NSSymbolImages.m)
#   0112  AppKit: SF_SOLVE_TIME=1 prints each whole-tree constraint solve's time and the sum (Finch's solver core
#         in place of ours was measured with it and taken back: Terminal's Preferences 1574 ms of solving with
#         ours, over 10000 ms with Finch's used as a throwaway solver; SF-AA, "Taken from Finch")
#   0113  AppKit: macOS 26's toolbar buttons: an image button or pull-down that is a toolbar item's view draws its
#         glyph alone, centred, one height (28 points) for all, a row of them in one rounded capsule, a small
#         down chevron after a pull-down's glyph, the room around each glyph the same; a preferences toolbar's
#         selected item in a soft rounded rectangle (Activity Monitor's stop/info/actions row, owner's photo)
#   0114  AppKit: macOS's overlay scrollers (the style of a Mac with a trackpad; legacy with AppleShowScrollBars=Always
#         or SF_SCROLLERS=legacy): a thin rounded knob over the content, no track or arrows, wider on a faint
#         track while dragged, shown when the user scrolls (-flashScrollers) and faded a second later (a one-shot
#         timer, then a fade that stops itself: nothing runs at rest); no room taken, no corner, a scroller
#         with nothing to scroll hidden; in the legacy style the square where two scrollers meet is painted
#   0115  AppKit: -[NSEvent CGEvent] autoreleases with -autorelease (CoreFoundation's CFAutorelease does not
#         autorelease a CF-owned object: every CGEvent asked for leaked)
#   0116  AppKit (COCOA4, the owner's findings): a window kept after -close keeps its window-server window
#         (destroyed with the object), so Terminal's Preferences opens again after Command-W; NSCursor's +hide/
#         +unhide counted and +setHiddenUntilMouseMoves: hides only until the pointer moves (the pointer stayed
#         invisible over Terminal after typing); an application outlives its last window (SFQuitsWithLastWindow
#         =YES for the old rule); NSPathCell without -[NSURL initWithScheme:host:path:]; +[NSColor
#         colorWithRed:green:blue:alpha:] (Activity Monitor's CPU windows raised on it); the window server
#         thread drains a pool per message (every NSEvent it made stayed); NSColorPanel built in code when its
#         nib is missing (colour swatch, palette, red/green/blue sliders and fields, opacity slider and field shown
#         unless +[NSColor ignoresAlpha]): Terminal's colour wells opened nothing; the HSB conversions in CGFloat
#         (they wrote floats into doubles: -getHue:... answered denormals and +colorWithCalibratedHue:... stack
#         garbage: Terminal's marks pure blue, a red line around its window); the desk's per-application menu
#         socket ($XDG_RUNTIME_DIR/app-menu/<pid>: the main menu, invoke, the menu strip on/off); Terminal's
#         Window Groups symbol (rectangle.3.offgrid, our drawing)
#   0117  WindowServer: a pointer hidden until it moves is shown at its next motion or entry, on the input
#         thread; SF_CURSOR_TRACE=1
#   0118  CoreGraphics: CGColorSpaceCreateWithICCData/ICCProfile/ICCBased keep the profile (CGColorSpaceCopyICCData),
#         model and components from its header; CGColorSpaceCreateIndexed and the indexed getters (Codex's
#         bodies); kCGColorSpaceCoreMedia709
#   0119  Onyx2D: the path a gradient fills under a clip path is released (its edges leaked at each one)
#   0120  AppKit (TERM5, the owner's hands-on round): -centerScanRect: and -backingAlignedRect:options: (NSView,
#         NSWindow) put edges on the backing store's own pixels (its pixels per point along each axis), dirty
#         rects too (Terminal's rows and selection no longer end half way through a pixel at 150 %); with no
#         preference set, transparency is reduced while the compositor cannot blur behind a window (Terminal's
#         default profile then draws opaque, as macOS with Reduce Transparency; `defaults write
#         com.apple.universalaccess reduceTransparency -bool false` gives translucency back); windows tell the
#         window server whether they are opaque; menus: motion coalesced, a submenu opens after the pointer
#         rests 60 ms on its item instead of being built while the pointer passes, SF_WS_TIMING lines;
#         NSPathControl has no intrinsic width (its cell's 10000 points made Terminal's Profiles > Text box
#         10000 points wide: the black bar over "Background"); SF_IMAGE_TRACE
#         (night, later): the colour panel's accessory view (Terminal's background well), one toggle per click of
#         a colour well; a wrapping label longer than its width is as tall as its lines; click sequences need
#         the same window, 4 points and 0.5 s (com.apple.mouse.doubleClickThreshold), a table's double action
#         both clicks on one row; a window ordered out gives up key and main (Activity Monitor ended with
#         SIGSEGV when its inspector closed); tab accessory views in a slot of their own; one-line strings
#         truncated head/middle/tail with an ellipsis; the help button's question mark; crash reports in
#         ~/Library/Logs/DiagnosticReports/<name>-<pid>.crash (SF_NO_CRASH_REPORT=1: none)
#         a view taken out of the hierarchy takes the constraints above that refer to it (Activity Monitor's
#         tab switch messaged a freed view); a colour well without a border activates on a click
#   0121  WindowServer: the opaque region of an opaque toplevel; _windowServerCanBlurBehind; SF_WS_SCALE (a test
#         instrument: one application's backing stores at a chosen scale); pointer motion in SF_WS_TIMING
#   0122  Onyx2D: a clip's edges within 1/1024 of a pixel boundary are on it (a dirty rect that went to points
#         and back took one more row, which the window's clear made transparent and no fill covered);
#         O2_FILL_TRACE lists the rectangles filled
#   0123  AppKit (TERM6): a menu's panel (its shadow and rounded body) drawn once small and pieced together for
#         every size and every highlighted row (it was eight path fills over the whole menu each time;
#         SF_MENU_VECTOR=1 draws the vectors); the accent colour read from the preferences at most once a
#         second; a popup's role asked of the window server before it is drawn; the main menu revalidated
#         four times a second only while a menu bar server takes it; crashes: a table click on a row but beside
#         every column (column -1 as an index), drawing on a progress indicator's animation thread (all
#         windows drawn there beside the main thread: SIGBUS in Onyx2D), a view marked for display from another
#         thread; without EGL a view hosting a layer draws its layer tree on the CPU (background, CGImage /
#         NSImage / BGRA CVPixelBuffer contents with gravity, border, corner radius, sublayers, opacity) and a
#         60 Hz check marks it for display when the tree changes; a view's alphaValue fades its drawing;
#         -[NSMenu performKeyEquivalent:] and -update go over a copy of the items taken after the delegate filled
#         the menu in (Terminal ended with a CFArray index trap on a Command key); the crash report's directory
#         is made at every level (a new home had no ~/Library/Logs: no report); SF_COLORPANEL_TRACE
#   0124  WindowServer: kWSWindowPrepareRole (a popup's xdg_popup asked for before AppKit draws it, the flush
#         waits for its configure); frames unused for 2 s beyond two per window are let go
#         (SF_WS_KEEP_FRAMES=1 keeps them); SF_WS_DUMP_ALPHA=1 dumps the alpha too
#   0125  AppKit (TERM6): the menu panel's pieces drawn without antialiasing (0123's pieces left half-transparent
#         lines where they met) and the shadow rings' hole the panel's own rounded shape (a plain hole left a
#         darker band down the inside edges); a menu of a window's strip draws the strip alone and does not
#         validate the whole main menu first; the accent colour read again only when the global preferences
#         file changed; Reduce Transparency: NO in an application whose user chose an opacity below 100 % in
#         the colour panel (SFTranslucencyChosen in its defaults, announced with
#         NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification); tail truncation by halving; a split
#         view's missing divider moves nothing (Terminal's exception) and its min/max divider positions
#   0126  WindowServer: SF_WS_TIMING says how long a flush waited for a popup's configure
#   0127  AppKit (TERM6): -floatValue and -setFloatValue: of NSCell, NSControl (NSActionCell, NSScroller) take and
#         answer float, as in macOS's API (CGFloat answered in d0: an application built for macOS read s0, the
#         colour panel's opacity read 0 and set it, every slider's value set from Terminal was garbage; code
#         built against the old header must be built again); a colour well's click is a click unless the
#         pointer moves three points (the compositor's motion at the press started a colour drag: Terminal's
#         background well never opened the panel); menus opaque where the compositor cannot blur;
#         SF_SLIDER_TRACE; crashes found by the robustness pass under MallocScribble: an alert's button ending its
#         sheet let the alert go (and its window) before -_alertButton: was done (Terminal, SIGSEGV on a freed
#         target after Escape on a sheet's Cancel); a button clicked by its key equivalent stays until its action
#         is done (SF_KEYEQ_TRACE); the find bar's controls stop messaging a finder that is gone; SF_CA_TRACE
#         says when a hosted layer is drawn on the CPU
#   0129  WindowServer: frames are kept again unless SF_WS_TRIM_FRAMES=1 (0124's letting go of frames unused for
#         2 s made Activity Monitor create an 8 MB frame at each refresh: CPU 2.5 -> 11 % with bursts, RSS
#         swinging 75-111 MB; measured on the M1)
#   0128  AppKit (TERM6, the owner's finding): a table column's sort indicator has its own slot at the header
#         cell's trailing edge (-sortIndicatorRectForBounds:, -drawSortIndicatorWithFrame:inView:ascending:
#         priority:), the title's rect excludes it while the column shows one (Activity Monitor's chevron was
#         drawn on top of "% CPU"), and a title too wide is cut with an ellipsis
#   0130  AppKit (TERM6, the owner's findings): a column divider drag follows the newest pointer position only,
#         re-tiles without reloading every row, saves the widths and tells the delegate at the release; a table's
#         layout solves each changed row once per pass (cell views are layout boundaries; a boundary moved without
#         changing size skips its solve; row views no longer autoresize their cells; NSViewGlobalFrameDidChange
#         only for views with surfaces); what is right of a dragged column is copied along in the window, only the
#         column is drawn; strings drawn in a rectangle are laid out once and kept (by their own width when they fit
#         on one line); vertical gradients filled a row of pixels at a time; NSClipView copies on scroll
#         (copiesOnScroll, as macOS; SF_CLIP_NO_COPY=1 / SF_TABLE_NO_COPY=1 / SF_TYPESET_NO_CACHE=1 to compare);
#         header drag reorders columns (it was missing) and the sort is taken at the release; NSSplitView: one pane
#         left fills the split view (Terminal's grey box when a split closed), panes are not laid out again at
#         -addSubview: (Terminal places them itself; its window shrank at each split and close), the last pane
#         takes the rounding remainder; SF_SPLIT_TRACE, SF_WINFRAME_TRACE (who changed a window's frame)
#   0131  AppKit (TERM6): the string layout cache of 0130 let go of a generation while a layout found in it was
#         being drawn and kept (use after free: Activity Monitor's text garbled after a few minutes, the owner's
#         report; a crash within 20 s with SF_TYPESET_LIMIT=30, the generation size, now settable to test)
#   0132  AppKit (TERM6, Activity Monitor's inspector): a tab view's selected item view is held by its margins in the
#         layout (what is in it can make the tab view, and the window, larger); a window is made as large as its
#         content's fitting size when it is shown and when its tab view shows another tab (the inspector's rows were
#         squeezed into the nib's 274 points, one over another); a wrapping label wraps only when something else sets
#         its width and its text is not a short value a little too wide ("391.08 GB" had wrapped onto the next row,
#         the sample window's status one word per line); the control's NSControlLineBreakMode and
#         NSControlUsesSingleLineMode from the nib (-usesSingleLineMode); SF_VIEW_DUMP=1 + SIGUSR2: every window's
#         view tree on stderr
#   0200-0207 (CODEX-FX, found with Firefox; merged by TERM7 from integrations/siliconforest/firefox/cocoa-patches,
#         numbers kept; applied after 0132):
#   0200  Onyx2D: shared FreeType faces and the process-wide glyph bitmap cache are used under one lock (Firefox's
#         threads drew different glyphs of one face at once: SIGSEGV in ft_smooth_render)
#   0201  AppKit: an application without a display (a sandboxed helper) runs its run loop instead of spinning on a
#         nil display (its CFRunLoop sources and timers starved, a core busy)
#   0202  QuartzCore: CALayerContext renders at the window's pixel scale (-setBackingScale:; at 150 % the layer tree
#         was drawn at 1x and stretched)
#   0203  AppKit: a view's layer context gets its window's backing scale before it renders
#   0204  AppKit: -setLayer: on a view without a superview (a window's root) also gives its layer context the new
#         layer (it kept drawing the old one)
#   0207  QuartzCore: a layer context invalidated, freed or given another layer clears the context pointer of the
#         tree it held (a tree kept by the application messaged a freed context: Firefox's close-tab crash)
#   (0205 and 0206 of that series are not merged, and CODEX-FX withdrew both: 0205 is an opt-in experiment with no
#   measured gain whose walk of the tree at each commit reads the context's root without holding it; 0206 changes the
#   class frame/content conversions, which Terminal and Activity Monitor never call, and Firefox's tab strip is right
#   without it; SF-Y "TERM8 round")
#   0133  AppKit (TERM7): without OpenGL a view with a layer draws into its window (its own bitmap was drawn and
#         never shown: a hosted layer's contents, a movie's frames, stayed the window's grey) and what a view put
#         in its layer through -updateLayer/-displayLayer: is drawn there too; CVPixelBuffer contents are drawn (a
#         CF object's class is the bridge's, not Nil); layers marked -setNeedsDisplay are displayed before the tree is
#         drawn; a view controller made without a nib name uses the nib named after its class (macOS 10.10;
#         Activity Monitor's CPU Usage and CPU History items were empty views); -[NSImage drawInRect:...fraction:]
#         multiplies the alpha already set (a faded view's: CPU Usage's segments were all lit);
#         NSCollectionViewCompositionalLayout lays out (sections from a provider, groups of a subitem with a count,
#         fractional and absolute dimensions: CPU History); NSSplitView's arranged subviews (macOS 10.11; GPU History
#         raised); a text view's container lower than one line keeps its first line, raised by what the glyphs
#         lack (the inspector's Executable Path was not drawn); the standard NSImageName names and the AppKit names
#         VLC's interface imports
#   0134  QuartzCore (TERM7): CALayer -display draws -drawInContext: into a bitmap at the layer's pixel size and
#         makes it the contents, -displayIfNeeded, -setNeedsDisplay asks for a render, CALayerContext displays the
#         marked layers before it renders; CAOpenGLLayer (CGL: a
#         context of the layer's pixel format, its offscreen surface read back as the contents; without OpenGL
#         it draws nothing and says so)
#   0136  AppKit (TERM7): a wrapping label keeps its whole height for its lines (a two-line explanation sized for
#         two lines lost the second to the point the text is moved down: Terminal's Preferences > Window Groups)
#   0135  CoreGraphics (TERM7): CGDisplayUsesOpenGLAcceleration; display fade reservations (none available)
#   0210, 0210w, 0212, 0214, 0215, 0217, 0219 (CODEX-FX, found with Firefox; merged by TERM8, numbers kept,
#         regenerated against this tree; applied after 0136):
#   0210  AppKit, 0210w WindowServer: finger scrolling in pixels with its phases, only with SFFX_PRECISE_SCROLL=1 and a
#         compositor that reports a finger axis source (the M1's trackpad reports wheel steps: inert there)
#   0212  AppKit: NSMenu -appearance/-setAppearance:/-effectiveAppearance, inherited by its popups (Firefox's context
#         menu raised on the missing selector)
#   0214  AppKit: an NSPasteboardItem's data provider is given the destination pasteboard (Firefox's drags offered
#         no types)
#   0215  CoreText: a copy of a font with attributes keeps its graphics font (CTFontCreateCopyWithAttributes drew a
#         Noto Emoji copy with Inter)
#   0217  Onyx2D: a font of a collection keeps fontconfig's face index (CJK fonts drew their first, Japanese, face)
#   0219  QuartzCore: a layer context releases its renderer, root layer and CGL context and pixel format (adapted:
#         the main series had no 0208; replaced by 0219q since TERM9 adopted 0208, the file is kept for its history)
#   0220  CoreText (CODEX-FX, merged by TERM8 unchanged): a font descriptor made from data holds its own graphics font
#         (every face of a collection) and is not registered by name, as on macOS; no file in /tmp (Firefox's GPU
#         process may not write files, so every web font drew no text)
#   0137  AppKit (TERM8, VLC 3's interface): +[NSColor currentControlTint] and +colorForControlTint: (macOS's
#         AppleAquaColorVariant/AppleAccentColor), the NSControlTint values; the standard template images
#         (NSImageNameActionTemplate, ...Add, ...Remove, ...Refresh, ...) drawn as the symbols they stand for;
#         -[NSStatusItem _update] (no status bar on this desktop: items kept, shown nowhere, said once);
#         -[NSCell/NSTextField allowsEditingTextAttributes/importsGraphics] and their setters;
#         -[NSMutableAttributedString setAlignment:range:], -[NSTextView setAlignment:range:];
#         -[NSSegmentedCell rectForSegment:inFrame:]; NSOutlineView -setDropItem:dropChildIndex:, NSSliderCell -trackRect,
#         NSClipView -documentRect, NSBox -sizeToFit, NSButtonCell -mouseEntered:/-mouseExited:, NSBrowserCell
#         -setImage:, NSAnimationNonblockingThreaded (timed on the main run loop), NSView
#         -wantsExtendedDynamicRangeOpenGLSurface (all raised "not implemented" or were missing); a modal panel's
#         wait now includes the window server's events (a click woke -runModalForWindow: only when a timer fired:
#         VLC's first-run alert never answered); the first NSDocumentController made stays the shared one (one a nib
#         made and released left it dangling); -[NSImage drawInRect:...] and NSString drawing with no current graphics
#         context draw nothing (0133's alpha read crashed there: Terminal ended at every minimise, the owner's report),
#         -[NSString drawWithRect:options:attributes:(context:)] and -boundingRectWithSize:options:attributes:context:
#         (Terminal draws its miniwindow's title with it), -[NSAttributedString drawWithRect:options:] (raised)
#   0139  AppKit, 0139w WindowServer (TERM8): a pinch (zwp_pointer_gestures_v1, when the compositor offers it) is an
#         NSEventTypeMagnify event with -magnification (the change of scale) and -phase, sent to -magnifyWithEvent:
#   0141w WindowServer (TERM8): with the compositor's wp_cursor_shape_v1, NSCursor's standard cursors (and the xcursor
#         names AppKit gives window edges) are asked for by shape: the desk draws its own pointer set at the display's
#         scale (one pointer family; Terminal's text area shows the desk's I-beam); an application's own NSCursor
#         image still goes as a bitmap; without the global the theme path stays
#   0143w WindowServer (TERM8, Firefox left running with no window): a window whose next role is of another kind (a
#         popup whose parent is gone shown as a toplevel, a level change between a layer and an ordinary window) gets
#         a new wl_surface (a surface keeps its role for life: "Surface already has a role" ended the connection); and
#         when the connection ends the application ends too, as a Mac application does when its window server goes
#         (it said why; SF_WS_SURVIVE_DISCONNECT=1 keeps it alive for tests)
#   0145w WindowServer (TERM8): an application's own cursor image that is the one already shown is not copied into a
#         new shared-memory buffer again (AppKit sets Terminal's I-beam at every pointer motion)
#   0146  Onyx2D (TERM8, FX-010): the glyph bitmap cache knows a face by its address and a number given the first time
#         it is seen (FreeType's client slot): a face freed and another made at its address (Firefox's web-font subsets)
#         was given the first one's glyphs ("Busness" on nytimes.com)
#   0147  AppKit (TERM8, FX-004): NSTextField +labelWithString:, +wrappingLabelWithString:, +labelWithAttributedString:,
#         +textFieldWithString:; NSButton +buttonWithTitle:target:action: (and with an image), +checkboxWithTitle:...,
#         +radioButtonWithTitle:... (Firefox's crash reporter raised on +wrappingLabelWithString:)
#   0144  AppKit (TERM8): the app-menu socket takes "reopen" (macOS's reopen event: the delegate asked, unhide, a
#         minimised window back, else the untitled one: the dock's click on a windowless application) and "quit"
#         (-terminate:, with or without a window); a reopen with no window on screen brings a minimised one back first
#   0142  AppKit (TERM8): a tracking area made with NSTrackingInVisibleRect follows the view's visible rectangle (its own
#         rectangle is ignored, as on macOS): Terminal's text view never got -cursorUpdate:, the pointer stayed an arrow
#   0140  AppKit (TERM8): the layout solver meets constraints in priority order (one objective per priority,
#         a higher priority first, as Cocoa's solver does) instead of a weighted sum: a label hugging at 750 no
#         longer loses to six compression resistances of 749 (Activity Monitor's "Context Switches:" got 59 of 95 pt)
#   0138  QuartzCore (TERM8): CALayer -needsDisplayOnBoundsChange, -autoresizingMask (sublayers follow their
#         superlayer by their masks, as with no layout manager on macOS) -visibleRect and -layoutSublayers/-setNeedsLayout/-layoutIfNeeded (VLC's CAOpenGLLayer raised on them)
#   0148w WindowServer (TERM9, frame pacing): for every frame committed the flip that shows it (wp_presentation feedback
#         for a GPU frame, the desk answers those; a frame callback for the others, done at the flip with its time):
#         the latest flip (in host time), the measured refresh and the commits still waiting, for CoreVideo's display link
#         (_windowServerDisplayClock/_windowServerDisplayClockWait: ./patches/0149-corevideo-...)
#   0156w WindowServer (TERM9, FXPERF's FX-029 ask; opt-in SF_WS_PACE_PRESENTS=1, off by default): a window presents at
#         most once per frame callback; a flush while its last commit is not drawn only marks the present pending and
#         the callback presents the newest backing store (a callback missing for 100 ms holds nothing back)
#   0375w WindowServer (CHONKPERF, ChonkCraft's white bars): a flush held back by SF_WS_PACE_PRESENTS copies the
#         backing store into a frame at the flush (AppKit has finished drawing then); the frame callback only attaches
#         and commits that copy. Before, the callback copied the backing store while the main thread could be halfway
#         through its next drawing (white rows below each of Onyx2D's four bands). SF_WS_PACE_HOLD=0: as before
#   0376w WindowServer (bake-in step 4): SF_WS_PACE_PRESENTS is default on (SF_WS_PACE_PRESENTS=0 turns it off), with
#         0375w's hold-copy and 0156w's 100 ms missing-callback guard active
#   0377w WindowServer (bake-in step 6): sfGPUFrameCreate passes SFIOSurfaceGPUStorage=1 so GPU output frames get
#         dma-buf storage without requiring global SFFX_IOSURFACE_GPU=1
#   0378  QuartzCore (bake-in step 7): CAOpenGLLayer and CALayerContext pass SFIOSurfaceGPUStorage=1; GPU path perf
#         flags (dirty frames, damage, render thread, cached lookups) default on when GPU present is active (=0 disables)
#   0379  AppKit (bake-in step 7): automatic GPU presentation for windows whose layer tree holds a CAOpenGLLayer or
#         IOSurface contents; CPU-drawn windows keep the backing-store path (SFFX_GPU_PRESENT=0 disables, =1 forces)
#   0380w WindowServer (bake-in step 7): GPU presenter entry points accept calls unless SFFX_GPU_PRESENT=0; vector
#         compare and GPU damage default on (=0 disables)
#   0384w WindowServer: CGAssociateMouseAndMouseCursorPosition(false) locks the focused window's pointer
#         (zwp_pointer_constraints_v1, persistent) and takes zwp_relative_pointer_v1 dx/dy (positive right,
#         positive down, as NSEvent's deltas are on macOS). Without a relative pointer, motion stays absolute
#         and its dy is positive down only while disassociated. (true) unlocks. Unlocked motion is unchanged.
#   0385  CoreGraphics: those two calls go to WindowServer and succeed; CGDisplayMoveCursorToPoint moves within
#         the display; a mode whose refresh is 0 is reported as 60 Hz
#   0386  AppKit: -[NSOpenGLContext flushBuffer] presents through the GPU IOSurface ring (SF_NSGL_GPU_PRESENT=0
#         keeps the CPU readback; any failure falls back to it); NSWindow backing-rect conversion; the pixel
#         format query writes a GLint; -[NSApplication setAppleMenu:] keeps the menu and -appleMenu returns it;
#         -[NSWindow frameRectForContentRect:styleMask:] answers GLFW's instance call with the class calculation
#   0387w WindowServer: _windowServerSFFXPresentLayers presents a live GPU layer directly. The pace-hold used to
#         set presentPending and return success; the frame callback does not compose that layer (0375w), so
#         Minecraft's compose counter stayed at 3 and the window stayed the wallpaper. SF_WS_PACE_PRESENTS
#         still holds a window that has no GPU layer.
#   0388w WindowServer: a live GPU layer commits once per frame callback. 0387w committed every swap, and
#         the compositor replaced those commits before a flip (WMPACING shown=0). The render thread composes
#         into one attached buffer while the callback is outstanding; the callback commits it. A callback
#         that does not arrive within 100 ms commits once and waits again. A window with no GPU layer is
#         unchanged.
#   0389w WindowServer: a GL layer is drawn opaque (texture RGB, alpha written as 1). Premultiplied
#         source-over was keeping Minecraft's partial alpha (FBO0 alpha 64) and the content area stayed
#         clear, so the desk wallpaper showed through. SFFX_GPU_LAYER_ALPHA=keep is the old blend.
#         SFFX_GPU_LAYER_PROBE=1 logs the layer IOSurface (CPU and the imported texture, with the import's
#         glGetError) and the composed dma-buf inside the layer rect.
#   0390w WindowServer: a paced GPU commit re-attaches the last composed frame (gpuComposed, else the
#         front buffer) and damages the whole window before wl_surface.commit. SFFX_GPU_BUF_TRACE=1 logs
#         the buffer id, fd, offset, and whether that buffer is the one just composed. CPU windows are
#         unchanged.
#   0394w WindowServer: a GPU frame taken while a callback is in flight (0388w) is returned to the
#         pool when that path commits a different frame instead (callback later than 100 ms). The
#         abandoned frame was never committed, so the compositor will never release it. A frame
#         already given to the compositor is left busy. If every non-given frame stays busy for
#         more than 100 ms, reclaim the oldest of those and log SFWS RECLAIM-UNRELEASED. The
#         scanout buffer is not reclaimed. 0393w (reclaim any oldest frame) is not in this series.
#   0149  CoreVideo (TERM9; built by ./corevideo-displaylink.nix on CODEX's ../finch/CoreVideo/sf-displaylink.nix): the
#         display link ticks right after the flip that showed the application's last frame (inNow = that flip,
#         inOutputTime = the next), waits for a frame still in flight (at most two refreshes), else ticks on the
#         display's phase; the 60 Hz timer only without the clock (SF_CV_TIMER=1 keeps it); the measured refresh
#   0153  QuartzCore (FXLEAD, FX-036, the blank page): -[CALayer display] asks a delegate that wants to update its layer
#         itself (-wantsUpdateLayer, NSView) for -updateLayer, as AppKit's -displayLayer: does on macOS; Firefox ends the
#         suspension of its layer commits there (a stale first picture, then nothing); inert for views that answer NO
#   (0155, FXLEAD's layer-contents use count + release at -dealloc: NOT in the series - FXLEAD withdrew it at 02:21Z, its
#         repeat showed FX-011/012 unchanged and Firefox's parent counts the use itself; the file is kept for its history)
#   0154  Onyx2D (FXPERF, adopted unchanged): an installed font file of 1 MB or more is mapped once per process and
#         shared by every data provider (it was read whole into a private copy each time: Firefox's parent held ten
#         30 MB copies of the CJK collection, footprint 921 -> 634 MB)
#   0160  QuartzCore (TERM10, FX-029): a layer property set to the value it has asks for no render; with
#         SFFX_GPU_SKIP_UNCHANGED=1 (opt-in, for FXPERF's A/B) a bare CATransaction commit schedules a render without
#         counting as a change, so 0216's frame reuse can apply; SF_CA_DIAG counts rendered/reused/rendered-unchanged
#   IN THE SERIES since TERM13 (17 November, owner's order "install them both"; installed 06:34Z as AppKit 6a2dd27a,
#   libWindowServer 752999d3, QuartzCore.pd ab4f4daf; see SF-Y "TERM13"): 0178, 0178a, 0178w (TERM12's, unchanged)
#   STILL HELD (patch files in ./patches, NOT in the lists below, NOT installed): 0179, 0180a, 0180w
#   0178  QuartzCore: the layer tree rendered and presented on a render thread at each committed transaction
#         (SFFX_GPU_RENDER_THREAD=1 with SFFX_GPU_PRESENT=1; inert without), a process-wide frame lock, a reader/writer
#         gate between explicit transactions and renders (fails closed after 20 ms; SF_CA_GATE=soft / SF_CA_NO_GATE=1 for
#         A/B), contexts of windows off the screen not asked for renders by other windows' commits, SF_CA_FRAME_TRACE=1,
#         SF_CA_DUMP_STRIP=x,w,frames,path[,after_ms] (per-frame column record), SF_CA_DELAY_MS (diagnostic)
#   0178a AppKit: the presenter the render thread calls (export, GPU layer registration, window server present), the
#         main thread's frames under the frame lock, no readback of an unchanged commit frame, windows off the screen
#         not rendered
#   0178w WindowServer: _windowServerSFFXPresentLayers (a present from the render thread, refused when the window's
#         geometry serial moved: buffer, role, state/level/style change, any xdg configure), presents counted by source
#   0179  QuartzCore: painter's order (no depth test; zPosition orders siblings) and contents clamped to their edges
#         (FXPERF2's missing position:fixed marker; GL_REPEAT edge bleeding); SF_CA_OLD_ORDER=1 restores the old
#   0180a AppKit, 0180w WindowServer (FX-002): a full-size-content window with a transparent title bar and hidden title
#         draws its own title bar (client-side decorations, set_mode at run time), its buttons where the app puts them
#         (-_closeButtonOrigin), over its GPU layers via a window-server overlay; no menu strip there (menus on
#         right/Control-click of the buttons' row); SF_NO_CLIENT_TITLEBAR=1 disables. First capture: frame right, the
#         three buttons NOT visible yet.
#   0177  AppKit (TERM11, clipboard): an application's write to the general board is not replaced by another client's
#         selection that arrives before the write's offer is out (within a second; the desk's clipboard keeper re-offers
#         the previous copy): the offer went out with the other client's types and none of the data
#   0176  AppKit (TERM11, clipboard): data written after its type was offered goes at once into what paste requests are
#         answered from, and a new declaration empties it (Firefox's offer went out before its data: 0 bytes / a BOM)
#   0175  AppKit (TERM11): a view that has a layer context keeps it (a second one replaced it without invalidating it; a
#         render the first had queued messaged the freed view: Firefox SIGSEGV in -[CALayerContext _scheduleRender]'s
#         block as a panel window closed, seen with t11a); a paste request between an offer and its data is answered
#         from the board's own data
#   0174  AppKit (TERM11): SF_PB_TRACE=1 logs what an application declares and writes on a pasteboard
#   0173w WindowServer (TERM11, FX-022): the pointer entering a window is a mouse move there (a pointer arriving on
#         Firefox's open menu panel brought no move, and the item under it did not highlight)
#   0172  CoreVideo (TERM11, corevideo-displaylink.nix; FXPERF2's finding): the display link ticks at every refresh on
#         the display's phase; a flip reported first only moves the phase (it waited for a pending frame's flip and
#         Firefox locked to every second refresh, ~30-35 presented frames/s in 4 of 9 runs)
#   0171  AppKit (TERM11): SF_WIN_TRACE=1 traces pointer events reaching windows above the normal level and ignoresMouseEvents
#   0170  AppKit (TERM11, FX-022): a view with a layer that moves under another view puts its layer into the superview's
#         layer (or renders it with a context of its own when that one has none); a removed view's layer leaves its old
#         superlayer; before a tree renders, a subview's layer found outside it is put back. Firefox's menu panel put its
#         ChildView (the layers with its pixels) under a layer-backed content view whose layer had no sublayers: the panel
#         was read back empty, an invisible window that took clicks
#   0169  AppKit (TERM11, after CODEX-FX's review of 0164): after the delegate said NSTerminateNow, an application with
#         AppKit's own -terminate: ends without that asking the delegate a second time; a replaced -terminate: (Firefox's)
#         is run as before
#   0168  AppKit (TERM11, clipboard): another client's paste request is answered from the data that was offered, on a thread
#         of its own; only lazily provided data goes through the main thread, from the offered board (it was answered on the
#         main thread from the board as it was then: Firefox's copy reached every other client as 0 bytes)
#   0167  AppKit (TERM11): SF_WIN_TRACE=1 names the view whose layers are read back and prints the layer tree's shape
#   0166  AppKit (TERM11): SF_WIN_TRACE=1 also traces the layer read-back of windows above the normal level (popups)
#   0166w WindowServer (TERM11, owner's scroll feel): the momentum's release speed capped at 6000 points/s (a hard flick
#         coasted ~7 screens; now at most ~1900 points after the fingers' travel) and its decay by the time that passed
#   0165  AppKit (TERM11, FX-022): a window off the screen sends no flush (the window server gave a flushed hidden
#         window a role and mapped it: Firefox paints its menu panel after hiding it, which came back at level 8);
#         SF_WIN_TRACE=1 traces the notifications a window posts and its orders (Firefox rolls up popups on several)
#   0164  AppKit (TERM11): the desk's Quit (dock tile, switcher) asks the delegate -applicationShouldTerminate: first, as
#         macOS's quit Apple event does (Firefox replaces -terminate: by a notification only and quits itself from its
#         delegate: a windowless Firefox told -terminate: stayed alive)
#   0306  QuartzCore (FXPERF2, adopted by TERM11 unchanged): NV12/x420 video planes go up as R8/RG8 (R16/RG16), Mesa's copy
#         path, not LUMINANCE/LUMINANCE_ALPHA, which Mesa converted pixel by pixel (44 % of Firefox's parent main thread on
#         cnn.com; 1080p60 parent 78.4 -> 29.4 % of a core); luminance stays the fallback if the driver refuses
#   0320  QuartzCore (VLC, docs/roadmap/issues/SF-AH-vlc.md): an opaque CAOpenGLLayer's read-back picture is an image
#         without alpha (VLC draws its video with alpha 0 into an opaque layer: the window was black)
#   0321  QuartzCore (VLC): -[CALayerContext setLayer:] with the root it already has gives that root its pointer to
#         the context back when it lost it (AppKit detaches a view's layer when the view moves under a superview
#         without a layer): new contents asked for no frame, a player's picture stayed at its first frame
#   0322  AppKit (VLC): -[NSMenuItem parentItem] (VLC's menu validation asked for it; each of its menus ended in an
#         exception before it opened)
#   0323  AppKit (VLC): a layer the view's -makeBackingLayer made follows the window's backingScaleFactor (contentsScale),
#         a delegate answering -layer:shouldInheritContentsScale:fromWindow: deciding; AppKit's own backing layers are
#         unchanged (VLC's video was rendered at scale 1 and enlarged 1.5x)
#   0324  AppKit (VLC): when the desktop answers an application's request for a larger window with a smaller size, the
#         window keeps to that size until the desktop configures a larger one (VLC asks for its video's size in pixels,
#         larger than the screen; it was shown cut off, its controls out of sight)
#   0325  AppKit (VLC): NSAnimation's current value follows its progress (curve or delegate); -startWhenAnimation:reachesProgress:, -stopWhenAnimation:reachesProgress:,
#         -clearStartAnimation, -clearStopAnimation (VLC chains its fullscreen transition: it ended at the button)
#   0326  QuartzCore (VLC): CAOpenGLLayer makes its context current before locking it (VLC's order on its own threads)
#         and, where the context cannot be made current, draws and reads back nothing, keeping its last picture (black
#         frames while VLC's window was resized)
#   0327  AppKit (VLC): an NSOpenGLContext flushed from another thread has its frame drawn into its view on the main thread
#         (the newest only); NSOpenGLView's -reshape runs on the main thread, and at once when its frame changes, as on
#         macOS (VLC's NSOpenGLView output asserted it); a view wanting the best resolution gets a drawable in pixels
#   0328  AppKit (VLC): the first layers-only frame after a window was resized draws the window whole (its backing store is
#         new and empty: VLC's picture stood over the whole window, without menus and controls, during a corner drag)
#   0329  QuartzCore (VLC): CAOpenGLLayer reads its picture back only from its own context: where the application's drawing
#         left another context current, or none, the layer keeps its last picture (VLC keeps the context that was current
#         before its draw in one variable for all its threads; when its video thread asked for the context during a draw
#         on the main thread, that draw ended with no context current: black frames, about 0.1 s, during a corner drag).
#         SF_CAOGL_TRACE=1 says when; SF_CAOGL_TRACE=2 also logs every render (time, thread, size, a sample of the picture)
#   0331  QuartzCore (IOSURF): where IOSurfaces have GPU storage (SFFX_IOSURFACE_GPU=1), CAOpenGLLayer copies its picture
#         on the GPU (CGLSFFXCopyFramebuffer, rows flipped, alpha 1 for an opaque layer) into the next of two such
#         surfaces and makes that surface its contents, which the renderer binds without a copy; nothing is read back.
#         Without GPU storage it reads back as before. (VLC's 1080p picture: ~40 ms a frame of read-back, image and
#         per-pixel texture conversion on the render thread; the window showed ~24 of 30 pictures a second)
#   0333w WindowServer (IOSURF): a damage present finds the base's changed rows in one pass with sfGPUBaseEqual's
#         comparison (NEON under SFFX_GPU_VECTOR_COMPARE), not a whole compare and then memcmp row by row: VLC's control
#         bar redrawn twice a second cost 18-57 ms under the window server's lock, and its video presents waited
#   0334w WindowServer (IOSURF, attribute windowserverCadence only: VLC's private copy): SF_WS_CADENCE=1 (opt-in): a steady source's render-thread frames are held, once a frame
#         before their first layer is handed over, to a fixed phase of the refreshes (SF_WS_CADENCE_PHASE ms after wsClock's
#         refresh, 13: about the desk's flip, far from its latch) on the source's measured cadence (previous refresh +
#         interval in refreshes while the frame is ready in time): VLC's 30 fps pictures 2 refreshes apart instead of 1 or 3
#         when their commits drifted onto the desk's latch. =2 logs each frame
#   0304, 0305w (FXPERF2's FX-029 follow-ups, adopted by TERM11 unchanged; opt-in SFFX_GPU_DAMAGE=1): a layer-only
#         flush with nothing drawn into the window's own backing store tells the window server so, which then skips its
#         whole-backing-store compare (11 MB a present; ~10 % of Firefox's parent main thread on cnn.com)
#   0163  AppKit (TERM11, FX-022): ordering a window posts no move notifications (Firefox rolls its popups up in
#         -windowWillMove:: its menu panel closed itself 26-30 ms after opening, before the button was released); a
#         child window without a title bar tells the window server its parent (shown as a popup of it, at its frame);
#         a popup shown for the first time sends its frame before its role is asked for; key events that arrive for a
#         window that cannot be key (a popup holding the keyboard) go to the key window, as on macOS
#   0163w WindowServer (TERM11, FX-022): the keyboard going to one of our own popups (its grab) is no loss of key for
#         AppKit (a leave is told only when no enter on a window of ours follows within 40 ms; Firefox closed its
#         panel when its window resigned key); popups are the frameless windows at the pop-up menu level, frameless
#         child windows at any level, and a frameless window shown again after being a popup (Firefox lowers a
#         closing panel to level 8: it came back as a separate toplevel)
#   0300, 0301, 0302w (FXPERF2's FX-029 damage-only frames, adopted by TERM10; opt-in SFFX_GPU_DAMAGE=1, Firefox's
#         launcher): QuartzCore renders and exports only the changed rectangle, AppKit registers the GPU layer with it,
#         WindowServer composes and commits only it (wl_surface.damage_buffer). 0301 adapted to sit after 0158; the
#         CGL part (0303, EGLImage per IOSurface) is CODEX-FX's. FXPERF2's A/B (cnn.com idle, own Firefox): family
#         99.4 -> 86.9 % of a core, commits 85.6 -> 60/s, replaced unshown 26.5 -> 0.8/s
#   0162  AppKit (TERM10, FX-022): -addChildWindow:ordered: orders the child above its visible parent and no longer makes
#         it key (Firefox attaches its menu panel as a child right after showing it: the browser window resigned key and
#         Firefox closed the panel at once); -removeChildWindow: only detaches, as on macOS
#   0161  AppKit (TERM10): precise scroll deltas move a Cocoa scroll view by whole points (fractional offsets from
#         momentum drew Activity Monitor's table rows over each other)
#   0160a AppKit (TERM10, FX-029): a layer render that made no new frame (-_sfcaTakeNewFrame) flushes nothing
#   0158  AppKit (TERM10, FX-022): a layer-backed view in a window the window server cannot give GPU layers (a popup
#         or layer surface: _windowServerSFFXTakesGPULayers, 0158w) reads its layers back without copying a GPU frame
#         first (a copied-then-refused frame left the read-back empty: Firefox's menu panel was transparent)
#   0159w WindowServer (TERM10, the owner's "I have to scroll a lot"; the desk's contract, DESK10 desk10-001): the
#         trackpad's finger axis frames (points, the desk's acceleration and scroll speed applied, axis_stop at lift)
#         are precise scroll events for every application (was: Firefox only), began/changed/ended, then a momentum
#         phase from the release speed (last 100 ms of moving frames, 3+ frames, >300 pt/s; 0.95 a refresh; a finger
#         frame or a button ends it). A mouse wheel stays lines without momentum. SF_WS_FINGER_LINES=1: as before
#   0159  AppKit (TERM10): NSEvent -momentumPhase for those momentum events (bit 8 of the window server's scroll mods)
#   0158w WindowServer (TERM10, FX-022): a window the desk shows as a popup or a layer surface presents through
#         shared memory (the desk reads those buffers as shm and refused Firefox's dma-buf menu panel: "NotManaged");
#         its GPU layers are refused, so AppKit reads them back into the backing store. A menu-level window finds a
#         parent in the application's active or any mapped window before it is made a toplevel, and one that had to
#         be a toplevel drops that role when hidden (Firefox's panel came back as a toplevel on a fresh surface)
#   0157  QuartzCore (TERM10, FX-011/012): a layer the renderer meets without a texture name (a client thread added it
#         to the tree while the frame was drawn) gets its own; it bound none, so its contents went into the texture of
#         the layer drawn before it, which showed them until its own contents changed (foreign/stale tiles). The
#         render-scheduled flag as a full-barrier atomic (a change made while the main thread read the tree could be
#         left undrawn); texture names swapped under the tree lock; nested transactions inherit their outer one's
#         values; an implicit transaction is committed on its own thread. SF_CA_DIAG=1 / SF_CA_DUMP_DIR: what each frame
#         drew; SF_CA_OLD=1: the naming and flag as before (A/B)
#   0150  AppKit (TERM9, FX-023): NSEvent timestamps are seconds since the system started (mach_absolute_time), as on
#         macOS, not since 2001 (Firefox's Event.timeStamp was 26 years ahead of performance.now())
#   0230-0233 IOSurface (./iosurface.nix; CODEX-FX's iosurface-patches 0001-0004, FXLEAD's 0004): the per-session broker
#         (SFFX_IOSURFACE_SERVICE, iosurfaced --standalone), dma-buf storage (SFFX_IOSURFACE_GPU=1), NV12 GPU planes and
#         a process-local use count, a lookup never revives a surface being finalised (Firefox's crash firefox-5950)
#   0151  IOSurface (TERM9): libdrm loaded the first time GPU storage is asked for (nothing links it)
#   Firefox's GPU path in the main series (CODEX-FX's private R7 cohort adopted by TERM9, numbers kept; every piece acts
#   only with the launcher's SFFX_* variables, which no other application has: Terminal and Activity Monitor unchanged):
#   0208  QuartzCore: a layer context copies its rendered framebuffer into an IOSurface (CGLSFFXCopyFramebuffer) for the
#         window server, two per context, only with SFFX_GPU_PRESENT=1
#   0213  QuartzCore: that copy's IOSurface/CGL lookups made once (SFFX_GPU_CACHE_LOOKUPS)
#   0216  QuartzCore: a context whose tree, contents and IOSurface seeds did not change since the last render reuses its
#         frame (SFFX_GPU_DIRTY_FRAMES; read once)
#   0219q QuartzCore: CODEX-FX's own 0219 in place of the adapted one (it releases the exported frames too)
#   0209  AppKit: a layer-backed view's rendered IOSurface registered with the window server's GPU presenter instead of a
#         CPU read-back (SFFX_GPU_PRESENT=1, looked up once; without it AppKit never calls the presenter)
#   0209w WindowServer: the whole-window GPU presenter (sffx_gpu_present.h): the CPU backing store uploaded when changed,
#         registered layer surfaces drawn on the GPU into a dma-buf frame (zwp_linux_dmabuf_v1); only for a window that
#         has a registered layer
#   0206  AppKit: +frameRectForContentRect:styleMask: and +contentRectForFrameRect:styleMask: count the menu strip, as the
#         instance methods do (only applications that use the class conversions see it: Firefox; Terminal and Activity
#         Monitor send neither)
#   The five frameworks below are compiled with -O2 (upstream's recipes compile without -O: every
#   drawing, text and event path ran unoptimised); -fno-strict-aliasing for old code that casts.
#   0340-0347 (QTP, names macOS applications import that are not QuickTime Player's alone; first user: Apple's
#         QuickTime Player, docs/roadmap/issues/SF-AI-quicktime.md). 0340 AppKit: the enabled, hidden, title and tool
#         tip binding names, the text styles and +[NSFont preferredFontForTextStyle:options:] (sizes from Apple's
#         macOS text-style table), NSClickGestureRecognizer (configuration only, as the other recognisers); 0341 AppKit:
#         NSFileWrapper's URL interface over its path one, and a recycled child wrapper is no longer over-released;
#         0342 CoreGraphics: CGGetDisplaysWithPoint, CGGetDisplaysWithRect; 0343 QuartzCore: CATextLayer (CoreText,
#         wrapping, truncation, alignment); 0344 QuartzCore: CAKeyframeAnimation and its interpolation in the
#         renderer, and an animation the renderer cannot interpolate leaves the model value (it drew 0); 0345
#         QuartzCore: CAConstraint, CAConstraintLayoutManager, CALayer's layoutManager (autoresizing only without one).
#         0346 (CoreAudio, applied by ../m1-sound/sysaudio/build-sysaudio.nix) block-based property listeners; 0347
#         (libFoundation, applied by ../terminal-app/build-foundation.nix) more URL resource values; 0348 (libFoundation,
#         the same) a bundle without a path is nil; 0349 (libFoundation, the same) +[NSString pathWithComponents:].
#         The URL key names and NSFileCoordinator are in the framework wrappers (../terminal-app/compat).
#   0350  AppKit (QTP): a document application's launch as on macOS: one that keeps its documents in iCloud
#         shows the Open panel instead of an untitled document (NSShowAppCentricOpenPanelInsteadOfUntitledFile),
#         and files named at launch that the delegate does not take are opened by the document controller
#   0351  AppKit (QTP): document types named by uniform type identifier (LSItemContentTypes, conformance through
#         CoreServices' table); the document controller asks -typeForContentsOfURL:error: and makes documents with
#         -initWithContentsOfURL:ofType:error:, and has the block form of -openDocumentWithContentsOfURL:display:;
#         -_autosaveDirectoryURLCreateIfNecessary: (where autosaved untitled documents are kept)
#   0352  libFoundation (QTP, applied by ../terminal-app/build-foundation.nix): -[NSURL fileReferenceURL] answered by
#         the file's path URL, -filePathURL, -isFileReferenceURL
#   0354, 0355 libFoundation (QTP, applied by ../terminal-app/build-foundation.nix): to-many change notifications;
#         NSFileManager URL forms, -setByAddingObjectsFromSet:, security scope (none), resource setting (refused),
#         locale display names; 0359 libFoundation: -[NSError recoveryAttempter], -helpAnchor; 0361 libFoundation:
#         NSIntersectionRect of an unbounded rectangle and a finite one, as on macOS
#   0353  AppKit (QTP): names a document window is made with: NSWindow's layer-hosting request and title-bar
#         opacity (kept, answered, no effect here), -[NSDocument _windowTitleDisplayName], system-spacing anchors,
#         -[NSWindow isModalPanel], NSMenu's names (_setMenuName:, _menusWithName:), -[NSMenuItem
#         _matchesKeyEquivalent:modifierMask:], the light and medium system fonts, -[NSWindow _borderView] (its title bar
#         has no versions button here)
#   0356  AppKit (QTP): -[NSWindow titlebarHeight] (the menu strip's row here), symbol images by private name and at a
#         configuration (our few drawings), +[NSParagraphStyle defaultWritingDirectionForLanguage:],
#         -[NSMutableAttributedString setBaseWritingDirection:range:], NSView's layer coordinate conversions (identity)
#   0357  AppKit (QTP): -[NSApplication gestureEventMask] (kept; every gesture arrives), -[NSTextField
#         maximumNumberOfLines], accessibility value descriptions (kept), the diagonal resize cursors, the Open panel's
#         New Document button setting (no such button here), -[NSDocument _isDuplicate]/_originalDocumentURL (no Duplicate),
#         NSMenuItem's identifier (and from nibs), NSDocument's restorable-state methods (nothing is restored here) and
#         -unblockUserInteraction
#   0358  AppKit (QTP): -[NSWindowController setDocument:] brings the window's title up to date, as on macOS (a window
#         made in code kept an empty title); -[NSScreen devicePixelCounts]
#   0360  AppKit (QTP): a document window's title is the document's display name, as on macOS (the application's
#         name was appended: "movie.mov - QuickTime Player")
#   0362  AppKit (QTP; for every application, through the guarded install only): in full screen the menu strip
#         auto-hides as macOS's menu bar does - it lies over the content and slides in while the pointer is at the
#         top edge or over it; NSApplicationPresentationHideMenuBar hides it, options without a menu-bar bit keep it
#   0364  AppKit (QTP2; every application, through the guarded install only): the About panel as macOS's: its nib (this
#         framework's own, now installed with the resources) loaded when it is shown and let go when it closes
#         (-loadNib, -unloadNib:), the options kept and applied each time, the copyrightView and _optionsDictionary
#         instance variables (QuickTime Player replaces -showInfoPanel: and -windowWillClose: and reads them by offset)
#   0366  AppKit (QTP2; document applications, through the guarded install only): the Open Recent menus as macOS's
#         document controller keeps them: a menu named _NSRecentDocumentsMenu is emptied and filled by the shared
#         controller each time it shows (-[NSMenu update] -> -_depopulateOpenRecentMenu:, -_populateOpenRecentMenu:
#         includingIcons: from -recentDocumentURLs); -_installOpenRecentMenus at the end of launching; +[NSMenu
#         _menusWithName:]. QuickTime Player overrides the three (its menu showed only "Clear Menu"); (0365,
#         libFoundation: NSURL bookmarks, ../terminal-app/build-foundation.nix)
#   0367  AppKit (QTP2; every application, through the guarded install only): the methods AppKit adds to
#         NSMutableAttributedString are also answered by Foundation's bridged attributed strings (a mutable one is an
#         NSAttributedString object): -setBaseWritingDirection:range: on a string built with -appendAttributedString:
#         raised "unrecognized selector" (QuickTime Player's Open Recent titles)
#   0370  AppKit (CHONK1; every application, through the guarded install only): a maximum size of zero on an axis
#         does not constrain -setFrame:. AWT sets every new window maximum to 0x0 until it is shown, so the first
#         frame Java gave a window collapsed it to 0x0 (ChonkCraft: an empty window, content 0x-22)
#   0363  Onyx2D (QTP2; every application, through the guarded install only): an opaque image drawn on the device at
#         its own size (within two pixels) is copied a row at a time instead of resampled and blended pixel by pixel
#         (QuickTime Player's picture cost 150 ms a draw: two pictures a second); O2_NO_IMAGE_FAST_PATH=1 turns it off,
#         O2_IMAGE_TRACE=1 says why an image was resampled
#   0373  Onyx2D (CHONK2; every application, through the guarded install only): the same opaque image at another
#         scale along the axes (1/4 to 8: a picture made in points on a desk at 150 %) is resampled bilinearly through
#         a table of source columns and weights instead of pixel by pixel through the general path (ChonkCraft's
#         1280x778 frame cost 27 ms a draw: 34 frames a second); O2_NO_IMAGE_SCALE_FAST_PATH=1 turns it off
#   0374  Onyx2D (CHONK3; every application, through the guarded install only): that resampling is split into bands of
#         device rows drawn at once on up to four threads (ChonkCraft held the main thread ~12 ms a draw on one, after
#         the desk's frame callback: the frame missed its refresh); O2_IMAGE_SCALE_THREADS=1 draws on one
#   0009  Security: SecItemCopyMatching writes its result on every path and answers
#         errSecItemNotFound when nothing was found (Firefox crashed on the unwritten result)
#   (0007 and 0008 are libSystem's sandbox profile compiler: ./build-libsystem-cocoa.nix)
#
#   nix-build --extra-experimental-features 'nix-command flakes' patched.nix -A appkit --no-out-link
let
  a = import ./arm64.nix;
  inherit (a) pkgs pd;
  # one framework directory of the tree with the patches that touch it applied
  patchedDir = dir: patches: pkgs.runCommand "siliconforest-${builtins.baseNameOf dir}-src-cocoa" { } ''
    mkdir -p tree/${dir}
    cp -r ${a.src + "/${dir}"}/. tree/${dir}/
    chmod -R u+w tree
    cd tree
    for p in ${toString (map (p: "${p}") patches)}; do
      echo "applying $p"
      patch -p1 --no-backup-if-mismatch < $p
    done
    cp -r ${dir} $out
  '';
  appkitSrc = patchedDir "src/Frameworks/AppKit" [
    ./patches/0001-tip-appkit-font-weights-symbol-configuration.patch
    ./patches/0002-appkit-sharing-service-picker.patch
    ./patches/0005-appkit-server-decorations-and-scale.patch
    ./patches/0011-appkit-layout-api.patch
    ./patches/0012-appkit-controls-macos26.patch
    ./patches/0015-appkit-popup-view-array.patch
    ./patches/0016-appkit-event-queue-discard.patch
    ./patches/0017-appkit-popups.patch
    ./patches/0019-tip-appkit-stackview-accessibilityelement.patch
    ./patches/0020-appkit-macos26-additions.patch
    ./patches/0021-appkit-fixes-found-with-terminal.patch
    ./patches/0024-appkit-fonts-bindings-found-with-terminal.patch
    ./patches/0027-appkit-layout-once-per-resize.patch
    ./patches/0028-appkit-window-menu-strip.patch
    ./patches/0029-appkit-fixes-found-with-terminal-2.patch
    ./patches/0031-appkit-popup-button-content-bindings.patch
    ./patches/0032-appkit-measured-sizes-remembered.patch
    ./patches/0033-appkit-scroller-look-macos26.patch
    ./patches/0035-appkit-glyph-advances-font-directory-menu-archive.patch
    ./patches/0038-appkit-found-with-terminal-3.patch
    ./patches/0039-appkit-window-tabs.patch
    ./patches/0040-appkit-dirty-rects-as-drawn.patch
    ./patches/0041-appkit-windows-opaque-untitled-sheets.patch
    ./patches/0044-appkit-alerts-macos-layout.patch
    ./patches/0045-appkit-word-wrap-at-fragment-start.patch
    ./patches/0046-appkit-nib-floats-labels-menu-glyphs.patch
    ./patches/0047-appkit-bindings-write-back.patch
    ./patches/0048-appkit-find-bar.patch
    ./patches/0049-appkit-font-lookups-remembered.patch
    ./patches/0050-appkit-tab-view-macos26.patch
    ./patches/0051-appkit-draw-once.patch
    ./patches/0052-appkit-full-screen-key-equivalents.patch
    ./patches/0055-appkit-save-open-panels.patch
    ./patches/0056-appkit-print-to-pdf-help.patch
    ./patches/0057-appkit-rects-outside-display.patch
    ./patches/0059-appkit-found-walking-the-menus.patch
    ./patches/0100-appkit-activity-monitor-names.patch
    ./patches/0101-appkit-view-based-tables-hidden-columns.patch
    ./patches/0103-appkit-layer-backed-views-without-egl.patch
    ./patches/0104-appkit-found-with-activity-monitor.patch
    ./patches/0105-appkit-asset-catalog-colors-from-finch.patch
    ./patches/0106-appkit-nib-layout-standard-space-priorities.patch
    ./patches/0107-appkit-activity-monitor-look-and-cost.patch
    ./patches/0108-appkit-menu-item-getters-autoreleased.patch
    ./patches/0110-appkit-collection-view-from-finch.patch
    ./patches/0111-appkit-catalog-images-symbols-from-finch.patch
    ./patches/0112-appkit-solve-time-trace.patch
    ./patches/0113-appkit-toolbar-buttons-macos26.patch
    ./patches/0114-appkit-overlay-scrollers.patch
    ./patches/0115-appkit-cgevent-autoreleased.patch
    ./patches/0116-appkit-owner-findings-windows-cursor-colors.patch
    ./patches/0120-appkit-device-pixels-opaque-default-menu-tracking.patch
    ./patches/0123-appkit-menus-fast-crashes-layers-without-egl.patch
    ./patches/0125-appkit-menu-panel-seams-translucency-choice-split-view.patch
    ./patches/0127-appkit-float-value-abi-colour-well-click-opaque-menus.patch
    ./patches/0128-appkit-table-header-sort-indicator-slot.patch
    ./patches/0130-appkit-column-drag-scroll-copy-split-panes.patch
    ./patches/0131-appkit-typeset-cache-generation-kept.patch
    ./patches/0132-appkit-inspector-tab-content-window-fits-single-line-values.patch
    ./patches/0201-appkit-headless-run-loop.patch
    ./patches/0203-appkit-layer-context-window-scale.patch
    ./patches/0204-appkit-replace-hosted-layer-root.patch
    ./patches/0133-appkit-hosted-layers-cpu-class-named-nibs-arranged-subviews-names.patch
    ./patches/0136-appkit-wrapped-label-keeps-its-last-line.patch
    ./patches/0210-precise-scroll-deltas-and-gesture-phase.patch
    ./patches/0212-menu-appearance-and-popup-inheritance.patch
    ./patches/0214-pasteboard-item-provider-receives-destination-board.patch
    ./patches/0137-appkit-vlc-interface-modal-events-minimise-crash.patch
    ./patches/0139-appkit-pinch-magnify.patch
    ./patches/0140-appkit-layout-priorities-in-order.patch
    ./patches/0142-appkit-tracking-area-in-visible-rect.patch
    ./patches/0144-appkit-reopen-and-quit-from-the-desk.patch
    ./patches/0147-appkit-label-and-button-constructors.patch
    ./patches/0209-view-registers-gpu-layer-with-private-windowserver.patch
    ./patches/0206-window-class-content-geometry-counts-menu-strip.patch
    ./patches/0150-appkit-event-timestamps-since-startup.patch
    ./patches/0158-appkit-popup-layers-read-back-without-a-gpu-frame.patch
    ./patches/0159-appkit-scroll-momentum-phase.patch
    ./patches/0160a-appkit-layer-render-without-a-new-frame-presents-nothing.patch
    ./patches/0161-appkit-precise-scrolling-by-whole-points.patch
    ./patches/0162-appkit-child-windows-ordered-not-made-key.patch
    ./patches/0301-appkit-gpu-layer-registered-with-its-damage.patch
    ./patches/0163-appkit-panels-shown-as-popups-keep-their-window-key.patch
    ./patches/0304-appkit-layer-only-flush-says-backing-store-unchanged.patch
    ./patches/0164-appkit-desk-quit-asks-the-delegate-first.patch
    ./patches/0165-appkit-hidden-windows-flush-nothing-window-trace.patch
    ./patches/0166-appkit-layer-readback-trace.patch
    ./patches/0167-appkit-layer-tree-trace.patch
    ./patches/0168-appkit-clipboard-answers-from-what-was-offered.patch
    ./patches/0169-appkit-desk-quit-asks-the-delegate-once.patch
    ./patches/0170-appkit-subview-layers-follow-their-views.patch
    ./patches/0171-appkit-mouse-event-trace.patch
    ./patches/0174-appkit-pasteboard-trace.patch
    ./patches/0175-appkit-view-keeps-its-layer-context-clipboard-fallback.patch
    ./patches/0176-appkit-clipboard-offered-data-follows-writes.patch
    ./patches/0177-appkit-clipboard-write-not-replaced-before-its-offer.patch
    ./patches/0178a-appkit-gpu-layers-presented-from-the-render-thread.patch
    ./patches/0322-appkit-menu-item-parent-item.patch
    ./patches/0323-appkit-custom-backing-layer-follows-window-scale.patch
    ./patches/0324-appkit-window-keeps-the-size-the-desktop-allows.patch
    ./patches/0325-appkit-linked-animations-and-current-value.patch
    ./patches/0327-appkit-opengl-view-drawn-and-reshaped-on-the-main-thread.patch
    ./patches/0328-appkit-first-layer-frame-after-a-resize-draws-the-window-whole.patch
    ./patches/0340-appkit-binding-and-text-style-names.patch
    ./patches/0341-appkit-file-wrapper-url-interface.patch
    ./patches/0350-appkit-document-application-launch.patch
    ./patches/0351-appkit-document-types-by-identifier.patch
    ./patches/0353-appkit-document-window-names.patch
    ./patches/0356-appkit-player-view-names.patch
    ./patches/0357-appkit-movie-window-names.patch
    ./patches/0358-appkit-window-title-and-device-pixels.patch
    ./patches/0360-appkit-document-window-title-is-the-name.patch
    ./patches/0362-appkit-full-screen-menu-strip-auto-hides.patch
    ./patches/0364-appkit-about-panel-nib-loaded-when-shown.patch
    ./patches/0366-appkit-open-recent-menus-filled-when-shown.patch
    ./patches/0367-appkit-mutable-attributed-string-methods-on-bridged-strings.patch
    ./patches/0370-appkit-zero-maximum-size-is-no-maximum.patch
    ./patches/0379-appkit-auto-gpu-present-for-gpu-layers.patch
    ./patches/0381-appkit-chonkcraft-additive-symbols.patch
    ./patches/0386-appkit-nsopengl-gpu-present-and-window-backing-rect.patch
  ];
  windowserverPatches = [
    ./patches/0004-windowserver-server-decorations-and-scale.patch
    ./patches/0018-windowserver-popup-placement.patch
    ./patches/0022-windowserver-presented-frame-dump.patch
    ./patches/0030-windowserver-app-id-without-bundle-identifier.patch
    ./patches/0036-windowserver-present-on-release-tab-toplevel.patch
    ./patches/0043-windowserver-sheet-parent.patch
    ./patches/0058-windowserver-activation-configure-timing.patch
    ./patches/0117-windowserver-cursor-shown-when-the-pointer-moves.patch
    ./patches/0121-windowserver-opaque-region-blur-query-test-scale.patch
    ./patches/0124-windowserver-popup-role-ahead-idle-frames.patch
    ./patches/0126-windowserver-popup-configure-wait-timing.patch
    ./patches/0129-windowserver-frames-kept-by-default.patch
    ./patches/0210w-windowserver-finger-pixels-and-scroll-phase.patch
    ./patches/0139w-windowserver-pinch-gestures.patch
    ./patches/0141w-windowserver-cursor-shapes.patch
    ./patches/0143w-windowserver-new-surface-for-a-new-role-ends-with-compositor.patch
    ./patches/0145w-windowserver-same-cursor-image-not-sent-again.patch
    ./patches/0209w-windowserver-whole-window-gpu-presenter.patch
    ./patches/0148w-windowserver-display-clock-from-presentation-feedback.patch
    ./patches/0156w-windowserver-presents-paced-by-frame-callbacks.patch
    ./patches/0158w-windowserver-popups-present-shared-memory.patch
    ./patches/0159w-windowserver-trackpad-finger-frames-precise-with-momentum.patch
    ./patches/0302w-windowserver-damage-only-compose-and-commit.patch
    ./patches/0163w-windowserver-popup-keyboard-and-child-popups.patch
    ./patches/0305w-windowserver-backing-store-compared-only-after-drawing.patch
    ./patches/0166w-windowserver-momentum-capped-and-timed.patch
    ./patches/0173w-windowserver-pointer-enter-is-a-move.patch
    ./patches/0178w-windowserver-layers-presented-from-the-render-thread.patch
    ./patches/0333w-windowserver-changed-rows-found-in-one-vector-pass.patch
    ./patches/0375w-windowserver-paced-present-copies-the-backing-store-at-the-flush.patch
    ./patches/0376w-windowserver-pace-presents-default-on.patch
    ./patches/0377w-windowserver-gpu-frame-requests-gpu-storage.patch
    ./patches/0380w-windowserver-gpu-presenter-auto-and-perf-defaults.patch
    ./patches/0384w-windowserver-pointer-lock-and-relative-motion.patch
    ./patches/0387w-windowserver-gpu-layer-present-not-paced.patch
    ./patches/0388w-windowserver-gpu-commit-on-frame-callback.patch
    ./patches/0389w-windowserver-opaque-gl-layer-and-probe.patch
    ./patches/0390w-windowserver-commit-the-composed-gpu-frame.patch
    ./patches/0394w-windowserver-return-uncommitted-gpu-frame.patch
  ];
  windowserverSrc = patchedDir "src/Frameworks/WindowServer" windowserverPatches;
  # (IOSURF) VLC's private copy only: the system's patches and the opt-in cadence hold (SF_WS_CADENCE)
  windowserverCadenceSrc = patchedDir "src/Frameworks/WindowServer" (windowserverPatches ++ [
    ./patches/0334w-windowserver-steady-sources-committed-on-a-steady-cadence.patch
  ]);
  authenticationServicesSrc = patchedDir "src/Frameworks/AuthenticationServices" [
    ./patches/0003-authenticationservices-web-session-browser-side.patch
  ];
  hiServicesSrc = patchedDir "src/Frameworks/HIServices" [
    ./patches/0383-hiservices-printcore-duplex-stubs.patch
  ];
  onyx2dSrc = patchedDir "src/Frameworks/Onyx2D" [
    ./patches/0006-onyx2d-glyphs-at-device-scale.patch
    ./patches/0013-onyx2d-png-straight-alpha-byte-order.patch
    ./patches/0026-onyx2d-copy-bits.patch
    ./patches/0037-onyx2d-font-by-name-once.patch
    ./patches/0042-tip-onyx2d-icns-png-entries.patch
    ./patches/0054-onyx2d-rectangles-without-edges.patch
    ./patches/0119-onyx2d-shading-path-released.patch
    ./patches/0122-onyx2d-clip-edges-on-pixels.patch
    ./patches/0200-onyx2d-serialize-shared-freetype-raster.patch
    ./patches/0217-graphics-font-keeps-fontconfig-collection-face-index.patch
    ./patches/0146-onyx2d-glyph-cache-knows-a-reused-face.patch
    ./patches/0154-onyx2d-font-files-mapped-once.patch
    ./patches/0363-onyx2d-images-at-device-pixels-copied.patch
    ./patches/0373-onyx2d-images-at-other-scales-resampled-by-table.patch
    ./patches/0374-onyx2d-scaled-images-drawn-in-bands-on-four-threads.patch
  ];
  # upstream's framework recipes name no optimisation level: their compile lines get one here
  optimised = d: d.overrideAttrs (old: {
    buildPhase = builtins.replaceStrings [ "$cc $cflags -c" ] [ "$cc $cflags -O2 -fno-strict-aliasing -c" ] old.buildPhase;
  });
  onyx2d = optimised (pd."onyx2d-arm64".override { src = onyx2dSrc; });
  coretextSrc = patchedDir "src/Frameworks/CoreText" [
    ./patches/0023-coretext-fixed-pitch-families-private-draw.patch
    ./patches/0034-coretext-graphics-font-cache-font-directories.patch
    ./patches/0053-coretext-lines-and-fonts-remembered.patch
    ./patches/0215-coretext-copy-keeps-graphics-font-for-rendering-attributes.patch
    ./patches/0220-coretext-memory-font-descriptors-without-filesystem.patch
    ./patches/0368-coretext-run-delegates-bypass-line-cache.patch
  ];
  coretext = optimised (pd."coretext-arm64".override { src = coretextSrc; });
  coregraphicsSrc = patchedDir "src/Frameworks/CoreGraphics" [
    ./patches/0025-coregraphics-private-additions.patch
    ./patches/0102-coregraphics-activity-monitor-cgs.patch
    ./patches/0109-coregraphics-imageio-thumbnail-metadata.patch
    ./patches/0118-coregraphics-icc-and-indexed-color-spaces.patch
    ./patches/0135-coregraphics-display-fade-opengl-acceleration.patch
    ./patches/0342-coregraphics-displays-with-point-and-rect.patch
    ./patches/0382-coregraphics-display-config-and-event-stubs.patch
    ./patches/0385-coregraphics-pointer-lock-and-cursor-warp.patch
  ];
  coregraphics = optimised (pd."coregraphics-arm64".override { src = coregraphicsSrc; });
  # QuartzCore: upstream's recipe (not optimised, as installed; its library is the root's QuartzCore.pd, beside the
  # compatibility wrapper of ../terminal-app/compat)
  quartzcoreSrc = patchedDir "src/Frameworks/QuartzCore" [
    ./patches/0202-layer-context-backing-pixel-scale.patch
    ./patches/0207-layer-context-detaches-retained-tree.patch
    ./patches/0134-quartzcore-layer-display-opengl-layer.patch
    ./patches/0138-quartzcore-layer-autoresizing-visible-rect-display-on-resize.patch
    ./patches/0208-layer-context-exportable-gpu-frame.patch
    ./patches/0213-cache-gpu-frame-export-provider-lookups.patch
    ./patches/0216-opt-in-gpu-frame-reuse-until-tree-mutation.patch
    ./patches/0219q-layer-context-releases-exported-gpu-frames.patch
    ./patches/0153-quartzcore-layer-display-asks-a-view-that-updates-its-layer.patch
    ./patches/0157-quartzcore-layer-tree-changed-from-other-threads.patch
    ./patches/0160-quartzcore-unchanged-properties-and-commits-render-nothing.patch
    ./patches/0300-quartzcore-damage-only-frames.patch
    ./patches/0306-quartzcore-video-planes-uploaded-as-red-green.patch
    ./patches/0178-quartzcore-layer-tree-rendered-on-a-render-thread.patch
    ./patches/0320-quartzcore-opaque-opengl-layer-ignores-alpha.patch
    ./patches/0321-quartzcore-layer-context-reclaims-its-root.patch
    ./patches/0326-quartzcore-opengl-layer-current-before-lock-and-keeps-its-picture.patch
    ./patches/0329-quartzcore-opengl-layer-reads-back-from-its-own-context.patch
    ./patches/0331-quartzcore-opengl-layer-picture-as-a-gpu-surface.patch
    ./patches/0343-quartzcore-text-layer.patch
    ./patches/0344-quartzcore-keyframe-animation.patch
    ./patches/0345-quartzcore-constraint-layout-manager.patch
    ./patches/0369-quartzcore-layer-contents-types.patch
    ./patches/0378-quartzcore-gpu-storage-and-auto-gpu-perf.patch
  ];
  quartzcore = pd."quartzcore-msm-arm64".override { src = quartzcoreSrc; };
  wp = "${pd."wayland-protocols"}/share/wayland-protocols";
  # upstream's recipe names every protocol and object file; the three protocols the patch
  # uses are generated and linked the same way
  mkWindowserver = src: optimised ((pd."windowserver-arm64".override { inherit src; }).overrideAttrs (old: {
    buildPhase = builtins.replaceStrings
      [ "cc=\"" "rpc_wayland.o xdg-shell-protocol.o" ]
      [ ''
        for x in unstable/xdg-decoration/xdg-decoration-unstable-v1 staging/fractional-scale/fractional-scale-v1 stable/viewporter/viewporter staging/xdg-activation/xdg-activation-v1 unstable/pointer-gestures/pointer-gestures-unstable-v1 unstable/relative-pointer/relative-pointer-unstable-v1 unstable/pointer-constraints/pointer-constraints-unstable-v1 staging/cursor-shape/cursor-shape-v1 unstable/tablet/tablet-unstable-v2 stable/presentation-time/presentation-time; do
          n=$(basename $x)
          wayland-scanner client-header ${wp}/$x.xml $n-client-protocol.h
          wayland-scanner private-code ${wp}/$x.xml $n-protocol.c
        done
        cc="''
        "rpc_wayland.o xdg-decoration-unstable-v1-protocol.o fractional-scale-v1-protocol.o viewporter-protocol.o xdg-activation-v1-protocol.o pointer-gestures-unstable-v1-protocol.o relative-pointer-unstable-v1-protocol.o pointer-constraints-unstable-v1-protocol.o cursor-shape-v1-protocol.o tablet-unstable-v2-protocol.o presentation-time-protocol.o xdg-shell-protocol.o" ]
      (builtins.replaceStrings
        [ "$cc $cflags -c xdg-shell-protocol.c -o xdg-shell-protocol.o" ]
        [ ''
          $cc $cflags -c xdg-shell-protocol.c -o xdg-shell-protocol.o
              for n in xdg-decoration-unstable-v1 fractional-scale-v1 viewporter xdg-activation-v1 pointer-gestures-unstable-v1 relative-pointer-unstable-v1 pointer-constraints-unstable-v1 cursor-shape-v1 tablet-unstable-v2 presentation-time; do $cc $cflags -c $n-protocol.c -o $n-protocol.o; done'' ]
        old.buildPhase);
  }));
  windowserver = mkWindowserver windowserverSrc;
  windowserverCadence = mkWindowserver windowserverCadenceSrc;
  # (0110) against the libFoundation the root has (NSIndexPath is in it), not upstream's
  foundation = import ../terminal-app/build-foundation.nix;
  # (0364) the About panel's nib, this framework's own (Cocotron's NSSystemInfoPanel, MIT), installed with its resources:
  # upstream's recipe installs only the string tables, so every application's About panel failed to load
  appkit = (optimised (pd."appkit-msm-arm64".override { src = appkitSrc; inherit windowserver foundation; })).overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      for l in "$src"/NSSystemInfoPanel/*.lproj; do
        d="$out/System/Library/Frameworks/AppKit.framework/Versions/A/Resources/$(basename "$l")/NSSystemInfoPanel.nib"
        mkdir -p "$d"
        for f in keyedobjects.nib classes.nib info.nib; do
          if [ -e "$l/NSSystemInfoPanel.nib/$f" ]; then install -m644 "$l/NSSystemInfoPanel.nib/$f" "$d/"; fi
        done
      done
    '';
  });
  # Security for arm64 (upstream's build) with SecItemCopyMatching's result defined on every path
  security = pd."security-arm64".overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/0009-security-secitemcopymatching-defined-result.patch ];
  });
  appFrameworks = a.appFrameworks.override (old: {
    inherit appkit windowserver;
    srcs = old.srcs // { AuthenticationServices = authenticationServicesSrc; HIServices = hiServicesSrc; };
  });
in {
  inherit appkitSrc windowserverSrc authenticationServicesSrc onyx2dSrc windowserver appkit appFrameworks onyx2d security;
  inherit windowserverCadenceSrc windowserverCadence;
  inherit coretextSrc coretext coregraphicsSrc coregraphics quartzcoreSrc quartzcore;
}
