// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney
//
// Public Map and Marker surface named by Preview's ten strong
// _MapKit_SwiftUI binds. Namespace, LocalizedStringKey, Text, View, and
// NSViewRepresentable come from SwiftUI. This file does not declare them.
//
// The raster is the pinned Natural Earth 1:110m land polygons in Web
// Mercator. MapCameraBounds distances are stored and not applied: this
// initializer has no camera, and there is no distance-to-span formula here.
// Interaction-mode bits are this provider's: pan 1<<0, zoom 1<<1,
// pitch 1<<2, rotate 1<<3. Gestures are not delivered. There are no live
// tiles. A representable NSView is not evidence that SwiftUI has hosted a
// window.

import AppKit
import CoreLocation
import Foundation
import SwiftUI

public struct MapCameraBounds {
    public var minimumDistance: CLLocationDistance?
    public var maximumDistance: CLLocationDistance?
    public init(
        minimumDistance: CLLocationDistance? = nil,
        maximumDistance: CLLocationDistance? = nil
    ) {
        self.minimumDistance = minimumDistance
        self.maximumDistance = maximumDistance
    }
}

public struct MapInteractionModes: OptionSet {
    public var rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let pan = MapInteractionModes(rawValue: 1 << 0)
    public static let zoom = MapInteractionModes(rawValue: 1 << 1)
    public static let pitch = MapInteractionModes(rawValue: 1 << 2)
    public static let rotate = MapInteractionModes(rawValue: 1 << 3)

    public static var all: MapInteractionModes {
        MapInteractionModes(rawValue: pan.rawValue | zoom.rawValue | pitch.rawValue | rotate.rawValue)
    }
}

public protocol MapContent {
    func placedMarkers() -> [PlacedMarker]
}

public struct PlacedMarker: Equatable, Sendable {
    public var title: String?
    public var coordinate: LonLat
    public init(title: String?, coordinate: LonLat) {
        self.title = title
        self.coordinate = coordinate
    }
}

public struct MapContentList: MapContent {
    public var items: [any MapContent]
    public init(_ items: [any MapContent]) { self.items = items }
    public func placedMarkers() -> [PlacedMarker] {
        items.flatMap { $0.placedMarkers() }
    }
}

@resultBuilder
public enum MapContentBuilder {
    public static func buildBlock(_ components: any MapContent...) -> MapContentList {
        MapContentList(components)
    }
}

public struct MapContentView<Annotation, Content> {
    public var content: Content
    public init(content: Content) { self.content = content }
}

public struct Marker<Label: View>: MapContent {
    public var title: LocalizedStringKey
    public var coordinate: CLLocationCoordinate2D

    public init(_ title: LocalizedStringKey, coordinate: CLLocationCoordinate2D) where Label == Text {
        self.title = title
        self.coordinate = coordinate
    }

    public func placedMarkers() -> [PlacedMarker] {
        let point = LonLat(longitude: coordinate.longitude, latitude: coordinate.latitude)
        return [PlacedMarker(title: readableMarkerTitle(title), coordinate: point)]
    }
}

public struct Map<Content> {
    public var bounds: MapCameraBounds?
    public var interactionModes: MapInteractionModes
    public var scope: Namespace.ID?
    public var content: Content
    public var markers: [PlacedMarker]
    public var coverage: LandCoverage

    public init<C: MapContent>(
        bounds: MapCameraBounds? = nil,
        interactionModes: MapInteractionModes = .all,
        scope: Namespace.ID? = nil,
        @MapContentBuilder content: () -> C
    ) where Content == MapContentView<Never, C> {
        let built = content()
        self.bounds = bounds
        self.interactionModes = interactionModes
        self.scope = scope
        self.content = MapContentView(content: built)
        self.markers = built.placedMarkers()
        self.coverage = NaturalEarthLand.coverage
    }

    public func makeRaster(width: Int = 360, height: Int = 180) -> MapRaster {
        let projected = markers.map { marker in
            ProjectedMarker(name: marker.title ?? "", coordinate: marker.coordinate)
        }
        return renderWorld(
            polygons: coverage.polygons, markers: projected, width: width, height: height)
    }
}

extension Map: View {
    public var body: LandMapRepresentable {
        LandMapRepresentable(raster: makeRaster())
    }
}

enum NaturalEarthLand {
    static let coverage: LandCoverage = {
        do {
            return try parseNaturalEarthLand(embeddedNaturalEarthLandGeoJSON())
        } catch {
            fatalError("Natural Earth land GeoJSON did not parse: \(error)")
        }
    }()
}

func readableMarkerTitle(_ title: LocalizedStringKey) -> String? {
    for child in Mirror(reflecting: title).children where child.label == "key" {
        return child.value as? String
    }
    return nil
}

public class LandMapView: NSView {
    public var raster: MapRaster

    public init(raster: MapRaster, frame frameRect: NSRect) {
        self.raster = raster
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        return nil
    }

    // Cocotron declares drawRect:. Apple's SDK renames that selector to draw(_:).
    public override func drawRect(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.currentContext()
        _ = context.graphicsPort()
        paint(dirtyRect)
    }

    private func paint(_ dirtyRect: NSRect) {
        let viewBounds = bounds
        let width = raster.width
        let height = raster.height
        guard width > 0, height > 0, viewBounds.size.width > 0, viewBounds.size.height > 0 else {
            return
        }
        NSColor.colorWithCalibratedRed(0.07, green: 0.20, blue: 0.42, alpha: 1).setFill()
        NSBezierPath.fillRect(viewBounds)
        let scaleX = viewBounds.size.width / CGFloat(width)
        let scaleY = viewBounds.size.height / CGFloat(height)
        for y in 0..<height {
            for x in 0..<width {
                let value = raster.at(x: x, y: y)
                if value == 0 { continue }
                let rect = pixelRect(
                    x: x, y: y, scaleX: scaleX, scaleY: scaleY, viewBounds: viewBounds)
                if !overlaps(rect, dirtyRect) { continue }
                if value == 1 {
                    NSColor.colorWithCalibratedRed(0.55, green: 0.64, blue: 0.42, alpha: 1).setFill()
                    NSBezierPath.fillRect(rect)
                } else {
                    NSColor.colorWithCalibratedRed(0.75, green: 0.16, blue: 0.14, alpha: 1).setFill()
                    let dot = NSRect(
                        origin: NSPoint(
                            x: rect.origin.x - scaleX, y: rect.origin.y - scaleY),
                        size: NSSize(width: scaleX * 3, height: scaleY * 3))
                    NSBezierPath.bezierPathWithOvalInRect(dot).fill()
                }
            }
        }
    }

    private func pixelRect(
        x: Int, y: Int, scaleX: CGFloat, scaleY: CGFloat, viewBounds: NSRect
    ) -> NSRect {
        let originY = isFlipped
            ? viewBounds.origin.y + CGFloat(y) * scaleY
            : viewBounds.origin.y + viewBounds.size.height - CGFloat(y + 1) * scaleY
        return NSRect(
            origin: NSPoint(x: viewBounds.origin.x + CGFloat(x) * scaleX, y: originY),
            size: NSSize(width: scaleX, height: scaleY))
    }

    private func overlaps(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        lhs.origin.x < rhs.origin.x + rhs.size.width
            && rhs.origin.x < lhs.origin.x + lhs.size.width
            && lhs.origin.y < rhs.origin.y + rhs.size.height
            && rhs.origin.y < lhs.origin.y + lhs.size.height
    }
}

public struct LandMapRepresentable: NSViewRepresentable {
    public var raster: MapRaster

    public init(raster: MapRaster) { self.raster = raster }

    public func makeNSView(context: Context) -> LandMapView {
        LandMapView(
            raster: raster,
            frame: NSRect(
                origin: NSPoint(x: 0, y: 0),
                size: NSSize(width: CGFloat(raster.width), height: CGFloat(raster.height))))
    }

    public func updateNSView(_ nsView: LandMapView, context: Context) {
        nsView.raster = raster
        nsView.setNeedsDisplay(true)
    }
}
