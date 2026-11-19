// SPDX-License-Identifier: MIT
@_spi(SwiftUI) import Observation

private final class Document: Observable, @unchecked Sendable {
    let registrar = ObservationRegistrar()
    private var currentPage = 1
    private var currentZoom = 100

    var page: Int {
        get {
            registrar.access(self, keyPath: \.page)
            return currentPage
        }
        set {
            registrar.withMutation(of: self, keyPath: \.page) {
                currentPage = newValue
            }
        }
    }

    var zoom: Int {
        get {
            registrar.access(self, keyPath: \.zoom)
            return currentZoom
        }
        set {
            registrar.willSet(self, keyPath: \.zoom)
            currentZoom = newValue
            registrar.didSet(self, keyPath: \.zoom)
        }
    }
}

// Callbacks are synchronous on the single thread driving this probe.
private final class Notifications: @unchecked Sendable {
    var pages: [Int] = []
    var zooms: [Int] = []
    var nested = 0
    var trackedPaths: [AnyKeyPath] = []
}

@main
private enum Probe {
    static func main() {
        let document = Document()
        let unrelated = Document()
        let notes = Notifications()
        let visiblePage = withObservationTracking {
            document.page
        } onChange: {
            notes.pages.append(document.page)
        }
        precondition(visiblePage == 1)
        unrelated.page = 2
        document.zoom = 125
        precondition(notes.pages.isEmpty)
        document.page = 2
        document.page = 3
        precondition(notes.pages == [1] && document.page == 3)

        let observed = withObservationTracking {
            withObservationTracking {
                document.zoom
            } onChange: {
                notes.zooms.append(document.zoom)
            }
        } onChange: {
            notes.nested += 1
        }
        precondition(observed == 125)
        document.zoom = 130
        document.zoom = 140
        precondition(notes.zooms == [125] && notes.nested == 1 && document.zoom == 140)
        let (page, pageAccesses) = ObservationTracking._collectAccesses { document.page }
        let (zoom, zoomAccesses) = ObservationTracking._collectAccesses { document.zoom }
        precondition(page == 3 && zoom == 140)
        guard var accesses = pageAccesses, let zoomAccesses else {
            preconditionFailure("Missing SwiftUI access lists")
        }
        ObservationTracking._mergeAccessLists(&accesses, zoomAccesses)
        let tracking = ObservationTracking(accesses)
        ObservationTracking._installTracking(tracking, willSet: { changed in
            if let keyPath = changed.changed {
                notes.trackedPaths.append(keyPath)
            }
        })
        document.page = 4
        document.zoom = 150
        tracking.cancel()
        document.page = 5
        precondition(notes.trackedPaths == [\Document.page, \Document.zoom])

        print("Observation PASS: key path filtering, one-shot notifications, nested tracking and SwiftUI tracking SPI")
    }
}
