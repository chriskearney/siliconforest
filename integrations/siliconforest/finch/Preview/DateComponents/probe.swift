// SPDX-License-Identifier: MIT
import Foundation
import Darwin

private func require(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
    if !condition() {
        let message = "DateComponents FAIL line \(line)\n"
        message.withCString { _ = fputs($0, stderr) }
        exit(1)
    }
}
private func check(_ condition: @autoclosure () throws -> Bool) rethrows {
    let passed = try condition(); require(passed)
}
@main struct Probe {
    static func main() throws {
        let empty = DateComponents()
        require(empty.year == nil && empty.calendar == nil && empty.timeZone == nil && empty.date == nil && !empty.isValidDate)
        var raw = DateComponents(year: 2024, month: 2, day: 29)
        var copy = raw; copy.year = 2023
        require(raw.year == 2024 && copy.year == 2023)
        raw.second = Int.max
        require(raw.second == nil)
        raw.setValue(12, for: .hour)
        require(raw.value(for: .hour) == 12)
        var nilLeap = DateComponents(year: 2024)
        let unsetLeap = nilLeap
        nilLeap.isLeapMonth = false
        require(unsetLeap == nilLeap && Set([unsetLeap,nilLeap]).count == 1)
        let utc = TimeZone(secondsFromGMT: 0)!
        let east = TimeZone(secondsFromGMT: 3600)!
        require(utc.secondsFromGMT() == 0 && east.secondsFromGMT() == 3600)
        require(TimeZone(identifier: "SiliconForest/No_Such_Zone") == nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let epoch = DateComponents(calendar: calendar, year: 1970, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        require(epoch.date!.timeIntervalSince1970 == 0 && epoch.isValidDate)
        var shifted = epoch; shifted.timeZone = east
        require(shifted.date!.timeIntervalSince1970 == -3600 && calendar.timeZone == utc)
        let leap = DateComponents(calendar: calendar, year: 2024, month: 2, day: 29, hour: 12)
        let invalid = DateComponents(calendar: calendar, year: 2023, month: 2, day: 29)
        require(leap.isValidDate && !invalid.isValidDate)
        var badNanos = leap; badNanos.nanosecond = 1_000_000_000
        require(!badNanos.isValidDate)
        let components = calendar.dateComponents([.year,.month,.day,.hour,.weekday,.dayOfYear,.isLeapMonth], from: leap.date!)
        require(components.year == 2024 && components.month == 2 && components.day == 29 && components.hour == 12)
        require(components.weekday == 5 && components.dayOfYear == 60 && components.isLeapMonth == false)
        require(calendar.dateComponents([], from: leap.date!) == DateComponents())
        var iso = Calendar(identifier: .iso8601); iso.timeZone = utc
        let week = iso.dateComponents([.weekOfYear,.yearForWeekOfYear], from: epoch.date!)
        require(week.weekOfYear == 1 && week.yearForWeekOfYear == 1970)
        let boundary = DateComponents(calendar: calendar, year: 2016, month: 1, day: 1).date!
        let isoBoundary = iso.dateComponents([.weekOfYear,.yearForWeekOfYear], from: boundary)
        require(isoBoundary.weekOfYear == 53 && isoBoundary.yearForWeekOfYear == 2015)
        let encoded = try JSONEncoder().encode(leap)
        let decoded = try JSONDecoder().decode(DateComponents.self, from: encoded)
        require(decoded == leap && decoded.date == leap.date)
        if let la = TimeZone(identifier: "America/Los_Angeles") {
            require(la.secondsFromGMT(for: Date(timeIntervalSince1970: 1704067200)) == -28800)
            require(la.secondsFromGMT(for: Date(timeIntervalSince1970: 1719792000)) == -25200)
            print("TimeZone IANA winter/summer PASS")
        } else { print("TimeZone IANA database unavailable: identifier returns nil") }
        do {
            _ = try JSONDecoder().decode(TimeZone.self, from: Data(#"{"identifier":"GMT","autoupdating":true}"#.utf8))
            preconditionFailure()
        } catch DecodingError.dataCorrupted { }
        do {
            _ = try JSONDecoder().decode(Calendar.self, from: Data(#"{"identifier":"unsupported"}"#.utf8))
            preconditionFailure()
        } catch DecodingError.dataCorrupted { }
        require(String(reflecting: DateComponents.self) == "Foundation.DateComponents")
        print("DateComponents PASS optional/scalar/value/hash/Codable metadata Gregorian/ISO epoch/leap/invalid/timezone/day-of-year conversions explicit-unavailable")
    }
}
