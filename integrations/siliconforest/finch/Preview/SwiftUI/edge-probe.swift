import SwiftUI
@main struct EdgeProof {
  static func main() {
    precondition(Edge.allCases.map(\.rawValue) == [0, 1, 2, 3])
    precondition(Edge(rawValue: -1) == nil && Edge(rawValue: 4) == nil)
    precondition(MemoryLayout<Edge>.size == 1 && MemoryLayout<Edge.Set>.size == 1)
    let edges: [Edge] = [.top, .leading, .bottom, .trailing]
    for edge in edges {
      precondition(Edge.Set(edge).rawValue == 1 << edge.rawValue)
    }
    precondition(Edge.Set.all.rawValue == 15)
    precondition(Edge.Set.horizontal == [.leading, .trailing])
    precondition(Edge.Set.vertical == [.top, .bottom])
    precondition(Edge.Set.horizontal.intersection(.vertical).isEmpty)
    precondition(Edge.Set.horizontal.union(.vertical) == .all)
    precondition(Edge.Set.all.subtracting(.horizontal) == .vertical)
    precondition(Edge.Set.all.symmetricDifference(.vertical) == .horizontal)
    precondition(HorizontalEdge.Set.all == [.leading, .trailing])
    precondition(VerticalEdge.Set.all == [.top, .bottom])
    precondition(MemoryLayout<HorizontalEdge>.size == 1 && MemoryLayout<VerticalEdge>.size == 1)
    print("OpenSwiftUI Edge PASS case/raw/invalid/frozen-size/single-bit/set-algebra/horizontal/vertical")
  }
}
