// SPDX-License-Identifier: MIT
import Synchronization

final class Token: Sendable {}

@main struct Probe {
    static func main() {
        let counter = Atomic<UInt32>(5)
        precondition(counter.wrappingAdd(2, ordering: .relaxed).oldValue == 5)
        precondition(counter.compareExchange(expected: 7, desired: 11, ordering: .acquiringAndReleasing).exchanged)
        precondition(!counter.compareExchange(expected: 7, desired: 19, ordering: .acquiringAndReleasing).exchanged)
        precondition(counter.load(ordering: .acquiring) == 11)

        let signed = Atomic<Int32>(-6)
        precondition(signed.exchange(-4, ordering: .relaxed) == -6)
        precondition(signed.load(ordering: .acquiring) == -4)

        let state = Mutex<[Int]>([])
        state.withLock { $0.append(2) }
        let result = state.withLock { $0.first }
        precondition(result == 2)

        let lazy = AtomicLazyReference<Token>()
        let first = Token()
        precondition(lazy.load() == nil)
        precondition(lazy.storeIfNil(first) === first)
        precondition(lazy.storeIfNil(Token()) === first)
        precondition(lazy.load() === first)
        print("Synchronization PASS for atomic operations, lock state and lazy identity")
    }
}
