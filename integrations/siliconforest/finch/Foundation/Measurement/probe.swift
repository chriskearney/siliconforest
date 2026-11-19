// SPDX-License-Identifier: MIT OR Apache-2.0
// Headless conversion of Measurement through Finch NSUnitLength.
import Foundation
import Darwin

@main
struct Probe {
    static func main() {
        func say(_ line: String) {
            print(line)
            fflush(stdout)
        }
        func check(_ value: Bool, _ name: String) {
            if !value {
                say("FAIL \(name)")
                exit(1)
            }
            say("PASS \(name)")
        }

        let mile = Measurement(value: 1, unit: NSUnitLength.miles())
        check(mile.value == 1, "mile value")
        let meters = mile.converted(to: NSUnitLength.meters())
        check(meters.value == 1609.344, "one mile is 1609.344 meters")
        check(meters.unit === NSUnitLength.meters(), "converted unit is meters")
        check(mile.value == 1, "source mile unchanged")

        let inch = Measurement(value: 1, unit: NSUnitLength.inches()).converted(to: NSUnitLength.meters())
        check(inch.value == 0.0254, "one inch is 0.0254 meters")

        let kilometers = Measurement(value: 1000, unit: NSUnitLength.meters()).converted(to: NSUnitLength.kilometers())
        check(kilometers.value == 1, "1000 meters is 1 kilometer")

        let same = Measurement(value: 3, unit: NSUnitLength.meters()).converted(to: NSUnitLength.meters())
        check(same.value == 3, "same unit keeps the value")

        let back = meters.converted(to: NSUnitLength.miles())
        check(back.value == 1, "1609.344 meters is one mile")

        let inches = Measurement(value: 2, unit: NSUnitLength.feet()).converted(to: NSUnitLength.inches())
        say("OBS two-feet-inches \(inches.value)")
        check(abs(inches.value - 24) < 1e-9, "two feet is 24 inches")

        say("MEASUREMENT PROBE PASS")
    }
}
