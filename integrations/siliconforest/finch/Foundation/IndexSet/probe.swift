// SPDX-License-Identifier: MIT
import Foundation

@main
struct Probe {
    static func main() {
        var indices = IndexSet(integersIn: 1..<5)
        indices.insert(integersIn: 12..<16)
        precondition(Array(indices.rangeView) == [1..<5, 12..<16])
        precondition(Array(indices) == [1, 2, 3, 4, 12, 13, 14, 15])
        precondition(indices.count(in: 3..<13) == 3)
        precondition(!indices.intersects(integersIn: 5..<12))
        let copy = indices
        precondition(indices.remove(2) == 2)
        precondition(copy.contains(2) && !indices.contains(2))
        precondition(Array(copy.filteredIndexSet { $0 % 2 == 0 }) == [2, 4, 12, 14])
        precondition(IndexSet._unconditionallyBridgeFromObjectiveC(copy._bridgeToObjectiveC()) == copy)
        print("IndexSet ranges, filtering, copy-on-write and Objective-C bridge PASS")
    }
}
