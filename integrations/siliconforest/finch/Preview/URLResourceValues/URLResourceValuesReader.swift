//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public typealias URLResourceKey = NSURLResourceKey

@available(macOS 10.10, iOS 8, watchOS 2, tvOS 9, *)
public struct URLResourceValues {
    var _values: [URLResourceKey: Any]
    var _keys: Set<URLResourceKey>

    public init() {
        _values = [:]
        _keys = []
    }

    fileprivate init(keys: Set<URLResourceKey>, values: [URLResourceKey: Any]) {
        _values = values
        _keys = keys
    }

    func contains(_ key: URLResourceKey) -> Bool {
        return _keys.contains(key)
    }

    func _get<T>(_ key: URLResourceKey) -> T? {
        return _values[key] as? T
    }

    func _get(_ key: URLResourceKey) -> Bool? {
        return (_values[key] as? NSNumber)?.boolValue
    }

    func _get(_ key: URLResourceKey) -> Int? {
        return (_values[key] as? NSNumber)?.integerValue
    }

    private mutating func _set(_ key: URLResourceKey, newValue: __owned Any?) {
        _keys.insert(key)
        _values[key] = newValue
    }

    private mutating func _set(_ key: URLResourceKey, newValue: String?) {
        _keys.insert(key)
        _values[key] = newValue as NSString?
    }

    private mutating func _set(_ key: URLResourceKey, newValue: Bool?) {
        _keys.insert(key)
        if let value = newValue {
            _values[key] = NSNumber(bool: value)
        } else {
            _values[key] = nil
        }
    }

    public var allValues: [URLResourceKey: Any] {
        return _values
    }

    public var name: String? {
        get { return _get(.nameKey) }
        set { _set(.nameKey, newValue: newValue) }
    }

    public var localizedName: String? { return _get(.localizedNameKey) }

    public var isRegularFile: Bool? { return _get(.isRegularFileKey) }

    public var isDirectory: Bool? { return _get(.isDirectoryKey) }

    public var isSymbolicLink: Bool? { return _get(.isSymbolicLinkKey) }

    public var isPackage: Bool? {
        get { return _get(.isPackageKey) }
        set { _set(.isPackageKey, newValue: newValue) }
    }

    public var typeIdentifier: String? { return _get(.typeIdentifierKey) }

    public var fileSize: Int? { return _get(.fileSizeKey) }
}

extension URL {
    public func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
        var error: NSError?
        guard let values = SFURLReadResourceValues(_bridgeToObjectiveC(), Array(keys), &error) else {
            if let error { throw error }
            throw SFURLResourceReaderFailure.backendReturnedNoError
        }
        return URLResourceValues(keys: keys, values: values)
    }
}

public enum SFURLResourceReaderFailure: Error {
    case backendReturnedNoError
}

extension NSURLResourceKey {
    public static var nameKey: Self { Self(rawValue: "NSURLNameKey") }
    public static var localizedNameKey: Self { Self(rawValue: "NSURLLocalizedNameKey") }
    public static var isRegularFileKey: Self { Self(rawValue: "NSURLIsRegularFileKey") }
    public static var isDirectoryKey: Self { Self(rawValue: "NSURLIsDirectoryKey") }
    public static var isSymbolicLinkKey: Self { Self(rawValue: "NSURLIsSymbolicLinkKey") }
    public static var isPackageKey: Self { Self(rawValue: "NSURLIsPackageKey") }
    public static var typeIdentifierKey: Self { Self(rawValue: "NSURLTypeIdentifierKey") }
    public static var fileSizeKey: Self { Self(rawValue: "NSURLFileSizeKey") }
    public static var contentTypeKey: Self { Self(rawValue: "NSURLContentTypeKey") }
    public static var contentModificationDateKey: Self { Self(rawValue: "NSURLContentModificationDateKey") }
    public static var fileResourceIdentifierKey: Self { Self(rawValue: "NSURLFileResourceIdentifierKey") }
    public static var hasHiddenExtensionKey: Self { Self(rawValue: "NSURLHasHiddenExtensionKey") }
    public static var volumeIsLocalKey: Self { Self(rawValue: "NSURLVolumeIsLocalKey") }
    public static var volumeUUIDStringKey: Self { Self(rawValue: "NSURLVolumeUUIDStringKey") }
}
