// SPDX-License-Identifier: MIT
import Foundation

@main
struct Probe {
    static func main() {
        let start = Date(timeIntervalSinceReferenceDate: 1234)
        let interval = DateInterval(start: start, duration: 600)
        precondition(interval.end.timeIntervalSince(start) == 600)
        precondition(interval.contains(start) && interval.contains(interval.end))
        precondition(!interval.contains(interval.end + 1))
        let other = DateInterval(start: start + 300, duration: 600)
        precondition(interval.intersection(with: other)?.duration == 300)
        let calendar: NSCalendar.Unit = [.day, .minute]
        precondition(calendar.contains(.day) && calendar.contains(.minute) && !calendar.contains(.year))
        print("DateInterval intersection and NSCalendar.Unit flags PASS")
    }
}
