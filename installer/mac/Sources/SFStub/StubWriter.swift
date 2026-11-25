// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Carries out a StubPlan on the stub's mounted volumes. The file operations reproduce what upstream's
// Python did (Asahi Linux installer v0.9.2, commit dffbb38e: src/stub.py, src/util.py, src/m1n1.py;
// Copyright (c) 2021 The Asahi Linux contributors, MIT, LICENSES/third-party/asahi-installer-LICENSE.txt), including
// the decmpfs LZFSE writer of util.py stream_compress, so the resulting trees compare equal.

import Compression
import Darwin
import Foundation

public struct StubWriter {
    public let target: StubTarget
    public let staged: [String: URL]
    /// Each action as it runs, for the log and the differential test's operation sequence.
    public var log: (String) -> Void = { _ in }
    /// The externally visible effects in the form upstream's subprocess calls had (`xattr -wx`, `chflags`,
    /// `fsctl`, `os.chflags`), with absolute paths, for the differential test's command sequence.
    public var effect: (String) -> Void = { _ in }
    /// Refuse roots that are not mount points (on by default; tests that write into plain directories turn it off).
    public var requireMountPoints = true
    /// Set the APFS bootable flag (needs root and a real APFS volume; tests on plain directories record it instead).
    public var bootable: (URL) throws -> Void = StubWriter.setVolumeBootable
    /// Set system flags such as schg (needs root); tests without root record them instead.
    public var systemFlags: (String, UInt32) throws -> Void = { path, flags in try StubWriter.posix(chflags(path, flags), "chflags \(path)") }

    public init(target: StubTarget, staged: [String: URL]) { self.target = target; self.staged = staged }

    // MARK: paths

    func url(_ p: StubPath) throws -> URL {
        guard let root = target.roots[p.volume] else { throw StubError("no \(p.volume.rawValue) volume in the target") }
        let parts = p.path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.contains("..") else { throw StubError("\(p) climbs out of its volume") }
        return p.path.isEmpty ? root : URL(fileURLWithPath: root.path + "/" + p.path)
    }

    static func isMountPoint(_ u: URL) -> Bool {
        var s = statfs()
        guard statfs(u.path, &s) == 0 else { return false }
        let mnt = withUnsafeBytes(of: &s.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return mnt == u.resolvingSymlinksInPath().path
    }

    static func posix(_ r: Int32, _ what: @autoclosure () -> String) throws {
        if r != 0 { throw StubError("\(what()): \(String(cString: strerror(errno)))") }
    }

    // MARK: primitives (Python semantics)

    /// os.makedirs(path, exist_ok=True)
    static func makedirs(_ path: String) throws {
        var st = stat()
        if lstat(path, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFDIR { return }
            if (st.st_mode & S_IFMT) == S_IFLNK, stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR { return }
            throw StubError("\(path) exists and is not a directory")
        }
        let parent = (path as NSString).deletingLastPathComponent
        if !parent.isEmpty, parent != path { try makedirs(parent) }
        if mkdir(path, 0o777) != 0 && errno != EEXIST { try posix(-1, "mkdir \(path)") }
    }

    /// open(path, "wb").write(data)
    static func writeFile(_ path: String, _ write: (Int32) throws -> Void) throws {
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
        guard fd >= 0 else { throw StubError("open \(path): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        try write(fd)
    }

    static func writeAll(_ fd: Int32, _ d: Data, _ path: String) throws {
        try d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var off = 0
            while off < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + off, raw.count - off)
                if n < 0 { if errno == EINTR { continue }; try posix(-1, "write \(path)") }
                off += n
            }
        }
    }

    static func copyData(from src: String, to dst: String) throws {
        try writeFile(dst) { out in
            let fd = open(src, O_RDONLY)
            guard fd >= 0 else { throw StubError("open \(src): \(String(cString: strerror(errno)))") }
            defer { close(fd) }
            var buf = [UInt8](repeating: 0, count: 1 << 20)
            while true {
                let n = read(fd, &buf, buf.count)
                if n < 0 { if errno == EINTR { continue }; try posix(-1, "read \(src)") }
                if n == 0 { break }
                try writeAll(out, Data(buf[0..<n]), dst)
            }
        }
    }

    static func mode(_ path: String) throws -> mode_t {
        var st = stat(); try posix(stat(path, &st), "stat \(path)"); return st.st_mode
    }

    /// shutil.copy: data, then the source's permission bits.
    static func copy(_ src: String, _ dst: String) throws {
        try copyData(from: src, to: dst)
        try posix(chmod(dst, try mode(src) & 0o7777), "chmod \(dst)")
    }

    /// Directory entries in readdir order, as os.scandir gives them to shutil.copytree.
    static func readdirNames(_ path: String) throws -> [String] {
        guard let d = opendir(path) else { throw StubError("opendir \(path): \(String(cString: strerror(errno)))") }
        defer { closedir(d) }
        var out: [String] = []
        while let e = readdir(d) {
            let name = withUnsafeBytes(of: e.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(e.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { out.append(name) }
        }
        return out
    }

    /// shutil.copytree(src, dst) with copy2 and symlinks followed (os.makedirs(dst) must create it).
    static func copytree(_ src: String, _ dst: String, _ effect: (String) -> Void) throws {
        var st = stat()
        if lstat(dst, &st) == 0 { throw StubError("\(dst) already exists") }
        try makedirs(dst)
        for n in try readdirNames(src) {
            let s = src + "/" + n, d = dst + "/" + n
            var sst = stat()
            try posix(stat(s, &sst), "stat \(s)")
            if (sst.st_mode & S_IFMT) == S_IFDIR { try copytree(s, d, effect) } else { try copy2(s, d, effect) }
        }
        try copystat(src, dst, effect)
    }

    static func copy2(_ src: String, _ dst: String, _ effect: (String) -> Void) throws {
        try copyData(from: src, to: dst)
        try copystat(src, dst, effect)
    }

    /// shutil.copystat on macOS: times, mode bits, st_flags (Python on macOS copies no xattrs here).
    static func copystat(_ src: String, _ dst: String, _ effect: (String) -> Void = { _ in }) throws {
        var st = stat()
        try posix(stat(src, &st), "stat \(src)")
        var times = [timespec(tv_sec: st.st_atimespec.tv_sec, tv_nsec: st.st_atimespec.tv_nsec),
                     timespec(tv_sec: st.st_mtimespec.tv_sec, tv_nsec: st.st_mtimespec.tv_nsec)]
        try posix(utimensat(AT_FDCWD, dst, &times, 0), "utimensat \(dst)")
        try posix(chmod(dst, st.st_mode & 0o7777), "chmod \(dst)")
        effect("os.chflags \(dst) 0x\(String(st.st_flags, radix: 16))")
        if chflags(dst, st.st_flags) != 0 && errno != ENOTSUP && errno != EOPNOTSUPP { try posix(-1, "chflags \(dst)") }
    }

    public static func setVolumeBootable(_ root: URL) throws {
        typealias FsctlFn = @convention(c) (UnsafePointer<CChar>, UInt, UnsafeMutableRawPointer, UInt32) -> Int32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fsctl") else { throw StubError("fsctl is not available") }
        let fsctl = unsafeBitCast(sym, to: FsctlFn.self)
        var cmd: Int32 = 1
        let APFSIOC_VOL_BOOTABLE: UInt = 0xC004_4A57   // _IOWR('J', 'W', int32_t), as upstream
        guard fsctl(root.path, APFSIOC_VOL_BOOTABLE, &cmd, 0) == 0 else {
            throw StubError("fsctl APFSIOC_VOL_BOOTABLE on \(root.path): \(String(cString: strerror(errno)))")
        }
    }

    public static func isVolumeBootable(_ root: URL) throws -> Bool {
        typealias FsctlFn = @convention(c) (UnsafePointer<CChar>, UInt, UnsafeMutableRawPointer, UInt32) -> Int32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "fsctl") else { throw StubError("fsctl is not available") }
        let fsctl = unsafeBitCast(sym, to: FsctlFn.self)
        var cmd: Int32 = 0
        guard fsctl(root.path, 0xC004_4A57, &cmd, 0) == 0 else { throw StubError("fsctl: \(String(cString: strerror(errno)))") }
        return cmd == 1
    }

    // MARK: run

    public func run(_ plan: [StubAction]) throws {
        if requireMountPoints {
            for (v, r) in target.roots where !Self.isMountPoint(r) { throw StubError("\(v.rawValue) root \(r.path) is not a mount point") }
        }
        for act in plan {
            log(act.description)
            try perform(act)
        }
    }

    func staged(_ m: String) throws -> String {
        guard let u = staged[m] else { throw StubError("\(m) was not staged") }
        return u.path
    }

    func perform(_ act: StubAction) throws {
        switch act {
        case .mkdir(let p):
            try Self.makedirs(try url(p).path)
        case .member(let m, let p):
            try Self.copyData(from: try staged(m), to: try url(p).path)
        case .memberSymlink(let m, let p):
            let target = try Data(contentsOf: URL(fileURLWithPath: try staged(m)))
            let path = try url(p).path
            var st = stat()
            if lstat(path, &st) == 0 { try Self.posix(unlink(path), "unlink \(path)") }
            try Self.posix(symlink(String(decoding: target, as: UTF8.self), path), "symlink \(path)")
        case .bytes(let d, let p, _):
            let path = try url(p).path
            try Self.writeFile(path) { try Self.writeAll($0, d, path) }
        case .copyFile(let src, let p):
            try Self.copy(src.path, try url(p).path)
        case .copyTree(let src, let p):
            try Self.copytree(src.path, try url(p).path, effect)
        case .script(let tpl, let tokens, let p):
            var text = try String(contentsOf: tpl, encoding: .utf8)
            for (k, v) in tokens.sorted(by: { $0.key < $1.key }) {
                let value: String
                switch v {
                case .vgid: value = target.vgid
                case .prebootVolumeUUID: value = target.prebootVolumeUUID
                case .literal(let s): value = s
                }
                text = text.replacingOccurrences(of: k, with: value)
            }
            let path = try url(p).path
            try Self.writeFile(path) { try Self.writeAll($0, Data(text.utf8), path) }
            try Self.posix(chmod(path, 0o755), "chmod \(path)")
        case .bootObject(let stage1, let vars, let p):
            let path = try url(p).path
            var d = try Data(contentsOf: stage1)
            d.append(M1n1.variablesBlob(vars))
            try Self.writeFile(path) { try Self.writeAll($0, d, path) }
        case .symlinkToMounted(let t, let p):
            let target = try url(t).path, path = try url(p).path
            try Self.posix(symlink(target, path), "symlink \(path)")
        case .compressedMember(let m, let p):
            let src = try staged(m)
            guard let crc = try Self.memberCRC(m, self) else { throw StubError("no CRC for \(m)") }
            let path = try url(p).path
            try Decmpfs.writeLZFSE(from: src, to: path, expectedCRC: crc) { size in
                effect("xattr -wx com.apple.decmpfs \(Decmpfs.upstreamHex(size: size)) \(path)")
                effect("os.chflags \(path) 0x\(String(UF_COMPRESSED, radix: 16))")
            }
        case .setXattr(let name, let d, let p):
            let path = try url(p).path
            let r = d.withUnsafeBytes { setxattr(path, name, $0.baseAddress, d.count, 0, 0) }
            try Self.posix(r, "setxattr \(name) \(path)")
            effect("xattr -wx \(name) \(d.map { String(format: "%02X", $0) }.joined()) \(path)")
        case .chflags(let flag, let clear, let p, let ifExists):
            let path = try url(p).path
            var st = stat()
            if lstat(path, &st) != 0 { if ifExists { return }; try Self.posix(-1, "lstat \(path)") }
            let flags = clear ? st.st_flags & ~flag : st.st_flags | flag
            try systemFlags(path, flags)
            effect("chflags \(flag == StubPlanner.SF_IMMUTABLE ? (clear ? "noschg" : "schg") : String(flag, radix: 16)) \(path)")
        case .removeIfExists(let p):
            let path = try url(p).path
            var st = stat()
            if lstat(path, &st) == 0 { try Self.posix(unlink(path), "unlink \(path)") }
        case .setBootable(let v):
            guard let r = target.roots[v] else { throw StubError("no \(v.rawValue) volume") }
            effect("fsctl APFSIOC_VOL_BOOTABLE \(r.path) 1")
            try bootable(r)
        }
    }

    /// CRC-32 of a staged member, from its stage record.
    static func memberCRC(_ m: String, _ w: StubWriter) throws -> UInt32? {
        guard let u = w.staged[m] else { return nil }
        let rec = u.appendingPathExtension("sfstage.json")
        return try JSONDecoder().decode(StubStager.Record.self, from: Data(contentsOf: rec)).crc32
    }
}

/// m1n1 boot object assembly (port of Asahi v0.9.2 src/m1n1.py build, MIT).
public enum M1n1 {
    public static func variablesBlob(_ vars: [String]) -> Data {
        var d = Data()
        for v in vars { d.append(Data(v.utf8)); d.append(0x0A) }
        d.append(contentsOf: [0, 0, 0, 0])
        return d
    }
}

/// decmpfs with LZFSE chunks in the resource fork (type 12), as upstream's util.py stream_compress wrote it:
/// 64 KiB chunks, a little-endian u32 offset table of (chunks + 1) entries at the start of the fork, then the
/// chunks; the `com.apple.decmpfs` xattr "fpmc", type 12, the uncompressed size; then st_flags = UF_COMPRESSED.
/// The file is read back through the kernel's decompression and its CRC-32 checked.
public enum Decmpfs {
    public static let chunkSize = 0x10000

    public static func header(size: UInt64) -> Data {
        var d = Data([0x66, 0x70, 0x6D, 0x63, 0x0C, 0, 0, 0])
        for i in 0..<8 { d.append(UInt8((size >> (8 * UInt64(i))) & 0xFF)) }
        return d
    }

    /// The decmpfs header as upstream passed it to `xattr -wx`: a fixed upper-case prefix, then the size's bytes in lower case.
    public static func upstreamHex(size: UInt64) -> String {
        "66706D630C000000" + (0..<8).map { String(format: "%02x", (size >> (8 * UInt64($0))) & 0xFF) }.joined()
    }

    public static func writeLZFSE(from src: String, to path: String, expectedCRC: UInt32, beforeFlags: (UInt64) -> Void = { _ in }) throws {
        guard let input = FileHandle(forReadingAtPath: src) else { throw StubError("can't open \(src)") }
        defer { try? input.close() }
        let size = try input.seekToEnd()
        try input.seek(toOffset: 0)
        try StubWriter.writeFile(path) { _ in }
        let numChunks = Int((size + UInt64(chunkSize) - 1) / UInt64(chunkSize))
        var curPos = UInt32((numChunks + 1) * 4)
        var table: [UInt32] = []
        table.reserveCapacity(numChunks + 1)
        let rsrcPath = path + "/..namedfork/rsrc"
        let fd = open(rsrcPath, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
        guard fd >= 0 else { throw StubError("open \(rsrcPath): \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        try StubWriter.writeAll(fd, Data(count: Int(curPos)), rsrcPath)
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: max(1, compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)), alignment: 16)
        defer { scratch.deallocate() }
        var outCap = chunkSize
        var out = [UInt8](repeating: 0, count: outCap)
        for _ in 0..<numChunks {
            table.append(curPos)
            let inbuf = try input.read(upToCount: chunkSize) ?? Data()
            var csize = 0
            while true {
                csize = inbuf.withUnsafeBytes { (ib: UnsafeRawBufferPointer) in
                    out.withUnsafeMutableBufferPointer { ob in
                        compression_encode_buffer(ob.baseAddress!, outCap, ib.bindMemory(to: UInt8.self).baseAddress!, ib.count, scratch, COMPRESSION_LZFSE)
                    }
                }
                if csize == 0 { outCap *= 2; out = [UInt8](repeating: 0, count: outCap) } else { break }
            }
            try StubWriter.writeAll(fd, Data(out[0..<csize]), rsrcPath)
            curPos += UInt32(csize)
        }
        table.append(curPos)
        var t = Data(capacity: table.count * 4)
        for v in table { withUnsafeBytes(of: v.littleEndian) { t.append(contentsOf: $0) } }
        guard lseek(fd, 0, SEEK_SET) == 0 else { throw StubError("seek \(rsrcPath)") }
        try StubWriter.writeAll(fd, t, rsrcPath)
        try StubWriter.posix(fsync(fd), "fsync \(rsrcPath)")
        beforeFlags(size)
        let h = header(size: size)
        try StubWriter.posix(h.withUnsafeBytes { setxattr(path, "com.apple.decmpfs", $0.baseAddress, h.count, 0, 0) }, "setxattr decmpfs \(path)")
        try StubWriter.posix(chflags(path, UInt32(UF_COMPRESSED)), "chflags UF_COMPRESSED \(path)")
        // Read back through the kernel's decompression.
        guard let back = FileHandle(forReadingAtPath: path) else { throw StubError("can't reopen \(path)") }
        defer { try? back.close() }
        var crc = CRC32()
        var total: UInt64 = 0
        while let d = try back.read(upToCount: 8 << 20), !d.isEmpty { crc.update(d); total += UInt64(d.count) }
        guard total == size else { throw StubError("\(path): read back \(total) bytes, wrote \(size)") }
        guard crc.value == expectedCRC else { throw StubError("\(path): failed to compress file: CRC mismatch") }
    }
}
