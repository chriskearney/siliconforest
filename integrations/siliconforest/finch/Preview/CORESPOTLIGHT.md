# CoreSpotlight attributes for AppIntents

Finch 2d9b1bb1af57e14462e4621d194929188a8845b0,
`userland/CoreSpotlight/CSSearchableItem.m`, MIT OR Apache-2.0.
Copyright (c) 2026 The Finch Project contributors. Both licenses accompany the
output. Upstream file SHA256:
`2cc5a95bbb8e18a67cd95f3eeaefe953a172f3f5c9c2c8be9fd2910531940027`.

Mines only CSSearchableItemAttributeSet's real field dictionaries, recognized
field names, KVC storage and independent dictionary copy, plus custom-key
validation/metadata. SiliconForest adds direct typed contentType/contentTypeTree,
title and displayName accessors instead of advertising dynamic forwarding,
uses synchronized initialization for the field-name table, and rejects unknown
or invalid keys and unavailable archive operations explicitly. Secure coding
is not advertised. The remaining recognized fields are retained through KVC.
No index/query/service class, disk database, search result, or success callback
is supplied. A custom key's searchable flags store requested metadata only.

Pinned AppIntents creates CSSearchableItemAttributeSet(contentType: .item) and
sets title in IndexedEntity.defaultAttributeSet. The requested displayName field
is preserved independently. The Swift convenience initializer must consume the
same verified UTType overlay and identifier; no object-layout coercion.
`corespotlight-attributes.nix` initially builds the Objective-C portion and its
standalone arm64 data/error-boundary probe. Compiler/runtime results and the
Swift wrapper are separate proof until measured. Private staging only.

`corespotlight.nix` combines the model with a real Swift convenience initializer
using an explicit `uniformTypeIdentifiers` package input and the coherent private
Foundation URL overlay. It emits the CoreSpotlight Swift module and open Clang
bridge headers for AppIntents consumers. `corespotlight-check.nix` checks exact
classes, versions, code signatures and both probes' direct imports.

The combined candidate passed both standalone probes on M1. The Objective-C
probe checked ordinary/custom fields, invalid keys, independent copy, nil removal
and four error boundaries. The Swift probe checked `.item` -> `public.item`,
contentTypeTree, title/displayName, Unicode, copy, 10,000 writes and nil removal.
All five staged binary digests, existing Foundation and installed underlying
UTType provider stayed unchanged. No app, GUI, index or search operation ran.
These results qualify this attribute subset, not AppIntents or Preview UI.

The UTType package input must provide `usr/lib/swift/UniformTypeIdentifiers.swiftmodule`,
`usr/lib/swift/libswiftUniformTypeIdentifiers.dylib`, and its open Clang bridge
under `include`. Compile consumers with both packages' Swift/include paths and
the same Foundation overlay; link the private CoreSpotlight framework and Swift
UTType library. The provider builds and checks only; it never installs them.
