# PersonNameComponents bridge

The observed open AppIntents loader, PID 3204, stops on:

`_$s10Foundation20PersonNameComponentsV19_bridgeToObjectiveCSo08NSPersoncD0CyF`

Receipt: `runs/preview/app-private/evidence/appintents-attributed-20261119T074148Z.json`.
`Foundation.framework/Versions/C/Foundation` reexports `Foundation.sf-under`, and
that image reexports `/usr/lib/swift/libswiftFoundation.dylib`. The symbol is a
Swift Foundation export. The other five native imports are equality, the
metadata accessor, the nominal type descriptor, and the Encodable and Decodable
witnesses.

Pinned swift-foundation `c20150400269a6afffe5b3a9f9fa8bbd51d69e1a` has no
`PersonNameComponents` source. `sources.json` records the Swift 5.4 Darwin
overlay carried by Finch `2d9b1bb1af57e14462e4621d194929188a8845b0`,
`userland/Foundation/swift/Darwin/PersonNameComponents.swift`, SHA-256
`e9308ddc957b9f834e2f28a4ff3f48db52e96a6bc6641a47a9aafe1bcda2b121`.
The original notices and the Apache license with Swift exception stay in the
file. `compatibility.patch` makes two compile adjustments and no storage
change: the phonetic accessors call the same bridge methods explicitly, because
this compiler does not apply the later `_ObjectiveCBridgeable` conformance
inside those closures, and `description` uses `+` because this Foundation
`String` has no `appending(_:)`. Storage is the retained `NSPersonNameComponents` object through the
existing `_MutableHandle` copy-on-write box. Equality is the retained object's
`isEqual:`, which compares six strings and `phoneticRepresentation`. Hashing
combines that object, so it follows the retained `hash` (`givenName` xor
`familyName`). Codable encodes the six strings with their case names and omits
`phoneticRepresentation`. That is the overlay's behavior. The retained class's
own `NSCoding` still archives `NS.phoneticRepresentation`.

The retained M1 Foundation
`94a07b510d116a7cfb4f302708f1a3ee7286d4be9c94037b77db13dc48959c2f` exports
`NSPersonNameComponents` and `NSPersonNameComponentsFormatter`, including the
seven stored fields, copy, `isEqual:`, `hash`, and keyed coding. The cross SDK
`libFoundation` exports neither the class nor a header.
`include/NSPersonNameComponents.h` declares those public names with nullable
object properties. It is not an Apple header and it is not a second
implementation. The build overlays it into the existing Foundation umbrella.

The source snapshot compiled with this file matches
`attributed-string/compiled-inputs-final.json`. That snapshot produced
`attributed-string/build/libswiftFoundation.dylib`, SHA-256
`d02a85edbe5ef478d32ab2f13e1c859524d9fbbf0fa630fbb089101a2093b66e`
(5,141 exports, including the prior 2,018). Those export names are the same
set as the frozen library AppIntents PID 3204 loaded,
`attributed-string/build-1fff856b/libswiftFoundation.dylib`, SHA-256
`1fff856bea529b0a22d98b89de5a03c31ad0be3499595b445f6e51c2e64c64cc`.
Data.swift in the snapshot is the munmap handoff
`5157a44dafcbe324e77e60fd7cfd08068de4a7de8fd26994a80656a4d704ff2a`.
Compile that snapshot plus this one Swift file. The new library must keep
every one of those 5,141 export names. Do not replace either baseline library
or edit AttributedString or Data sources. The NSError/CFError alias stays on
the link. The cross SDK does not define the class symbol, so the link allows
`_OBJC_CLASS_$_NSPersonNameComponents` and its metaclass to resolve from the
retained Foundation at runtime. AppIntents stays unlaunched until this
provider has a passing separate-client probe.

`probe.swift` is a separate client. It checks empty and partial fields, copy
independence, equality and `Set` hashing, a copied Objective-C bridge in both
directions, Unicode, JSON, the overlay's omitted phonetic field, and that both
retained classes are present. No AppIntents or Preview launch is part of this
slice.
