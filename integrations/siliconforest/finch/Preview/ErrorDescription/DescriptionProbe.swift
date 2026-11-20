// SPDX-License-Identifier: MIT OR Apache-2.0
// Headless Error.localizedDescription probe. Does not launch an app.

import Foundation

@_silgen_name("sf_localized_description_symbol")
func sf_localized_description_symbol() -> Int32

private struct Described: LocalizedError {
    var errorDescription: String? { "sf-custom-desc" }
    var failureReason: String? { "sf-custom-reason" }
}

private struct Both: LocalizedError, CustomNSError {
    static var errorDomain: String { "SFDescDomain" }
    var errorCode: Int { 9 }
    var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: "sf-userinfo-desc"] }
    var errorDescription: String? { "sf-both-desc" }
}

private struct Plain: CustomNSError {
    static var errorDomain: String { "SFPlain" }
    var errorCode: Int { 3 }
}

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: String) {
    if ok {
        print("PASS \(name) \(detail)")
    } else {
        print("FAIL \(name) \(detail)")
        failures += 1
    }
}

@main
enum DescriptionProbe {
    static func main() {
        check("symbol", sf_localized_description_symbol() == 1, "found=\(sf_localized_description_symbol())")

        guard let native = NSError(domain: "SFNative", code: 4, userInfo: [NSLocalizedDescriptionKey: "sf-native-text"]) else {
            print("FAIL native-init nil")
            exit(1)
        }
        let boxed: any Error = native
        let embedded = boxed._getEmbeddedNSError()
        check(
            "nserror-identity",
            embedded === native
                && boxed.localizedDescription == native.localizedDescription
                && boxed.localizedDescription == "sf-native-text",
            "same=\(embedded === native) text=\(boxed.localizedDescription) native=\(native.localizedDescription)"
        )

        guard let bare = NSError(domain: "SFNative", code: 5, userInfo: nil) else {
            print("FAIL bare-init nil")
            exit(1)
        }
        let bareBoxed: any Error = bare
        let bareText = bareBoxed.localizedDescription
        let bareNative = bare.localizedDescription
        check(
            "nserror-fallback",
            bareBoxed._getEmbeddedNSError() === bare && bareText == bareNative && bareText == "SFNative error 5",
            "same=\(bareBoxed._getEmbeddedNSError() === bare) text=\(bareText) native=\(bareNative)"
        )

        let described = Described()
        let describedText = described.localizedDescription
        guard let describedNative = NSError(
            domain: described._domain,
            code: described._code,
            userInfo: [NSLocalizedDescriptionKey: "sf-custom-desc"]
        ) else {
            print("FAIL described-native nil")
            exit(1)
        }
        check(
            "localized-custom",
            describedText == "sf-custom-desc" && describedText == describedNative.localizedDescription,
            "text=\(describedText) native=\(describedNative.localizedDescription) domain=\(described._domain) code=\(described._code)"
        )

        let both = Both()
        check(
            "localized-overrides-userinfo",
            both.localizedDescription == "sf-both-desc" && both._domain == "SFDescDomain" && both._code == 9,
            "text=\(both.localizedDescription) domain=\(both._domain) code=\(both._code)"
        )

        let urlError = URLError(.unsupportedURL, userInfo: [NSLocalizedDescriptionKey: "sf-url-desc"])
        let urlBoxed: any Error = urlError
        check(
            "urlerror-stored",
            urlBoxed._getEmbeddedNSError() === urlError._nsError
                && urlBoxed.localizedDescription == "sf-url-desc"
                && urlBoxed.localizedDescription == urlError._nsError.localizedDescription,
            "same=\(urlBoxed._getEmbeddedNSError() === urlError._nsError) text=\(urlBoxed.localizedDescription)"
        )

        let plain = Plain()
        let plainText = plain.localizedDescription
        let plainNative = NSError(domain: "SFPlain", code: 3, userInfo: nil)?.localizedDescription
        check(
            "custom-without-description",
            plainText == plainNative && plainText == "SFPlain error 3" && plain._domain == "SFPlain" && plain._code == 3,
            "text=\(plainText) native=\(plainNative ?? "nil") domain=\(plain._domain) code=\(plain._code)"
        )

        if failures == 0 {
            print("DESCRIPTION PROBE PASS")
            exit(0)
        }
        print("DESCRIPTION PROBE FAIL \(failures)")
        exit(1)
    }
}
