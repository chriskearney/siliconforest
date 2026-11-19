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

/// Calls the Objective-C method. The Swift property on `Error` is this
/// extension, so using it on the stored `NSError` would recurse.
private func objcLocalizedDescription(_ error: NSError) -> String {
    let selector = Selector(("localizedDescription"))
    guard let value = error.perform(selector)?.takeUnretainedValue() else {
        preconditionFailure("NSError localizedDescription returned nil")
    }
    if let text = value as? String {
        return text
    }
    return String(value as! NSString)
}

/// The pinned `Error.localizedDescription` entry.
///
/// The runtime's default user-info hook is unset in this module, so a plain
/// Swift error would otherwise bridge with no dictionary. Copy the real
/// `LocalizedError` and `CustomNSError` fields onto the Finch keys, then call
/// the real `NSError` method. An error that already has an embedded `NSError`
/// uses that object.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public extension Error {
    var localizedDescription: String {
        // Open the existential the same way a client does. A generic witness
        // call from this extension does not match that ABI.
        let boxed: any Error = self
        if let embedded = boxed._getEmbeddedNSError() as? NSError {
            return objcLocalizedDescription(embedded)
        }
        var info: [String: Any] = [:]
        if let custom = boxed as? CustomNSError {
            for (key, value) in custom.errorUserInfo {
                info[key] = value
            }
        }
        if let localized = boxed as? LocalizedError {
            if let text = localized.errorDescription {
                info[NSLocalizedDescriptionKey] = text
            }
            if let text = localized.failureReason {
                info[NSLocalizedFailureReasonErrorKey] = text
            }
            if let text = localized.recoverySuggestion {
                info[NSLocalizedRecoverySuggestionErrorKey] = text
            }
        }
        let passed: [String: Any]? = info.isEmpty ? nil : info
        guard let error = NSError(domain: boxed._domain, code: boxed._code, userInfo: passed) else {
            preconditionFailure("NSError(domain:code:userInfo:) returned nil for \(boxed._domain) code \(boxed._code)")
        }
        return objcLocalizedDescription(error)
    }
}

#endif
