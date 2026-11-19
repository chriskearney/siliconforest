// SPDX-License-Identifier: MIT OR Apache-2.0
import CoreSpotlight
import UniformTypeIdentifiers

@main struct Probe {
    static func main() {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        precondition(attributes.contentType == "public.item")
        precondition(attributes.contentTypeTree == ["public.item"])
        attributes.displayName = "Survey 🌲"
        attributes.title = "Field notes"
        let copy = attributes.copy() as! CSSearchableItemAttributeSet
        copy.displayName = "Changed"
        precondition(attributes.displayName == "Survey 🌲" && copy.displayName == "Changed")
        precondition(copy.title == "Field notes")
        attributes.displayName = nil
        precondition(attributes.displayName == nil && copy.displayName == "Changed")
        for i in 0..<10000 { attributes.title = "page \(i)" }
        precondition(attributes.title == "page 9999")
        print("CORESPOTLIGHT SWIFT PASS UTType.item identifier title displayName Unicode copy 10000 writes nil removal")
    }
}
