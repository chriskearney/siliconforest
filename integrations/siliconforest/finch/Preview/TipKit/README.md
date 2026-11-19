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

`TipKit/probe.swift` is a separate module. It calls those bodies. It does
not call predicate expressions or `popoverTip`. `tipkit-test.swift` stays
unrun: it needs `#Rule`, which is not in the Finch sources, and view types
this SwiftUI image does not export.

## Missing export groups

Thirty-five of the forty-two audited names are in the export trie. These
seven are absent. They are not given stand-in symbols.

Foundation predicate conformances. P13 `libswiftFoundation` exports no
`PredicateExpressions` symbols, and Preview binds these names two-level to
TipKit as conformances of Foundation types:

- `_$s10Foundation20PredicateExpressionsO10ComparisonVy_xq_G6TipKit05EventB10ExpressionA2gHRzAgHR_rlMc`
- `_$s10Foundation20PredicateExpressionsO5ValueVy_xG6TipKit05EventB10ExpressionAGMc`
- `_$s10Foundation20PredicateExpressionsO7KeyPathVy_xq_G6TipKit05EventB10ExpressionA2gHRzrlMc`
- `_$s10Foundation20PredicateExpressionsO8VariableVy_xG6TipKit05EventB10ExpressionAGMc`

Predicate `Rule` initializer. It names `EventPredicateExpression` and
`Foundation.PredicateExpressions.Variable`:

- `_$s6TipKit4TipsO4RuleVyAeC5EventVy_xG_AA0E19PredicateExpression_pSb6Output10Foundation0fG0PRts_XPAK0F11ExpressionsO8VariableVy_AHGXEtcSeRzSERzs8SendableRzlufC`

`SwiftUI.View.popoverTip(_:isPresented:attachmentAnchor:arrowEdge:action:)`.
P13 SwiftUI exports 384 names and has no `Binding`, `PopoverAttachmentAnchor`,
or `Edge`. The method and its opaque-result thunk:

- `_$s7SwiftUI4ViewP6TipKitE07popoverD0_11isPresented16attachmentAnchor9arrowEdge6actionQrAD0D0_pSg_AA7BindingVySbGSgAA017PopoverAttachmentJ0OAA0L0OSgyAD4TipsO6ActionVctF`
- `_$s7SwiftUI4ViewP6TipKitE07popoverD0_11isPresented16attachmentAnchor9arrowEdge6actionQrAD0D0_pSg_AA7BindingVySbGSgAA017PopoverAttachmentJ0OAA0L0OSgyAD4TipsO6ActionVctFQOMQ`

The closure `Rule` initializer in this source is an extra symbol,
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

P14 still has the Foundation `PredicateExpressions` gap and the SwiftUI
symbols Preview already binds that this 384-export SwiftUI does not provide.
This seat does not replace those images.
