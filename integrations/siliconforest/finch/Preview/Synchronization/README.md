# Swift Synchronization for Preview

This package builds Synchronization from the pinned Swift 6.3.3 release
and links it to the SiliconForest Swift runtime. It generates the
upstream atomic integer and storage specializations at build time.
The Darwin mutex implementation imports the existing unfair-lock
declarations through the packaged Clang module.

Add the output's `usr/lib/swift` and `include` directories to Swift's
import search path. Link the Swift library from `usr/lib/swift`.

The native probe exercises both integer atomic operations used by
OpenSwiftUI, lock state updates, and object identity through a lazy
atomic reference.
