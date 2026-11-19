// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
@_spi(SwiftUI) import Observation

@Observable final class Model { var value = 0 }
final class Counter: @unchecked Sendable { var value = 0 }
enum Expected: Error { case thrown }

@main struct CollectionProof {
    static func main() throws {
        let first = Model(), second = Model(), third = Model()
        let before = ObservationRegistrar.latestAccessLists.count
        let wrapper = _withObservation { first.value }
        precondition(wrapper.accessList != nil && ObservationRegistrar.latestAccessLists.count == before + 1)
        let emptyWrapper = _withObservation { 9 }
        precondition(emptyWrapper.value == 9 && emptyWrapper.accessList == nil)
        precondition(ObservationRegistrar.latestAccessLists.count == before + 1)
        let empty = ObservationTracking._collectAccesses { 7 }
        precondition(empty.value == 7 && empty.accessList == nil)
        let single = ObservationTracking._collectAccesses { first.value }
        precondition(single.value == 0 && single.accessList != nil)
        let sibling = ObservationTracking._collectAccesses { second.value }
        var merged = single.accessList!
        ObservationTracking._mergeAccessLists(&merged, sibling.accessList!)
        let firstChanges = Counter(), secondChanges = Counter()
        let tracking = ObservationTracking(merged)
        ObservationTracking._installTracking(tracking, willSet: { state in
            precondition(state.changed == \Model.value)
            firstChanges.value += 1
        })
        first.value = 1
        precondition(firstChanges.value == 1)
        tracking.cancel()
        first.value = 2
        precondition(firstChanges.value == 1)
        let secondTracking = ObservationTracking(merged)
        ObservationTracking._installTracking(secondTracking, willSet: { _ in secondChanges.value += 1 })
        second.value = 3
        precondition(secondChanges.value == 1)
        secondTracking.cancel()

        // Inner collection must restore the parent's access-list storage on return.
        var inner: ObservationTracking._AccessList?
        let outer = ObservationTracking._collectAccesses {
            _ = first.value
            inner = ObservationTracking._collectAccesses { second.value }.accessList
            return third.value
        }
        precondition(inner != nil && outer.accessList != nil)
        let outerChanges = Counter(), innerChanges = Counter()
        let outerTracking = ObservationTracking(outer.accessList)
        let innerTracking = ObservationTracking(inner)
        ObservationTracking._installTracking(outerTracking, willSet: { _ in outerChanges.value += 1 })
        ObservationTracking._installTracking(innerTracking, willSet: { _ in innerChanges.value += 1 })
        third.value = 4
        precondition(outerChanges.value == 1 && innerChanges.value == 0)
        second.value = 5
        precondition(innerChanges.value == 1)
        outerTracking.cancel(); innerTracking.cancel()

        // Throwing child scopes must also restore the parent's collection.
        let afterThrow = ObservationTracking._collectAccesses {
            do {
                let _: (value: Int, accessList: ObservationTracking._AccessList?) = try ObservationTracking._collectAccesses {
                    _ = second.value
                    throw Expected.thrown
                }
            } catch Expected.thrown {} catch { preconditionFailure("unexpected error") }
            return first.value
        }
        precondition(afterThrow.accessList != nil)
        let throwChanges = Counter()
        let restoredTracking = ObservationTracking(afterThrow.accessList)
        ObservationTracking._installTracking(restoredTracking, willSet: { _ in throwChanges.value += 1 })
        first.value = 6
        precondition(throwChanges.value == 1)
        restoredTracking.cancel()
        print("Observation SwiftUI patched helper + real @Observable macro PASS empty/read/merge/both-models/cancel/nested/throw-restoration")
    }
}
