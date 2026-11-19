/* SPDX-License-Identifier: MIT */
import Foundation
import SFUTTypeBridge

public struct UTType: Hashable, @unchecked Sendable {
    private let object: SFUTTypeObject

    public init?(_ identifier: String) {
        guard let object = SFUTTypeObject.lookup(identifier: identifier) else { return nil }
        self.object = object
    }

    public init?(filenameExtension: String) {
        guard let object = SFUTTypeObject.lookup(filenameExtension: filenameExtension) else { return nil }
        self.object = object
    }

    public static var item: UTType { UTType("public.item")! }
    public static var data: UTType { UTType("public.data")! }
    public var identifier: String { object.identifier }
    public var preferredFilenameExtension: String? { object.preferredFilenameExtension }
    public func conforms(to other: UTType) -> Bool { object.conforms(to: other.object) }
    public static func == (lhs: UTType, rhs: UTType) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}
