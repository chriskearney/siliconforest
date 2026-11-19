//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// _sfJSONEncoderCast derives from the pinned Collection Stdlib Defaults.swift
// _specializingCast helper. Use a checked standard cast after metatype equality.
// SiliconForest adds the scoped CoreFoundation Unicode adapter and error below.
import CoreFoundation

public enum SFJSONEncoderUnavailable: Error { case iso8601DateStrategy }

@inline(__always)
internal func _sfJSONEncoderCast<Input, Output>(_ value: Input, to type: Output.Type) -> Output? {
    guard Input.self == Output.self else { return nil }
    return value as? Output
}

internal func _sfJSONEncoderCaseRange(_ text: Substring, uppercase: Bool) -> Range<String.Index>? {
    let set = CFCharacterSetGetPredefined(uppercase ? .uppercaseLetter : .lowercaseLetter)
    let scalars = text.unicodeScalars
    guard let index = scalars.firstIndex(where: { CFCharacterSetIsLongCharacterMember(set, $0.value) }) else { return nil }
    return index..<scalars.index(after: index)
}
