// SPDX-License-Identifier: MIT
import Combine
@main struct Probe {
    static func main() {
        let source = PassthroughSubject<Int, Never>()
        var events: [Int] = []
        var completed = false
        let subscription = source
            .filter { $0.isMultiple(of: 2) }
            .map { $0 * 3 }
            .sink(receiveCompletion: { _ in completed = true },
                  receiveValue: { events.append($0) })
        for n in 1...5 { source.send(n) }
        source.send(completion: .finished)
        source.send(8)
        withExtendedLifetime(subscription) {}
        precondition(events == [6, 12] && completed)
        var current: [String] = []
        let subject = CurrentValueSubject<String, Never>("begin")
        let second = subject.sink { current.append($0) }
        subject.value = "end"
        second.cancel()
        subject.value = "ignored"
        precondition(current == ["begin", "end"])
        print("Combine PASS for demand, mapping, completion and cancellation")
    }
}
