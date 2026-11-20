// SPDX-License-Identifier: MIT
import AppKit
import _AppIntents_AppKit

private struct Item: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fixture"
    static let defaultQuery = Query()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Fixture") }
}

private struct Query: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Item] {
        identifiers.map { Item(id: $0) }
    }
}

@main
private enum Probe {
    static func main() {
        let left = NSView(frame: .zero)
        let right = NSView(frame: .zero)
        precondition(left.appEntityIdentifier == nil && right.appEntityIdentifier == nil)
        let first = EntityIdentifier(for: Item(id: "First"))
        let second = EntityIdentifier(for: Item(id: "Second"))
        left.appEntityIdentifier = first
        right.appEntityIdentifier = second
        precondition(left.appEntityIdentifier == first && right.appEntityIdentifier == second)
        left.appEntityIdentifier = second
        precondition(left.appEntityIdentifier == second)
        right.appEntityIdentifier = nil
        precondition(left.appEntityIdentifier == second && right.appEntityIdentifier == nil)
        print("AppIntents AppKit PASS: per-view identifiers, replacement and removal")
    }
}
