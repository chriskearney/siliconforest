// SPDX-License-Identifier: MIT
import _StringProcessing

@main
private enum Probe {
    static func main() throws {
        let regex = try Regex("p[a-z]+", as: Substring.self).ignoresCase()
        let names = "PDF, png, and pS"
        guard let first = try regex.firstMatch(in: names[...]) else {
            preconditionFailure("No match")
        }
        precondition(names[first.range] == "PDF")
        precondition(names.matches(of: regex).map { String($0.output) } == ["PDF", "png", "pS"])

        let unicode = try Regex("é.+", as: Substring.self)
        let decomposed = "xxe\u{301}lan"
        let match = try unicode.firstMatch(in: decomposed[...])
        precondition(match?.output == "élan")
        do {
            _ = try Regex("(", as: Substring.self)
            preconditionFailure("Invalid pattern accepted")
        } catch {}
        print("Swift Regex PASS: case folding, Unicode, range, repeated matches and invalid pattern")
    }
}
