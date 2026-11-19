// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Derived from Swift swift-5.4.3-RELEASE's Darwin/Foundation/URL.swift.
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors.
// Licensed under Apache License v2.0 with Runtime Library Exception.
// Narrow NSURL-backed value/bridge for the existing open Foundation overlay.
// It does not claim bookmark, resource-value, or security-scope support.
@_exported import Foundation

public struct URL: Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    private var reference: NSURL

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
    public var isFileURL: Bool { reference.isFileURL() }
    public var description: String { absoluteString }
    public var debugDescription: String { absoluteString }

    public static func ==(lhs: URL, rhs: URL) -> Bool {
        lhs.absoluteString == rhs.absoluteString
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(absoluteString) }

    // No security-scoped grant service exists; never report acquiring a grant.
    public func startAccessingSecurityScopedResource() -> Bool { false }
    public func stopAccessingSecurityScopedResource() {}
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
