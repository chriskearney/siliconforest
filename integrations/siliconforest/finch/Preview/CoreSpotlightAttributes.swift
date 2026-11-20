// SPDX-License-Identifier: MIT OR Apache-2.0
// Original typed bridge over the scoped Finch attribute implementation.
@_exported import SFCoreSpotlightAttributesBridge
import UniformTypeIdentifiers

public extension CSSearchableItemAttributeSet {
    convenience init(contentType: UniformTypeIdentifiers.UTType) {
        self.init(itemContentType: contentType.identifier)
    }
}
