// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

import Foundation

public struct Ext4Error: Error, CustomStringConvertible, Equatable {
    /// A stable code for tests and the helper's journal, such as "unsupported-feature".
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var description: String { "\(code): \(message)" }
}

/// Byte-addressed storage holding one ext4 filesystem: a plain file, or the raw device node of an
/// attached disk image. All I/O the grower does is whole 4 KiB blocks at 4 KiB-aligned offsets, which
/// is what a raw (character) disk device needs.
public protocol BlockDevice: AnyObject {
    var path: String { get }
    var byteSize: UInt64 { get }
    func read(offset: UInt64, count: Int) throws -> [UInt8]
    func write(offset: UInt64, bytes: [UInt8]) throws
    func sync() throws
}

public final class FileDevice: BlockDevice {
    public let path: String
    public let byteSize: UInt64
    public let writable: Bool
    public private(set) var bytesWritten: UInt64 = 0
    private let fd: Int32

    // <sys/disk.h>: _IOR('d', 24, uint32_t) and _IOR('d', 25, uint64_t)
    private static let DKIOCGETBLOCKSIZE: UInt = 0x4004_6418
    private static let DKIOCGETBLOCKCOUNT: UInt = 0x4008_6419

    public init(path: String, writable: Bool) throws {
        self.path = path
        self.writable = writable
        let fd = open(path, writable ? O_RDWR : O_RDONLY)
        guard fd >= 0 else { throw Ext4Error("open", "cannot open \(path): \(String(cString: strerror(errno)))") }
        self.fd = fd
        var st = stat()
        guard fstat(fd, &st) == 0 else { close(fd); throw Ext4Error("open", "cannot stat \(path)") }
        switch st.st_mode & S_IFMT {
        case S_IFREG:
            byteSize = UInt64(st.st_size)
        case S_IFCHR, S_IFBLK:
            var bs: UInt32 = 0
            var count: UInt64 = 0
            guard ioctl(fd, FileDevice.DKIOCGETBLOCKSIZE, &bs) == 0, ioctl(fd, FileDevice.DKIOCGETBLOCKCOUNT, &count) == 0 else {
                close(fd); throw Ext4Error("open", "cannot read the size of \(path)")
            }
            byteSize = UInt64(bs) * count
        default:
            close(fd); throw Ext4Error("open", "\(path) is neither a file nor a disk device")
        }
    }

    deinit { close(fd) }

    public func read(offset: UInt64, count: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: count)
        var done = 0
        try buf.withUnsafeMutableBytes { p in
            while done < count {
                let n = pread(fd, p.baseAddress! + done, count - done, off_t(offset) + off_t(done))
                if n < 0 { if errno == EINTR { continue }; throw Ext4Error("io", "read at \(offset) failed: \(String(cString: strerror(errno)))") }
                if n == 0 { throw Ext4Error("io", "short read at \(offset + UInt64(done)) (end of \(path))") }
                done += n
            }
        }
        return buf
    }

    public func write(offset: UInt64, bytes: [UInt8]) throws {
        guard writable else { throw Ext4Error("io", "device opened read-only") }
        var done = 0
        try bytes.withUnsafeBytes { p in
            while done < bytes.count {
                let n = pwrite(fd, p.baseAddress! + done, bytes.count - done, off_t(offset) + off_t(done))
                if n < 0 { if errno == EINTR { continue }; throw Ext4Error("io", "write at \(offset) failed: \(String(cString: strerror(errno)))") }
                done += n
            }
        }
        bytesWritten += UInt64(bytes.count)
    }

    /// F_FULLFSYNC asks the drive to flush its cache too; fall back to fsync where unsupported.
    public func sync() throws {
        if fcntl(fd, F_FULLFSYNC) == 0 { return }
        guard fsync(fd) == 0 else { throw Ext4Error("io", "fsync failed: \(String(cString: strerror(errno)))") }
    }
}
