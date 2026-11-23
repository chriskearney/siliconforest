import Foundation

/// Sizes are always bytes (`Int64`). Display uses decimal units, as Finder and diskutil do.
public enum Bytes {
    public static let kb: Int64 = 1_000
    public static let mb: Int64 = 1_000_000
    public static let gb: Int64 = 1_000_000_000
    public static let tb: Int64 = 1_000_000_000_000
    public static let mib: Int64 = 1 << 20
    public static let gib: Int64 = 1 << 30

    /// "412.3 GB", "524 MB", "1 TB". `precision` applies to GB/TB.
    public static func format(_ value: Int64, precision: Int = 1) -> String {
        let v = Double(value)
        if abs(value) >= tb {
            return trim(v / Double(tb), precision: max(precision, 2)) + " TB"
        } else if abs(value) >= gb {
            return trim(v / Double(gb), precision: v / Double(gb) >= 100 ? 0 : precision) + " GB"
        } else if abs(value) >= mb {
            return String(format: "%.0f MB", v / Double(mb))
        } else if abs(value) >= kb {
            return String(format: "%.0f KB", v / Double(kb))
        }
        return "\(value) bytes"
    }

    /// Whole gigabytes, for the partition editor's big numbers: ("412", "GB").
    public static func split(_ value: Int64) -> (number: String, unit: String) {
        let s = format(value)
        let parts = s.split(separator: " ")
        return (String(parts.first ?? ""), String(parts.last ?? ""))
    }

    static func trim(_ v: Double, precision: Int) -> String {
        var s = String(format: "%.\(precision)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// Parses "80G", "80GB", "512M", "1.5T", "2147483648" (bytes).
    public static func parse(_ text: String) -> Int64? {
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Int64)] = [("TB", tb), ("T", tb), ("GB", gb), ("G", gb), ("MB", mb), ("M", mb), ("KB", kb), ("K", kb), ("B", 1)]
        for (suffix, mult) in units where t.hasSuffix(suffix) {
            guard let n = Double(t.dropLast(suffix.count)) else { return nil }
            return Int64(n * Double(mult))
        }
        return Int64(t)
    }

    /// Rounds down to `alignment` (APFS and GPT both want 4 KiB at least).
    public static func alignDown(_ value: Int64, to alignment: Int64) -> Int64 {
        guard alignment > 0 else { return value }
        return (value / alignment) * alignment
    }
}
