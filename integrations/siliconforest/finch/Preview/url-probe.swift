// SPDX-License-Identifier: MIT
// Synthetic value/bridge/lifetime checks only. No file is opened or written.
import Foundation

private struct ProbeError: LocalizedError, CustomNSError {
    static var errorDomain: String { "org.siliconforest.foundation-probe" }
    var errorCode: Int { 19 }
    var errorDescription: String? { "test error" }
    var errorUserInfo: [String: Any] { ["code": errorCode] }
}

@main
struct URLProbe {
    static func main() {
        let path = "/tmp/preview URL fixture"
        let reference = NSURL(fileURLWithPath: path)
        let value = URL._unconditionallyBridgeFromObjectiveC(reference)
        precondition(value.isFileURL && value.path == path)
        precondition(value._bridgeToObjectiveC() === reference)
        precondition(URL(string: "") == nil)
        let base = URL(fileURLWithPath: "/tmp/Preview fixtures", isDirectory: true)
        let pdf = base.appendingPathComponent("report draft").appendingPathExtension("pdf")
        precondition(pdf.isFileURL && pdf.path == "/tmp/Preview fixtures/report draft.pdf")
        precondition(pdf.lastPathComponent == "report draft.pdf" && pdf.pathExtension == "pdf")
        precondition(pdf.absoluteString.hasSuffix("/report%20draft.pdf"))
        let remote = URL(string: "https://example.invalid/preview/")!
        let image = remote.appendingPathComponent("cover sheet").appendingPathExtension("png")
        precondition(image.absoluteString == "https://example.invalid/preview/cover%20sheet.png")
        precondition(image.lastPathComponent == "cover sheet.png" && image.pathExtension == "png")
        let urlCoding: any Codable = pdf
        precondition(urlCoding is URL)
        precondition(!value.startAccessingSecurityScopedResource())
        value.stopAccessingSecurityScopedResource()
        var values: Set<URL> = []
        for _ in 0..<10000 {
            let copy = value
            values.insert(copy)
            precondition(copy.path == path && copy._bridgeToObjectiveC() === reference)
        }
        precondition(values.count == 1)
        let dictionary = ["meaning": 42]
        let bridged = dictionary as NSDictionary
        let restored = bridged as! [String: Int]
        precondition(restored == dictionary)
        let text: NSString = "legacy string"
        precondition((text as String) == "legacy string")
        let date = Date(timeIntervalSinceReferenceDate: 123)
        precondition((date as NSDate).timeIntervalSinceReferenceDate() == 123)
        let error = ProbeError()
        let localized: any LocalizedError = error
        let custom: any CustomNSError = error
        precondition(localized.errorDescription == "test error")
        precondition(localized.recoverySuggestion == nil && localized.helpAnchor == nil)
        precondition(type(of: custom).errorDomain == "org.siliconforest.foundation-probe")
        precondition(custom._code == 19 && custom.errorUserInfo["code"] as? Int == 19)
        let plain: LocalizedStringResource = "Open PDF"
        precondition(String(localized: plain) == "Open PDF")
        let name = "Résumé.pdf"
        let count = 2
        let message: LocalizedStringResource = "100% done: \(name), \(count, specifier: "%lld") pages"
        precondition(message.key == "100%% done: %@, %lld pages")
        precondition(String(localized: message) == "100% done: Résumé.pdf, 2 pages")
        precondition(!Locale.current.identifier.isEmpty)
        if CommandLine.arguments.count == 2 {
            let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let localized = LocalizedStringResource("PDF page", defaultValue: "PDF page",
                                                    bundle: .atURL(bundleURL))
            precondition(String(localized: localized) == "PDF page from the bundle")
        }
        let allowedCharacters = CharacterSet(charactersIn: "a/é😀")
        precondition(allowedCharacters.contains("é") && allowedCharacters.contains("😀"))
        let raw = "a %/é😀"
        precondition(raw[...].addingPercentEncoding(withAllowedCharacters: allowedCharacters) ==
                     "a%20%25/%C3%A9%F0%9F%98%80")
        precondition("".addingPercentEncoding(withAllowedCharacters: allowedCharacters) == "")
        let existing = CharacterSet(charactersIn: "%2f")
        precondition("%2f".addingPercentEncoding(withAllowedCharacters: existing) == "%2f")
        print("Character set membership and UTF-8 URL encoding=PASS")
        print("LocalizedError and CustomNSError dispatch=PASS")
        print("Localization literal, interpolation, and current locale=PASS")
        print("URL bridge, path operations, Codable conformance, and 10000 copies=PASS")
    }
}
