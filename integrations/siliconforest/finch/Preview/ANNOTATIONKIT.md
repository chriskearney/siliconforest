# AnnotationKit reader candidate

Original SiliconForest code. Public import names, selectors, property types,
class ancestry and delegate signatures came from the unchanged owner Preview
26.5 app and read-only installed runtime metadata on the authorized M6 (27.2.1).
The reference OS differs; signatures are evidence, not full compatibility proof.
Private metadata/REA receipts remain ignored. No Apple implementation, header,
archive, asset or dependency was copied into this provider.

Implements stable annotation identity, geometry translation, property storage,
page collections, bounds-checked atomic selection, notifications, page lookup,
transparent noninteractive reader overlay lifetime, delegate bounds/scale,
and SDR CoreGraphics rectangle/border-fill drawing. No disk writes or services.
The SF-prefixed model population methods are our original API, not a claim to
understand Apple's annotation archives. Only supported exact shape classes draw;
other geometry, transformed overlay axes, archive decode/encode, clipboard,
editing tools and popups fail explicitly with an NSError-backed exception.
Form fill and image-description editing capabilities are false. Missing editor
menus/toolbars return nil. Telemetry logs its absence; no recording is created.

`annotationkit.nix` builds only a private candidate and an arm64 semantic probe.
The probe checks selection atomicity and retained model data, notifications,
class ancestry, delegate scale/bounds, overlay identity/noninteraction/teardown,
real bitmap pixels and four explicit unsupported operations. It requests no
window, but run under the GUI lock and owner idle guard because it creates an
AppKit overlay. Target runtime and app launch results are reported separately.

M1 standalone verification passed with the private QTP loader paths: stable
identity/translated bounds, immutable page input, extended selection and invalid
selection atomicity, notifications, page lookup, delegate scale/intersection,
transparent overlay create/reuse/relinquish/teardown, exact device RGB red
bitmap pixels, and four exceptions with the expected NSError domain/code and
nonempty description. Binary digests stayed unchanged. A separate isolated
system-CoreGraphics/retained-Onyx comparison passed the same pixel checks.
Named red and bitmap row direction were initially wrong probe assumptions;
the failed receipts remain private. The error graph is retained explicitly by
our exception subclass through unwinding, independent of baseline constructor
metadata ownership. This is not a shared Foundation fix or full ABI claim.

The tested provider loaded in unchanged Preview during bounded P5. P5 then
stopped at ImageCaptureCore; after the coordinator's tested capture browser was
added privately, P6 stopped at CorePDF. No Preview window has appeared. All 174
app files, both executable slices, retained p0 and owner source stayed unchanged;
two off-box executable reads also matched the original byte for byte. No global
install, owner input, compositor restart or push was performed.
