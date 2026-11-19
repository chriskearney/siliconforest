// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Derived from Swift swift-5.4.3-RELEASE's Darwin/Foundation/URL.swift.
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception.
// Narrow NSURL-backed value/bridge for the existing open Foundation overlay.
@_exported import Foundation

public struct URL: Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, @unchecked Sendable {
    // NSURL holds an immutable URL.
    private let reference: NSURL

    private init(reference: NSURL) { self.reference = reference }

    public init?(string: __shared String) {
        guard !string.isEmpty, let value = NSURL(string: string) else { return nil }
        reference = value
    }

    public init(fileURLWithPath path: __shared String) {
        reference = NSURL(fileURLWithPath: path.isEmpty ? "." : path)
    }

    public init(fileURLWithPath path: __shared String, isDirectory: Bool) {
        reference = NSURL(fileURLWithPath: path.isEmpty ? "." : path, isDirectory: isDirectory)
    }

    public var absoluteString: String { reference.absoluteString() ?? "" }
    public var path: String { reference.path() ?? "" }
    public var lastPathComponent: String { reference.lastPathComponent() ?? "" }
    public var pathExtension: String { reference.pathExtension() ?? "" }
    public var isFileURL: Bool { reference.isFileURL() }
    public var description: String { absoluteString }
    public var debugDescription: String { absoluteString }

    public func appendingPathComponent(_ pathComponent: String) -> URL {
        reference.appendingPathComponent(pathComponent).map(URL.init(reference:)) ?? self
    }

    public func appendingPathExtension(_ pathExtension: String) -> URL {
        reference.appendingPathExtension(pathExtension).map(URL.init(reference:)) ?? self
    }

    public static func ==(lhs: URL, rhs: URL) -> Bool {
        lhs.absoluteString == rhs.absoluteString
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(absoluteString) }

    // No security-scoped grant service exists; never report acquiring a grant.
    public func startAccessingSecurityScopedResource() -> Bool { false }
    public func stopAccessingSecurityScopedResource() {}
}

extension URL: Codable {
    private enum CodingKeys: Int, CodingKey {
        case base
        case relative
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relative = try container.decode(String.self, forKey: .relative)
        let base = try container.decodeIfPresent(URL.self, forKey: .base)
        guard let reference = NSURL(string: relative, relativeTo: base?.reference) else {
            throw DecodingError.dataCorruptedError(forKey: .relative, in: container,
                                                   debugDescription: "Invalid URL string.")
        }
        self.init(reference: reference)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reference.relativeString(), forKey: .relative)
        if let base = reference.base() {
            try container.encode(URL(reference: base), forKey: .base)
        }
    }
}

extension URL: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURL { reference }

    public static func _forceBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) {
        result = URL(reference: source)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) -> Bool {
        result = URL(reference: source)
        return true
    }
    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURL?) -> URL {
        precondition(source != nil, "Cannot bridge a nil NSURL to URL")
        return URL(reference: source!)
    }
}
