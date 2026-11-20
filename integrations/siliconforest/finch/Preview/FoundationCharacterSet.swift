// SPDX-License-Identifier: MIT
public struct CharacterSet: Sendable {
    private let members: Set<Unicode.Scalar>

    public init(charactersIn string: __shared String) {
        members = Set(string.unicodeScalars)
    }

    public func contains(_ member: Unicode.Scalar) -> Bool {
        members.contains(member)
    }
}

public extension StringProtocol {
    func addingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
        let hex = Array("0123456789ABCDEF".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(utf8.count)
        for byte in utf8 {
            if byte < 0x80 && allowedCharacters.contains(Unicode.Scalar(byte)) {
                output.append(byte)
            } else {
                output.append(0x25)
                output.append(hex[Int(byte >> 4)])
                output.append(hex[Int(byte & 0x0F)])
            }
        }
        return String(decoding: output, as: UTF8.self)
    }
}
