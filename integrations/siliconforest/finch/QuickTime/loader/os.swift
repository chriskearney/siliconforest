// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The Swift `os` module, reduced to Logger's creation: enough for a program that keeps a
// Logger. The log object is libSystem's own (os_log_create), so anything logged through
// it reaches the system log as any os_log call does. Written from the public API
// documentation of os.Logger.
import Foundation

@_silgen_name("os_log_create")
internal func _sf_os_log_create(_ subsystem: UnsafePointer<CChar>, _ category: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

public struct Logger: @unchecked Sendable {
  internal var logObject: UnsafeMutableRawPointer?

  public init(subsystem: String, category: String) {
    self.logObject = subsystem.withCString { s in
      category.withCString { c in _sf_os_log_create(s, c) }
    }
  }

  public init() {
    self.logObject = nil
  }
}
