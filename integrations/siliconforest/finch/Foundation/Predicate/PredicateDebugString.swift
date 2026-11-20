// SPDX-License-Identifier: Apache-2.0 WITH Runtime Library Exception
// Package description protocol from pinned Predicate+Description.swift.
// That file's formatter calls String.replacing, which this overlay does not
// provide, and it also names expression types outside this slice. Evaluation
// does not read this state. The protocol lets the pinned LocalizedString.swift
// debug extensions compile unchanged.

@available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
package struct DebugStringConversionState {}

@available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
package protocol DebugStringConvertiblePredicateExpression : StandardPredicateExpression {
    func debugString(state: inout DebugStringConversionState) -> String
}
