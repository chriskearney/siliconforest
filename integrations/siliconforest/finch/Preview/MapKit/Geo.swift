// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney
//
// World Web Mercator projection and Natural Earth 1:110m land polygons.
// This file does not import SwiftUI. The Map and Marker ABI lives in MapKit.swift.

import Darwin

public struct LonLat: Equatable, Sendable {
    public var longitude: Double
    public var latitude: Double
    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

public struct LandPolygon: Sendable {
    public var rings: [[LonLat]]
    public init(rings: [[LonLat]]) { self.rings = rings }
}

public struct LandCoverage: Sendable {
    public var polygons: [LandPolygon]
    public var ringCount: Int
    public var pointCount: Int
    public init(polygons: [LandPolygon], ringCount: Int, pointCount: Int) {
        self.polygons = polygons
        self.ringCount = ringCount
        self.pointCount = pointCount
    }
}

public struct ProjectedMarker: Equatable, Sendable {
    public var name: String
    public var coordinate: LonLat
    public init(name: String, coordinate: LonLat) {
        self.name = name
        self.coordinate = coordinate
    }
}

public struct MapRaster: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]
    public func at(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

public enum GeoJSONError: Error, CustomStringConvertible {
    case syntax(Int)
    case shape(String)
    public var description: String {
        switch self {
        case let .syntax(offset): return "GeoJSON syntax at byte \(offset)"
        case let .shape(message): return message
        }
    }
}

public enum WebMercator {
    public static let latitudeLimit = 85.0511287798066

    public static func pixel(
        _ point: LonLat, width: Int, height: Int
    ) -> (x: Int, y: Int)? {
        guard width > 0, height > 0 else { return nil }
        guard point.longitude >= -180, point.longitude <= 180 else { return nil }
        guard point.latitude >= -latitudeLimit, point.latitude <= latitudeLimit else { return nil }
        let xNorm = (point.longitude + 180) / 360
        let yNorm = yOf(latitude: point.latitude)
        var x = Int(xNorm * Double(width))
        var y = Int(yNorm * Double(height))
        if x == width { x = width - 1 }
        if y == height { y = height - 1 }
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return (x, y)
    }

    public static func coordinate(x: Int, y: Int, width: Int, height: Int) -> LonLat {
        let xNorm = (Double(x) + 0.5) / Double(width)
        let yNorm = (Double(y) + 0.5) / Double(height)
        let longitude = -180 + xNorm * 360
        let mercator = (0.5 - yNorm) * 2 * Double.pi
        let latitude = (2 * atan(exp(mercator)) - Double.pi / 2) * 180 / Double.pi
        return LonLat(longitude: longitude, latitude: latitude)
    }

    private static func yOf(latitude: Double) -> Double {
        let radians = latitude * Double.pi / 180
        let mercator = log(tan(Double.pi / 4 + radians / 2))
        return 0.5 - mercator / (2 * Double.pi)
    }
}

public func contains(_ point: LonLat, rings: [[LonLat]]) -> Bool {
    var inside = false
    for ring in rings {
        if ring.count < 2 { continue }
        let box = ringBox(ring)
        if point.longitude < box.minX || point.longitude > box.maxX
            || point.latitude < box.minY || point.latitude > box.maxY {
            continue
        }
        for index in 0..<(ring.count - 1) {
            let start = ring[index]
            let end = ring[index + 1]
            if (start.latitude > point.latitude) != (end.latitude > point.latitude) {
                let x = start.longitude + (point.latitude - start.latitude)
                    * (end.longitude - start.longitude) / (end.latitude - start.latitude)
                if point.longitude < x { inside.toggle() }
            }
        }
    }
    return inside
}

public func contains(_ point: LonLat, polygons: [LandPolygon]) -> Bool {
    for polygon in polygons where contains(point, rings: polygon.rings) {
        return true
    }
    return false
}

public func renderWorld(
    polygons: [LandPolygon], markers: [ProjectedMarker], width: Int, height: Int
) -> MapRaster {
    var pixels = [UInt8](repeating: 0, count: width * height)
    let prepared = polygons.map { polygon in
        polygon.rings.map { ring in (ring, ringBox(ring)) }
    }
    for y in 0..<height {
        for x in 0..<width {
            let point = WebMercator.coordinate(x: x, y: y, width: width, height: height)
            if containsPrepared(point, prepared) {
                pixels[y * width + x] = 1
            }
        }
    }
    for marker in markers {
        guard let pixel = WebMercator.pixel(marker.coordinate, width: width, height: height) else {
            continue
        }
        pixels[pixel.y * width + pixel.x] = 2
    }
    return MapRaster(width: width, height: height, pixels: pixels)
}

private struct RingBox {
    var minX, maxX, minY, maxY: Double
}

private func ringBox(_ ring: [LonLat]) -> RingBox {
    var box = RingBox(minX: .infinity, maxX: -.infinity, minY: .infinity, maxY: -.infinity)
    for point in ring {
        box.minX = min(box.minX, point.longitude)
        box.maxX = max(box.maxX, point.longitude)
        box.minY = min(box.minY, point.latitude)
        box.maxY = max(box.maxY, point.latitude)
    }
    return box
}

private func containsPrepared(_ point: LonLat, _ polygons: [[([LonLat], RingBox)]]) -> Bool {
    for polygon in polygons {
        var inside = false
        for (ring, box) in polygon {
            if point.longitude < box.minX || point.longitude > box.maxX
                || point.latitude < box.minY || point.latitude > box.maxY {
                continue
            }
            for index in 0..<(ring.count - 1) {
                let start = ring[index]
                let end = ring[index + 1]
                if (start.latitude > point.latitude) != (end.latitude > point.latitude) {
                    let x = start.longitude + (point.latitude - start.latitude)
                        * (end.longitude - start.longitude) / (end.latitude - start.latitude)
                    if point.longitude < x { inside.toggle() }
                }
            }
        }
        if inside { return true }
    }
    return false
}

public func parseNaturalEarthLand(_ text: String) throws -> LandCoverage {
    var parser = JSONParser(bytes: Array(text.utf8))
    let value = try parser.parseValue()
    parser.skip()
    if parser.index != parser.bytes.count { throw GeoJSONError.syntax(parser.index) }
    guard case let .object(root) = value else { throw GeoJSONError.shape("root is not an object") }
    guard string(root, "type") == "FeatureCollection" else {
        throw GeoJSONError.shape("type is not FeatureCollection")
    }
    guard case let .array(features)? = root["features"] else {
        throw GeoJSONError.shape("features is missing")
    }
    var polygons: [LandPolygon] = []
    var rings = 0
    var points = 0
    polygons.reserveCapacity(features.count)
    for feature in features {
        guard case let .object(fields) = feature else { throw GeoJSONError.shape("feature is not an object") }
        guard case let .object(geometry)? = fields["geometry"] else {
            throw GeoJSONError.shape("geometry is missing")
        }
        guard string(geometry, "type") == "Polygon" else {
            throw GeoJSONError.shape("geometry is not Polygon")
        }
        guard case let .array(coordinates)? = geometry["coordinates"] else {
            throw GeoJSONError.shape("coordinates are missing")
        }
        var polygon: [[LonLat]] = []
        for ringValue in coordinates {
            guard case let .array(positions) = ringValue else {
                throw GeoJSONError.shape("ring is not an array")
            }
            var ring: [LonLat] = []
            ring.reserveCapacity(positions.count)
            for position in positions {
                guard case let .array(pair) = position, pair.count == 2,
                      case let .number(longitude) = pair[0],
                      case let .number(latitude) = pair[1] else {
                    throw GeoJSONError.shape("position is not a lon/lat pair")
                }
                ring.append(LonLat(longitude: longitude, latitude: latitude))
            }
            rings += 1
            points += ring.count
            polygon.append(ring)
        }
        polygons.append(LandPolygon(rings: polygon))
    }
    return LandCoverage(polygons: polygons, ringCount: rings, pointCount: points)
}

private func string(_ object: [String: JSONValue], _ key: String) -> String? {
    if case let .string(value)? = object[key] { return value }
    return nil
}

private enum JSONValue {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

private struct JSONParser {
    var bytes: [UInt8]
    var index = 0

    mutating func parseValue() throws -> JSONValue {
        skip()
        guard index < bytes.count else { throw GeoJSONError.syntax(index) }
        switch bytes[index] {
        case UInt8(ascii: "n"):
            try literal([UInt8]("null".utf8))
            return .null
        case UInt8(ascii: "t"):
            try literal([UInt8]("true".utf8))
            return .bool(true)
        case UInt8(ascii: "f"):
            try literal([UInt8]("false".utf8))
            return .bool(false)
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "["):
            return .array(try parseArray())
        case UInt8(ascii: "{"):
            return .object(try parseObject())
        default:
            return .number(try parseNumber())
        }
    }

    mutating func skip() {
        while index < bytes.count, bytes[index] == 32 || bytes[index] == 9
            || bytes[index] == 10 || bytes[index] == 13 {
            index += 1
        }
    }

    private mutating func literal(_ text: [UInt8]) throws {
        guard index + text.count <= bytes.count, Array(bytes[index..<(index + text.count)]) == text else {
            throw GeoJSONError.syntax(index)
        }
        index += text.count
    }

    private mutating func parseArray() throws -> [JSONValue] {
        index += 1
        var values: [JSONValue] = []
        skip()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return values
        }
        while true {
            values.append(try parseValue())
            skip()
            guard index < bytes.count else { throw GeoJSONError.syntax(index) }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return values
            }
            guard bytes[index] == UInt8(ascii: ",") else { throw GeoJSONError.syntax(index) }
            index += 1
        }
    }

    private mutating func parseObject() throws -> [String: JSONValue] {
        index += 1
        var fields: [String: JSONValue] = [:]
        skip()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return fields
        }
        while true {
            skip()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                throw GeoJSONError.syntax(index)
            }
            let key = try parseString()
            skip()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                throw GeoJSONError.syntax(index)
            }
            index += 1
            fields[key] = try parseValue()
            skip()
            guard index < bytes.count else { throw GeoJSONError.syntax(index) }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return fields
            }
            guard bytes[index] == UInt8(ascii: ",") else { throw GeoJSONError.syntax(index) }
            index += 1
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var units: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == UInt8(ascii: "\"") {
                return String(decoding: units, as: UTF8.self)
            }
            if byte != UInt8(ascii: "\\") {
                units.append(byte)
                continue
            }
            guard index < bytes.count else { throw GeoJSONError.syntax(index) }
            let escaped = bytes[index]
            index += 1
            switch escaped {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"):
                units.append(escaped)
            case UInt8(ascii: "n"): units.append(10)
            case UInt8(ascii: "r"): units.append(13)
            case UInt8(ascii: "t"): units.append(9)
            case UInt8(ascii: "u"):
                let scalar = try parseHex()
                let encoded = String(UnicodeScalar(scalar)!).utf8
                units.append(contentsOf: encoded)
            default:
                throw GeoJSONError.syntax(index)
            }
        }
        throw GeoJSONError.syntax(index)
    }

    private mutating func parseHex() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard index < bytes.count else { throw GeoJSONError.syntax(index) }
            let byte = bytes[index]
            index += 1
            value <<= 4
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): value += UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): value += UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): value += UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw GeoJSONError.syntax(index)
            }
        }
        return value
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
            index += 1
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                index += 1
            }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                index += 1
            }
        }
        guard index > start, let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
            throw GeoJSONError.syntax(start)
        }
        return value
    }
}
