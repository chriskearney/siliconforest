// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scoped TipKit derived from The Finch Project, revision
// 2d9b1bb1af57e14462e4621d194929188a8845b0, userland/TipKit/TipKit.swift
// (SHA-256 8f972e83bb877fbc9664a74f38b0760a94112dc8bb8cb9f7c25dafa38e05405f).
// Copyright (c) 2026 The Finch Project contributors.
//
// Kept: JSON datastore, configure, events, donations, parameters, closure and
// compound rules, MaxDisplayCount, MaxDisplayDuration, invalidation, and the
// Tip requirements that name SwiftUI.Text and SwiftUI.Image.
//
// Predicate rules compile against the tested p9 Foundation module
// (libswiftFoundation aa7de512, swiftmodule 8ad0dda8). That image supplies
// PredicateExpressions. The four EventPredicateExpression conformances and
// the event Rule initializer are real TipKit symbols. Equal conforms too;
// p9 has no NotEqual, so that Finch conformance is not declared.
// A thrown predicate error, including undefinedVariable, becomes false
// because the rule uses try?. SwiftUI.View.popoverTip is still absent:
// this build does not use the M6 SwiftUI runtime.
// TipViews.swift is not compiled. CloudKit is accepted and ignored, as in Finch.
// displayFrequency is stored and not read by status(), as in Finch.
// Group containers throw: this Foundation has no containerURL.
// Notifications post on the calling thread: the Darwin Dispatch overlay has
// no DispatchQueue, so Finch's main-queue async hop is unavailable.
// @Parameter and #Rule are not in the Finch sources. Parameter is a stored
// wrapper with wrappedValue; callers construct it explicitly.
//
// TipGroup uses the real @Observable macro from the host plugin
// libObservationMacros.so and the Darwin Observation module. Preview's 42
// TipKit imports still do not name TipGroup. currentTipUpdates is omitted:
// Finch delivers it on OperationQueue.main, and this Foundation has no
// DispatchQueue and no proven main queue.

import Foundation
import Observation
import SwiftUI

@frozen
public enum Tips {}

extension Tips: @unchecked Sendable {}

final class TipStore: @unchecked Sendable {
    static let shared = TipStore()
    static let changedName = "FinchTipKitChanged"

    private let lock: NSLock = NSLock()!
    var configured = false
    var showAllForTesting: Bool?
    var shownForTesting: Set<String> = []
    var hiddenForTesting: Set<String> = []
    var displayFrequency: Tips.ConfigurationOption.DisplayFrequency = .immediate
    private var records: [String: Data]?
    private var location: URL?

    static var defaultLocation: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tipkit-default")
    }

    private var directory: URL { location ?? Self.defaultLocation }

    private var file: URL {
        directory.appendingPathComponent("FinchTipKit.json")
    }

    /// This Foundation FileManager has removeItem(atPath:) and no createDirectory.
    /// mkdir is the Darwin call that actually creates the datastore directory.
    private func ensureDirectory(_ url: URL) {
        var built = ""
        for part in url.path.split(separator: "/") {
            built += "/" + part
            _ = built.withCString { mkdir($0, 0o755) }
        }
    }

    func use(_ directory: URL?) {
        lock.lock()
        location = directory
        records = nil
        lock.unlock()
    }

    private func loaded() -> [String: Data] {
        if let records { return records }
        let decoded = (try? Data(contentsOf: file)).flatMap {
            try? JSONDecoder().decode([String: Data].self, from: $0)
        } ?? [:]
        records = decoded
        return decoded
    }

    private func write() {
        guard let records else { return }
        ensureDirectory(directory)
        if let encoded = try? JSONEncoder().encode(records) {
            try? encoded.write(to: file, options: .atomic)
        }
    }

    private func key(_ kind: String, _ id: String) -> String { "\(kind).\(id)" }

    func data(_ kind: String, _ id: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return loaded()[key(kind, id)]
    }

    func setData(_ data: Data?, _ kind: String, _ id: String) {
        lock.lock()
        var next = loaded()
        next[key(kind, id)] = data
        records = next
        write()
        lock.unlock()
        notify()
    }

    func value<T: Decodable>(_ type: T.Type, _ kind: String, _ id: String) -> T? {
        data(kind, id).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func setValue<T: Encodable>(_ value: T?, _ kind: String, _ id: String) {
        setData(value.flatMap { try? JSONEncoder().encode($0) }, kind, id)
    }

    func notify() {
        if let center = NotificationCenter.default() {
            center.postNotificationName(TipStore.changedName, object: nil)
        }
    }

    func reset() {
        lock.lock()
        records = [:]
        try? FileManager.default.removeItem(atPath: file.path)
        lock.unlock()
        notify()
    }

    var datastoreFile: URL {
        lock.lock()
        defer { lock.unlock() }
        return file
    }
}

extension Tips {
    public struct ConfigurationOption: Sendable {
        enum Kind: Sendable {
            case cloudKit
            case datastore(DatastoreLocation)
            case displayFrequency(DisplayFrequency)
        }
        var kind: Kind

        public static func cloudKitContainer(_ cloudKitContainer: CloudKitContainer?) -> ConfigurationOption {
            ConfigurationOption(kind: .cloudKit)
        }

        public struct CloudKitContainer: Equatable, Sendable {
            var name: String?
            public static var automatic: CloudKitContainer { CloudKitContainer(name: nil) }
            public static func named(_ containerName: String) -> CloudKitContainer { CloudKitContainer(name: containerName) }
        }

        public static func datastoreLocation(_ storeLocation: DatastoreLocation) -> ConfigurationOption {
            ConfigurationOption(kind: .datastore(storeLocation))
        }

        public struct DatastoreLocation: Equatable, Sendable {
            var url: URL?
            var group: String?
            public static var applicationDefault: DatastoreLocation { DatastoreLocation() }
            public static func groupContainer(identifier: String) throws -> DatastoreLocation {
                throw TipKitError.missingGroupContainerEntitlements
            }
            public static func url(_ url: URL) -> DatastoreLocation { DatastoreLocation(url: url) }
        }

        public static func displayFrequency(_ displayFrequency: DisplayFrequency) -> ConfigurationOption {
            ConfigurationOption(kind: .displayFrequency(displayFrequency))
        }

        public struct DisplayFrequency: Equatable, Sendable {
            var interval: TimeInterval
            public static var immediate: DisplayFrequency { DisplayFrequency(interval: 0) }
            public static var hourly: DisplayFrequency { DisplayFrequency(interval: 3600) }
            public static var daily: DisplayFrequency { DisplayFrequency(interval: 86400) }
            public static var weekly: DisplayFrequency { DisplayFrequency(interval: 7 * 86400) }
            public static var monthly: DisplayFrequency { DisplayFrequency(interval: 30 * 86400) }
        }
    }

    public static func configure(_ configuration: [ConfigurationOption] = []) throws {
        let store = TipStore.shared
        if store.configured { return }
        for option in configuration {
            switch option.kind {
            case .datastore(let location):
                if location.group != nil {
                    throw TipKitError.missingGroupContainerEntitlements
                }
                if let url = location.url {
                    store.use(url)
                }
            case .displayFrequency(let frequency):
                store.displayFrequency = frequency
            case .cloudKit:
                break
            }
        }
        store.configured = true
        store.notify()
    }

    public static func resetDatastore() throws {
        TipStore.shared.reset()
    }

    public static var datastoreFileForTesting: URL { TipStore.shared.datastoreFile }

    public static func showAllTipsForTesting() {
        TipStore.shared.showAllForTesting = true
        TipStore.shared.notify()
    }

    public static func showTipsForTesting(_ tips: [any Tip.Type]) {
        TipStore.shared.shownForTesting.formUnion(tips.map { String(reflecting: $0) })
        TipStore.shared.notify()
    }

    public static func hideAllTipsForTesting() {
        TipStore.shared.showAllForTesting = false
        TipStore.shared.notify()
    }

    public static func hideTipsForTesting(_ tips: [any Tip.Type]) {
        TipStore.shared.hiddenForTesting.formUnion(tips.map { String(reflecting: $0) })
        TipStore.shared.notify()
    }
}

public struct TipKitError: Error, Hashable {
    var code: Int
    public var description: String {
        switch code {
        case 1: "The value given to a tips predicate isn't of a supported type."
        case 2: "Group containers are unavailable: Foundation has no container URL."
        default: "Tips has already been configured."
        }
    }
    public static let invalidPredicateValueType = TipKitError(code: 1)
    public static let missingGroupContainerEntitlements = TipKitError(code: 2)
    public static let tipsDatastoreAlreadyConfigured = TipKitError(code: 3)
}

extension Tips {
    public struct EmptyDonation: Codable, Sendable {
        public init() {}
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
        public init(from decoder: any Decoder) throws {}
    }

    public struct DonationTimeRange: Hashable, Codable, Sendable {
        var seconds: TimeInterval
        public static var hour: DonationTimeRange { DonationTimeRange(seconds: 3600) }
        public static var day: DonationTimeRange { DonationTimeRange(seconds: 86400) }
    }

    public struct DonationLimit: Sendable {
        public let maximumCount: Int
        public let maximumAge: DonationTimeRange?
        public init(maximumCount: Int, maximumAge: DonationTimeRange? = nil) {
            self.maximumCount = maximumCount
            self.maximumAge = maximumAge
        }
    }

    public struct Event<DonationInfo>: Identifiable, Sendable
        where DonationInfo: Decodable, DonationInfo: Encodable, DonationInfo: Sendable {
        public let id: String
        var limit: DonationLimit?
        public typealias ID = String

        public init(id: String) where DonationInfo == EmptyDonation { self.id = id }
        public init(id: String) { self.id = id }
        public init(id: String, donationLimit: DonationLimit) where DonationInfo == EmptyDonation {
            self.id = id
            limit = donationLimit
        }

        public var donations: [Donation] {
            TipStore.shared.value([Donation].self, "event", id) ?? []
        }

        func record(_ info: DonationInfo) {
            var all = donations
            all.append(Donation(date: Date(), info: info))
            if let limit {
                if let age = limit.maximumAge {
                    let cutoff = Date().addingTimeInterval(-age.seconds)
                    all.removeAll { $0.date < cutoff }
                }
                if all.count > limit.maximumCount {
                    all.removeFirst(all.count - limit.maximumCount)
                }
            }
            TipStore.shared.setValue(all, "event", id)
        }
    }
}

extension Tips.Event {
    public struct Donation: Codable, Sendable {
        public let date: Date
        let info: DonationInfo
        init(date: Date, info: DonationInfo) {
            self.date = date
            self.info = info
        }
        enum CodingKeys: String, CodingKey { case date, info }
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(info, forKey: .info)
        }
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            date = try container.decode(Date.self, forKey: .date)
            info = try container.decode(DonationInfo.self, forKey: .info)
        }
    }

    public func donate() async where DonationInfo == Tips.EmptyDonation {
        record(Tips.EmptyDonation())
    }

    public func donate(_ donation: DonationInfo) async {
        record(donation)
    }
}

extension Tips {
    public struct Parameter<Value>: Identifiable, Sendable
        where Value: Decodable, Value: Encodable, Value: Sendable {
        public let id: String
        let initialValue: Value
        public typealias ID = String

        public init(_ enclosingInstance: (some Any).Type, _ name: String, _ initialValue: Value) {
            id = "\(String(reflecting: enclosingInstance)).\(name)"
            self.initialValue = initialValue
        }

        public var wrappedValue: Value {
            get { TipStore.shared.value(Value.self, "parameter", id) ?? initialValue }
            nonmutating set { TipStore.shared.setValue(newValue, "parameter", id) }
        }
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
public protocol EventPredicateExpression<Output>: PredicateExpression {}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension PredicateExpressions.Comparison: EventPredicateExpression
    where LHS: EventPredicateExpression, RHS: EventPredicateExpression {}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension PredicateExpressions.KeyPath: EventPredicateExpression
    where Root: EventPredicateExpression {}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension PredicateExpressions.Value: EventPredicateExpression {}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension PredicateExpressions.Variable: EventPredicateExpression {}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension PredicateExpressions.Equal: EventPredicateExpression
    where LHS: EventPredicateExpression, RHS: EventPredicateExpression {}

struct _TipExpression: @unchecked Sendable {
    let evaluateBindings: (PredicateBindings) throws -> Bool

    init(_ expression: any EventPredicateExpression<Bool>) {
        evaluateBindings = { try expression.evaluate($0) }
    }

    func evaluate(_ bindings: PredicateBindings) throws -> Bool {
        try evaluateBindings(bindings)
    }
}

extension Tips {
    public struct Rule: Sendable {
        public enum CompoundOperation: Sendable, Hashable {
            case disjunction
            case conjunction
        }
        let check: @Sendable () -> Bool

        public init(_ operation: CompoundOperation, _ rules: [Rule]) {
            check = {
                operation == .conjunction
                    ? rules.allSatisfy { $0.check() }
                    : rules.contains { $0.check() }
            }
        }

        /// Event predicate rule. The closure result is evaluated by status()
        /// against the donated event. try? maps a thrown PredicateError,
        /// including undefinedVariable, to false.
        @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
        public init<Donation>(
            _ event: Event<Donation>,
            _ eventBuilder: (PredicateExpressions.Variable<Event<Donation>>) -> any EventPredicateExpression<Bool>
        ) where Donation: Decodable, Donation: Encodable, Donation: Sendable {
            let variable = PredicateExpressions.Variable<Event<Donation>>()
            let expression = _TipExpression(eventBuilder(variable))
            check = {
                (try? expression.evaluate(PredicateBindings((variable, event)))) ?? false
            }
        }

        /// Closure rule. This is not the predicate initializer Preview imports.
        public init(_ check: @escaping @Sendable () -> Bool) {
            self.check = check
        }
    }

    @resultBuilder
    public struct RuleBuilder {
        public static func buildExpression(_ child: Rule) -> [Rule] { [child] }
        public static func buildPartialBlock(first: [Rule]) -> [Rule] { first }
        public static func buildPartialBlock(accumulated: [Rule], next: [Rule]) -> [Rule] {
            accumulated + next
        }
    }
}

public protocol TipOption: Sendable {}

extension Tips {
    public struct MaxDisplayCount: TipOption {
        let value: Int
        public init(_ maxDisplayCount: Int) { value = maxDisplayCount }
    }

    public struct MaxDisplayDuration: TipOption {
        let value: TimeInterval
        public init(_ maxDisplayDuration: TimeInterval) { value = maxDisplayDuration }
    }

    struct CollectedOptions: TipOption {
        var all: [any TipOption]
    }

    @resultBuilder
    public struct OptionsBuilder {
        public static func buildExpression(_ child: some TipOption) -> some TipOption {
            CollectedOptions(all: [child])
        }
        public static func buildPartialBlock(first: some TipOption) -> some TipOption {
            CollectedOptions(all: flatten(first))
        }
        public static func buildPartialBlock(accumulated: some TipOption, next: some TipOption) -> some TipOption {
            CollectedOptions(all: flatten(accumulated) + flatten(next))
        }
        public static func buildFinalResult(_ component: some TipOption) -> [any TipOption] {
            flatten(component)
        }
        static func flatten(_ option: any TipOption) -> [any TipOption] {
            if let options = option as? CollectedOptions { return options.all.flatMap(flatten) }
            return [option]
        }
    }
}

public protocol Tip: Identifiable, Sendable {
    var id: String { get }
    var title: Text { get }
    var message: Text? { get }
    var image: Image? { get }
    @Tips.RuleBuilder var rules: [Tips.Rule] { get }
    @Tips.OptionsBuilder var options: [any TipOption] { get }
    var actions: [Tips.Action] { get }
}

extension Tip {
    public var id: String { String(describing: Self.self) }
    public var message: Text? { nil }
    public var image: Image? { nil }
    public var rules: [Tips.Rule] { [] }
    public var options: [any TipOption] { [] }
    public var actions: [Tips.Action] { [] }
}

extension Tips {
    public enum Status: Hashable, Sendable {
        case pending
        case available
        case invalidated(InvalidationReason)
    }

    public enum InvalidationReason: Hashable, Sendable, Codable {
        case actionPerformed
        case displayCountExceeded
        case displayDurationExceeded
        case tipClosed
    }

    public struct Action: Identifiable, Sendable {
        public let id: String
        public let title: String
        public typealias ID = String
        public init(id: String? = nil, title: String) {
            self.id = id ?? UUID().uuidString
            self.title = title
        }
    }
}

struct TipRecord: Codable {
    var invalidated: Tips.InvalidationReason?
    var displayCount = 0
    var firstDisplay: Date?
}

extension Tip {
    var record: TipRecord {
        TipStore.shared.value(TipRecord.self, "tip", id) ?? TipRecord()
    }

    func updateRecord(_ change: (inout TipRecord) -> Void) {
        var next = record
        change(&next)
        TipStore.shared.setValue(next, "tip", id)
    }

    public var status: Tips.Status {
        let store = TipStore.shared
        let type = String(reflecting: Self.self)
        if store.hiddenForTesting.contains(type) || store.showAllForTesting == false { return .pending }
        if store.showAllForTesting == true || store.shownForTesting.contains(type) { return .available }
        guard store.configured else { return .pending }
        let current = record
        if let reason = current.invalidated { return .invalidated(reason) }
        for option in Tips.OptionsBuilder.flatten(Tips.CollectedOptions(all: options)) {
            if let max = option as? Tips.MaxDisplayCount, current.displayCount >= max.value {
                return .invalidated(.displayCountExceeded)
            }
            if let max = option as? Tips.MaxDisplayDuration, let first = current.firstDisplay,
               Date().timeIntervalSince(first) > max.value {
                return .invalidated(.displayDurationExceeded)
            }
        }
        return rules.allSatisfy { $0.check() } ? .available : .pending
    }

    public var shouldDisplay: Bool { status == .available }

    public func invalidate(reason: Tips.InvalidationReason) {
        updateRecord { $0.invalidated = reason }
    }

    public func noteDisplayed() {
        updateRecord { record in
            record.displayCount += 1
            if record.firstDisplay == nil { record.firstDisplay = Date() }
        }
    }
}

@Observable
public final class TipGroup: @unchecked Sendable {
    public enum Priority: Sendable, Hashable {
        case firstAvailable
        case ordered
    }

    let priority: Priority
    let tips: [any Tip]

    public init(_ priority: Priority = .firstAvailable, @Tips.GroupBuilder _ builder: () -> [any Tip]) {
        self.priority = priority
        tips = builder()
    }

    @MainActor
    public var currentTip: (any Tip)? {
        switch priority {
        case .firstAvailable:
            return tips.first { $0.shouldDisplay }
        case .ordered:
            for tip in tips {
                if tip.shouldDisplay { return tip }
                if case .invalidated = tip.status { continue }
                return nil
            }
            return nil
        }
    }
}

extension Tips {
    @resultBuilder
    public struct GroupBuilder {
        public static func buildBlock() -> [any Tip] { [] }
        public static func buildBlock(_ components: any Tip...) -> [any Tip] { components }
        public static func buildPartialBlock(first: any Tip) -> [any Tip] { [first] }
        public static func buildPartialBlock(first: [any Tip]) -> [any Tip] { first }
        public static func buildPartialBlock(accumulated: [any Tip], next: any Tip) -> [any Tip] { accumulated + [next] }
        public static func buildPartialBlock(accumulated: [any Tip], next: [any Tip]) -> [any Tip] { accumulated + next }
        public static func buildIf(_ element: [any Tip]?) -> [any Tip] { element ?? [] }
        public static func buildEither(first: [any Tip]) -> [any Tip] { first }
        public static func buildEither(second: [any Tip]) -> [any Tip] { second }
        public static func buildArray(_ components: [[any Tip]]) -> [any Tip] { components.flatMap { $0 } }
    }
}
