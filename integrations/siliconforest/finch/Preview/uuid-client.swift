// SPDX-License-Identifier: MIT
// A separate library exercises real Foundation UUID ABI/value boundaries.
import Foundation
public func makeUUID() -> UUID { UUID() }
public func parseUUID(_ value: String) -> UUID? { UUID(uuidString: value) }
public func canonicalUUID(_ value: UUID) -> String { value.uuidString }
public func copyUUID(_ value: UUID) -> UUID { value }
