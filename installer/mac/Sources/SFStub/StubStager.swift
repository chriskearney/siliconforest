// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Foundation

/// Downloads every restore-image member a plan needs into a work directory on macOS's own volume,
/// checking each one's CRC-32 and size, before anything is written to the stub (DESIGN D6, ENGINE
/// section 10: "files downloaded and checked before the first disk write"). Upstream streamed members
/// straight onto the stub while downloading.
public struct StubStager {
    public let zip: ZipReader
    public let work: URL

    public init(zip: ZipReader, work: URL) { self.zip = zip; self.work = work }

    /// Staged file for a member: `work/members/<member path>`. Member names are checked not to escape.
    public func stagedURL(_ name: String) throws -> URL {
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), !name.isEmpty else {
            throw StubError("unsafe member name \(name)")
        }
        return work.appendingPathComponent("members", isDirectory: true).appendingPathComponent(name)
    }

    /// A record of what was staged, kept next to the files so a resumed job can trust a complete stage.
    struct Record: Codable { var name: String; var size: UInt64; var crc32: UInt32 }

    @discardableResult
    public func stage(_ entries: [ZipEntry], progress: (String, UInt64, UInt64) -> Void = { _, _, _ in }) throws -> [String: URL] {
        var out: [String: URL] = [:]
        let fm = FileManager.default
        for e in entries {
            let dest = try stagedURL(e.name)
            let rec = dest.appendingPathExtension("sfstage.json")
            if let d = try? Data(contentsOf: rec), let r = try? JSONDecoder().decode(Record.self, from: d),
               r.name == e.name, r.size == e.size, r.crc32 == e.crc32,
               (try? fm.attributesOfItem(atPath: dest.path)[.size] as? UInt64) == e.size {
                out[e.name] = dest
                continue
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: rec)
            let tmp = dest.appendingPathExtension("partial")
            try? fm.removeItem(at: tmp)
            guard fm.createFile(atPath: tmp.path, contents: nil) else { throw StubError("can't create \(tmp.path)") }
            let h = try FileHandle(forWritingTo: tmp)
            var done: UInt64 = 0
            do {
                try zip.stream(e) { chunk in
                    try h.write(contentsOf: chunk)
                    done += UInt64(chunk.count)
                    progress(e.name, done, e.size)
                }
                try h.synchronize()
                try h.close()
            } catch {
                try? h.close(); try? fm.removeItem(at: tmp)
                throw error
            }
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: tmp, to: dest)
            try JSONEncoder().encode(Record(name: e.name, size: e.size, crc32: e.crc32)).write(to: rec)
            out[e.name] = dest
        }
        return out
    }
}
