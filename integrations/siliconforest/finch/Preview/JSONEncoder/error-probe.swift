// SPDX-License-Identifier: MIT
import Foundation

private func verify(_ error: any Error, original: NSError) {
    precondition(error._domain == "SFJSONErrorProbe" && error._code == 73)
    precondition(error._userInfo != nil)
    precondition(error._getEmbeddedNSError() === original)
    precondition(_convertErrorToNSError(error) === original)
    precondition(original.userInfo()?["token"] as? String == "retained")
}

private struct ThrowingEncode: Encodable {
    let error: NSError
    func encode(to encoder: Encoder) throws { throw error }
}

private let errorKey = CodingUserInfoKey(rawValue: "error")!
private struct ThrowingDecode: Decodable {
    init(from decoder: Decoder) throws { throw decoder.userInfo[errorKey] as! NSError }
}

@main struct Probe {
    static func main() throws {
        guard let original = NSError(domain: "SFJSONErrorProbe", code: 73, userInfo: ["token":"retained"]),
              let empty = NSError(domain: "", code: 9, userInfo: nil) else {
            preconditionFailure("NSError initializer failed")
        }
        verify(original as any Error, original: original)
        verify(_convertNSErrorToError(original), original: original)
        let emptyError: any Error = empty
        precondition(emptyError._domain.isEmpty && emptyError._code == 9)
        precondition((emptyError._userInfo == nil) == (empty.userInfo() == nil))
        precondition(emptyError._getEmbeddedNSError() === empty)

        let encoder = JSONEncoder()
        do { _ = try encoder.encode(ThrowingEncode(error: original)); preconditionFailure() }
        catch { verify(error, original: original) }

        let decoder = JSONDecoder()
        decoder.userInfo[errorKey] = original
        do { _ = try decoder.decode(ThrowingDecode.self, from: Data("{}".utf8)); preconditionFailure() }
        catch { verify(error, original: original) }

        do { _ = try decoder.decode([Int].self, from: Data("[".utf8)); preconditionFailure() }
        catch DecodingError.dataCorrupted(let context) {
            guard let underlying = context.underlyingError else { preconditionFailure("Missing parser error") }
            precondition(underlying._domain == "NSCocoaErrorDomain" && underlying._code == 3840)
            precondition(underlying._userInfo != nil)
            precondition(_convertErrorToNSError(underlying).code() == 3840)
        }

        // Both codecs remain usable after propagating the original NSError.
        let bytes = try encoder.encode(["answer":42])
        let result = try decoder.decode([String:Int].self, from: bytes)
        precondition(result["answer"] == 42)
        print("JSON NSError/Error PASS fields/identity/nullability codec-propagation parser-underlying-error reuse")
    }
}
