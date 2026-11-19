// SPDX-License-Identifier: MIT
import CoreFoundation

// Optional date-format machinery is unavailable in this coherent Foundation.
// Never pretend an ISO date decoded successfully.
public enum SFJSONDecoderUnavailable: Error { case iso8601DateStrategy }

internal func _sfJSONCapitalized(_ value: String) -> String {
    let cf = unsafeBitCast(value._bridgeToObjectiveC(), to: CFString.self)
    let result = CFStringCreateMutableCopy(nil, 0, cf)!
    CFStringCapitalize(result, nil)
    return String._unconditionallyBridgeFromObjectiveC(unsafeBitCast(result, to: NSString.self))
}

internal func _sfJSONString(bytes: BufferView<UInt8>, encoding: String.Encoding) -> String? {
    let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
    return bytes.withUnsafeBufferPointer { buffer in
        guard let cf = CFStringCreateWithBytes(nil, buffer.baseAddress, buffer.count, cfEncoding, false) else { return nil }
        return String._unconditionallyBridgeFromObjectiveC(unsafeBitCast(cf, to: NSString.self))
    }
}

extension String {
    internal static func _tryFromUTF8(_ input: UnsafeBufferPointer<UInt8>) -> String? {
        String(validating: input, as: UTF8.self)
    }
}
