// SPDX-License-Identifier: MIT

@available(macOS 14, *)
extension ObservationTracking {
    @_spi(SwiftUI)
    public static func _collectAccesses<Value>(
        _ work: () throws -> Value
    ) rethrows -> (value: Value, accessList: _AccessList?) {
        var accesses: _AccessList?
        let value = try withUnsafeMutablePointer(to: &accesses) { pointer in
            let previous = _ThreadLocal.value
            _ThreadLocal.value = UnsafeMutableRawPointer(pointer)
            defer { _ThreadLocal.value = previous }
            return try work()
        }
        return (value, accesses)
    }

    @_spi(SwiftUI)
    public static func _mergeAccessLists(_ list: inout _AccessList, _ other: _AccessList) {
        list.merge(other)
    }
}
