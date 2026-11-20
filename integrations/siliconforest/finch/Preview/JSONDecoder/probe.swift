// SPDX-License-Identifier: MIT
import Foundation

private func require(_ condition: @autoclosure () throws -> Bool) rethrows {
    let passed = try condition()
    precondition(passed)
}

private func bytes(_ text: String) -> Data { Data(text.utf8) }

private struct Child: Decodable {
    let value: Int
}

private struct Model: Decodable {
    let text: String
    let flag: Bool
    let integer: Int64
    let unsigned: UInt64
    let real: Double
    let children: [Child]
    let optional: String?
    let dictionary: [String: Int]
}

private struct Retained: Decodable {
    let decoder: Decoder
    init(from decoder: Decoder) throws { self.decoder = decoder }
}

private struct Named: Decodable { let firstName: String }
private struct Wrapper: Decodable { let payload: Child }

private struct Context: Decodable {
    let number: Int
    init(from decoder: Decoder) throws {
        precondition(decoder.userInfo[CodingUserInfoKey(rawValue: "sentinel")!] as? String == "context")
        let container = try decoder.singleValueContainer()
        number = try container.decode(Int.self) + 1
    }
}

@main struct Probe {
    static func main() throws {
        let decoder = JSONDecoder()
        let input = #"{"text":"A\n\u00e9\uD83E\uDD16","flag":true,"integer":-9223372036854775808,"unsigned":18446744073709551615,"real":1.25e2,"children":[{"value":7},{"value":9}],"optional":null,"dictionary":{"raw_key":2},"ignored":{"x":[1,2]}}"#
        let model = try decoder.decode(Model.self, from: bytes(input))
        precondition(model.text == "A\né🤖" && model.flag)
        precondition(model.integer == Int64.min && model.unsigned == UInt64.max)
        precondition(model.real == 125 && model.children.map(\.value) == [7, 9])
        precondition(model.optional == nil && model.dictionary["raw_key"] == 2)
        try require(try decoder.decode(Int64.self, from: bytes("9007199254740993.0")) == 9007199254740993)
        try require(try decoder.decode([Bool?].self, from: bytes("[true,null,false]")) == [true,nil,false])

        decoder.userInfo[CodingUserInfoKey(rawValue: "sentinel")!] = "context"
        try require(try decoder.decode(Context.self, from: bytes("41")).number == 42)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        try require(try decoder.decode(Named.self, from: bytes(#"{"first_name":"Ada"}"#)).firstName == "Ada")
        try require(try decoder.decode([String: Int].self, from: bytes(#"{"raw_key":2}"#))["raw_key"] == 2)
        decoder.keyDecodingStrategy = .useDefaultKeys

        let retained: Retained = try {
            let data = bytes(#"{"large":[0,1,2,3],"text":"retained"}"#)
            return try decoder.decode(Retained.self, from: data)
        }()
        enum Keys: String, CodingKey { case text }
        let retainedContainer = try retained.decoder.container(keyedBy: Keys.self)
        try require(try retainedContainer.decode(String.self, forKey: .text) == "retained")

        let malformed = ["", "{", "[1,", #"{"x":tru}"#, #""\uD800""#, "01", "1 trailing"]
        var corrupt = 0
        for text in malformed {
            do {
                _ = try decoder.decode(Int.self, from: bytes(text))
                preconditionFailure("Malformed input accepted: \(text)")
            } catch DecodingError.dataCorrupted { corrupt += 1 }
              catch DecodingError.typeMismatch {
                // Request the actual value to force validation of lazy string contents.
                do { _ = try decoder.decode(String.self, from: bytes(text)); preconditionFailure() }
                catch DecodingError.dataCorrupted { corrupt += 1 }
            }
        }
        precondition(corrupt == malformed.count)
        do { _ = try decoder.decode(Wrapper.self, from: bytes(#"{"payload":{"value":"wrong"}}"#)); preconditionFailure() }
        catch DecodingError.typeMismatch(_, let context) {
            precondition(context.codingPath.map(\.stringValue) == ["payload", "value"])
        }
        do { _ = try decoder.decode(Child.self, from: bytes("{}")); preconditionFailure() }
        catch DecodingError.keyNotFound(let key, _) { precondition(key.stringValue == "value") }
        do { _ = try decoder.decode(Int.self, from: bytes("null")); preconditionFailure() }
        catch DecodingError.valueNotFound { }
        do { _ = try decoder.decode(UInt8.self, from: bytes("256")); preconditionFailure() }
        catch DecodingError.dataCorrupted { }

        let invalidUTF8: [UInt8] = [0x22, 0xff, 0x22]
        do { _ = try decoder.decode(String.self, from: Data(invalidUTF8)); preconditionFailure() }
        catch DecodingError.dataCorrupted { }
        let decimal = try decoder.decode(Decimal.self, from: bytes("123456789.125"))
        precondition(decimal.description == "123456789.125")

        let payload = try decoder.decode(Data.self, from: bytes(#""AAEC/w==""#))
        precondition(Array(payload) == [0,1,2,255])
        decoder.dateDecodingStrategy = .secondsSince1970
        try require(try decoder.decode(Date.self, from: bytes("123.5")).timeIntervalSince1970 == 123.5)
        decoder.dateDecodingStrategy = .iso8601
        do { _ = try decoder.decode(Date.self, from: bytes(#""2026-11-19T00:00:00Z""#)); preconditionFailure() }
        catch SFJSONDecoderUnavailable.iso8601DateStrategy { }

        let utf16: [UInt8] = [0xff,0xfe,0x34,0,0x32,0]
        try require(try decoder.decode(Int.self, from: Data(utf16)) == 42)
        decoder.allowsJSON5 = true
        try require(try decoder.decode(Child.self, from: bytes("{/*comment*/value:7}")).value == 7)
        print("JSONDecoder PASS real-Decodable nested/custom/context/retained-decoder scalar/range/precision unicode/UTF16 base64 JSON5 coding-path-errors iso8601-explicit-unavailable")
    }
}
