// SPDX-License-Identifier: MIT
extension NSAttributedString {
    public struct Key: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}

// Retained CoreFoundation performs locale-aware Unicode and ICU regex searching.
internal import SFAttributeRuntime
internal func _sfAttributedRange(in string: String, of needle: String,
                                options: String.CompareOptions, locale: Locale? = nil) -> Range<String.Index>? {
    if options.rawValue & 1024 == 0 && (string.isEmpty || needle.isEmpty) { return nil }
    let found: CFRange
    func cf(_ value: String) -> CFString {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer {
            CFStringCreateWithBytes(nil, $0.baseAddress, $0.count, CFStringBuiltInEncodings.UTF8.rawValue, false)!
        }
    }
    if options.rawValue & 1024 != 0 {
        found = sf_attribute_regex_range(cf(string), cf(needle), options.rawValue)
        guard found.location != kCFNotFound else { return nil }
    } else {
        let value = cf(string)
        var flags = options.rawValue & ~UInt(2)
        if options.rawValue & 2 == 0 { flags |= 16 }
        let cfLocale = locale.map { CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: cf($0.identifier)))! }
        var result = CFRange()
        guard CFStringFindWithOptionsAndLocale(value, cf(needle), CFRange(location: 0, length: CFStringGetLength(value)), CFStringCompareFlags(rawValue: flags), cfLocale, &result) else { return nil }
        found = result
    }
    let lower = string.utf16.index(string.utf16.startIndex, offsetBy: found.location)
    let upper = string.utf16.index(lower, offsetBy: found.length)
    guard let a = String.Index(lower, within: string), let b = String.Index(upper, within: string) else { return nil }
    return a..<b
}

extension UInt8 {
    internal static let carriageReturn: UInt8 = 13
    internal static let newline: UInt8 = 10
}
