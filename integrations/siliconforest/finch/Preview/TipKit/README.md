# Scoped TipKit

P13 Preview PID 5015 exits -6 because dyld cannot load
`/System/Library/Frameworks/TipKit.framework/Versions/A/TipKit`. Receipt
`app-private/p13/v2-20261119T145115Z/launch-result.json`. The arm64e Preview
image has 42 strong imports from that path, ordinal 48. `build.py` installs
this provider under that name, compatibility 1.0.0, current 1.0.0.

The image keeps Finch's JSON datastore, `Tips.configure`, events, donations,
parameters, closure and compound rules, `MaxDisplayCount`,
`MaxDisplayDuration`, and invalidation. `status()` still requires a
configured store, then honors invalidation, the display cap and duration,
then `rules.allSatisfy`. `configure` is idempotent and does not throw
`tipsDatastoreAlreadyConfigured`. CloudKit is accepted and ignored.
`displayFrequency` is stored and is not read by `status()`.

`TipKit/probe.swift` is a separate module. It calls those bodies and one
event predicate rule: `Comparison` of `Value(1)` and `Value(2)` with
`.lessThan`, which `status()` treats as available, and the reversed pair,
which stays pending. It does not call `popoverTip` or a key-path
expression. `tipkit-test.swift` stays unrun: it needs `#Rule`, which is
not in the Finch sources, and view types this SwiftUI image does not export.

The predicate compile uses p9 `libswiftFoundation`
`aa7de512b8f76a22d9f9484455b5fccd35af9b99f5d0e9c943b54bfaefd530c0` and
swiftmodule `8ad0dda8f4e565a44588e308cdf9f84c4e9c0eb3f6586d0768b95fc6072647e8`.
The install name is still `/usr/lib/swift/libswiftFoundation.dylib`. A
runtime search path has to supply that p9 dylib and `libswiftos`. P13
`2de8e8fc00a7acd6b1633add2db6cf13c9a7f6892d0c34250665bdd69921f0d6` has no
`PredicateExpressions` and will not resolve these symbols. This build does
not replace the QTP or active Foundation images.

The Linux image is `6c9b27caeacb2d5d17464111c696ce61f67f5e17030841604d2c18de3a3b5d31`
(360115 bytes). The linked probe is
`90110ff25d96c6ea9842addbb2164a58dac903bd731df7bd061133e7d7f39e2e`
(125337 bytes). M1 receipt
`runs/preview/retained/tipkit/evidence/tipkit-20261119T165446Z.json`
(SHA-256 `3dd8d459a14795279e07ef7889f35ad3dc39180083bae63e042d5f74cb62028f`)
records PID 7552, exit 0, no signal. dyld loaded that TipKit image and p9
`libswiftFoundation` from the private scratch. Receipt
`tipkit-20261119T154704Z` (PID 5410) covers the earlier closure-rule image
`8f54374985fb961c2e060f444e74080928309deae9b27217916123cf9fc2510f` only.

## Export groups

Forty of the forty-two audited names are in the export trie. The five
predicate names match Preview's imports:

- `_$s10Foundation20PredicateExpressionsO10ComparisonVy_xq_G6TipKit05EventB10ExpressionA2gHRzAgHR_rlMc`
- `_$s10Foundation20PredicateExpressionsO5ValueVy_xG6TipKit05EventB10ExpressionAGMc`
- `_$s10Foundation20PredicateExpressionsO7KeyPathVy_xq_G6TipKit05EventB10ExpressionA2gHRzrlMc`
- `_$s10Foundation20PredicateExpressionsO8VariableVy_xG6TipKit05EventB10ExpressionAGMc`
- `_$s6TipKit4TipsO4RuleVyAeC5EventVy_xG_AA0E19PredicateExpression_pSb6Output10Foundation0fG0PRts_XPAK0F11ExpressionsO8VariableVy_AHGXEtcSeRzSERzs8SendableRzlufC`

`Equal` also conforms. That symbol is
`_$s10Foundation20PredicateExpressionsO5EqualVy_xq_G6TipKit05EventB10ExpressionA2gHRzAgHR_rlMc`.
It is not one of the forty-two. p9 has no `NotEqual`, so that Finch
conformance is not declared. `DonationFilter`, `DonatedWithin`, and the
parameter `Rule` initializer are not added. A thrown `PredicateError`,
including `undefinedVariable`, becomes false because the rule uses `try?`.
The probe does not evaluate a key path. p9 `_validateForPredicateUsage`
fatalErrors on a multi-component key path.

`SwiftUI.View.popoverTip(_:isPresented:attachmentAnchor:arrowEdge:action:)`
stays absent. P13 SwiftUI exports 384 names and has no `Binding`,
`PopoverAttachmentAnchor`, or `Edge`. This lane does not use the M6
SwiftUI runtime. The method and its opaque-result thunk:

- `_$s7SwiftUI4ViewP6TipKitE07popoverD0_11isPresented16attachmentAnchor9arrowEdge6actionQrAD0D0_pSg_AA7BindingVySbGSgAA017PopoverAttachmentJ0OAA0L0OSgyAD4TipsO6ActionVctF`
- `_$s7SwiftUI4ViewP6TipKitE07popoverD0_11isPresented16attachmentAnchor9arrowEdge6actionQrAD0D0_pSg_AA7BindingVySbGSgAA017PopoverAttachmentJ0OAA0L0OSgyAD4TipsO6ActionVctFQOMQ`

The closure `Rule` initializer remains
`_$s6TipKit4TipsO4RuleVyAESbyYbccfC`. It is not the predicate initializer.

## Unavailable besides those seven

`TipViews.swift` is not compiled. `TipGroup.currentTip` is compiled with the
real `@Observable` macro
(`swiftc -load-plugin-library` `libObservationMacros.so` from the Swift
6.3.3 host) and links
`/nix/store/jj285a5nvzzk36bxc6spdx67km16l7p7-siliconforest-preview-observation-arm64/usr/lib/swift/libswiftObservation.dylib`.
The headless client checks `firstAvailable` and `ordered` against live tip
status. `currentTipUpdates` is not compiled: Finch delivers that stream on
`OperationQueue.main`, and this Foundation has no `DispatchQueue`.
Preview's 42 TipKit imports do not name `TipGroup`.

Group containers throw `missingGroupContainerEntitlements` because this
Foundation has no `containerURL`. Notifications post on the calling thread
because the Darwin Dispatch overlay has no `DispatchQueue`. `@Parameter` and
`#Rule` are not in the Finch sources.

`popoverTip` still needs `Binding`, `PopoverAttachmentAnchor`, and `Edge`.
This seat does not replace the SwiftUI image.
