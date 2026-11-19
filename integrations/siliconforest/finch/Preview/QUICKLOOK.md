# Preview's scoped QuickLook reader

Retains the existing open QTP QuickLook thumbnail-absence API/time key and
QLSeamlessDocumentOpener factory. Adds only three data keys from Finch
2d9b1bb1af57e14462e4621d194929188a8845b0:userland/QuickLook/QuickLook.m,
and mines item/model storage and view lifetime from QuickLookUI.m. Finch
copyright and MIT OR Apache-2.0 notices and both licenses are preserved.
This is not the whole panel/generator framework.

Exact P10 audit: current QTP links are intact, system fallbacks absent. QuickLook
lacks Preview's three display-state keys. QuickLookUI provides only the opener,
not Preview's document, NSView subclass and closer. Reference macOS 27.2.1
metadata confirms class ancestry and relevant method types; app origin is 26.5.
Names/types only, no Apple implementation, headers, resources or instances used.

The reader decodes local images with NSImage and uses the separately owned
retained PDFKit for unrotated PDF pages. Loaded state/page counts derive from
actual decoded data. View drawing dispatches through the document, with real
page selection and bounded zoom. Unknown media, missing files/providers,
remote URLs, invalid pages/zoom and rotated PDF rendering fail explicitly.
No invented loaded/page-count success, no placeholder icon presented as a read
result. No editing, saving, sharing, private thumbnail callback or seamless
service is provided. Opener/closer factories return nil; closer metadata stores
its display state and reports no animation. Existing thumbnail absence remains.

`quicklook-reader.nix` builds a private candidate and an arm64 reader probe.
Runtime/Preview UI acceptance is separate from exports and construction.

The exact arm64 candidate passed the M1 headless probe under gui.lock and the
owner-idle guard: all keys/classes, retained thumbnail/time-key absence behavior,
real image pixels, three retained PDF pages with exact RGB centers, direct
QLPreviewView -> document drawing, PDF text, page/zoom/error bounds and lifecycle.
All candidate/fixture hashes and current PDFKit/Onyx/QTP hashes stayed unchanged.
No window or unmodified Preview UI acceptance is claimed. The original app
remains stopped at its separately owned AppIntents loader gate.
