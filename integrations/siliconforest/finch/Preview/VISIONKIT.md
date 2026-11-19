# VisionKitCore unavailable-analysis candidate

This original MIT implementation exports Preview's three mandatory class names
and `vk_cgImageRemoveBackgroundWithDownsizing`. It does not provide OCR, form
detection, image segmentation or background removal. Analysis/removal callback
results are always nil with an explicit unsupported NSError. Nil callbacks
raise an exception carrying that error. No progress or successful output is
fabricated; constructing an analysis result also fails explicitly.

Interface evidence comes from the unchanged owner-provided Preview arm64e
slice. Its request constructor uses
`initWithCGImage:orientation:requestType:`; its analyzer sends
`processRequest:progressHandler:completionHandler:`. Retained block type names
identify the completion arguments as `(VKCImageAnalysis *, NSError *)` and
`(CGImageRef, NSError *)`. The C call supplies an image, two integral options
and the completion block. The caller ignores both operation return values.
Only interface names and observed calling behavior informed this source; no
Apple implementation or extracted assets are included. Progress callback
shape and option meanings are deliberately not invented. Request fields are
stored; its image is retained/released through open CoreGraphics. New `sf_`
getters are probe helpers, not claims about Apple's interface.

```sh
nix-build --extra-experimental-features 'nix-command flakes' --no-out-link \
  integrations/siliconforest/finch/Preview/visionkit-check.nix
```

The static check validates all class/metaclass exports and the C entry point,
install name and versions, signatures, and provider/probe direct bindings
against the open build providers. The thin arm64 probe exercises nil-image
request storage and explicit failures; it does not validate real-image retain
lifetime or the complete private ABI. After the coordinator's kernel guard
passed, its standalone M1 probe exited zero: one analysis error, one removal
error, zero progress, with unchanged provider/probe hashes. The next actual
Preview launch loaded it and stopped at PaperKit. No provider was staged or
executed during the kernel hold. Neither result is Preview UI acceptance.

## Swift provider audit

The actual live SwiftUI provider supplies 42 of Preview's 362 direct imports;
it is QTP's documented binding subset, not Finch's full OpenSwiftUI build.
AppIntents is absent (0 of 320). These are measured exports under the recorded
private search paths, with effective re-exports considered. Finch revision
`2d9b1bb1af57e14462e4621d194929188a8845b0` has substantive AppIntents source
and OpenSwiftUI adaptations, but no built full Finch artifacts were available
for a binary export comparison. Source presence is not export or ABI proof.

An actual Linux cross-compiler input audit of pinned Finch AppIntents fails at
`import CoreGraphics`. Independent module tests also fail for CoreSpotlight
and UniformTypeIdentifiers. The current Foundation module cannot typecheck a
reference to `LocalizedStringResource`; Finch supplies that API in its
Foundation localization source. Full Finch SwiftUI also needs its pinned
OpenSwiftUI/attribute-graph dependencies and supplemental Observation module.
These are concrete build prerequisites, not symbols to fill with successful
no-op implementations. No complete Finch framework was adopted here.
