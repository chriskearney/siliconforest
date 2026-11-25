// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Foundation

/// A property-list value that keeps the distinctions the stub needs (booleans are not integers).
public indirect enum PValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int64)
    case real(Double)
    case data(Data)
    case date(Date)
    case array([PValue])
    case dict([String: PValue])

    public static func parse(_ data: Data) throws -> PValue {
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try from(obj)
    }

    static func from(_ o: Any) throws -> PValue {
        switch o {
        case let s as String: return .string(s)
        case let d as Data: return .data(d)
        case let d as Date: return .date(d)
        case let a as [Any]: return .array(try a.map(from))
        case let d as [String: Any]: return .dict(try d.mapValues(from))
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .real(n.doubleValue) }
            return .int(n.int64Value)
        default: throw StubError("unsupported property-list value \(type(of: o))")
        }
    }

    public subscript(_ key: String) -> PValue? { if case .dict(let d) = self { return d[key] } else { return nil } }
    public var string: String? { if case .string(let s) = self { return s } else { return nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var array: [PValue]? { if case .array(let a) = self { return a } else { return nil } }
    public var dict: [String: PValue]? { if case .dict(let d) = self { return d } else { return nil } }
}

/// Writes XML property lists byte-for-byte as upstream did (Python's `plistlib.dump`, default arguments):
/// tab indent, keys sorted by code point, base64 data wrapped to the indent-dependent width, `&`, `<`, `>`
/// escaped and CR/CRLF folded to LF. Our own implementation of that output format, so the stub's
/// rewritten BuildManifest.plist and SystemVersion.plist equal upstream's exactly.
public enum PythonPlistWriter {
    static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"

    public static func write(_ v: PValue) throws -> Data {
        var out = Data(header.utf8)
        out.append(Data("<plist version=\"1.0\">\n".utf8))
        try value(v, level: 0, into: &out)
        out.append(Data("</plist>\n".utf8))
        return out
    }

    static func line(_ s: String, _ level: Int, _ out: inout Data) {
        out.append(Data(String(repeating: "\t", count: level).utf8))
        out.append(Data(s.utf8))
        out.append(0x0A)
    }

    static func escape(_ s: String) throws -> String {
        for u in s.unicodeScalars where u.value < 0x20 && u.value != 0x09 && u.value != 0x0A && u.value != 0x0D {
            throw StubError("strings must not contain control characters")
        }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func value(_ v: PValue, level: Int, into out: inout Data) throws {
        switch v {
        case .string(let s): line("<string>\(try escape(s))</string>", level, &out)
        case .bool(let b): line(b ? "<true/>" : "<false/>", level, &out)
        case .int(let i): line("<integer>\(i)</integer>", level, &out)
        case .real: throw StubError("real numbers are not written by the stub")   // Python's repr() is not reproduced
        case .date: throw StubError("dates are not written by the stub")
        case .data(let d):
            line("<data>", level, &out)
            let maxLine = max(16, 76 - 8 * level)
            let maxBin = (maxLine / 4) * 3
            var i = 0
            while i < d.count {
                let chunk = d.subdata(in: d.startIndex + i ..< d.startIndex + min(i + maxBin, d.count))
                line(chunk.base64EncodedString(), level, &out)
                i += maxBin
            }
            line("</data>", level, &out)
        case .array(let a):
            if a.isEmpty { line("<array/>", level, &out); return }
            line("<array>", level, &out)
            for x in a { try value(x, level: level + 1, into: &out) }
            line("</array>", level, &out)
        case .dict(let d):
            if d.isEmpty { line("<dict/>", level, &out); return }
            line("<dict>", level, &out)
            for k in d.keys.sorted(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }) {
                line("<key>\(try escape(k))</key>", level + 1, &out)
                try value(d[k]!, level: level + 1, into: &out)
            }
            line("</dict>", level, &out)
        }
    }
}
