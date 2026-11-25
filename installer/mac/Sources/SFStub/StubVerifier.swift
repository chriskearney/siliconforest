// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Darwin
import Foundation

/// Reads a stub back against the plan that wrote it: what each path must be once every action has run (a later
/// action wins over an earlier one at the same path). The engine's idempotent check for S35, S55 and S60, so a
/// resumed job knows whether the content step finished without trusting its own journal.
public enum StubVerifier {
    enum Want {
        case dir, absent, symlink
        case file(size: UInt64?, data: Data?, compressed: Bool, mode: mode_t?)
        case tree(URL)
    }

    /// Everything that is not as the plan leaves it; empty when the stub is complete. `rootOnly`: also check what only
    /// root can do (the schg flag, the bootable flag), which tests on images without root record instead.
    public static func unmet(_ plan: [StubAction], target: StubTarget, staged: [String: URL], rootOnly: Bool) -> [String] {
        let w = StubWriter(target: target, staged: staged)
        var want: [String: Want] = [:], order: [String] = []
        var xattrs: [(String, String, Data)] = [], flags: [(String, UInt32)] = [], bootable: [URL] = []
        func set(_ p: StubPath, _ v: Want) {
            guard let path = try? w.url(p).path else { return }
            if want[path] == nil { order.append(path) }
            want[path] = v
        }
        func size(_ u: URL) -> UInt64? { (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? UInt64) ?? nil }
        for a in plan {
            switch a {
            case .mkdir(let p): set(p, .dir)
            case .member(let m, let p): set(p, .file(size: staged[m].flatMap(size), data: nil, compressed: false, mode: nil))
            case .memberSymlink(_, let p), .symlinkToMounted(_, let p): set(p, .symlink)
            case .bytes(let d, let p, _): set(p, .file(size: UInt64(d.count), data: d, compressed: false, mode: nil))
            case .copyFile(let u, let p):
                let d = (size(u) ?? 0) < 16 << 20 ? try? Data(contentsOf: u) : nil
                set(p, .file(size: size(u), data: d, compressed: false, mode: nil))
            case .copyTree(let u, let p): set(p, .tree(u))
            case .script(_, _, let p): set(p, .file(size: nil, data: nil, compressed: false, mode: 0o755))
            case .bootObject(let s, let vars, let p):
                let d = (try? Data(contentsOf: s)).map { $0 + M1n1.variablesBlob(vars) }
                set(p, .file(size: d.map { UInt64($0.count) }, data: d, compressed: false, mode: nil))
            case .compressedMember(let m, let p): set(p, .file(size: staged[m].flatMap(size), data: nil, compressed: true, mode: nil))
            case .setXattr(let n, let d, let p): if let path = try? w.url(p).path { xattrs.append((path, n, d)) }
            case .chflags(let f, let clear, let p, _): if !clear, let path = try? w.url(p).path { flags.append((path, f)) }
            case .removeIfExists(let p): set(p, .absent)
            case .setBootable(let v): if let r = target.roots[v] { bootable.append(r) }
            }
        }
        var bad: [String] = []
        for path in order { if let why = check(path, want[path]!) { bad.append(why) } }
        for (path, n, d) in xattrs {
            var buf = [UInt8](repeating: 0, count: max(d.count, 1) + 1)
            let r = getxattr(path, n, &buf, buf.count, 0, 0)
            if r != d.count || Data(buf.prefix(d.count)) != d { bad.append("xattr \(n) on \(path)") }
        }
        if rootOnly {
            for (path, f) in flags {
                var st = stat()
                if lstat(path, &st) != 0 || st.st_flags & f != f { bad.append("flag 0x\(String(f, radix: 16)) on \(path)") }
            }
            for r in bootable where (try? StubWriter.isVolumeBootable(r)) != true { bad.append("bootable \(r.path)") }
        }
        return bad
    }

    static func check(_ path: String, _ w: Want) -> String? {
        var st = stat()
        let exists = lstat(path, &st) == 0
        let type = st.st_mode & S_IFMT
        switch w {
        case .absent: return exists ? "\(path) should be gone" : nil
        case .dir: return exists && type == S_IFDIR ? nil : "\(path) is not a directory"
        case .symlink: return exists && type == S_IFLNK ? nil : "\(path) is not a symlink"
        case .file(let size, let data, let compressed, let mode):
            guard exists, type == S_IFREG else { return "\(path) is missing" }
            if let size, UInt64(st.st_size) != size { return "\(path) is \(st.st_size) bytes, not \(size)" }
            if compressed && st.st_flags & UInt32(UF_COMPRESSED) == 0 { return "\(path) is not compressed" }
            if let mode, st.st_mode & 0o7777 != mode { return "\(path) has mode \(String(st.st_mode & 0o7777, radix: 8))" }
            if let data, (try? Data(contentsOf: URL(fileURLWithPath: path))) != data { return "\(path) has other contents" }
            return nil
        case .tree(let src):
            guard exists, type == S_IFDIR else { return "\(path) is missing" }
            guard let names = try? StubWriter.readdirNames(src.path) else { return "can't read \(src.path)" }
            for n in names {
                var s = stat()
                guard stat(src.path + "/" + n, &s) == 0 else { return "can't stat \(src.path)/\(n)" }
                let sub: Want = (s.st_mode & S_IFMT) == S_IFDIR ? .tree(src.appendingPathComponent(n))
                    : .file(size: UInt64(s.st_size), data: nil, compressed: false, mode: s.st_mode & 0o7777)
                if let why = check(path + "/" + n, sub) { return why }
            }
            return nil
        }
    }
}
