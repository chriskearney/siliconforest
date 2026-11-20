// SPDX-License-Identifier: Apache-2.0 WITH Runtime Library Exception
// Swift Measurement over Finch NSMeasurement. The pinned swift-foundation
// tree has only the non-framework format stub, so this is the framework type
// Preview imports. converted(to:) calls measurementByConvertingToUnit:.

// The nominal NSUnit bound keeps converted(to:) on the extension
// requirement only. Preview imports that symbol as Rbzrl.
@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
public struct Measurement<UnitType: NSUnit> {
    public let value: Double
    public let unit: UnitType

    public init(value: Double, unit: UnitType) {
        self.value = value
        self.unit = unit
    }
}

@available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
extension Measurement where UnitType: NSDimension {
    public func converted(to otherUnit: UnitType) -> Measurement<UnitType> {
        let measured = NSMeasurement(doubleValue: value, unit: unit)
        let converted = SFMeasurementByConverting(measured, otherUnit)
        return Measurement(value: converted.doubleValue, unit: otherUnit)
    }
}
