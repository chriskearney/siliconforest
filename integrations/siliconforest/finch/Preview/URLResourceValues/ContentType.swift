// SPDX-License-Identifier: MIT OR Apache-2.0
// Mined from pinned open Finch UTType.swift; no Apple implementation.
import Foundation

extension URLResourceValues {
  public var contentType: UTType? {
    return allValues[.contentTypeKey] as? UTType
  }
}
