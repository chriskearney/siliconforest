# SF-AB: Finch non-GUI frameworks

Finch source pin: `2d9b1bb1af57e14462e4621d194929188a8845b0`, MIT OR Apache-2.0
(the Finch project, github.com/calebtrueman/finch; these frameworks are Finch's work,
adopted with its notices: `NOTICE`, `LICENSES/third-party/`).
Recipes and patches: `integrations/puredarwin/finch/`. Candidate tests execute on the real
M1 through CLI SSH, under `/private/var/db/sffinch/`; identical Linux-built
reference programs run on the authorized M5. TERM5 owns screen/input checks.
The owner authorized reviewed media-framework replacements on 15 November, with
cold hashes and adjacent `.pre-finch` originals. Security/corecrypto stay isolated.
A build or symbol inventory is not a runtime pass. Latest installed-media evidence
and remaining limits are recorded below; earlier table entries retain their scope.

| Framework | Finch files taken | What we changed | Existing SiliconForest library and reconciliation | Test result on the M1 | Not done |
|---|---|---|---|---|---|
| Security | `userland/Security/{SecObjects,SecKeychain,SecKeychainCrypto,SecTrustSettings,SecRevocation}.c`, their internal headers; `SecAccess.c`, `gen-constants.py`; `userland/certificates/ca-bundle.h` (through pinned source recipe) | PureDarwin cross build, local keychain backend, exclude Network declarations from the core slice; extra declarations from published open-source headers | Installed PureDarwin Security has 3,479 exports. Finch's export whitelist has 588 entries including wildcard patterns; it is not a count of actual exports. Merge candidate re-exports the retained PureDarwin image as `Security.pd`; no disk replacement. Core object types must be exercised before broad use of mixed APIs. | PASS core (RSA/EC/tamper/trust/authorization/invalid item query); PASS storage (create/update/reopen, corrupt files, symlinks, ownership). Prior encryption missing-selector FAIL preserved. After COCOA3 installed its Foundation fix, all three original programs PASS: core0.49s/storage15s/encryption21s, including fresh-process/concurrent writes/tamper/plaintext migration. | Full conformance, service-backed keychain, SecureTransport/Network, authorization changes, system installation |
| corecrypto | `userland/corecrypto/abi/*.[ch]`, `digest.c`, `include/`, `exports.txt`, `tools/seal-corecrypto.py` (through pinned source recipe) | Cross build arm64; integrity parser accepts arm64 as well as arm64e; exact OpenSSL 3.5.9 backend | No separate library at `/usr/lib/system/libcorecrypto.dylib` on M1. PureDarwin embeds its corecrypto in libSystem: leave it intact; candidate loads separately. | PASS: 40,990 digest comparisons/0 failures against installed CommonCrypto; OpenSSL backend 26 checks; keychain crypto helper (M1 CLI). Shared-library SHA256/HMAC/AES128/192/256/RNG vectors and entropy failure-path checks PASS. Private ABI comparisons against PD Security FAIL (digest/RNG differences and missing functions; GCM test SIGSEGV). | Private ABI compatibility is absent: do not pass PD private contexts into Finch or replace PD libSystem. CommonCrypto runtime checks and installation pending. |
| CommonCrypto | `userland/corecrypto/compat/`, comparison tests, build method; published CommonCrypto-600035 source fetched by hash | Separate dispatch_once state; use public dyld SDK version query; cross build | Existing CommonCrypto stays inside libSystem; staged standalone library uses Finch corecrypto | FAIL: differential suite SIGBUS; keys suite missing reference CCDHCreate | Diagnose standalone candidate; no installation or replacement |
| Accounts | `userland/Accounts/*.m` whole | Source-derived declarations, own block types and enums; Linux cross build | Absent on M1; new path only; current-root gap scan has no missing import | PASS staged and installed without DYLD overrides: value model/access refusal; Finch accounts-test exits 0; reference BLOCKED because the original test saves/removes accounts and requests access. Installed at new paths with hashes. | No account service (Finch returns empty account list / access errors) |
| LocalAuthentication | `userland/LocalAuthentication/*.m` whole | Source-derived declarations and own type definitions; Linux cross build | Absent on M1; new path only; current-root gap scan has no missing import | PASS staged and installed without DYLD overrides: policy errors, property round-trip, reuse-duration bound. Installed at new paths with hashes. | No biometry or authentication prompt (Finch returns explicit errors) |
| CoreBluetooth | `userland/CoreBluetooth/{CBUUID,CBValues,CBManagers}.m`, `CBInternal.h` whole | Own declarations and public enum values; Linux MRC build | Absent on M1; clean import scan, installed only at new framework path | Value test exits 0; unsupported managers/callbacks match Finch `.expected`; same after install without DYLD overrides | No Bluetooth transport; same-binary native value output MATCH |
| CoreWLAN | `userland/CoreWLAN/*.m` whole | Own declarations; Linux ARC build | Absent on M1; clean import scan; installed only at new framework path | PASS CLI: empty client, SSID value/string/copy, configuration defaults; same without DYLD overrides | Does not expose SiliconForest's Wi-Fi driver; archive decoding not exercised |
| CryptoTokenKit | `userland/CryptoTokenKit/*.m` whole | Own declarations and enum values; links retained PD Security | Absent on M1; clean import scan; installed only at new framework path | TLV/PIN value test exits 0; no-reader/watchers match Finch `.expected`; same after install without DYLD overrides | No smart-card driver; certificate constructor not exercised; same-binary native value output MATCH |
| CoreLocation | `userland/CoreLocation/*.m` whole | Own coordinate/value/delegate declarations; Linux ARC build | Absent on M1; clean import scan; installed only at new framework path | PASS staged and installed: coordinates, invalid coordinate, WGS84 equatorial distance within 1 mm, values, disabled service | No positioning/geocoding service; archive/delegate paths untested |
| StoreKit | Whole `userland/StoreKit/*.m` | Own declarations; link against COCOA3's rehearsed Foundation decimal/weak collection update | Absent on M1; clean imports,60 exports/version379/compat1; installed only new path with hash ledger | PASS staged and installed without DYLD overrides: values/payment copy,weak observer lifetime,offline product-request callback,purchase refusal,finish/removal,restore refusal | No App Store/payment service/review UI; candidate assertion probe only,not a native service comparison |
| UserNotifications | `userland/UserNotifications/*.m` whole | Own declarations, CF URL key alias in place of wrapper-only Foundation constant | Absent on M1; clean import scan; installed only at new framework path | PASS staged and installed: content copy, real interval timer, delivered list and removal; volatile test permission setting, no defaults file changed | No banners; calendar trigger depends on Foundation's untested date matching method |
| OpenDirectory | `userland/OpenDirectory/*.[cm]`, `account-tools/{account_store,password_hash}.c` whole | Own declarations; contain account library inside framework; accept real Contains enum value in validation | Absent on M1; nested CFOpenDirectory and support library have clean imports; installed only at new outer framework path | PASS staged and installed: ObjC current-user/query; CF object type IDs, UID values, invalid-node error, Contains query. Same-binary native ObjC query output MATCH; public library version1 metadata correction staged | Account mutation/password paths untested; non-root account-update helper not installed; installed initial version0 metadata unchanged pending coordinator integration |
| Contacts | `userland/Contacts/*.m`, `Contacts_Finch.h`, `CNStrings.inc` whole | Own declarations, generated getters/history events, little-endian history token helpers | Absent on M1; not installed; current ImageIO/CoreGraphics lack four thumbnail exports | All sources compile; LINK FAIL: thumbnail creation function and three option constants | ImageIO request filed; model/store/vCard tests not run; modern Foundation selectors need runtime checks |
| MediaAccessibility | `userland/MediaAccessibility/MediaAccessibility.m` whole | Own C signatures/enums and ImageIO metadata declarations; Linux/Nix CoreText/CG link | Absent on M1; not installed | Builds against real Cocoa ImageIO metadata provider; same Linux-built M5 probe passes default types/ranges and own-PNG caption write/read | M1 defaults/types/ranges pass; caption write/read FAIL (Cocoa lacks XMP writing). Temporary readback patch now refuses without changing the PNG; negative M1 preservation test PASS. No install or preference mutation |
| Intents | Whole handwritten `Intents.m`, original generator with own limited model catalogue | Generator accepts our headers and excludes Foundation class generation; own fields and typed variadic localization methods; link new Foundation | Absent; builds and clean imports,72 exports; staged only | Original value/archive test SIGABRT on NSUserActivity targetContentIdentifier; isolated original store test SIGABRT on NSDateInterval encodeWithCoder:. Earlier value/copy/archive cases complete before failure | Exact Foundation follow-up requests filed; no install,full SDK catalogue or passing conformance claim |
| libcompression | `userland/libcompression/compression.c`, exports and original comparison test; exact pinned LZFSE/LZ4/Brotli | Linux/Nix build against PD open header; statically linked PD liblzma 5.8.3/zlib; preserve codec licenses | Repository implementation is zlib-only; live M1 path and libSystem exports are absent. Staged only per coordinator instruction; integration request filed | PASS on M1: six codecs, buffer and chunked stream APIs, empty/text/1 MiB pattern/3 MiB noise/5 MiB repetitive data; clean imports. M5 cross-decoding against Apple libcompression PASS with the Linux-built test | No install/swap; integration remains with Claude |
| SecurityFoundation / SecurityInterface | Whole Finch `SecurityFoundation.m`, `SecurityInterface.m` and constants | Own declarations, open PD/AppKit and published OSS AuthorizationPlugin headers | Installed SecurityFoundation exports a version constant; retained. SecurityInterface absent. Finch SF links only with staged Security; no core changes | SecurityFoundation BUILDS; SI sources compile, LINK FAIL against base AppKit/Foundation on NSTableCellView/NSCache | Cocoa patch supplies table-cell class on M1; NSCache and two retained-Security exports remain missing. No GUI tests or installs |
| CloudKit | Six Objective-C `userland/CloudKit/*.m` files and property generator | Own method/field declarations, generator input; retain/copy/weak storage; local ASCII validation | Absent on M1; clean imports; installed only new framework path | PASS staged and installed: unavailable-service suite matches Finch expected output; value/model/archive/share/operation/weak-delegate tests exit 0. Staged native isLongLived getter correction and initial-selector alias pass independent assertions; same-binary comparison DIFF only Foundation array quoting | Initial installed getter declaration unchanged pending coordinator integration; Swift/full property catalogue absent; notification reason remains Finch default; no cloud service |
| CFNetwork | All ten `userland/CFNetwork/*.c` files and shared internal header | Source-derived declarations, PD CFRuntime layout, HTTP scheduling adapter; require actual run-loop completion in comparison test | Framework absent on M1; PD source has proxy API only. Whole candidate imports resolve against retained root; installed only at new path | PASS staged and installed: incremental HTTP parse/copy, Basic auth, TXT/FTP assertions; loopback GET/redirect/chunked/POST/HEAD/socket/refused connections; 11 run-loop body bytes + end event. Original suite exits 0; version3860.255.112/compat1 metadata correction staged, installed initial version0 untouched | Raw Mac comparison DIFF: version string, localhost address ordering, unsupported reachability. HTTP/socket/parser outputs otherwise match in this test; Internet TLS and service registration untested |
| SystemConfiguration / Network | Network12 Swift files + C facade audited;Foundation prerequisite reproducer only | Linux/Nix Swift6.3.3 cross sysroot using PD OSS declarations;actual type-check failure preserved | SystemConfiguration retained;Network canonical path absent;no Network built or staged | Foundation imports,but Data/URL/UUID/NSLock conveniences needed by Finch fail to type-check | Foundation owner dependency request;then Security protocol helpers,whole Network build,loopback/reference tests |
| ColorSync | All four `userland/ColorSync/ColorSync*.c` files and exact skcms module at Finch's Skia m155 pin | Own declarations, PD CFRuntime layout, Linux/Nix C++ backend build; licenses retained | Thin 11-export wrapper replaced with reviewed 293-export provider; all old names retained, cold hash and .pre-finch backup recorded. Old wrapper name-string objects must not enter ICC APIs | Installed CLI regressions PASS including compat18/18; 152 profile/transform/tag/MD5 result lines MATCH identical Linux-built M5 client. Local ICC checksum uses existing private MIT MD5 after public CC_MD5 regression | Public CC_MD5 failure separately filed to PERF; device preferences, external CMM plugins and profile-file install untested; Finch CMM limits remain |
| ImageIO | None yet | None | PureDarwin CGImageSource implementation retained | Not run | Reconcile with graphics owner before any whole ImageIO port |
| CoreImage CPU | All7 CoreImage implementation/constant/filter-table files;original comparison program | Own30-class/119 typed-protocol declarations;real retained color-provider adapters;validated direct float/half bitmap recipes;software-rendering comparison | Canonical path absent,but QuartzCore.pd has5 static class collisions+4 generated CI filter names;owner reconciliation requested,no install | Private corrected dependencies: original raw suite, CPU probe and semantic extent probe MATCH same-byte M5;86/86 pixels and6extents agree | Gray conversion, PNG premultiplication and finite geometry dependency bugs fixed privately; TERM must adopt canonical Onyx/CG patches. GPU/Metal/kernel language/CV interop/profile/RAW/detector paths unverified |
| PDFKit non-GUI | PDFKit.m ten document/page/text/model classes prepared;PDFView and print method excluded | Own declarations/numeric facts;actual Linux/Nix build failure and CGPDF export audit;original one-page fixture/public CLI probe | Canonical path absent;retained CoreGraphics/Onyx expose11/56 CGPDF calls needed;45 missing;no candidate built/staged | M1 not run;Linux-built probe native M5 passes3 lines:page/version/metadata/text/find/selection. First native fixture clipped text;smaller original text fixture corrected | Graphics-owner public CGPDF scanner/object/string/permission/outline/context dependency request;then framework build,M1 execution and comparisons |
| Accelerate | Whole vDSP/vMisc/BLAS/LAPACK/Quadrature/LinearAlgebra/SparseBLAS/Sparse groups, all18 vImage C sources, BLAS ABI generator and original tests | Own declarations and Sparse overload glue; compiler-rt complex helpers; saturating int16 conversion; exact-value sinpi reduction; observed Quadrature workspace rules; NSObject LA lifetime adapter | Previously absent canonical umbrella now INSTALLED: all nine groups, 3,478 effective exports. Cocoa subset retained separately; final recipe rebuild reproduces all 40 installed files | Independent vectors/BLAS ABIs/LAPACK LU-inverse and sparse direct/iterative/lifecycle assertions PASS. Same-byte native comparisons MATCH vDSP300/vMisc207/BLAS614/SparseBLAS348/Quadrature40 lines. LA247 differs only NSObject superclass; Sparse62 differs on FGMRES diagonal-preconditioner acceptance | vImage 1,158/1,159 lines match; Display P3 coarse80/82 DIFF retained. Installed Root/VT/HAL/desktop/app-open/compat18 checks PASS. Full catalogue and general numerical equivalence unclaimed |
| CoreMedia | All15 `userland/CoreMedia/*.[cm]` implementation files and internal headers | Own declarations,PD CFRuntime,correct28-byte/align4 custom-block callback ABI; grow comparison description buffers | Repository thin75-export implementation; live canonical path absent. Candidate2609 retains75/75. INSTALLED at previously absent canonical path; cold hashes before load | Original comparison exits0 but DIFF CF descriptions; independent time/block/sample/NV12 ownership probe MATCH same Linux-built M5 binary | Installed root-provider/VT600hardware/HAL/app-open/compat18 checks PASS;callback clients must rebuild;general ABI conformance unclaimed |
| CoreVideo | All10 `userland/CoreVideo/*.[cm]` plus independent host-clock portion in reconciliation variant | Own declarations,PD CFRuntime,optional real ICC/709 provider resolution; separate exact-PD-display-link variant | Merged414 now INSTALLED with .pre-finch; retains97/97 and omits8 Finch-only DL APIs. Whole414 retains89/97 and is ineligible | Whole and merged complete CPU tests on M1; independent probe MATCH M5. Whole comparison DIFF descriptions,IOSurface allocation,3 missing color-space providers | Installed CLI: Root selection,VT600hardwareframes,WAV/AAC HAL,desktopprocesses,compat18/18 PASS;fresh open-aTerminal/AM+processes PASS;TERM5panel checks pending;GL/Metal compatibility not inferred |
| AudioToolbox | Whole5 file/format/converter/ExtAudioFile C implementations; owned FFmpeg bridge and retained-PD queue adapter | Original PCM slice retained; extended read-only M4A/MP3 demux + AAC/MP3/ALAC via Linux/Nix LGPL FFmpeg8.1.2, priming/valid length/seek; private codec exports hidden | INSTALLED reviewed variant has 135 effective exports, retaining all 84 old names (six System Sound wrappers +78 PD). Queue objects/operations stay wholly in exact retained PD image beside it | Final audio-codecs-v7 all9 M1 exits0. Original3,WAV/ALAC decode+seek MATCH identical-byte M5; AAC/MP3 numerical DIFF. WAV/AAC afplay each queued/completed12000 HAL frames,12callbacks,error0 | Installed WAV/AAC HAL, System Sound completion, Root/VT/desktop/app-open/compat18 checks PASS. No acoustic claim; compressed encoding/CAF/multichannel/malformed-input breadth unverified; buffered256MiB/1Mpacket bounds |
| AVFAudio | Original6 value/file/converter files plus whole AVAudioEngine.m offline graph/player/mixer/source/sink implementation;19 public classes | Own declarations; compressed input-block bridge/cookies/range checks; reject upstream silent realtime dropping with NoConnection | Previously absent canonical path now INSTALLED with 334 exports against installed codec/retained-PD family. Earlier stage variants kept separately | Original4 tests remain as prior results. Extended avaudio-engine-v3 all8 M1 exits0; original offline graph,WAV/ALAC file MATCH same-byte M5. AAC/MP3 numerical DIFF; native raw-ALAC case FAIL retained despite M1 completion | Installed file/converter/offline engine and full regressions PASS; first fixture-invocation failure rolled back and corrected with unchanged bytes. Realtime variant now INSTALLED,334/334 retained: AVPlayerNode file→retained AudioQueue/HAL48kHz,3lifetimes,error0; offline hash/native graph MATCH. Concurrent graph/device changes and sample-accurate pause unqualified; raw-ALAC/recorder/session/voice/MIDI/spatial limits remain |
| AVFoundation asset core | Whole AVFMovie,AVAsset,AVAssetReader,AVAssetWriter,AVMetadataItem,AVMetadataTables,AVFConstants,AVFTypes,AVTime,AVTimedMetadataGroup,AVMediaSelection,AVSampleCursor,AVAssetWriterInputGroup files | Own declarations;exclude video-composition reader class;retained locale/scanner/file adapters;private CF ISO8601 date helper;AVFAudio slice re-export | INSTALLED 2,482-export asset/no-device-capture variant at previously absent canonical path, with retained UTType dependency. Reader maps supported full-track codec-delay edit to asset time | M1 both programs exit0 and complete stdout MATCH identical Linux-built M5 programs;both open syntheticMP4/MOV,all20 video cursor entries matchLinuxffprobe;10H264 samples/2134bytes survive compressed mux round-trip | Installed Root/VT/HAL/desktop/app-open/compat18 PASS and 900 native movie PTS/hashes PASS. Arbitrary edit lists, general mux/codec coverage and AVPlayer unimplemented; finite own movie app uses its own CPU frame-layer path |
| Canonical Metal (Darling, not Finch) | Reviewed darling-metal whole, Indium/Iridium/mslc support | MPL-2.0 policy patch: real devices only when SF_METAL_ENABLE_REAL_DEVICE=1; support libraries stay inside framework | INSTALLED 185 exports, retains185/185 Darling and2/2 previous canonical exports; cold hashes/.pre-finch | Default/invalid-opt-in probes and no-DYLD Homebrew ffmpeg H264/HEVC HW/SW bit-exact, desktop/apps/HAL/AVD/compat18 PASS | Known real-device kernel exit hang remains; no new real-device or window-presentation claim |
| Retained VideoToolbox integration | No Finch decoder; existing `m1-avd` sources rebuilt by owned override recipe | Compile decoder+client against packed CoreMedia ABI,link staged pair; inventory exact10CM/27CV imports | Retained AVD+FFmpeg implementation now INSTALLED at previously absent canonical path, 172 exports (83 prior retained). All10 CM/27 CV imports resolved; retained PD audio has no CM/CV imports | Software decode10/10 samples/pictures,errors0;10 NV12 hashes+PTS/dimensions MATCH native M5 and hashes MATCH Linux ffmpeg | Hardware now PASS:600 H264/HEVC pictures,hardware1/errors0,PTS/pixels matchSW/Linux/M5;canonical Root VT installed;600hardware/HAL/app-open/compat18 checks PASS |
| AVKit and bounded AVPlayer | Whole Finch AVKit.m/AVPlayer model; own real backend, transport controller and capture-input item | Own VT/AudioQueue engine, real CPU AVPlayerLayer/controls; native-observed scalar/retention/transport contracts | Private AVKit77exports/all73retained; AVFoundation2501->2574 superset; no canonical replacement | Native/M1 no-item/ready/failed controller rows raw EXACT; real play/pause/seek/toggle/HAL230400@48k and CPU draws observed. Earlier quietv3 all150 frames matched | **Newv7 strictFAIL149/150(frame40wrong),2othercontexts/stale+1, attribution under investigation.**11/18 imports resolve (9bounded implementations,2unavailable); no GUI/PiP/capture/touch-bar/KVO-family claim |
| MediaPlayer local state | TERM8 own fixture plus own registration/ownership fixes | Copied local metadata, stable commands, nonretaining target/action registrations and removable copied block tokens; explicit absent system service | Private provider only; native constants/classes readonly, no Now Playing mutation on M5 | Same-byte M5/M1 metadata MATCH; M1 local copied state, command lifetime, no synthetic events, intervals and artwork assertions PASS | No system Now Playing, media-key routing or external command delivery; not installed canonically |
| MediaToolbox utilities | No Finch decoder/asset implementation; own six metadata/registration operations | Real format/color names and transform orientation; unavailable professional registry explicitly diagnosed | New private prefix only |52+211 native-matched stdout rows retained; M1 void opt-in called twice/one unavailable diagnostic |6/7 QuickTime imports; FigAsset callable ABI remains unknown and absent |
| QuickTime private dependencies | Finch FeatureFlags protocol shape; own public/runtime-derived declarations and refusal bodies | Eight loadable frameworks with genuine Swift metadata; no private services fabricated | Private TCC,PhotosFormats,MediaRemote,GeoKit,MobileAsset,MonitorPanel,PerformanceAnalysis,FeatureFlags; no installed replacement | All21 required names resolve; M1 C/ObjC negative callbacks and Swift witness fixtures PASS; actual unchanged app load reaches missing Quartz.framework | No Qt startup/window/playback; offline cached-root-v6 still155 strong imports/39classes/466selectors missing; other owners' dependencies remain |
| QuickTime loader libraries (SF-AI) | Finch's CGFloat.swift (Apache-2.0 with the Swift Runtime Library Exception, from the Swift project's overlay), compiled in from the pinned source | Own SwiftUI binding subset, DeveloperToolsSupport, Swift os module, QuickLook/QuickLookUI absence providers, Quartz umbrella | New staged prefix only; nothing installed | Workstation build; all 42 names QuickTime Player binds from them are exported (static check); not loaded on the M1 | No SwiftUI rendering; no thumbnails or previews; offline scan still has 112 unbound symbols |
| VT decoder capability queries | Selected VTIsStereoMVHEVCDecodeSupported and VTCopyVideoDecoderExtensionProperties shape from Finch VTDecompression.c | Own format admission/typed errors; built-in codecs report no extension, no stereo output; exact existing child re-exported | Private174-effective-export wrapper above172-export provider, none lost and child text identical | Linux build; same-byte M5/M1 extension error/untouched-out facts match; M1 query fixture exit0 at19:39Z | No canonical install; stereo false is truthful platform capability difference from native M5 true |
| Homebrew ffmpeg bottle milestone | Relocated open-source9.0.2_1 closure; retained VT decoder/constants; selected real no-device capture bodies; Finch CI constants | Source-only AVFoundation absence port; CoreImage facade re-exports actual QuartzCore CI classes (zero new classes); existing Cocoa nil-Metal implementation staged; no imports erased | All nine media providers now installed. Final bottle trial needs Metal-only override because canonical Metal lacks MTLCreateSystemDefaultDevice; AppKit/QuartzCore retained | Final installed-media H264/HEVC600 NV12 pictures bit-exact HW/SW/Linux/same-byte M5; HW/SWfps267.38/184.96 and268.82/149.93. Hardware required/reported; no fallback | Plain-root load failure retained; GFX2 owns canonical Metal fix. Nil-device override makes no rendering claim. Capture/GPU/filter/optional encoders unsupported or untested; no kernel work by this stream |
| CLI comparison harness | `userland/tests` programs plus `tools/host-tests.sh` capture/diff policy, pinned masks/exceptions and `.expected` files | Linux/Nix21-program bundle, separate timed receipts, identical binary hash requirement, public framework load names with renewed ad-hoc hashes; strict missing-reference/difference reporting | Isolated sffinch staging; retained dependencies plus eight numeric libraries and staged CFNetwork/ColorSync/CloudKit/OpenDirectory fixes | All21 M1 exits0 after the Foundation update;13 reviewed native references exit0 with identical binary hashes. Results12 MATCH (including3 pinned expected),4 EXIT_OK assertions,4 DIFF (CFNetwork/CloudKit/LA/Sparse),1 BLOCKED (Accounts). Six host failure-policy checks and all six repository checks PASS | CLI subset only; GUI/Swift/cross-store and remaining blocked ports excluded. Accounts reference intentionally unrun due service mutation/access requests. Mac runs use Linux-built bytes, SHA256 checks,30s limit,fresh deleted tmp; no Mac builds |
| OpenScripting | `ASValues.m`, `ASParser.m`, `ASInterpreter.m` and original headers; full OSA.m facade inspected | Staged engine recipe and CLI language probe; use PD locale initializer | Framework/osascript absent; CoreServices lacks Apple-event descriptor/component exports. No install | BUILD FAIL: missing Foundation enumeration/date/file declarations and NSDataDetector; probe not run | Full OSA facade, interpreter runtime, standard additions and original OSAKit/AppKit comparison tests unported |
| CoreData Objective-C/SQLite | All14 `userland/CoreData/*.m` implementation/constant files | Own declarations/numeric/hierarchy facts;PD comparator-block sorting;link retained Foundation updates;private embedded SQLite;Swift overlay excluded | Live thin PD157 exports retained. Candidate279 retains47/157;missing110 are old helper classes/metaclasses,ivars and selector helper. Isolated family staged only | Fresh SQLite store probe MATCH same Linux-built native M5:insert3/reopen/predicate/update9/delete/final2 and read-only ZITEM/Z_METADATA inspection;original28-line property/relationship/entity/model/store hash suite MATCH | No install or private-context interoperability;Swift/Combine,cross-store compatibility,relationships,batch/migration/custom/XML/binary/service paths unverified |
| libsandbox / others | None yet | None | Must compare before selecting code | Not run | Whole slice |

New owner priority: staged media (CoreMedia/CoreVideo, device-independent AudioToolbox/AVFAudio, AVFoundation assets), then CoreData/Network/CoreImage CPU/PDFKit non-GUI. Vulkan then Metal are coordinated separately. The later media-ownership assignment authorizes installation of reviewed supersets;
other owners retain AppKit/QuartzCore/core-library and kernel changes.

Revised priority after the survey (14 November): finish this evidence; missing drop-in frameworks, whole Accelerate, staged libcompression, CFNetwork, comparison harness. SystemConfiguration is deferred because the survey rates ours stronger. No Mac-side build is authorized.

Runtime evidence stays in `runs/sffinch/` (not committed). Finch's copyright and
SPDX notices remain in its pinned source and patch context. OpenSSL retains its
Apache-2.0 license. No Apple SDK, bundle resources or binaries are imported.

Uninstall the new frameworks on the M1 with `python3 /private/var/db/sffinch/runtime/uninstall-new.py`; the matching installer must remain beside it. It verifies each recorded file before removing it. Six AGENTS.md local checks passed (274 Python tests, 77 C groups, cross ABI, six mutation detections, validate/plan/source/publication dry runs).

## Installed media ownership (15 November)

The current [installed-media ledger and evidence](../../../integrations/puredarwin/finch/media/INSTALLED.md)
supersedes the earlier staged-only entries. Nine reviewed media providers are
installed; MediaAccessibility and whole CPU CoreImage retain explicit blockers.

The disk kernel now publishes `/dev/pdavd`. An isolated Homebrew ffmpeg run using
Finch CoreMedia/CoreVideo and our retained m1-avd VideoToolbox decoded 300 H.264
and 300 HEVC 1280x720 B-frame pictures in hardware. Complete NV12 framemd5 records
were bit-exact against software, Linux FFmpeg and the same Linux-built control
on the M5. End-to-end hardware/software rates were 179.64/141.64 fps for H.264
and 120.97/77.42 fps for HEVC. These single trials include startup and hash output
on a normally loaded desktop; they are not isolated decoder benchmarks. The
VideoToolbox client required and reported hardware, with zero callback errors.
Evidence: `hardware-decode-v1/qualified.json` and
`m5-hardware-media-v1-reference.json` under ignored `runs/sffinch/`.

CoreVideo is installed at its canonical path. The candidate preserves the exact
PureDarwin display-link implementation/private objects and all 97 old exports,
with 414 effective exports. Whole Finch CoreVideo alone lost eight private
display-link names and was therefore not selected. The main image's cold SHA256
was `dbe7b0d8e0ffd490f08627985092c2a7c51988be82a5750507ea144be8934017`,
verified on the M1 before activation/execution; originals remain `.pre-finch`.
Root selection was proved with dladdr, both codecs' 600 hardware frame hashes
matched the prior baseline, WAV/AAC each completed 12,000 HAL frames, desktop
processes remained alive, and `sf_compat_push.sh check` passed 18/18. Two earlier
installer/launcher failures rolled back and their receipts remain. The first plain SSH `open -a` selected a nonexistent default Wayland socket.
Using the running session's `/private/var/run/gpu-desktop` fixed that launcher
failure: fresh Terminal/Activity Monitor processes now open and remain alive.
TERM5 still owns panel/input evidence.

CoreVideo must precede CoreMedia: the latter imports ten CV names absent from
the former thin provider. Canonical CoreMedia and VideoToolbox paths were absent
in the fresh inventory; both are now installed at those canonical paths. Each passed root-provider
selection, all600 hardware PTS/hashes, HAL, fresh app opens and compatibility
18/18. Queue
operations remain wholly inside the retained PD AudioToolbox image, with opaque
objects never passed into Finch's queue/converter internals. The installation
variant imports the existing six MIT System Sound wrapper APIs unchanged, so
its 135 effective exports retain all 84 installed names (six wrapper + 78 PD).
That variant passed all ten staged checks and is now installed, with20 cold
file hashes and adjacent originals. Root WAV/AAC HAL and System Sound completion
pass along with600 hardware frame records, fresh app opens and compatibility
18/18. AVFAudio and AVFoundation are now installed and qualified; the corrected
AVFAudio fixture invocation retains the earlier rolled-back failure.

Our [movie test](../../../integrations/puredarwin/finch/tests/movie/README.md)
now passes headlessly on the M1: 900 ordered hardware NV12 hashes/PTS match
Linux and the identical Linux-built M5 executable; 1,440,000 stereo audio frames
complete at 48 kHz through retained AudioQueue/HAL/coreaudiod. Over 30 seconds,
wall time was 29.943529 s versus 29.999979 s audio time (-56.450 ms), with
60.000 ms maximum and 9.887 ms mean video-delivery lateness. Video/audio-clock
delivery offset starts at 0 and ends 17.333 ms late: A/V delivery drift is
17.333 ms across the run, distinct from the clock/wall difference. Queued/
completed counts describe returned source buffers; the sample clock ends at
1,439,999 frames, not a DAC presentation acknowledgement. This establishes
ordered headless delivery and HAL consumption, not acoustic output or scanout.
Its first run's raw-media timestamp failure remains recorded; the AVAssetReader
patch now maps a full untrimmed single unity-rate codec-delay edit to asset
time. Arbitrary edit lists are not implemented. The original hosted-CALayer run reported unavailable libEGL, so its submissions
were not called rendered video. Our corrected CPU frame-layer NSView now draws
all 900 images into the real window CGContext: ordered decoded hashes/PTS
match Linux and the same new Linux-built M5 program. Hardware1, source1.44M
frames at48kHz, scheduling drift6.666ms over30s, maximum lateness73.333ms;
queue-clock/wall difference-21.018ms. There is no compositor/DAC presentation
acknowledgement; TERM5 owns visual verification. No input/capture by me.

Whole Accelerate and MediaAccessibility now build against Cocoa's real ICC/
indexed-color and ImageIO metadata implementations, without SDK imports or
success stubs. vImage's original comparison client completes on both machines with identical
Linux-built bytes:1,158/1,159 output lines match. The remaining Display P3 coarse
color result is80 versus82; keep that DIFF. Its first private-stage load failed
because nested vecLib/vImage paths were missing from the override; explicit
private search paths fixed it, without altering library imports or algorithms.
MediaAccessibility's native own-PNG caption round-trip passes, but on M1 the
backend finalized pixels without persisting XMP. Our patch now verifies the
temporary caption before rename and returns false without replacing the input
when unsupported. The positive case remains FAIL; the negative refusal/unchanged-
PNG case passes. This framework stays staged pending the precise ImageIO request
to TERM5. Whole CoreImage must still avoid duplicate legacy
CI classes in QuartzCore; only the previously qualified re-export facade is
eligible until TERM5 supplies a coherent single-class-provider change.

## Canonical Metal and realtime audio (15 November, 05:41Z)

[Metal policy](../../../integrations/puredarwin/finch/Metal/README.md) now supplies
the canonical framework, retaining all 185 Darling exports and the previous two.
Disabled creation/enumeration never initializes Vulkan; the real device requires
`SF_METAL_ENABLE_REAL_DEVICE=1` and retains its known kernel exit hang. The
unmodified Homebrew bottle now passes H264/HEVC HW/SW comparisons with no DYLD
overrides. Every prior plain-root failure remains in its original receipt.

[Realtime AVFAudio](../../../integrations/puredarwin/finch/AVFAudio/engine/realtime-README.md)
now renders AVAudioPlayerNode files into retained PD AudioQueue/HAL at the queried
48 kHz device rate. Three output lifetimes, native-identical offline samples,
all 334 old exports and the full installed-family regressions pass. This does
not claim acoustic output, general live graph mutation or precise pause/resume.

VLC/IINA acquisition and source-only AVKit/networking work continue separately;
a player launch returning zero is not playback evidence.

## Further staged media and networking (15 November, 08:12Z)

AVKit's whole Finch view/player model is staged, with same-byte native/M1 value
checks and a fresh functional rerun. It covers2/18 QuickTime AVKit imports and
none of the7 private MediaToolbox functions; this Finch player lacks the H264/
audio backend. No installed replacement or rendered-player claim.

FoundationNetworking's isolated SF-prefixed whole Finch implementation passes
strict example.com HTTPS, missing-CA rejection and native-matched cookie/cache
checks on M1. The canonical archive builds; TERM6 has the exact integration
proposal. Foundation is not installed by this stream. WebSocket/proxy/background
behavior remains source-compiled, unqualified.

VideoToolbox compression is installed with OpenH264 and the retained PDAppleAVD
decoder. All83 prior exports remain,172total. M1 software encodes30 ordered720p
frames at3.43fps; ffmpeg decodes all30 with58.873634dB PSNR against our pattern.
The same Linux-built API probe completes on native M5; its hardware query is
unsupported and does not prove native software selection. No AVE hardware
encode has occurred. The software-compression provider was installed08:38:25Z
with cold hashes/.pre-finch and full600-picture/HAL/apps/compat18 regression. See SF-AD for the
owner-paused preloaded-firmware hardware study and preserved private inputs.

VLC is the smaller verified third-party target. The Linux-built original entry
now reaches its plugins; the latest failure reports real QuartzCore/AppKit/VT
imports and ends SIGSEGV. Exact grouped gaps and failed runtime receipts remain
in players/GAPS.md and runs/sffinch. TERM6 has the GUI dependencies; no player
window, decoding/audio or capture claim follows from open-a returning zero.

15 November owner pause: AVE source and inputs are preserved; installed/live
non-AVE CIO08 is confirmed, with no AVE module or boot argument. No more AVE
builds/boots/probes/extraction. VLC's independent headless v4 now receives a real
avcodec picture through actual vdummy, opens auhal and records104448 HAL-read
frames; direct sf-catch run exits0. No window/capture or exact decoded-frame count
is claimed yet. The AUHAL source fix and three proven browser AAC fixes compile
in the owned AudioToolbox candidate; file/codec/queue, final rawASC/ESDS PCM,
real-device HAL and corrected SystemSound prefix tests pass. The reviewed update
is queued behind the kernel owner, with cold hashes/original+prior snapshots and
full regressions required. No CoreAudio or Foundation replacement is involved.

AudioToolbox update installed09:33:26Z:20 cold file hashes, .pre-finch plus prior
version snapshots;135 prior effective exports retained.600 hardware decode
PTS/hashes, WAV/AAC HAL, System Sound, AVPlayerNode3lifetimes, browser cookie/AUHAL,
app-open/desktop and compatibility18/18 pass. No CoreAudio/coreaudiod replaced.
VLCv5 vendor counters121video/189audio exceed the fixture's60samples/95packets;
this is an accounting discrepancy, not a claim of121 unique decoded pictures.
HAL101376/direct103936 and traced exit0 provide real headless output evidence.
The fresh canonical-audio v6 run also passes with no framework override,
104448 HAL-consumed frames and traced direct exit0. TERM6 GUI window/capture
remains pending, along with unique-source-frame accounting.

## Installed browser media and VLC follow-up (15 November, 17:27Z)

AVFoundation now retains the complete installed asset/capture family and adds
CODEX-FX's three speech classes, NV12 display layer and honest restricted/
asynchronous-denied capture authorization. Its export set grows2482->2501
without losses. The prefix test reads two tracks/10.000s, reports no devices or
voices, and draws1024/1024 red NV12 pixels on Mesa M1. The canonical update
passes600 hardware decode PTS/hashes, WAV/AAC HAL, the30-second movie, app opens
and compatibility18/18. Cold receipts and previous files are retained. Source:
`media/bottle/avfoundation-complete.nix`; evidence:
`runs/sffinch/install-AVFoundation-browser-v2`. CGL remains CODEX-FX's one
implementation; this stream uses its private prefix, not a competing install.

The installed VideoToolbox update accepts VLC's Temporal/DeinterlaceFields only
when every supplied H264 SPS proves frame-only coding. Unknown/interlaced input
still fails. Native Require/Enable literals retain observed conflict behavior;
old key values remain unchanged. Host sanitizer/fuzz checks, six M1 options,
four native creation cases and1200 hardware/software H264/HEVC PTS/hash values
pass. Actual vendor VLC's prefix headless module completes120 PDAppleAVD jobs
with no errors/timeouts/DART faults and accepts HAL buffers. No GUI inference.

Two update attempts rolled back: a controller codec-name classification bug,
then a102.596ms end wall/queue offset. Both receipts remain. Controlled runs
and new instrumentation distinguish fixed HAL producer lead from clock-rate
drift. Early/late mean-offset change is-0.365ms on the restored provider and
-0.010ms on the candidate; each has900 matching frames and1440000 audio frames.
The third cold packet passes all22 programs/apps/compat18. Its canonical movie
reports0.104ms relative drift and-86.291ms fixed end offset. No bound was widened;
the new expected-hash probe requires populated measurement windows, while all
frame/hardware/HAL/rate checks remain. Source/limits:
`tests/movie/README.md`; receipt: `install-VideoToolbox-progressive-v3`.

VLC private compatibility now supplies real Gregorian/file/volume/scheme and
CFPreferences suite operations, plus explicit unavailable contacts, automation,
script, web and updater behavior. Both Foundation wrapper variants and their
exports are retained. A private Foundation build honors AppKit's allocation
hook before decoding cyclic NIB objects; a512-byte padded/cyclic-UID test passes.
VLCv15 clears that failure and reaches the missing NSStatusItem update backend.
With the upstream optional status icon disabled, subsequent Foundation calendar
and locale gaps use existing CFCalendar/CFLocale engines. Same-byte native/M1
vectors match42 calendar cases and16 direction cases. VLCv18 reaches extension
setup, then catches missing +[NSColor currentControlTint] and exits1; the
NSActionTemplate image is also absent. Exact AppKit requests and the private
Foundation integration patch are with TERM7. No player window, GUI playback,
compositor capture, acoustic output or screen-input claim.

AVKit now provides6/18 reviewed QuickTime imports: the prior player view,
immutable identity snapshots, independent timecode metadata and rational
slow-motion ranges. MediaToolbox supplies5/7: format names, rotation/flips,
dynamic-range labels and actual format-description color metadata. Expanded
math/name vectors match native exactly. Persistent file-reference URLs remain
unsupported; the identifier returns a working path URL and the difference is
recorded. FigAsset's ABI and the professional reader registry remain unresolved.
Both providers stay staged; the Finch player still lacks its H264/AAC backend.

TERM7 installed Foundation networking through its guarded workflow: plain
example.com HTTPS works without environment overrides; missing-CA verification
fails closed. This stream does not install Foundation. Owner-paused AVE source
and private inputs remain preserved, with no further builds/boots/probes or
extraction. CODEX-TB's latest qualified kernel is non-AVE CIO29 per its ledger.

The post-install canonical VLC hardware run also passes with no framework or
library override: actual videotoolbox module,60 additional PDAppleAVD jobs/
completions, zero additional errors/timeouts/DART faults/stale replies, contexts0,
traced exit0 and102400 HAL-read frames. Its own counters still report121 video
and189 audio decodes for the60-sample/95-packet fixture; do not treat those as
unique pictures. Raw rc stats, kernel before/after and own HAL evidence are in
`runs/sffinch/vlc-hardware-canonical-v1/qualification.json`. This remains dummy
video output; the AppKit window dependency is unchanged.


November15 continuation: AVKit's coherent bounded local-file player now uses
real AVAssetReader/VideoToolbox frames and retained AudioQueue output. The final
M1 stage-v3 matches all150 frame hashes and PTS, reports150 actual AVD
completions/no errors, and returns230400 audio frames after a0.2s seek from a
240000-frame/48kHz source. Own AVPlayerLayer/transport shapes render into a CPU
bitmap; no window/panel/acoustic or streaming support is inferred. AVFoundation
exports2501->2574 with none lost; browser speech/display/auth wrapper retained.
See finch/AVKit/README.md and AVFoundation/player/README.md for bounds.

Eight requested private QuickTime dependencies are staged: TCC, PhotosFormats,
MediaRemote, GeoKit, MobileAsset, MonitorPanel, PerformanceAnalysis and
FeatureFlags. All21 required imports resolve and negative-service/Swift witness
fixtures pass on M1. No service is fabricated. AVKit remains6/18 required
imports; MediaToolbox now6/7, with the professional-reader void opt-in explicitly
reporting no registry. Unknown FigAssetCreateWithURL ABI remains absent. Actual
unchanged QuickTime load-v4 returns-6 in dyld at missing Quartz.framework after
clearing WebKit/CoreMediaIO; no app startup or playback. See finch/QuickTime.

Retained media DIFFs are classified in finch/DIFFERENCES-2026-11-15.md. AAC/MP3
fixture differences are bounded decoder/PNS/rounding variations; LA differs in
private superclass metadata. Sparse's genuine missing matrix+opaque overload
is fixed and native-matched; extra enum-overload convergence remains a visible
compatibility difference. CI gray conversion, PNG alpha and geometry were real
bugs. Private CI/Onyx/CG now match all86pixel+6extent rows and independent
semantic predicates; canonical Onyx/CG adoption belongs to TERM.

Zero-copy remains private and unqualified on hardware. Optional AVD capture
import retains ABI1/default behavior. Follow-up DART invalidation failures
quarantine backing until reboot and reject subsequent DMA; task ownership
retains identity against PID reuse. Linux kext SDK and logical fault fixtures
are separate from a hardware trial, which belongs to CODEX-TB. Native
cross-process tests disproved GetUseCount as a global lifetime predicate; the
producer now uses IsInUse and passes explicit child-hold/release controls.
Handoff ordering, GPU completion, actual storage aliasing and1080p60 remain
unproven. No AVE activity or kernel collection was built or installed here.

Additional November15 evidence: M1 media-private-controls-v1 matches native
audio-level properties and draws real changing pixels; AVKit now7/18 reviewed
imports. New decoder queries cover5/5 reviewed VT imports at the export level.
Offline cached-root-v6 has155strong gaps/39classes/466unimplemented selectors;
this is not a fresh installed-root inventory. Actual Qt remains v4/Quartz
loader failure. Actual `media-private-controls-v3` at19:39Z proves both-role GPU
FD/16KiB storage and explicit cross-process H/R deferred-release controls. VT
query errors/out slots match native. Process-exit cleanup remains rawFAIL:
the dead child's count stays held, safely quarantining the decoder backing;
native automatic cleanup is not implemented by the private provider.

The extra retained vImage P3 checksum80/82 was a real named-profile adapter
bug: absent ICC data selected sRGB by model alone. The private correction uses
our real ColorSync P3 profile, and the unchanged1159-row original comparison
now matches82. Focused component data still retains rawDIFF for absent ICC
metadata and small arithmetic residuals shared by explicit profiles; see
finch/Accelerate/P3-DIFFERENCE-2026-11-15.md. No canonical install occurred.

The first600-frame1080p GPU-output control completed600AVDjobs without errors,
but all output-storage checks failed: the original private IOSurface validator
rejected legitimate CV Yoffset512. Native same-byte public allocation probes
confirm that offset and distinct flattened topBPR. A separate CoreVideo bug
under-reserves its advertised1080p dataSize; the staged correction retains the
512-byte header and reserves dataSize+64. FX owns the bounded-offset IOSurface
fix. After the actual kernel-owner recovery, corrected M1 CPU/GPU layout
metadata matches all required native fields, and the independent600-frame
hardware output test passes NV12 hashes/PTS/GPU storage/held64 control with
clean AVD deltas and contexts0. It explicitly copies1866240000 bytes; strict
zero-copy still fails. This CPU-hashing correctness run does not measure
browser1080p60. External capture import and consumer IPC/fences remain
unqualified. MediaPlayer's new local-state absence provider also passes its
M1 assertions and readonly same-byte native constants/classes comparison;
there is no system Now Playing or remote event service, no canonical install.


The later capture-input value model matches every raw native row on the M1 at
20:48:14–15Z. A separate AVCaptureView NSView subclass deliberately returns nil
from all three observed initializers, with one unavailable diagnostic, verified
on the M1 at20:58:27–29Z. Its negative contract is not capture parity:73exports
retain71, ten reviewed AVKit imports resolve but only eight have implemented
behavior. No capture hardware, window, input or canonical install was used.


Controller follow-up: all three complete native/M1 scalar-state comparisons
match without masks, and real transport/HAL assertions complete. The new
strict hardware-frame comparison nevertheless fails149/150 under concurrent
decoder contexts, with one new global stale completion; frame40 differs before
any transport action. This is an unresolved decoder/copy/concurrency bug, not
an accepted arithmetic difference. See finch/AVKit/CONTROLLER-2026-11-15.md;
older quiet single-client passes remain scoped to their own receipts.

## Media handover, 16 November wind-down

The owner ended the session. No experiment, install, reboot or kernel install
is queued by this stream. See the [complete media handover](../../../integrations/puredarwin/finch/firefox-media/HANDOVER-2026-11-16.md)
and [SF-AG's current media section](SF-AG-firefox.md#media-handover-16-november-wind-down)
for installed hashes/selectors/rollback, commands, exact private enable procedure,
failed evidence, ranked defects and the next five steps. Source07372dff6 is
committed and not pushed; its batched CGL is not installed.

The Firefox selector retains CoreVideo clock0172 plus the qualified shared VT
producer and normalized audio family. The earlier600H264/300HEVC installed
zero-drop/pixel/job gate remains valid. Decoder copies are0/frame; matched RDD
CPU14.745→8.558% at1080p60 and26.889→16.533% at4K30. Separate private QC/CGL
work removes the remaining measured CPU upload: one batched H264 pair passes
65 checks/600 frames each/zero drops, both actual images inspected, family
CPU77.350→73.495% of one core. This is not a full4K, installed or panel claim.
The current4K AVD failure is IOVA capacity/fragmentation in its2GiB aperture,
not proof of absent physical memory. Proposed kernel49 was not installed;
48 stays qualified and no reboot is authorized during wind-down. Pool32 and
retirement-off remain the installed defaults, with completion waits/leases kept.

The1080p60 input-gap stalls remain open. Gecko40ms rVFC notifications are not
25Hz panel delivery. XPI write/profile evidence and the failed strict60fps
presentation runs remain preserved. Audio's10.66/15.96ms model correction and
ten PCM-state checks pass; the exact own server slot clears within12.193ms
after connection loss, but acoustic sync and all abnormal exits are unqualified.
VLC/QuickTime/AVKit remain parked: VLC has no movie-window playback proof;
AVKit's strict controller fails149/150 hashes; QuickTime still lacks Quartz at
load. AVE remains paused exactly as SF-AD records, with source/private inputs
preserved and no further builds, extraction or probes. Historical staged-only
and zero-copy-unqualified statements above describe their earlier cohorts;
this handover records the later installed Firefox state without erasing them.
