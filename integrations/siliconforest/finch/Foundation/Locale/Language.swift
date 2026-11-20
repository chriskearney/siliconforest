// SPDX-License-Identifier: MIT
import CoreFoundation
@_implementationOnly import SFLocaleICU

private func localeTransform(
    _ input: String,
    _ operation: (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>, Int32, UnsafeMutablePointer<Int32>) -> Int32
) -> String? {
    input.withCString { source in
        var status: Int32 = 0
        var scratch: CChar = 0
        let size = operation(source, &scratch, 0, &status)
        guard size > 0, size < 4096 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        status = 0
        let actual = buffer.withUnsafeMutableBufferPointer { bytes in
            operation(source, bytes.baseAddress!, Int32(bytes.count), &status)
        }
        guard actual == size, status <= 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(validatingCString: $0.baseAddress!) }
    }
}

extension Locale {
    public struct LanguageCode: Hashable, Codable, Sendable {
        public let identifier: String
        public init(_ identifier: String) { self.identifier = identifier }
    }

    public struct Language: Hashable, Codable, Sendable {
        private let identifier: String

        public init(identifier: String) {
            self.identifier = identifier
        }

        public var languageCode: LanguageCode? {
            localeTransform(identifier, { uloc_getLanguage($0, $1, $2, $3) }).map(LanguageCode.init)
        }

        public var maximalIdentifier: String {
            let maximal = localeTransform(identifier, { uloc_addLikelySubtags($0, $1, $2, $3) }) ?? identifier
            return localeTransform(maximal, { uloc_toLanguageTag($0, $1, $2, 0, $3) }) ?? maximal
        }
    }

    public var language: Language { Language(identifier: identifier) }
}

extension StringProtocol {
    public func capitalized(with locale: Locale?) -> String {
        let string = unsafeBitCast(String(self) as NSString, to: CFString.self)
        let copy = CFStringCreateMutableCopy(nil, 0, string)
        let region = locale.map { CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: unsafeBitCast($0.identifier as NSString, to: CFString.self))) }
        CFStringCapitalize(copy, region ?? nil)
        return unsafeBitCast(copy, to: NSString.self) as String
    }
}
