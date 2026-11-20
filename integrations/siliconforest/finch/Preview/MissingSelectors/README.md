# Missing selectors for Preview

AppKit, Quartz, and CoreImage selectors that Preview's SwiftUI import
needs and the reexported frameworks do not provide.

`appkit_missing.m`, `quartz_missing.m`, and `coreimage_missing.m` are the
implementations. `sf_min.h` is the minimal AppKit surface they compile
against. `AppKitOverlay.h` and `AppKitOverlay.swift` are the Swift entry
points: `NSApplicationMain`, section-header menu items, and rect fill.
`probe.c` checks the symbols on the M1 and does not start NSApplication.

The overnight build script hardcodes nix store paths and is not included.
Framework bases, objects, and dylibs are not included.
