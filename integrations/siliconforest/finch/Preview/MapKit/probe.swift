// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney
//
// Headless checks for the land parser and Web Mercator raster.
// This client does not import SwiftUI and does not draw a window.

import Darwin

@main
enum MapKitGeoProbe {
    static func main() {
        var failed = false
        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("ok \(name)")
            } else {
                print("FAIL \(name)")
                failed = true
            }
        }

        let square: [[LonLat]] = [[
            LonLat(longitude: 0, latitude: 0),
            LonLat(longitude: 10, latitude: 0),
            LonLat(longitude: 10, latitude: 10),
            LonLat(longitude: 0, latitude: 10),
            LonLat(longitude: 0, latitude: 0),
        ]]
        check("square contains center", contains(LonLat(longitude: 5, latitude: 5), rings: square))
        check("square excludes outside", !contains(LonLat(longitude: 15, latitude: 15), rings: square))
        let holed = square + [[
            LonLat(longitude: 4, latitude: 4),
            LonLat(longitude: 6, latitude: 4),
            LonLat(longitude: 6, latitude: 6),
            LonLat(longitude: 4, latitude: 6),
            LonLat(longitude: 4, latitude: 4),
        ]]
        check("hole excludes center", !contains(LonLat(longitude: 5, latitude: 5), rings: holed))
        check("hole keeps inner land", contains(LonLat(longitude: 2, latitude: 2), rings: holed))

        let origin = WebMercator.pixel(LonLat(longitude: 0, latitude: 0), width: 360, height: 180)
        check("origin pixel", origin?.x == 180 && origin?.y == 90)
        let east = WebMercator.pixel(LonLat(longitude: 180, latitude: 0), width: 360, height: 180)
        check("east edge clamps", east?.x == 359 && east?.y == 90)
        check("lat 89 unprojected", WebMercator.pixel(
            LonLat(longitude: 0, latitude: 89), width: 360, height: 180) == nil)
        check("nonfinite unprojected", WebMercator.pixel(
            LonLat(longitude: .nan, latitude: 0), width: 360, height: 180) == nil)
        let back = WebMercator.coordinate(x: 180, y: 90, width: 360, height: 180)
        check("inverse near origin", abs(back.longitude) < 1 && abs(back.latitude) < 1)

        let coverage: LandCoverage
        do {
            coverage = try parseNaturalEarthLand(embeddedNaturalEarthLandGeoJSON())
        } catch {
            print("FAIL parse \(error)")
            exit(1)
        }
        check("127 polygons", coverage.polygons.count == 127)
        let holedCount = coverage.polygons.filter { $0.rings.count > 1 }.count
        check("one holed polygon", holedCount == 1)
        let caspian = LonLat(longitude: 50, latitude: 42)
        var caspianHole = false
        for polygon in coverage.polygons where polygon.rings.count > 1 {
            let outer = contains(caspian, rings: [polygon.rings[0]])
            let full = contains(caspian, rings: polygon.rings)
            if outer && !full { caspianHole = true }
        }
        check("caspian hole", caspianHole)

        let land = [
            LonLat(longitude: 21, latitude: 7),
            LonLat(longitude: 133, latitude: -25),
            LonLat(longitude: 2.3, latitude: 48.5),
            LonLat(longitude: 77, latitude: 27),
            LonLat(longitude: -42, latitude: 72),
            LonLat(longitude: -55, latitude: -10),
            LonLat(longitude: 10, latitude: 23),
            LonLat(longitude: -0.12, latitude: 51.5),
            LonLat(longitude: 139.7, latitude: 35.7),
        ]
        let water = [
            LonLat(longitude: -30, latitude: 0),
            LonLat(longitude: -140, latitude: 0),
            LonLat(longitude: -74, latitude: 40.7),
            caspian,
        ]
        for point in land {
            check("land \(point.longitude),\(point.latitude)", contains(point, polygons: coverage.polygons))
        }
        for point in water {
            check("water \(point.longitude),\(point.latitude)", !contains(point, polygons: coverage.polygons))
        }

        let marker = ProjectedMarker(name: "sample", coordinate: land[0])
        let raster = renderWorld(polygons: coverage.polygons, markers: [marker], width: 36, height: 18)
        if let pixel = WebMercator.pixel(land[0], width: 36, height: 18) {
            check("marker pixel", raster.at(x: pixel.x, y: pixel.y) == 2)
        } else {
            check("marker pixel", false)
        }
        if let ocean = WebMercator.pixel(water[0], width: 36, height: 18) {
            check("ocean pixel", raster.at(x: ocean.x, y: ocean.y) == 0)
        } else {
            check("ocean pixel", false)
        }
        if failed { exit(1) }
        print("mapkit-geo-semantic-passed")
    }
}
