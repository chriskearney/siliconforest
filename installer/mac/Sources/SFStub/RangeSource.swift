// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// Ported in part from Asahi Linux installer v0.9.2 (tag v0.9.2, commit dffbb38e), src/urlcache.py:
//   Copyright (c) 2021 The Asahi Linux contributors. MIT licence; the full notice is in LICENSES/third-party/asahi-installer-LICENSE.txt.
// Deliberate changes from upstream (ENGINE.md section 10): every range response must be HTTP 206 with a
// Content-Range naming exactly the requested span and the expected total size; the block cache is bounded
// (upstream's never evicts); the remote size must equal the profile's; https only (file sources are for tests).

import Foundation

public struct StubError: Error, CustomStringConvertible, Equatable, Sendable {
    public var description: String
    public init(_ d: String) { description = d }
}

/// Random access to the restore image's bytes.
public protocol RangeSource: AnyObject {
    var size: UInt64 { get }
    /// Bytes actually transferred (network or disk), for progress and for the "only the needed ranges" claim.
    var bytesFetched: UInt64 { get }
    func read(offset: UInt64, length: Int) throws -> Data
}

/// A local file (tests, and a restore image the user already has).
public final class FileRangeSource: RangeSource {
    let handle: FileHandle
    public let size: UInt64
    public private(set) var bytesFetched: UInt64 = 0

    public init(path: String) throws {
        guard let h = FileHandle(forReadingAtPath: path) else { throw StubError("can't open \(path)") }
        handle = h
        size = try h.seekToEnd()
    }

    public func read(offset: UInt64, length: Int) throws -> Data {
        guard offset + UInt64(length) <= size else { throw StubError("read past the end: \(offset)+\(length) > \(size)") }
        try handle.seek(toOffset: offset)
        let d = try handle.read(upToCount: length) ?? Data()
        guard d.count == length else { throw StubError("short read at \(offset)") }
        bytesFetched += UInt64(length)
        return d
    }
}

/// What a range response must look like (ENGINE.md section 10). Pure, so it is tested without a network.
public enum RangeRule {
    public static func check(status: Int, contentRange: String?, offset: UInt64, length: Int, total: UInt64, bodyCount: Int) throws {
        guard status == 206 else { throw StubError("expected HTTP 206 for bytes \(offset)-\(offset + UInt64(length) - 1), got \(status)") }
        let want = "bytes \(offset)-\(offset + UInt64(length) - 1)/\(total)"
        guard contentRange == want else { throw StubError("Content-Range \(contentRange ?? "missing") does not match the request (\(want))") }
        guard bodyCount == length else { throw StubError("range body is \(bodyCount) bytes, asked for \(length)") }
    }
}

/// One HTTP transport call; replaceable in tests.
public protocol HTTPTransport: Sendable {
    /// Returns (status, headers with lowercased names, body).
    func send(_ request: URLRequest) throws -> (Int, [String: String], Data)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    public init(timeout: TimeInterval = 60) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: c)
    }

    public func send(_ request: URLRequest) throws -> (Int, [String: String], Data) {
        final class Box: @unchecked Sendable { var r: Result<(Int, [String: String], Data), Error>? }
        let box = Box()
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            if let error { box.r = .failure(error) }
            else if let http = response as? HTTPURLResponse {
                var h: [String: String] = [:]
                for (k, v) in http.allHeaderFields { h[String(describing: k).lowercased()] = String(describing: v) }
                box.r = .success((http.statusCode, h, data ?? Data()))
            } else { box.r = .failure(StubError("not an HTTP response")) }
            sem.signal()
        }.resume()
        sem.wait()
        return try box.r!.get()
    }
}

/// HTTPS range reads of Apple's restore image (port of upstream's URLCache, without its cache; see
/// BlockCache). The size comes from HEAD and must equal `expectedSize` when one is given.
public final class HTTPRangeSource: RangeSource {
    public let url: URL
    public let size: UInt64
    public private(set) var bytesFetched: UInt64 = 0
    public private(set) var requests = 0
    let transport: HTTPTransport
    let retries: Int
    let sleep: (Double) -> Void

    public init(url: URL, expectedSize: UInt64?, transport: HTTPTransport = URLSessionTransport(), retries: Int = 10,
                sleep: @escaping (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws {
        guard url.scheme == "https" else { throw StubError("only https restore image URLs are allowed: \(url)") }
        self.url = url
        self.transport = transport
        self.retries = retries
        self.sleep = sleep
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let (status, headers, _) = try transport.send(req)
        guard status == 200 else { throw StubError("HEAD \(url.lastPathComponent): HTTP \(status)") }
        guard let len = headers["content-length"].flatMap({ UInt64($0) }) else { throw StubError("HEAD gave no Content-Length") }
        guard (headers["accept-ranges"] ?? "").contains("bytes") else { throw StubError("the server does not offer byte ranges") }
        if let expectedSize, len != expectedSize { throw StubError("remote size \(len), the profile says \(expectedSize)") }
        size = len
    }

    public func read(offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        guard offset + UInt64(length) <= size else { throw StubError("read past the end: \(offset)+\(length) > \(size)") }
        var last: Error = StubError("no attempt")
        var delay = 1.0
        for attempt in 0...retries {
            do {
                var req = URLRequest(url: url)
                req.setValue("bytes=\(offset)-\(offset + UInt64(length) - 1)", forHTTPHeaderField: "Range")
                requests += 1
                let (status, headers, body) = try transport.send(req)
                try RangeRule.check(status: status, contentRange: headers["content-range"], offset: offset, length: length,
                                    total: size, bodyCount: body.count)
                bytesFetched += UInt64(body.count)
                return body
            } catch {
                last = error
                if attempt < retries { sleep(delay); delay += 1 }
            }
        }
        throw StubError("bytes \(offset)+\(length) failed after \(retries + 1) attempts: \(last)")
    }
}

/// A bounded LRU cache of fixed-size blocks over another source, with read-ahead for small sequential
/// reads (the zip directory and small members). Large reads go straight through, so streaming the
/// BaseSystem never fills memory. Upstream's cache never evicted.
public final class BlockCache: RangeSource {
    public let base: RangeSource
    public let blockSize: Int
    public let capacity: Int
    public let passThrough: Int
    var blocks: [UInt64: Data] = [:]
    var order: [UInt64] = []
    public var size: UInt64 { base.size }
    public var bytesFetched: UInt64 { base.bytesFetched }

    public init(_ base: RangeSource, blockSize: Int = 1 << 20, capacity: Int = 64, passThrough: Int = 4 << 20) {
        self.base = base; self.blockSize = blockSize; self.capacity = capacity; self.passThrough = passThrough
    }

    public var cachedBlocks: Int { blocks.count }

    func touch(_ b: UInt64) {
        if let i = order.firstIndex(of: b) { order.remove(at: i) }
        order.append(b)
        while order.count > capacity { blocks[order.removeFirst()] = nil }
    }

    func block(_ b: UInt64, readahead: Int) throws -> Data {
        if let d = blocks[b] { touch(b); return d }
        var n = 1
        while n < max(1, readahead), blocks[b + UInt64(n)] == nil, n < capacity / 2 { n += 1 }
        let off = b * UInt64(blockSize)
        let len = Int(min(UInt64(n * blockSize), size - off))
        let data = try base.read(offset: off, length: len)
        var i = 0
        while i * blockSize < data.count {
            let s = i * blockSize
            blocks[b + UInt64(i)] = data.subdata(in: s..<min(s + blockSize, data.count))
            touch(b + UInt64(i))
            i += 1
        }
        return blocks[b]!
    }

    public func read(offset: UInt64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        guard offset + UInt64(length) <= size else { throw StubError("read past the end: \(offset)+\(length) > \(size)") }
        if length >= passThrough { return try base.read(offset: offset, length: length) }
        let first = offset / UInt64(blockSize), last = (offset + UInt64(length) - 1) / UInt64(blockSize)
        var out = Data(capacity: length)
        for b in first...last {
            let d = try block(b, readahead: Int(last - b + 1))
            let bStart = b * UInt64(blockSize)
            let from = Int(max(offset, bStart) - bStart)
            let to = Int(min(offset + UInt64(length), bStart + UInt64(d.count)) - bStart)
            out.append(d.subdata(in: from..<to))
        }
        guard out.count == length else { throw StubError("cache assembled \(out.count) of \(length) bytes") }
        return out
    }
}
