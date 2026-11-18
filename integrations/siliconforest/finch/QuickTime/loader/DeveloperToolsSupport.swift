// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// DeveloperToolsSupport, reduced to the asset-catalogue resource names that generated
// asset symbols create. A resource is a name and the bundle whose catalogue holds it;
// looking the image up is the user-interface framework's business. Written from the
// public API documentation; the Finch project has the fuller framework.
import Foundation

public struct ImageResource: Hashable, @unchecked Sendable {
  public let name: String
  public let bundle: Bundle

  public init(name: String, bundle: Bundle) {
    self.name = name
    self.bundle = bundle
  }
}

public struct ColorResource: Hashable, @unchecked Sendable {
  public let name: String
  public let bundle: Bundle

  public init(name: String, bundle: Bundle) {
    self.name = name
    self.bundle = bundle
  }
}
