// SPDX-License-Identifier: MIT OR Apache-2.0
// Headless URLError and _BridgedStoredNSError probe. Does not launch an app.

import Foundation
import Darwin

@_silgen_name("sf_url_error_symbols")
func sf_url_error_symbols(_ missing: UnsafeMutablePointer<Int32>) -> Int32

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: String) {
    if ok {
        print("PASS \(name) \(detail)")
    } else {
        print("FAIL \(name) \(detail)")
        failures += 1
    }
}

private func make<E: _BridgedStoredNSError>(_ code: E.Code, userInfo: [String: Any]) -> E {
    E(code, userInfo: userInfo)
}

@main
enum URLErrorProbe {
    static func main() {
        var missing: Int32 = -1
        let found = sf_url_error_symbols(&missing)
        check("symbols", found == 6 && missing == 0, "found=\(found) missing=\(missing)")

        let unsupported = URLError.Code.unsupportedURL
        check(
            "unsupported-code",
            unsupported.rawValue == NSURLErrorUnsupportedURL && unsupported.rawValue == -1002,
            "raw=\(unsupported.rawValue) constant=\(NSURLErrorUnsupportedURL)"
        )

        let text = "https://example.invalid/sfurl"
        let info: [String: Any] = [NSURLErrorFailingURLStringErrorKey: text]
        let made: URLError = make(unsupported, userInfo: info)
        let boxed: any Error = made
        let embedded = boxed._getEmbeddedNSError()
        let domain = made._nsError.domain() ?? ""
        let infoNil = made._nsError.userInfo() == nil
        let boxedInfoNil = boxed._userInfo == nil
        check(
            "urlerror-identity",
            domain == URLError._nsErrorDomain
                && domain == boxed._domain
                && made._nsError.code() == unsupported.rawValue
                && boxed._code == unsupported.rawValue
                && made.code == unsupported
                && made.failingURL?.absoluteString == text
                && embedded === made._nsError
                && infoNil == boxedInfoNil
                && made.errorCode == unsupported.rawValue
                && URLError.errorDomain == URLError._nsErrorDomain,
            "domain=\(domain) code=\(boxed._code) failing=\(made.failingURL?.absoluteString ?? "nil") same=\(embedded === made._nsError) userInfoNil=\(infoNil) boxedInfoNil=\(boxedInfoNil)"
        )

        let again = URLError(_nsError: made._nsError)
        check(
            "urlerror-roundtrip",
            again._nsError === made._nsError && again == made && again.failingURL?.absoluteString == text,
            "same=\(again._nsError === made._nsError) equal=\(again == made)"
        )

        let twin: URLError = make(.unsupportedURL, userInfo: info)
        let blank = URLError(.badURL, userInfo: [:])
        var left = Hasher()
        var right = Hasher()
        var other = Hasher()
        made.hash(into: &left)
        twin.hash(into: &right)
        blank.hash(into: &other)
        let leftHash = left.finalize()
        let rightHash = right.finalize()
        let otherHash = other.finalize()
        let blankDirect = blank._nsError.userInfo()
        check(
            "urlerror-equal",
            made == twin
                && made._nsError !== twin._nsError
                && made != blank
                && blank.code == .badURL
                && blank.code.rawValue == NSURLErrorBadURL
                && blank.failingURL == nil
                && leftHash == rightHash
                && leftHash != otherHash
                && (blankDirect == nil) == (blank._userInfo == nil),
            "twinSameObject=\(made._nsError === twin._nsError) blankCode=\(blank.code.rawValue) blankInfoNil=\(blankDirect == nil) hash=\(leftHash)/\(otherHash)"
        )

        if failures == 0 {
            print("URL ERROR PROBE PASS")
            exit(0)
        }
        print("URL ERROR PROBE FAIL \(failures)")
        exit(1)
    }
}
