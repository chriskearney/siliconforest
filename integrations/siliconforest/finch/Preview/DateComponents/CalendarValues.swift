// SPDX-License-Identifier: MIT
// Scoped DateComponents support through real open CoreFoundation calendar APIs.
import CoreFoundation
import SFCalendarRuntime

private func cfString(_ value: String) -> CFString {
    unsafeBitCast(value._bridgeToObjectiveC(), to: CFString.self)
}
private func swiftString(_ value: CFString) -> String {
    String._unconditionallyBridgeFromObjectiveC(unsafeBitCast(value, to: NSString.self))
}

public struct TimeZone: Hashable, Codable, @unchecked Sendable, CustomDebugStringConvertible {
    // CFTimeZone is immutable; retain the actual validated zone, not a later re-read.
    private let reference: CFTimeZone
    public var identifier: String { swiftString(CFTimeZoneGetName(reference)) }
    private init(reference: CFTimeZone) { self.reference = reference }
    public init?(identifier: String) {
        guard let zone = CFTimeZoneCreateWithName(nil, cfString(identifier), false) else { return nil }
        self.reference = zone
    }
    public init?(secondsFromGMT: Int) {
        guard let zone = CFTimeZoneCreateWithTimeIntervalFromGMT(nil, Double(secondsFromGMT)) else { return nil }
        self.reference = zone
    }
    internal var cf: CFTimeZone { reference }
    public static var current: TimeZone { TimeZone(reference: CFTimeZoneCopySystem()) }
    public static func ==(lhs: TimeZone, rhs: TimeZone) -> Bool { CFEqual(lhs.cf, rhs.cf) }
    public func hash(into hasher: inout Hasher) { hasher.combine(CFHash(cf)) }
    public func secondsFromGMT(for date: Date = Date()) -> Int {
        Int(CFTimeZoneGetSecondsFromGMT(cf, date.timeIntervalSinceReferenceDate))
    }
    public var debugDescription: String { identifier }
    private enum CodingKeys: Int, CodingKey { case identifier, autoupdating }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decodeIfPresent(Bool.self, forKey: .autoupdating) == true {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Autoupdating time zones unavailable in the reader slice."))
        }
        let name = try c.decode(String.self, forKey: .identifier)
        guard let value = TimeZone(identifier: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid time zone identifier."))
        }
        self = value
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identifier, forKey: .identifier)
    }
}

public struct Calendar: Hashable, Codable, Sendable, CustomDebugStringConvertible {
    public enum Identifier: String, Codable, Sendable { case gregorian, iso8601 }
    public enum Component: Hashable, Sendable {
        case era, year, month, day, hour, minute, second, nanosecond, weekday, weekdayOrdinal
        case quarter, weekOfMonth, weekOfYear, yearForWeekOfYear, dayOfYear
        case calendar, timeZone, isLeapMonth, isRepeatedDay
    }
    public let identifier: Identifier
    public var timeZone: TimeZone
    public var locale: Locale?
    public var firstWeekday: Int
    public var minimumDaysInFirstWeek: Int
    public init(identifier: Identifier) {
        self.identifier = identifier
        let calendar = CFCalendarCreateWithIdentifier(nil, CFCalendarIdentifier(rawValue: cfString(identifier.rawValue)))!
        timeZone = TimeZone(identifier: swiftString(CFTimeZoneGetName(CFCalendarCopyTimeZone(calendar))))!
        locale = nil
        firstWeekday = CFCalendarGetFirstWeekday(calendar)
        minimumDaysInFirstWeek = CFCalendarGetMinimumDaysInFirstWeek(calendar)
    }
    private func makeCF() -> CFCalendar {
        let calendar = CFCalendarCreateWithIdentifier(nil, CFCalendarIdentifier(rawValue: cfString(identifier.rawValue)))!
        CFCalendarSetTimeZone(calendar, timeZone.cf)
        if let locale { CFCalendarSetLocale(calendar, CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: cfString(locale.identifier)))) }
        CFCalendarSetFirstWeekday(calendar, firstWeekday)
        CFCalendarSetMinimumDaysInFirstWeek(calendar, minimumDaysInFirstWeek)
        return calendar
    }
    public var debugDescription: String { "\(identifier.rawValue) \(timeZone.identifier)" }
    private static let fields: [(Component, String)] = [
        (.era,"G"),(.year,"y"),(.month,"M"),(.day,"d"),(.hour,"H"),(.minute,"m"),(.second,"s"),
        (.nanosecond,"#"),(.weekday,"E"),(.weekdayOrdinal,"F"),(.quarter,"Q"),(.weekOfMonth,"W"),
        (.weekOfYear,"w"),(.yearForWeekOfYear,"Y"),(.dayOfYear,"D"),(.isLeapMonth,"l")]
    public func date(from components: DateComponents) -> Date? {
        // Repeated-day policy is outside this limited reader conversion API.
        guard components.isRepeatedDay != true else { return nil }
        var values = [Int32](), description = ""
        for (component, format) in Self.fields {
            if let value = components.value(for: component) {
                guard let narrowed = Int32(exactly: value) else { return nil }
                values.append(narrowed); description += format
            }
        }
        if let leap = components.isLeapMonth { values.append(leap ? 1 : 0); description += "l" }
        let calendar = makeCF()
        if let zone = components.timeZone { CFCalendarSetTimeZone(calendar, zone.cf) }
        var absolute: CFAbsoluteTime = 0
        let ok = description.withCString { format in
            values.withUnsafeMutableBufferPointer { vector in
                _CFCalendarComposeAbsoluteTimeV(calendar, &absolute, format, vector.baseAddress, Int32(vector.count))
            }
        }
        return ok ? Date(timeIntervalSinceReferenceDate: absolute) : nil
    }
    public func dateComponents(_ requested: Set<Component>, from date: Date) -> DateComponents {
        let fields = Self.fields.filter { requested.contains($0.0) }
        var result = DateComponents()
        if requested.contains(.calendar) { result.calendar = self }
        if requested.contains(.timeZone) { result.timeZone = timeZone }
        guard !fields.isEmpty else { return result }
        var values = [Int32](repeating: 0, count: fields.count)
        let description = fields.map { $0.1 }.joined()
        let calendar = makeCF()
        let ok = values.withUnsafeMutableBufferPointer { vector in
            var addresses = (0..<vector.count).map { vector.baseAddress!.advanced(by: $0) }
            return addresses.withUnsafeMutableBufferPointer { pointers in
                description.withCString { format in
                    _CFCalendarDecomposeAbsoluteTimeV(calendar, date.timeIntervalSinceReferenceDate, format, pointers.baseAddress!, Int32(pointers.count))
                }
            }
        }
        precondition(ok || fields.isEmpty, "CoreFoundation calendar conversion failed")
        for (index, field) in fields.enumerated() {
            if field.0 == .isLeapMonth { result.isLeapMonth = values[index] != 0 }
            else { result.setValue(Int(values[index]), for: field.0) }
        }
        if requested.contains(.calendar) { result.calendar = self }
        if requested.contains(.timeZone) { result.timeZone = timeZone }
        return result
    }
    private enum CodingKeys: Int, CodingKey { case identifier, locale, timeZone, firstWeekday, minimumDaysInFirstWeek, current }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decodeIfPresent(Int.self, forKey: .current) == 2 {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Autoupdating calendars unavailable in the reader slice."))
        }
        let name = try c.decode(String.self, forKey: .identifier)
        guard let id = Identifier(rawValue: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Calendar identifier unsupported by this reader slice."))
        }
        self.init(identifier: id)
        locale = try c.decodeIfPresent(Locale.self, forKey: .locale)
        timeZone = try c.decode(TimeZone.self, forKey: .timeZone)
        firstWeekday = try c.decode(Int.self, forKey: .firstWeekday)
        minimumDaysInFirstWeek = try c.decode(Int.self, forKey: .minimumDaysInFirstWeek)
        guard (1...7).contains(firstWeekday) && (1...7).contains(minimumDaysInFirstWeek) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid calendar week configuration."))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identifier.rawValue, forKey: .identifier)
        try c.encode(locale, forKey: .locale)
        try c.encode(timeZone, forKey: .timeZone)
        try c.encode(firstWeekday, forKey: .firstWeekday)
        try c.encode(minimumDaysInFirstWeek, forKey: .minimumDaysInFirstWeek)
        try c.encode(0, forKey: .current)
    }
}
