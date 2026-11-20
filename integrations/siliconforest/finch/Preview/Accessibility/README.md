# Accessibility chart values for SwiftUI

This scoped Accessibility.framework build uses Finch's open chart, axis,
series, point, and custom-content implementations from the repository's
pinned Finch revision. The build verifies the original source digest and
includes both Finch licenses. Its Clang module exposes the concrete types
used by the SwiftUI renderer.

The chart archive bridge encodes and reads a versioned dictionary of chart
titles, axes, series values, labels, and geometry. A malformed dictionary or
an unknown archive version fails the failable initializer. Attributed styling,
custom axis types, and value-description closures do not round-trip through
this dictionary format. The bridge supplies local chart data and has no
screen reader or live audio graph.

The M1 probe covers a numeric axis, a categorical axis, series points, chart
geometry, invalid input, and custom content. The Objective-C declarations
also typecheck with a separate Swift client.
