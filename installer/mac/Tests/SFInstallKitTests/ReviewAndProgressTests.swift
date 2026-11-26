// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Testing
import Foundation
@testable import SFAppEngine
@testable import SFCopy
import SFLiveDisk
import SFEngine
import SFInstallKit
import SFFlow
import Combine

@Suite("Preview13: the Confirm summary copy")
struct ReviewCopyTests {
    @Test func installBlocksListMacOSThenEachNewPartition() {
        let b = Copy.Confirm.installBlocks(volume: "Macintosh HD", macOSFrom: 245_000_000_000, macOSTo: 196_000_000_000,
                                          partitions: [.init(role: "root", bytes: 46_000_000_000), .init(role: "stub", bytes: 500_000_000), .init(role: "boot", bytes: 2_500_000_000)])
        #expect(b.map(\.name) == ["macOS (Macintosh HD)", "SiliconForest launcher", "SiliconForest boot", "SiliconForest system"])
        #expect(b[0].change == "Shrinks from 245 GB to 196 GB." && b[0].detail == "Your files stay.")
        #expect(b[1].change == "New, 500 MB.")
        #expect(b[2].change == "New, 2.5 GB.")
        #expect(b[3].change == "New, 46 GB.")
        #expect(b.dropFirst().allSatisfy { $0.detail == nil })
    }

    @Test func removeBlocksGrowMacOSBackAndDeleteOurs() {
        let b = Copy.Confirm.removeBlocks(volume: "Macintosh HD", macOSFrom: 196_000_000_000, macOSTo: 245_000_000_000, roles: ["root", "boot", "stub"])
        #expect(b.map(\.change) == ["Grows back from 196 GB to 245 GB.", "Deleted.", "Deleted.", "Deleted."])
        #expect(b[0].detail == "Your files stay.")
        #expect(b.map(\.name) == ["macOS (Macintosh HD)", "SiliconForest launcher", "SiliconForest boot", "SiliconForest system"])
    }

    @Test func sizesAndFixedLines() {
        #expect(Copy.Confirm.size(245_000_000_000) == "245 GB")
        #expect(Copy.Confirm.size(2_500_000_000) == "2.5 GB")
        #expect(Copy.Confirm.size(512_000_000) == "512 MB")
        #expect(Copy.Confirm.warning == "Back up your Mac first. This changes your disk.")
        #expect(Copy.Confirm.installHeader == "What will change")
        #expect(Copy.Confirm.installButton(gigabytes: 49) == "Erase 49 GB and Install")
        #expect(Copy.Confirm.removeButton == "Remove SiliconForest")
        #expect(Copy.Confirm.typeName("Macintosh HD") == "Type the name of your macOS volume to confirm: Macintosh HD")
        #expect(Copy.Confirm.footnote(target: "internal disk", version: "0.1.0", stage1: "abcd1234…", plan: "0123456789ab…", removal: false)
                == "Release 0.1.0, signature verified. Stage 1 abcd1234… (pinned v2). Disk: internal disk. Plan 0123456789ab….")
    }

    @Test func noTechnicalWordsOnTheSummary() {
        let all = (Copy.Confirm.installBlocks(volume: "Macintosh HD", macOSFrom: 2, macOSTo: 1, partitions: [.init(role: "stub", bytes: 1), .init(role: "boot", bytes: 1), .init(role: "root", bytes: 1)])
                   + Copy.Confirm.removeBlocks(volume: "Macintosh HD", macOSFrom: 1, macOSTo: 2, roles: ["stub", "boot", "root"]))
            .flatMap { [$0.name, $0.change, $0.detail ?? ""] }.joined(separator: " ").lowercased()
        for word in ["apple_apfs", "efi", "linux filesystem", "gpt", "partition"] { #expect(!all.contains(word), "\(word)") }
    }
}

@Suite("Preview13: the download row")
struct FetchProgressTests {
    private func t(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    @Test func theTotalIsFixedAndTheCountNeverGoesBack() {
        let m = FetchProgressSmoother(interval: 0)
        #expect(m.accept(file: "SHA256SUMS", done: 0, total: 0, bytes: 0, now: t(0))?.isDeterminate == false)
        let a = m.accept(file: "a", done: 0, total: 133, bytes: 0, now: t(1))!
        #expect(a.filesTotal == 133 && a.isDeterminate)
        // Preview12 passed the loop index as the total (0 of 1, 0 of 2 …). A changed total is ignored.
        let b = m.accept(file: "b", done: 3, total: 4, bytes: 100, now: t(2))!
        #expect(b.filesTotal == 133 && b.filesDone == 3)
        let c = m.accept(file: "c", done: 1, total: 133, bytes: 50, now: t(3))!
        #expect(c.filesDone == 3 && c.bytes == 100, "monotonic")
        let d = m.accept(file: "d", done: 500, total: 133, bytes: 0, now: t(4))!
        #expect(d.filesDone == 133 && d.isFinished)
    }

    @Test func updatesAreLimitedToAboutFourASecond() {
        let m = FetchProgressSmoother(interval: 0.25)
        var shown = 0
        for i in 0..<100 { if m.accept(file: "f", done: Int64(i), total: 1000, bytes: Int64(i), now: t(Double(i) * 0.01)) != nil { shown += 1 } }
        #expect(shown >= 3 && shown <= 5, "100 events in one second: \(shown)")
        // The last file always gets through.
        #expect(m.accept(file: "z", done: 1000, total: 1000, bytes: 9, now: t(1.01))?.isFinished == true)
    }

    @Test func theLabelIsIndeterminateUntilTheTotalIsKnown() {
        #expect(Copy.Download.label(done: 0, total: 0, bytes: 0) == "Downloading…")
        #expect(Copy.Download.label(done: 0, total: 0, bytes: 41_000_000) == "Downloading… 41 MB")
        #expect(Copy.Download.label(done: 7, total: 133, bytes: 41_000_000) == "7 of 133 files")
        #expect(Copy.Download.label(done: 133, total: 133, bytes: 1) == "Verifying…")
        #expect(FetchProgress(file: "", filesDone: 7, filesTotal: 0, bytes: 0).fraction == nil)
        #expect(FetchProgress(file: "", filesDone: 7, filesTotal: 14, bytes: 0).fraction == 0.5)
    }

    @Test func theFetcherReportsAFixedTotalFromTheFirstCall() async throws {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("p13-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: src) }
        var lines = ""
        for n in ["a", "b", "c"] {
            let d = Data(n.utf8); try d.write(to: src.appendingPathComponent(n))
            lines += "\(SHA256Hasher.hex(d))  \(n)\n"
        }
        try Data(lines.utf8).write(to: src.appendingPathComponent("SHA256SUMS"))
        try Data("sig".utf8).write(to: src.appendingPathComponent("SHA256SUMS.sig"))
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("p13c-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cache) }
        let seen = Locked<[(String, Int64, Int64, Int64)]>([])
        // The signature check fails afterwards (no signer): only the progress events matter here.
        _ = try? await ReleaseFetcher(cache: cache).fetch(.folder(src)) { f, d, t, b in seen.mutate { $0.append((f, d, t, b)) } }
        let events = seen.value
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.2 == 3 }, "the total never changes: \(events)")
        var last: Int64 = 0
        for e in events { #expect(e.1 >= last); last = e.1 }
        #expect(events.last?.1 == 3 && events.last?.3 == 3)
    }
}

final class Locked<T>: @unchecked Sendable {
    private let l = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    var value: T { l.lock(); defer { l.unlock() }; return v }
    func mutate(_ f: (inout T) -> Void) { l.lock(); f(&v); l.unlock() }
}

@Suite("Preview13: the step list follows the active step")
struct ScrollFollowTests {
    private func t(_ s: Double) -> Date { Date(timeIntervalSinceReferenceDate: s) }

    @Test func scrollsWhenTheActiveRowChangesNotOnEveryTick() {
        var f = ScrollFollow()
        do { let r = f.activeChanged(to: 3, now: t(0)); #expect(r) }
        do { let r = f.activeChanged(to: 3, now: t(1)); #expect(!r, "same row: no scroll") }
        do { let r = f.activeChanged(to: 4, now: t(2)); #expect(r) }
    }

    @Test func throttlesToAboutFourASecond() {
        var f = ScrollFollow(minInterval: 0.25)
        do { let r = f.activeChanged(to: 1, now: t(0)); #expect(r) }
        do { let r = f.activeChanged(to: 2, now: t(0.1)); #expect(!r, "too soon") }
        do { let r = f.activeChanged(to: 3, now: t(0.4)); #expect(r) }
    }

    @Test func scrollingAwayPausesAndANewStepOrComingBackResumes() {
        var f = ScrollFollow(minInterval: 0.25, settle: 0.8)
        _ = f.activeChanged(to: 5, now: t(0))
        f.rowDisappeared(5, now: t(0.3))
        #expect(!f.paused, "our own scroll just happened")
        f.rowAppeared(5)
        f.rowDisappeared(5, now: t(5))
        #expect(f.paused, "the person scrolled away")
        f.rowAppeared(5)
        #expect(!f.paused, "they scrolled back to the active row")
        f.rowDisappeared(5, now: t(9))
        #expect(f.paused)
        do { let r = f.activeChanged(to: 6, now: t(10)); #expect(r) }
        #expect(!f.paused, "a new step starts: follow again")
        f.rowDisappeared(4, now: t(11))
        #expect(!f.paused, "other rows don't matter")
    }
}

@Suite("Preview13: the footer follows the confirmation field")
@MainActor
struct FooterInvalidationTests {
    @Test func typingInTheConfirmationFieldInvalidatesTheSession() throws {
        let f = try DiskFixture.named("j293-512")
        let s = Session(live: LiveInstallController { throw NSError(domain: "test", code: 1) }, origin: .github(tag: "installer-v0.0.0-test"),
                        backend: SimulatedDiskBackend(fixture: f, timeScale: 0, failures: []))
        let live = try #require(s.live)
        live.resumeExpected = TypedConfirmation(diskName: "Macintosh HD")
        var changes = 0
        let bag = s.objectWillChange.sink { _ in changes += 1 }
        defer { bag.cancel() }
        #expect(!live.typedMatches)
        live.typedName = "macintosh  hd "
        #expect(changes >= 1, "the footer observes the Session, so LiveRun's change must reach it")
        #expect(live.typedMatches, "case and spacing are forgiven")
        live.typedName = "Macintosh"
        #expect(!live.typedMatches)
    }
}
