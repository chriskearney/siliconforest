// SPDX-License-Identifier: MIT
// Headless client for the scoped TipKit provider. It calls configure, donate,
// parameter storage, a closure rule, invalidation, MaxDisplayCount, and a
// Comparison of two Values through the event Rule initializer.
// It does not call popoverTip or a key-path expression.

import Foundation
import SwiftUI
import TipKit

struct RuleTip: Tip {
    static let opened = Tips.Event<Tips.EmptyDonation>(id: "openedConverter")
    static let isPro = Tips.Parameter(RuleTip.self, "isPro", false)
    var title: Text { Text(verbatim: "Convert units") }
    var rules: [Tips.Rule] {
        Tips.Rule { RuleTip.opened.donations.count >= 2 && RuleTip.isPro.wrappedValue }
    }
    var actions: [Tips.Action] { [Tips.Action(title: "Go")] }
}

struct CapTip: Tip {
    var title: Text { Text(verbatim: "Cap") }
    var options: [any TipOption] { Tips.MaxDisplayCount(1) }
}

struct OpenTip: Tip {
    var title: Text { Text(verbatim: "Open") }
    var rules: [Tips.Rule] { Tips.Rule { true } }
}

struct PredTrueTip: Tip {
    static let event = Tips.Event<Tips.EmptyDonation>(id: "pred-true")
    var title: Text { Text(verbatim: "Pred true") }
    var rules: [Tips.Rule] {
        Tips.Rule(PredTrueTip.event) { _ in
            PredicateExpressions.Comparison(
                lhs: PredicateExpressions.Value(1),
                rhs: PredicateExpressions.Value(2),
                op: .lessThan)
        }
    }
}

struct PredFalseTip: Tip {
    static let event = Tips.Event<Tips.EmptyDonation>(id: "pred-false")
    var title: Text { Text(verbatim: "Pred false") }
    var rules: [Tips.Rule] {
        Tips.Rule(PredFalseTip.event) { _ in
            PredicateExpressions.Comparison(
                lhs: PredicateExpressions.Value(2),
                rhs: PredicateExpressions.Value(1),
                op: .lessThan)
        }
    }
}

final class NoteCount {
    var value = 0
}

@main
struct TipKitProbe {
    static func main() async {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory(), isDirectory: true)
        let notes = NoteCount()
        guard let center = NotificationCenter.default() else { fail("no center") }
        let token = center.addObserver(forName: "FinchTipKitChanged", object: nil, queue: nil) { _ in
            notes.value += 1
        }
        let rule = RuleTip()
        let cap = CapTip()
        let waiting = TipGroup(.ordered) { rule; OpenTip() }
        let first = TipGroup(.firstAvailable) { rule; OpenTip() }
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.url(root)),
            ])
            try Tips.configure()
        } catch {
            fail("configure \(error)")
        }
        guard rule.status == .pending, rule.shouldDisplay == false, RuleTip.opened.donations.count == 0 else {
            fail("initial \(rule.status) \(RuleTip.opened.donations.count)")
        }
        await RuleTip.opened.donate()
        guard RuleTip.opened.donations.count == 1, rule.status == .pending else {
            fail("one \(RuleTip.opened.donations.count) \(rule.status)")
        }
        await RuleTip.opened.donate()
        guard RuleTip.opened.donations.count == 2, rule.status == .pending else {
            fail("two \(RuleTip.opened.donations.count) \(rule.status)")
        }
        guard await waiting.currentTip == nil, await first.currentTip?.id == "OpenTip" else {
            fail("group-before \(await waiting.currentTip?.id ?? "nil") \(await first.currentTip?.id ?? "nil")")
        }
        RuleTip.isPro.wrappedValue = true
        guard rule.status == .available, rule.shouldDisplay, rule.id == "RuleTip" else {
            fail("pro \(rule.status) \(rule.shouldDisplay) \(rule.id)")
        }
        guard await waiting.currentTip?.id == "RuleTip", await first.currentTip?.id == "RuleTip" else {
            fail("group-pro \(await waiting.currentTip?.id ?? "nil") \(await first.currentTip?.id ?? "nil")")
        }
        rule.invalidate(reason: .tipClosed)
        guard case .invalidated(.tipClosed) = rule.status else { fail("closed \(rule.status)") }
        guard await waiting.currentTip?.id == "OpenTip", await first.currentTip?.id == "OpenTip" else {
            fail("group-after \(await waiting.currentTip?.id ?? "nil") \(await first.currentTip?.id ?? "nil")")
        }
        guard cap.status == .available else { fail("cap-before \(cap.status)") }
        cap.noteDisplayed()
        guard case .invalidated(.displayCountExceeded) = cap.status else { fail("cap-after \(cap.status)") }
        guard rule.actions.count == 1, cap.options.count == 1 else {
            fail("counts \(rule.actions.count) \(cap.options.count)")
        }
        let predTrue = PredTrueTip()
        let predFalse = PredFalseTip()
        guard predTrue.status == .available else { fail("pred-true \(predTrue.status)") }
        guard predFalse.status == .pending else { fail("pred-false \(predFalse.status)") }
        guard notes.value >= 6 else { fail("notify \(notes.value)") }
        let file = root.appendingPathComponent("FinchTipKit.json")
        guard let raw = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: raw),
              decoded.keys.contains(where: { $0.hasPrefix("event.") }),
              decoded.keys.contains(where: { $0.hasPrefix("parameter.") })
        else { fail("file missing") }
        center.removeObserver(token)
        print("configured-twice ok")
        print("donations 2")
        print("pro available")
        print("closed invalidated")
        print("cap invalidated")
        print("actions 1")
        print("group ordered")
        print("notify \(notes.value)")
        print("file keys \(decoded.count)")
        print("predicate comparison true")
        print("predicate comparison false")
        print("tipkit-scoped-behavior-passed")
    }

    static func fail(_ message: String) -> Never {
        fputs("tipkit-scoped-behavior-failed \(message)\n", stderr)
        exit(1)
    }
}
