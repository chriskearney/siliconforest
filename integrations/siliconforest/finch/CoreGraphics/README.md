# Swift CoreGraphics geometry overlay

The private compiler module exposes the retained CoreGraphics rectangle
headers. The Swift library supplies the rectangle operations used by Finch
AppIntents. Intersection and union call the existing CoreGraphics functions.
The empty check includes zero-width and zero-height rectangles, and hashing
uses the same components as retained rectangle equality.

A consumer built against the packaged module ran on the M1 with the private
Swift library. Its zero, intersection, union, edge contact and hash checks
passed. Other CoreGraphics Swift APIs are outside this build's scope.

[CGRectStandardize/README.md](CGRectStandardize/README.md) adds the missing
C `_CGRectStandardize` export beside the active CoreGraphics under image.
The additions wrapper bytes stay as they are. The separate-client M1 probe
passes negative extents, null, empty, and the existing intersection, union,
emptiness, and equality calls. AppIntents is not launched from that probe.
