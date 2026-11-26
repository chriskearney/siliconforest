// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// The buttons that send the person to a macOS settings pane (preview8). "Open Storage Settings" did nothing in
// preview7 (its action was empty). Each place has an ordered list of URLs: the first one macOS accepts wins, and the
// last entry is always the System Settings (or Disk Utility) app itself, so a pane id that a macOS version doesn't
// know still lands the person somewhere useful. Nothing here changes any setting.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum SystemLinks {
    public enum Place: Sendable, CaseIterable {
        case storageSettings, softwareUpdate, diskUtility, supportedMacs

        /// The URLs to try, in order.
        public var candidates: [URL] {
            func u(_ s: String) -> URL { URL(string: s)! }
            switch self {
            case .storageSettings:
                return [u("x-apple.systempreferences:com.apple.settings.Storage"),               // macOS 13 and later
                        u("x-apple.systempreferences:com.apple.settings.General"),                // the General pane, if Storage's id isn't known
                        URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                        URL(fileURLWithPath: "/System/Applications/System Preferences.app")]
            case .softwareUpdate:
                return [u("x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
                        u("x-apple.systempreferences:com.apple.preferences.softwareupdate"),
                        URL(fileURLWithPath: "/System/Applications/System Settings.app")]
            case .diskUtility:
                return [URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")]
            case .supportedMacs:
                return [u("https://github.com/chriskearney/siliconforest#readme")]
            }
        }
    }

    /// The titles of the check screen's buttons that go somewhere outside the installer (see `Copy.Check`).
    public static func place(forButton title: String) -> Place? {
        switch title {
        case "Open Storage Settings": return .storageSettings
        case "Open Software Update": return .softwareUpdate
        case "Open Disk Utility": return .diskUtility
        case "See Supported Macs", "Learn More": return .supportedMacs
        default: return nil
        }
    }

    #if canImport(AppKit)
    public nonisolated(unsafe) static var opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    #else
    public nonisolated(unsafe) static var opener: (URL) -> Bool = { _ in false }
    #endif

    /// Opens the first candidate the system accepts. Returns the one that opened, or nil if none did.
    @discardableResult
    public static func open(_ place: Place, using open: ((URL) -> Bool)? = nil) -> URL? {
        let go = open ?? opener
        for url in place.candidates {
            // A file URL for an app that isn't on this macOS is skipped rather than handed to the opener.
            if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) { continue }
            if go(url) { return url }
        }
        return nil
    }
}
