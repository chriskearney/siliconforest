# Scoped MapKit

P14 Preview stops because dyld cannot load
`/System/Library/Frameworks/_MapKit_SwiftUI.framework/Versions/A/_MapKit_SwiftUI`.
Receipt `app-private/p14/diagnostic-02/launch-result.json`. The unchanged
Preview image has 10 strong imports from that path, ordinal 51.

`MapKit.swift` declares those types against SwiftUI: `Map`, `Marker`,
`MapContentView`, `MapCameraBounds`, and `MapInteractionModes`. `Marker` is
`Marker<Label: View>` and its initializer is constrained to `Label == Text`.
`Map` stores `scope` as `Namespace.ID?` and conforms to `View` by returning
an `NSViewRepresentable`. `Geo.swift` parses the pinned Natural Earth
1:110m land GeoJSON and projects markers with Web Mercator. The view paints
water, land, and marker pixels with `NSView.draw(_:)`, `NSBezierPath`, and
`NSColor`.

`MapCameraBounds` distances are stored and not applied. This initializer has
no camera. Interaction-mode bits are pan `1<<0`, zoom `1<<1`, pitch `1<<2`,
and rotate `1<<3`. Gestures are not delivered. There are no live tiles.
The 1:110m coastline leaves New York in the water.

## Linux compile-001

`build.py` wrote `runs/preview/retained/mapkit/compile-001.log`. The P13
SwiftUI subset module built. The MapKit object did not. The subset has
`LocalizedStringKey`, `Text`, and `View`, and it has no `Namespace` or
`NSViewRepresentable`. The geo probe object also failed: the generated
raw string in `EmbeddedLand.swift` was indented less than its closing
delimiter. No arm64 image was emitted, and none of the 10 audited names
were present. Attempt B, `-F` on the M6 dylib directory, failed with
`no such module 'SwiftUI'` because that directory has no swiftmodule.

The Cocotron AppKit importer on this host renames `drawRect` to `draw(_:)`,
`currentContext()` to `current()`, and `colorWithCalibratedRed` to
`init(calibratedRed:green:blue:alpha:)`. `NSSize` members are `Double`
while `CGFloat` is a distinct type. This tree still spells the selectors
the headers declare.

## What this lane did not do

This Linux tree did not link a framework and did not relaunch Preview.
Runtime use of the M6 SwiftUI candidate waits until its closure passes.
ImageIO `_CGImageCreateByScaling` is the coordinator's fix.
