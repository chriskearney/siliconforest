//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if FOUNDATION_FRAMEWORK

/// A stored NSError bridge. `Code` is the numeric code inside `_nsErrorDomain`.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol _BridgedStoredNSError: Error, CustomNSError {
    associatedtype Code: RawRepresentable where Code.RawValue: FixedWidthInteger
    static var _nsErrorDomain: String { get }
    var _nsError: NSError { get }
    init(_nsError error: NSError)
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension _BridgedStoredNSError {
    /// AppIntents calls this protocol-extension initializer directly.
    public init(_ code: Code, userInfo: [String: Any] = [:]) {
        guard let error = NSError(domain: Self._nsErrorDomain, code: Int(code.rawValue), userInfo: userInfo) else {
            preconditionFailure("NSError(domain:code:userInfo:) returned nil for \(Self._nsErrorDomain) code \(Int(code.rawValue))")
        }
        self.init(_nsError: error)
    }

    public static var errorDomain: String { _nsErrorDomain }

    public var errorCode: Int { _nsError.code() }

    public var errorUserInfo: [String: Any] {
        guard let info = _nsError.userInfo() else { return [:] }
        var copy: [String: Any] = [:]
        for (key, value) in info {
            guard let key = key as? String else { continue }
            copy[key] = value
        }
        return copy
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Error where Self: _BridgedStoredNSError {
    public var _domain: String { _nsError.domain() ?? "" }
    public var _code: Int { _nsError.code() }
    public var _userInfo: AnyObject? {
        guard let info = _nsError.userInfo() else { return nil }
        return NSDictionary(dictionary: info)
    }
    public func _getEmbeddedNSError() -> AnyObject? { _nsError }
}

/// An error in `NSURLErrorDomain`. Codes match the retained NSURLSession header.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct URLError: _BridgedStoredNSError, Hashable {
    public let _nsError: NSError

    public init(_nsError error: NSError) {
        let domain = error.domain() ?? ""
        precondition(domain == Self._nsErrorDomain, "URLError domain is \(Self._nsErrorDomain), got \(domain)")
        self._nsError = error
    }

    public static var _nsErrorDomain: String { NSURLErrorDomain }

    public struct Code: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static var unknown: Code { Code(rawValue: NSURLErrorUnknown) }
        public static var cancelled: Code { Code(rawValue: NSURLErrorCancelled) }
        public static var badURL: Code { Code(rawValue: NSURLErrorBadURL) }
        public static var timedOut: Code { Code(rawValue: NSURLErrorTimedOut) }
        public static var unsupportedURL: Code { Code(rawValue: NSURLErrorUnsupportedURL) }
        public static var cannotFindHost: Code { Code(rawValue: NSURLErrorCannotFindHost) }
        public static var cannotConnectToHost: Code { Code(rawValue: NSURLErrorCannotConnectToHost) }
        public static var networkConnectionLost: Code { Code(rawValue: NSURLErrorNetworkConnectionLost) }
        public static var httpTooManyRedirects: Code { Code(rawValue: NSURLErrorHTTPTooManyRedirects) }
        public static var notConnectedToInternet: Code { Code(rawValue: NSURLErrorNotConnectedToInternet) }
        public static var zeroByteResource: Code { Code(rawValue: NSURLErrorZeroByteResource) }
        public static var fileDoesNotExist: Code { Code(rawValue: NSURLErrorFileDoesNotExist) }
        public static var fileIsDirectory: Code { Code(rawValue: NSURLErrorFileIsDirectory) }
        public static var noPermissionsToReadFile: Code { Code(rawValue: NSURLErrorNoPermissionsToReadFile) }
        public static var secureConnectionFailed: Code { Code(rawValue: NSURLErrorSecureConnectionFailed) }
        public static var serverCertificateUntrusted: Code { Code(rawValue: NSURLErrorServerCertificateUntrusted) }
    }

    public var code: Code { Code(rawValue: _nsError.code()) }

    public var failingURL: URL? {
        let info = errorUserInfo
        if let url = info[NSURLErrorFailingURLErrorKey] as? URL { return url }
        if let text = info[NSURLErrorFailingURLStringErrorKey] as? String { return URL(string: text) }
        return nil
    }

    public static func == (lhs: URLError, rhs: URLError) -> Bool {
        let leftDomain = lhs._nsError.domain() ?? ""
        let rightDomain = rhs._nsError.domain() ?? ""
        return leftDomain == rightDomain
            && lhs._nsError.code() == rhs._nsError.code()
            && sameUserInfo(lhs._nsError, rhs._nsError)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_nsError.domain() ?? "")
        hasher.combine(_nsError.code())
        if let info = _nsError.userInfo() {
            hasher.combine(NSDictionary(dictionary: info).hash)
        } else {
            hasher.combine(0)
        }
    }

    private static func sameUserInfo(_ lhs: NSError, _ rhs: NSError) -> Bool {
        switch (lhs.userInfo(), rhs.userInfo()) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return NSDictionary(dictionary: left).isEqual(NSDictionary(dictionary: right))
        default:
            return false
        }
    }
}

#endif
