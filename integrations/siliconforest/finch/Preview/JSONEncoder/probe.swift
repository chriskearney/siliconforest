// SPDX-License-Identifier: MIT
import Foundation

private func require(_ condition: @autoclosure () throws -> Bool) rethrows {
    let passed = try condition()
    precondition(passed)
}

private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

private struct Child: Codable, Equatable { let value: Int }
private struct Model: Codable, Equatable {
    let text: String
    let flag: Bool
    let signed: Int64
    let unsigned: UInt64
    let floating: Double
    let children: [Child]
    let optional: String?
    let data: Data
    let url: URL
    let date: Date
}

private struct Custom: Encodable {
    enum Keys: String, CodingKey { case values, child }
    func encode(to encoder: Encoder) throws {
        precondition(encoder.userInfo[CodingUserInfoKey(rawValue: "sentinel")!] as? String == "context")
        var container = encoder.container(keyedBy: Keys.self)
        var values = container.nestedUnkeyedContainer(forKey: .values)
        try values.encode(7)
        try values.encode(9)
        try Child(value: 11).encode(to: container.superEncoder(forKey: .child))
    }
}
private struct CustomResult: Decodable { let values: [Int]; let child: Child }
private struct Named: Codable { let firstName: String; let myURLProperty: Int; let élèveName: String }
private struct CustomKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private struct UnicodeNames: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CustomKey.self)
        try container.encode(1, forKey: CustomKey(stringValue: "aÉclairKey"))
        try container.encode(2, forKey: CustomKey(stringValue: "a𐐀valueKey"))
    }
}
private struct NonFinite: Encodable { let value: Double }
private enum Deliberate: Error { case failure }
private struct Failing: Encodable {
    func encode(to encoder: Encoder) throws { throw Deliberate.failure }
}
private struct Empty: Encodable {
    func encode(to encoder: Encoder) throws { }
}

@main struct Probe {
    static func main() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let model = Model(text: "quote\" slash/ back\\ newline\n tab\t nul\0 é🤖", flag: true,
                          signed: Int64.min, unsigned: UInt64.max, floating: -123.5,
                          children: [Child(value: 7), Child(value: 9)], optional: nil,
                          data: Data([0,1,2,255]), url: URL(string: "https://example.invalid/a")!,
                          date: Date(timeIntervalSince1970: 123.5))
        try require(try decoder.decode(Model.self, from: encoder.encode(model)) == model)
        try require(text(try encoder.encode("/")) == #""\/""#)
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try require(text(try encoder.encode("/")) == #""/""#)

        encoder.outputFormatting = [.sortedKeys]
        try require(text(try encoder.encode(["z":1,"a":2,"10":3,"2":4])) == #"{"10":3,"2":4,"a":2,"z":1}"#)
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let pretty = try encoder.encode(model)
        precondition(text(pretty).contains("\n"))
        try require(try decoder.decode(Model.self, from: pretty) == model)

        // Direct array fast paths and writer preformatted/pretty paths.
        let formats: [JSONEncoder.OutputFormatting] = [[], [.prettyPrinted]]
        for options in formats {
            encoder.outputFormatting = options
            let integers: [Int64] = [Int64.min, -1, 0, 9007199254740993, Int64.max]
            try require(try decoder.decode([Int64].self, from: encoder.encode(integers)) == integers)
            let unsigned: [UInt64] = [0, UInt64.max]
            try require(try decoder.decode([UInt64].self, from: encoder.encode(unsigned)) == unsigned)
            let strings = ["", "a/b", "é🤖", "\0\n\"\\"]
            try require(try decoder.decode([String].self, from: encoder.encode(strings)) == strings)
            let floats: [Double] = [-0.0, 1.25, 1e100]
            let back = try decoder.decode([Double].self, from: encoder.encode(floats))
            precondition(back == floats && back[0].sign == .minus)
        }

        encoder.userInfo[CodingUserInfoKey(rawValue: "sentinel")!] = "context"
        let custom = try decoder.decode(CustomResult.self, from: encoder.encode(Custom()))
        precondition(custom.values == [7,9] && custom.child.value == 11)
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let named = try encoder.encode(Named(firstName: "Ada", myURLProperty: 7, élèveName: "é"))
        let keys = try decoder.decode([String: StringOrInt].self, from: named)
        precondition(keys.keys.sorted() == ["first_name", "my_url_property", "élève_name"])
        let unicodeKeys = try decoder.decode([String: Int].self, from: encoder.encode(UnicodeNames()))
        precondition(unicodeKeys["a_éclair_key"] == 1 && unicodeKeys["a_𐐨value_key"] == 2)
        try require(try decoder.decode([String: Int].self, from: encoder.encode(["rawKey":2]))["rawKey"] == 2)
        encoder.keyEncodingStrategy = .custom { path in CustomKey(stringValue: "x_" + path.last!.stringValue) }
        try require(try decoder.decode([String: Int].self, from: encoder.encode(Child(value: 3)))["x_value"] == 3)
        encoder.keyEncodingStrategy = .useDefaultKeys

        do { _ = try encoder.encode(["payload": NonFinite(value: .infinity)]); preconditionFailure() }
        catch EncodingError.invalidValue(_, let context) {
            precondition(context.codingPath.map(\.stringValue) == ["payload", "value"])
        }
        do { _ = try encoder.encode(Double.nan); preconditionFailure() }
        catch EncodingError.invalidValue { }
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NAN")
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NAN")
        let nonFinite = try decoder.decode([Double].self, from: encoder.encode([Double.infinity, -.infinity, .nan]))
        precondition(nonFinite[0] == .infinity && nonFinite[1] == -.infinity && nonFinite[2].isNaN)
        do { _ = try encoder.encode(Failing()); preconditionFailure() }
        catch Deliberate.failure { }
        do { _ = try encoder.encode(Empty()); preconditionFailure() }
        catch EncodingError.invalidValue { }
        // The encoder remains usable after both library and user failures.
        try require(try decoder.decode(Child.self, from: encoder.encode(Child(value: 5))).value == 5)

        let decimal = try decoder.decode(Decimal.self, from: Data("123456789.125".utf8))
        try require(text(try encoder.encode(decimal)) == "123456789.125")
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        try require(try decoder.decode(Date.self, from: encoder.encode(model.date)) == model.date)
        encoder.dataEncodingStrategy = .deferredToData
        decoder.dataDecodingStrategy = .deferredToData
        try require(try decoder.decode(Data.self, from: encoder.encode(model.data)) == model.data)
        encoder.dateEncodingStrategy = .iso8601
        do { _ = try encoder.encode(model.date); preconditionFailure() }
        catch SFJSONEncoderUnavailable.iso8601DateStrategy { }

        print("JSONEncoder PASS real-Encodable/redecode nested/custom/super/context unicode/escaping sorted/pretty/direct-arrays integer-boundaries decimal/data/date key-strategies failure-paths/reuse iso8601-explicit-unavailable")
    }
}

private struct StringOrInt: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if (try? container.decode(String.self)) == nil { _ = try container.decode(Int.self) }
    }
}
