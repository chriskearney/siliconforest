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

/// Describes an error that provides localized messages describing why
/// an error occurred and provides more information about the error.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol LocalizedError : Error {
    /// A localized message describing what error occurred.
    var errorDescription: String? { get }

    /// A localized message describing the reason for the failure.
    var failureReason: String? { get }

    /// A localized message describing how one might recover from the failure.
    var recoverySuggestion: String? { get }

    /// A localized message providing "help" text if the user requests help.
    var helpAnchor: String? { get }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public extension LocalizedError {
    var errorDescription: String? { return nil }
    var failureReason: String? { return nil }
    var recoverySuggestion: String? { return nil }
    var helpAnchor: String? { return nil }
}

/// Describes an error type that specifically provides a domain, code,
/// and user-info dictionary.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public protocol CustomNSError : Error {
    /// The domain of the error.
    static var errorDomain: String { get }

    /// The error code within the given domain.
    var errorCode: Int { get }

    /// The user-info dictionary.
    var errorUserInfo: [String : Any] { get }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public extension CustomNSError {
    /// Default domain of the error.
    static var errorDomain: String {
        return _typeName(self, qualified: true)
    }

    /// The error code within the given domain.
    var errorCode: Int {
        return _getDefaultErrorCode(self)
    }

    /// The default user-info dictionary.
    var errorUserInfo: [String : Any] {
        return [:]
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public extension Error where Self : CustomNSError {
    /// Default implementation for customized NSErrors.
    var _domain: String { return Self.errorDomain }

    /// Default implementation for customized NSErrors.
    var _code: Int { return self.errorCode }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public extension Error where Self: CustomNSError, Self: RawRepresentable, Self.RawValue: FixedWidthInteger {
    /// Default implementation for customized NSErrors.
    var _code: Int { return self.errorCode }
}
