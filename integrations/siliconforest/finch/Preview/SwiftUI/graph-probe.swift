import Foundation
import Compute
import OpenAttributeGraphShims

final class Count { var updates = 0 }
struct Doubled: Rule {
    let input: Attribute<Int>
    let count: Count
    var value: Int { count.updates += 1; return input.value * 2 }
}
final class Token {
    let released: Count
    init(_ released: Count) { self.released = released }
    deinit { released.updates += 1 }
}
struct OwnedBody: Rule {
    let token: Token
    var value: Int { 42 }
}
struct Record { var number: Int; var amount: Double; var text: String }
@main struct GraphProof {
    static func main() {
        setbuf(stdout, nil)
        print("graph probe entered")
        setenv("IAG_PREFETCH_LAYOUTS", "1", 1)
        setenv("IAG_ASYNC_LAYOUTS", "0", 1)
        let graph = Graph()
        let subgraph = Subgraph(graph: graph)
        let count = Count()
        subgraph.apply {
            let input = Attribute(value: 3)
            let output = Attribute(Doubled(input: input, count: count))
            precondition(output.value == 6)
            precondition(output.value == 6 && count.updates == 1)
            input.value = 9
            precondition(output.value == 18 && count.updates == 2)
            output.invalidateValue()
            precondition(output.value == 18 && count.updates == 3)
            print("graph real rule/update/invalidation PASS")
        }
        var fields: [(String, Int)] = []
        forEachField(of: Record.self) { name, offset, _ in fields.append((String(cString: name), offset)) }
        precondition(fields.map { $0.0 } == ["number", "amount", "text"])
        precondition(fields.map { $0.1 } == [MemoryLayout<Record>.offset(of: \.number)!, MemoryLayout<Record>.offset(of: \.amount)!, MemoryLayout<Record>.offset(of: \.text)!])
        print("graph actual Swift metadata field offsets PASS")
        var observed = 0
        let observer = subgraph.addObserver { observed += 1 }
        subgraph.removeObserver(observer)
        let released = Count()
        subgraph.apply {
            let held = Attribute(OwnedBody(token: Token(released)))
            precondition(held.value == 42 && released.updates == 0)
        }
        precondition(released.updates == 0)
        subgraph.invalidate()
        precondition(released.updates == 1)
        precondition(observed == 0)
        precondition(attributeGraphVendor == .compute)
        print("Compute+OAG PASS graph/rule/recompute/invalidation/metadata/observer-removal/body-destruction")
    }
}
