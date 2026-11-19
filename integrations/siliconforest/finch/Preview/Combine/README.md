# Combine for Preview

This arm64 framework builds OpenCombine 0.14.0 with the pinned Finch Combine
adaptation and the SiliconForest Swift 6.3.3 runtime. It includes the
Finch publisher operators and the published-value inspection used by
OpenSwiftUI. The library, Swift module, and the helper headers required at
compile time are packaged together.

Use the output's `System/Library/Frameworks` as a framework search path and
`include` as a Swift import search path. The stock Swift runtime and its
Concurrency overlay supply the runtime dependencies. Foundation's Combine
conformances and its Dispatch, RunLoop, and publisher integrations belong
to the respective overlays.

The `combine-probe` verifies subject delivery, filtering, mapping,
completion, cancellation, and current-value delivery. The source and
adapter licenses are included in `share/licenses`.
