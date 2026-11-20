// SPDX-License-Identifier: MIT
import Foundation
import Darwin

enum Score: CodableAttributedStringKey {
    typealias Value = Int
    static let name = "org.siliconforest.probe.score"
}
struct ProbeScope: AttributeScope {
    let score: Score
    let foundation: AttributeScopes.FoundationAttributes
}
struct ScopedText: Codable, Equatable {
    var text: AttributedString
    enum Keys: String, CodingKey { case text }
    init(_ text: AttributedString) { self.text = text }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        text = try c.decode(AttributedString.self, forKey: .text, configuration: ProbeScope.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(text, forKey: .text, configuration: ProbeScope.self)
    }
}
@main struct Probe {
    static func main() throws {
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            if !value() { print("FAIL \(name)"); fflush(stdout); exit(1) }
            print("PASS \(name)"); fflush(stdout)
        }
        let original = AttributedString("Aé👩🏽‍💻e\u{301}\nline")
        check(String(original.characters) == "Aé👩🏽‍💻e\u{301}\nline", "unicode text")
        check(original.characters.count == 9, "grapheme count")
        check(Array(original.utf8) == Array("Aé👩🏽‍💻e\u{301}\nline".utf8), "UTF8")
        check(Array(original.utf16) == Array("Aé👩🏽‍💻e\u{301}\nline".utf16), "UTF16")
        var text = AttributedString("Hello café and café")
        let first = text.range(of: "café")!
        text[first][Score.self] = 7
        text[first].languageIdentifier = "fr"
        text[first].link = URL(string: "https://example.invalid/reader")!
        check(text[first][Score.self] == 7 && text[first].languageIdentifier == "fr", "range attributes")
        check(text.runs.count == 3, "run boundaries")
        check(String(text[first].characters) == "café", "substring")
        var copy = text
        copy[first][Score.self] = 9
        check(text[first][Score.self] == 7 && copy[first][Score.self] == 9, "copy on write")
        check(text != copy && Set([text, text, copy]).count == 2, "equality hash")
        let last = text.range(of: "CAFÉ", options: String.CompareOptions(rawValue: 5))!
        check(last.lowerBound != first.lowerBound, "backwards case search")
        check(text.range(of: "CAFÉ", options: String.CompareOptions(rawValue: 1), locale: Locale(identifier: "fr_FR")) == first, "localized search")
        check(text.range(of: "c.fé", options: String.CompareOptions(rawValue: 1024)) == first, "regex search")
        check(text.range(of: "missing") == nil, "no match")
        check(AttributedString("").range(of: "^", options: String.CompareOptions(rawValue: 1024)) != nil, "empty text regex")
        check(text.range(of: "[", options: String.CompareOptions(rawValue: 1024)) == nil, "invalid regex")
        check(text.range(of: "c.fé", options: String.CompareOptions(rawValue: 1028)) == last, "backwards regex")
        check(text.range(of: "c.fé", options: String.CompareOptions(rawValue: 1032)) == nil, "anchored regex")
        copy.replaceSubrange(last, with: AttributedString("tea"))
        check(String(copy.characters) == "Hello café and tea", "replace text")
        copy.append(AttributedString("!"))
        check(String(copy.characters) == "Hello café and tea!", "append")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(ScopedText(text))
        let round = try decoder.decode(ScopedText.self, from: data)
        check(round.text == text, "custom scope Codable")
        let defaults = try decoder.decode(AttributedString.self, from: encoder.encode(text))
        check(defaults[first].link == text[first].link && defaults[first].languageIdentifier == "fr", "default scope Codable")
        check(defaults[first][Score.self] == nil, "unknown attributes omitted by default scope")
        var many = AttributedString("")
        for i in 0..<24 { var t = AttributedString("\(i),"); t[Score.self] = i % 3; many.append(t) }
        check(many.runs.count == 24, "many runs")
        let tableData = try encoder.encode(ScopedText(many))
        let tableRound = try decoder.decode(ScopedText.self, from: tableData)
        check(tableRound.text == many, "attribute table Codable")
        let plain = AttributedString("plain")
        let plainRound = try decoder.decode(AttributedString.self, from: encoder.encode(plain))
        check(plainRound == plain, "plain Codable")
        do { _ = try decoder.decode(AttributedString.self, from: Data("[1]".utf8)); check(false, "malformed rejection") }
        catch { print("PASS malformed rejection \(error)") }
        check(String(reflecting: AttributedString.self) == "Foundation.AttributedString", "metadata")
        print("PASS AttributedString separate-client probe")
    }
}
