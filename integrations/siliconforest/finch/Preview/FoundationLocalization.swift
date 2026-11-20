// SPDX-License-Identifier: MIT OR Apache-2.0
// Adapted from Finch's userland/Foundation/swift/Finch/Localization.swift.
// This slice uses the retained NSLocale, bundle string tables and NSString formatter.
import Foundation

public struct Locale: Hashable, Codable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public static var current: Locale {
        // The POSIX locale also serves processes with no configured current locale.
        Locale(identifier: NSLocale.current()?.localeIdentifier() ?? "en_US_POSIX")
    }
}

// MARK: - Format specifiers

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
@preconcurrency public protocol _FormatSpecifiable: Equatable, Sendable {
    associatedtype _Arg: CVarArg, Sendable
    var _arg: _Arg { get }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int: _FormatSpecifiable { public var _arg: Int64 { Int64(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int8: _FormatSpecifiable { public var _arg: Int32 { Int32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int16: _FormatSpecifiable { public var _arg: Int32 { Int32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int32: _FormatSpecifiable { public var _arg: Int32 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int64: _FormatSpecifiable { public var _arg: Int64 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt: _FormatSpecifiable { public var _arg: UInt64 { UInt64(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt8: _FormatSpecifiable { public var _arg: UInt32 { UInt32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt16: _FormatSpecifiable { public var _arg: UInt32 { UInt32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt32: _FormatSpecifiable { public var _arg: UInt32 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt64: _FormatSpecifiable { public var _arg: UInt64 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Float: _FormatSpecifiable { public var _arg: Float { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Double: _FormatSpecifiable { public var _arg: Double { self } }
@_semantics("constant_evaluable") @_alwaysEmitIntoClient
internal func formatSpecifier<T>(_ type: T.Type) -> String {
    switch type {
    case is Int.Type: fallthrough
    case is Int64.Type: return "%lld"
    case is Int8.Type: fallthrough
    case is Int16.Type: fallthrough
    case is Int32.Type: return "%d"
    case is UInt.Type: fallthrough
    case is UInt64.Type: return "%llu"
    case is UInt8.Type: fallthrough
    case is UInt16.Type: fallthrough
    case is UInt32.Type: return "%u"
    case is Float.Type: return "%f"
    case is Double.Type: return "%lf"
    default: return "%@"
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension String {
    public struct LocalizationValue: Equatable, ExpressibleByStringInterpolation {
        /// The format key: literal text with a format specifier per argument.
        internal var key: String
        internal var arguments: [_Argument]

        internal struct _Argument: Equatable {
            let value: any CVarArg
            let description: String

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.description == rhs.description
            }
        }

        /// A key as it is: no arguments, so a % in it is the table's (a format the caller
        /// fills, as Font Book's "style-count %lld"), as Apple's. Only an interpolation's
        /// literal text escapes its %.
        public init(_ value: String) {
            key = value
            arguments = []
        }

        @_semantics("localization_key.init_literal")
        public init(stringLiteral value: String) {
            self.init(value)
        }

        @_semantics("localization_key.init_interpolation")
        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            internal var key = ""
            internal var arguments: [_Argument] = []

            @_semantics("localization.interpolation_init")
            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity + 2 * interpolationCount)
            }

            @_semantics("localization.interpolation.appendLiteral")
            public mutating func appendLiteral(_ literal: String) {
                let percent: UInt8 = 0x25
                let fragments = literal.utf8.split(separator: percent, omittingEmptySubsequences: false)
                key += String(decoding: Array(fragments.joined(separator: [percent, percent])), as: UTF8.self)
            }

            @_semantics("localization.interpolation.appendInterpolation_@_specifier")
            public mutating func appendInterpolation(_ string: String) {
                key += "%@"
                arguments.append(_Argument(value: string as NSString, description: string))
            }

            @_alwaysEmitIntoClient @_semantics("localization.interpolation.appendInterpolation_@_specifier")
            public mutating func appendInterpolation(_ substring: Substring) {
                self.appendInterpolation(String(substring))
            }

            @available(*, deprecated, message: "Localized string interpolation produces an unlocalized, debug description for this type of value. Use String(describing:) to make this explicit and silence this warning or provide a different value that has built-in support or conforms to CustomLocalizedStringResourceConvertible.")
            @_alwaysEmitIntoClient @_semantics("localization.interpolation.appendInterpolation_@_specifier")
            public mutating func appendInterpolation<T>(_ object: T) {
                self.appendInterpolation(String(describing: object))
            }

            @_semantics("localization.interpolation.appendInterpolation_@_specifier")
            public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject) {
                key += "%@"
                arguments.append(_Argument(value: subject, description: subject.description))
            }

            @_transparent
            public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T) {
                appendInterpolation(value, specifier: formatSpecifier(T.self))
            }

            @_semantics("localization.interpolation.appendInterpolation_param_specifier")
            public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) {
                key += specifier
                arguments.append(_Argument(value: value._arg, description: "\(value)"))
            }

        }

        internal func resolve(format: String) -> String {
            guard !arguments.isEmpty else { return format }
            return withVaList(arguments.map(\.value)) {
                NSString(format: format, arguments: $0) as String
            }
        }
    }
}

// MARK: - LocalizedStringResource

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
public protocol CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { get }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
public struct LocalizedStringResource: Equatable, Codable, CustomLocalizedStringResourceConvertible,
                                       ExpressibleByStringInterpolation {
    public let key: String
    public let defaultValue: String.LocalizationValue
    public let table: String?
    public var locale: Locale
    private let _bundle: BundleDescription
    public var bundle: BundleDescription { _bundle }

    public enum BundleDescription: Sendable {
        case main
        case forClass(AnyClass)
        case atURL(URL)

        internal var bundle: Bundle? {
            switch self {
            case .main: return Bundle.main()
            case .forClass(let c): return Bundle(for: c)
            case .atURL(let url): return Bundle(url: url._bridgeToObjectiveC())
            }
        }
    }

    @_semantics("string.init_localized")
    public init(_ keyAndValue: String.LocalizationValue, table: String? = nil, locale: Locale = .current,
                bundle: BundleDescription = .main, comment: StaticString? = nil) {
        key = keyAndValue.key
        defaultValue = keyAndValue
        self.table = table
        self.locale = locale
        _bundle = bundle
    }

    @_semantics("string.init_localized")
    public init(_ key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil,
                locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
        self.key = key.description
        self.defaultValue = defaultValue
        self.table = table
        self.locale = locale
        _bundle = bundle
    }

    @_semantics("localization_key.init_literal")
    public init(stringLiteral value: String) {
        self.init(String.LocalizationValue(stringLiteral: value))
    }

    @_semantics("localization_key.init_interpolation")
    public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
        self.init(String.LocalizationValue(stringInterpolation: stringInterpolation))
    }

    public var localizedStringResource: LocalizedStringResource { self }

    private enum CodingKeys: String, CodingKey { case key, defaultValue, table, locale, bundleURL }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(String(localized: self), forKey: .defaultValue)
        try c.encodeIfPresent(table, forKey: .table)
        try c.encode(locale, forKey: .locale)
        if case .atURL(let url) = _bundle { try c.encode(url, forKey: .bundleURL) }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        defaultValue = String.LocalizationValue(try c.decode(String.self, forKey: .defaultValue))
        table = try c.decodeIfPresent(String.self, forKey: .table)
        locale = try c.decode(Locale.self, forKey: .locale)
        _bundle = try c.decodeIfPresent(URL.self, forKey: .bundleURL).map { .atURL($0) } ?? .main
    }

    public static func == (lhs: LocalizedStringResource, rhs: LocalizedStringResource) -> Bool {
        lhs.key == rhs.key && lhs.defaultValue == rhs.defaultValue && lhs.table == rhs.table && lhs.locale == rhs.locale
    }

    public typealias StringInterpolation = String.LocalizationValue.StringInterpolation
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, *)
extension LocalizedStringResource: @unchecked Sendable {}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension String {
    public init(localized resource: LocalizedStringResource) {
        let value = resource.defaultValue
        let format = resource.bundle.bundle?.localizedString(forKey: resource.key, value: value.key,
                                                             table: resource.table) ?? value.key
        self = value.resolve(format: format)
    }
}
