# AppIntents AppKit entity identifiers

This scoped Swift bridge provides `NSView.appEntityIdentifier`, the one
symbol Preview imports from `_AppIntents_AppKit`. The storage comes from
Finch revision `2d9b1bb1af57e14462e4621d194929188a8845b0`
(`userland/_AppIntents_AppKit/_AppIntents_AppKit.swift`, MIT OR Apache-2.0).
The view owns the identifier via an Objective-C associated object. Assigning
`nil` removes it.

The arm64 build uses the native Swift compiler and public SDK, with the open
Finch AppIntents module first in the module and framework search paths.
Build that module from the sibling AppIntents port and its compatibility patch.
Use Swift 5 mode and library evolution, link against AppKit and the built open
AppIntents framework, and give the bridge the install name
`/System/Library/Frameworks/_AppIntents_AppKit.framework/Versions/A/_AppIntents_AppKit`.
Compile `Probe.swift` as a separate client of both frameworks.

On the M1 the probe loads the bridge and the tested open AppIntents framework.
It verifies initially absent values, independent storage on two NSViews,
replacement, and removal. The semantic scope is per-view metadata. System
entity routing, annotation rendering, and view-provider callbacks are separate
from this port.
