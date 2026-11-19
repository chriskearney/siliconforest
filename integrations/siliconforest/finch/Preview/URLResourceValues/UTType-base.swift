/* SPDX-License-Identifier: MIT */
import Foundation
import SFUTTypeBridge

public struct UTType: Hashable, _ObjectiveCBridgeable, @unchecked Sendable {
    private let object: SFUTTypeBridge.UTType

    public init?(_ identifier: String) {
        guard let object = SFUTTypeBridge.UTType.lookup(identifier: identifier) else { return nil }
        self.object = object
    }

    public init?(filenameExtension: String) {
        guard let object = SFUTTypeBridge.UTType.lookup(filenameExtension: filenameExtension) else { return nil }
        self.object = object
    }

    private init(object: SFUTTypeBridge.UTType) {
        self.object = object
    }

    public init?(filenameExtension: String, conformingTo supertype: UTType) {
        guard let object = SFUTTypeBridge.UTType.lookup(filenameExtension: filenameExtension,
                                                       conformingTo: supertype.object) else { return nil }
        self.object = object
    }

    public static var pdf: UTType { UTType("com.adobe.pdf")! }
    public static var png: UTType { UTType("public.png")! }
    public static var jpeg: UTType { UTType("public.jpeg")! }
    public static var tiff: UTType { UTType("public.tiff")! }
    public static var heic: UTType { UTType("public.heic")! }
    public static var image: UTType { UTType("public.image")! }
    public static var folder: UTType { UTType("public.folder")! }

    public func _bridgeToObjectiveC() -> SFUTTypeBridge.UTType { object }

    public static func _forceBridgeFromObjectiveC(_ source: SFUTTypeBridge.UTType, result: inout UTType?) {
        result = UTType(object: source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: SFUTTypeBridge.UTType, result: inout UTType?) -> Bool {
        result = UTType(object: source)
        return true
    }

    public static func _unconditionallyBridgeFromObjectiveC(_ source: SFUTTypeBridge.UTType?) -> UTType {
        guard let source else { preconditionFailure("Cannot bridge nil to UTType") }
        return UTType(object: source)
    }

    public static var item: UTType { UTType("public.item")! }
    public static var data: UTType { UTType("public.data")! }
    public var identifier: String { object.identifier }
    public var preferredFilenameExtension: String? { object.preferredFilenameExtension }
    public func conforms(to other: UTType) -> Bool { object.conforms(to: other.object) }
    public static func == (lhs: UTType, rhs: UTType) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}
