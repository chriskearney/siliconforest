// SPDX-License-Identifier: MIT
import Foundation
import UUIDInteropClient

@main struct Probe {
    static func main() {
        let expected = "00112233-4455-6677-8899-AABBCCDDEEFF"
        let value = parseUUID(expected.lowercased())!
        precondition(canonicalUUID(copyUUID(value)) == expected)
        precondition(value.uuid.0 == 0 && value.uuid.1 == 0x11 && value.uuid.15 == 0xff)
        let bytes: uuid_t = (0,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff)
        precondition(UUID(uuid: bytes) == value)
        precondition(Set([value, UUID(uuid: bytes)]).count == 1)
        let invalid = ["", "invalid", expected + "x", " " + expected, expected + " ",
            expected + "\0tail", "00112233-4455-6677-8899-GABBCCDDEEFF",
            "00112233445566778899AABBCCDDEEFF", "00112233-4455-6677-8899-AABBCCDDEEé"]
        for string in invalid { precondition(parseUUID(string) == nil) }
        precondition(parseUUID("00000000-0000-0000-0000-000000000000")!.uuidString == "00000000-0000-0000-0000-000000000000")
        var seen = Set<UUID>()
        for _ in 0..<1000 {
            let generated = makeUUID()
            let raw = generated.uuid
            precondition(raw.6 & 0xf0 == 0x40 && raw.8 & 0xc0 == 0x80)
            precondition(parseUUID(canonicalUUID(generated)) == generated)
            precondition(seen.insert(generated).inserted)
        }
        var copies = [UUID](repeating: value, count: 10000)
        copies[0] = makeUUID()
        precondition(copies[0] != value && copies[9999] == value)
        precondition(MemoryLayout<UUID>.size == 16 && MemoryLayout<UUID>.stride == 16)
        print("UUID PASS parse/format/bytes invalid=\(invalid.count) v4-unique=\(seen.count) copies=\(copies.count) cross-library ABI size=\(MemoryLayout<UUID>.size) type=\(String(reflecting: UUID.self))")
    }
}
