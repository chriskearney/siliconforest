import Foundation
import Testing
import SFAppEngine

/// Preview8: "Open Storage Settings" used to do nothing. These check which URL each button opens and the fallbacks.
@Suite("System links: the check screen's buttons open something")
struct SystemLinksTests {
    @Test func storageSettingsOpensTheStoragePaneFirst() {
        var tried: [String] = []
        let opened = SystemLinks.open(.storageSettings) { u in tried.append(u.absoluteString); return true }
        #expect(opened?.absoluteString == "x-apple.systempreferences:com.apple.settings.Storage")
        #expect(tried == ["x-apple.systempreferences:com.apple.settings.Storage"])
    }

    @Test func fallsBackWhenThePaneIdIsNotKnown() {
        var tried: [String] = []
        let opened = SystemLinks.open(.storageSettings) { u in
            tried.append(u.absoluteString)
            return u.absoluteString == "x-apple.systempreferences:com.apple.settings.General" || u.isFileURL
        }
        #expect(opened?.absoluteString == "x-apple.systempreferences:com.apple.settings.General")
        #expect(tried.count == 2)
    }

    @Test func aFileUrlForAMissingAppIsSkipped() {
        var tried: [URL] = []
        _ = SystemLinks.open(.diskUtility) { u in tried.append(u); return true }
        // Disk Utility exists on every Mac; on a box without it the opener is never handed a missing path.
        for u in tried where u.isFileURL { #expect(FileManager.default.fileExists(atPath: u.path)) }
    }

    @Test func returnsNilWhenNothingOpens() {
        #expect(SystemLinks.open(.storageSettings) { _ in false } == nil)
    }

    @Test func everyExternalButtonTitleMapsToAPlace() {
        #expect(SystemLinks.place(forButton: "Open Storage Settings") == .storageSettings)
        #expect(SystemLinks.place(forButton: "Open Software Update") == .softwareUpdate)
        #expect(SystemLinks.place(forButton: "Open Disk Utility") == .diskUtility)
        #expect(SystemLinks.place(forButton: "See Supported Macs") == .supportedMacs)
        #expect(SystemLinks.place(forButton: "Check Again") == nil)
        for p in SystemLinks.Place.allCases { #expect(!p.candidates.isEmpty) }
        #expect(SystemLinks.Place.storageSettings.candidates.first?.absoluteString == "x-apple.systempreferences:com.apple.settings.Storage")
    }
}
