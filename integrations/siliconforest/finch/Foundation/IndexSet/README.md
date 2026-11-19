# Swift IndexSet on retained NSIndexSet

The build uses the pinned Finch adaptation of the open Swift Darwin
IndexSet overlay and the installed PureDarwin NSIndexSet. The patch adapts
the imported method names and uses the existing range collection for
operations missing from NSIndexSet. The Objective-C source gives the
Swift overlay access to the existing sorted ranges. It uses the retained
NSIndexSet layout and must be linked with that Foundation build.

Run `prepare.sh` against Finch commit
`2d9b1bb1af57e14462e4621d194929188a8845b0`, add its output to the Swift
Foundation compilation, and link the compiled `IndexSetRanges.m`. The
native probe checks ranges, filtering, value-copy semantics, and the
Objective-C bridge.
