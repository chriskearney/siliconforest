# Preview mandatory-provider priorities

Evidence: owner-provided Preview 11.0/build 1113.5.3, original full-fat SHA256
`b0403a45bc454625aaa7a035f4ede247ef2c2bdd23b294e3dfa319800df1ebcd`;
arm64e load/import inventory, p0's actual dyld log, and a subsequent read-only
M1 path/export audit using p0's framework/library search directories. Private evidence lives outside this directory under
`runs/preview/app-private/evidence/`. No app code or extracted assets are here.

Actual bounded M1 launches P1–P4 passed the tested private Recap,
VisionKitCore and PaperKit providers and then the ModelIO load identity carrier
(zero implemented APIs). P4 stops at AnnotationKit, before UI. The table keeps
the original inventory order; it is not a UI-support or full dependency claim.
Later providers are selected from the actual next dyld/runtime stop.

| Order | Mandatory absent provider | Direct imports | Required next work |
|---|---|---:|---|
| 2 | RecapPerformanceTesting | 2 | Local `recap.nix` candidate for the exact runner/activation classes; recording explicitly unsupported. |
| 3 | VisionKitCore | 4 | `VKCImageAnalysis`, `VKCImageAnalyzer`, `VKCImageAnalyzerRequest`, `vk_cgImageRemoveBackgroundWithDownsizing`. Establish method/callback signatures before a provider; return unsupported analysis/removal, never unchanged output presented as successful removal. Finch's Vision framework is a different interface. |
| 8 | PaperKit | 3 Swift | `PaperViewController` type metadata/accessor and `display(_:readOnly:)` dispatch entry. Requires compatible Swift class metadata and view-controller behavior; a symbol-only shim cannot provide this ABI. |
| 9 | MediaAccessibility | 2 | `MAImageCaptioningCopyCaptionWithSource`, `MAImageCaptioningSetCaptionIntoMetadata`. Finch has open MediaAccessibility source, but does not define these two names; establish signatures and metadata/error semantics before porting. |
| 11 | Synapse | 3 | `SYDocumentAttributes`, `SYDocumentWorkflowsClient`, `SYFormFillingDocumentAttributes`. Separate real attribute storage from unavailable workflow service; establish selectors and failure callbacks. |
| 13 | ModelIO | 0 | Still a mandatory library load, despite no direct import; assess required umbrella/dependency behavior rather than calling zero imports optional. |
| 15 | AnnotationKit | 20 | Ten annotation/controller classes plus class metadata; document/UI integration is substantive. Coordinate view/model behavior with PDFKit ownership. |
| 21–30 | ImageCaptureCore, CorePDF, MetalKit, Hydra, SceneKit, FinderKit | 42 total | Respectively 3/17/2/4/14/2 imports. Finch supplies open ImageCaptureCore and MetalKit sources; audit actual imported interfaces before porting. CorePDF includes layout/selection operations to coordinate with CGPDF/PDFKit. |
| 35 | AppIntents | 320 Swift | Modern Swift ABI and protocol/type metadata work; Finch has open source, but its actual export coverage must be measured. |
| 43 | PDFKit | 46 | Coordinator owns the private model/view provider and fixtures. |
| 48–52 | TipKit and Swift integration frameworks, SoftLinking | 55 total | 42/1/1/10/1 imports for TipKit, _AppIntents_AppKit, _LocationEssentials, _MapKit_SwiftUI, SoftLinking. Distinguish unavailable features from required metadata/ABI. |

The corrected read-only audit resolves all 20 direct Recap imports against
the actual private Foundation and installed libobjc/libSystem providers.
It finds 23 of Preview's 61 mandatory main load paths absent before adding
this candidate: 20 frameworks and three Swift libraries. In particular,
libswiftCore, CoreFoundation, Dispatch, ObjectiveC and Concurrency are present
under the installed `/usr/lib/swift`; Observation, UniformTypeIdentifiers and
StringProcessing remain absent from the effective search paths.

The original live scanner treated the prefix as a filesystem overlay. Its
`usr/lib/swift` directory symlink masked installed Swift libraries that dyld
can fall back to. The new audit searches private directories, then the actual
installed filesystem; it does not mount the prefix over `/`. The original
missing-symbol totals for existing framework wrappers are still not validated
gaps. SwiftUI is present and its exact effective export coverage needs further
audit. Provider existence alone does not prove symbol or ABI compatibility.

The coordinator's kernel effective-protection COW fix passed its original
arm64e integrity probe. Subsequent bounded Preview launches retained all 174
bundle file hashes, with repeated original executable/slice hashes and off-box
byte comparisons. Kernel work and general PDF integration remain coordinator
owned. Framework candidates are staged only in owned private prefixes after
standalone verification; never overwrite QTP's runtime or install globally.

[ANNOTATIONKIT.md](ANNOTATIONKIT.md) describes the original reader model,
overlay and explicit unsupported operations. Runtime probe/app receipts remain
private; a static export check alone does not establish app UI support.
