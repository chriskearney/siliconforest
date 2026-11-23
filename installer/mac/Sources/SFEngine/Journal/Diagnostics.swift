import Foundation

/// Export Diagnostics (DESIGN §12): the journal and its tool log with identifiers replaced
/// consistently (`uuid-1`, `disk-A`), user paths reduced, and no secrets. Nothing is sent anywhere;
/// the app shows the file list before saving.
public enum Diagnostics {
    public struct Bundle: Codable, Sendable {
        public var files: [String]
        public var journal: [String]
        public var resizeLog: String?
        public var note: String
    }

    public final class Redactor {
        private var uuids: [String: String] = [:]
        private var disks: [String: String] = [:]
        public init() {}

        public func redact(_ s: String) -> String {
            var out = s
            let uuidRx = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
            for m in uuidRx.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
                let r = Range(m.range, in: s)!
                let key = s[r].uppercased()
                let v = uuids[key] ?? { let n = "uuid-\(uuids.count + 1)"; uuids[key] = n; return n }()
                out = out.replacingOccurrences(of: String(s[r]), with: v)
            }
            let diskRx = try! NSRegularExpression(pattern: "\\b(r?)disk([0-9]+)")
            let s2 = out
            for m in diskRx.matches(in: s2, range: NSRange(s2.startIndex..., in: s2)).reversed() {
                let num = String(s2[Range(m.range(at: 2), in: s2)!])
                let letter = disks[num] ?? { let l = String(UnicodeScalar(UInt8(65 + disks.count % 26))); disks[num] = l; return l }()
                out = (out as NSString).replacingCharacters(in: m.range, with: "\(s2[Range(m.range(at: 1), in: s2)!])disk-\(letter)")
            }
            let home = NSHomeDirectory()
            out = out.replacingOccurrences(of: home, with: "~")
            return out
        }
    }

    public static func bundle(journal: ChainJournal) -> Bundle {
        let r = Redactor()
        let lines = ((try? String(contentsOf: journal.url, encoding: .utf8)) ?? "").split(separator: "\n").map { r.redact(String($0)) }
        let logURL = journal.url.deletingPathExtension().appendingPathExtension("resize.log")
        let log = (try? String(contentsOf: logURL, encoding: .utf8)).map(r.redact)
        return Bundle(files: ["journal.jsonl"] + (log == nil ? [] : ["resize.log"]), journal: lines, resizeLog: log,
                      note: "Identifiers replaced consistently; no passwords, serial numbers, ECIDs or firmware are ever recorded.")
    }

    public static func write(journal: ChainJournal, to handle: FileHandle) throws {
        try handle.write(contentsOf: try Canonical.data(bundle(journal: journal)))
    }
}
