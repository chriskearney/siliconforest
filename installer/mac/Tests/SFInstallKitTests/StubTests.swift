// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
//
// SFStub tests that need no Apple restore image: every input here is synthetic (a fixture "IPSW" zip
// built in memory, with made-up manifests and bytes). The differential test against Asahi v0.9.2 on the
// real 13.5 image is scripts/stub-differential.sh, run on the M5.

import Compression
import Foundation
import Testing
@testable import SFStub

// MARK: a small zip writer for fixtures (stored or raw-deflate members, optional zip64 records)

struct FixtureZip {
    struct Member { var name: String; var data: Data; var deflate: Bool; var mode: UInt32 }
    var members: [Member] = []
    var zip64 = false

    mutating func file(_ name: String, _ data: Data, deflate: Bool = true) { members.append(Member(name: name, data: data, deflate: deflate, mode: 0o100644)) }
    mutating func dir(_ name: String) { members.append(Member(name: name, data: Data(), deflate: false, mode: 0o040755)) }
    mutating func symlink(_ name: String, to target: String) { members.append(Member(name: name, data: Data(target.utf8), deflate: false, mode: 0o120755)) }

    static func rawDeflate(_ d: Data) -> Data {
        if d.isEmpty { return Data([0x03, 0x00]) }
        var out = [UInt8](repeating: 0, count: d.count + 1024)
        let n = d.withUnsafeBytes { src in
            compression_encode_buffer(&out, out.count, src.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
        }
        return Data(out[0..<n])
    }

    func build() -> Data {
        var out = Data(), cd = Data()
        func le16(_ v: UInt16, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func le32(_ v: UInt32, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func le64(_ v: UInt64, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        for m in members {
            let comp = m.deflate ? Self.rawDeflate(m.data) : m.data
            let crc = CRC32.checksum(m.data)
            let off = UInt64(out.count)
            let name = Data(m.name.utf8)
            le32(0x0403_4B50, &out); le16(45, &out); le16(0x800, &out); le16(m.deflate ? 8 : 0, &out); le32(0, &out)
            le32(crc, &out); le32(UInt32(comp.count), &out); le32(UInt32(m.data.count), &out)
            le16(UInt16(name.count), &out); le16(0, &out); out.append(name); out.append(comp)
            var extra = Data()
            if zip64 { le16(1, &extra); le16(24, &extra); le64(UInt64(m.data.count), &extra); le64(UInt64(comp.count), &extra); le64(off, &extra) }
            le32(0x0201_4B50, &cd); le16(0x031E, &cd); le16(45, &cd); le16(0x800, &cd); le16(m.deflate ? 8 : 0, &cd); le32(0, &cd)
            le32(crc, &cd)
            le32(zip64 ? 0xFFFF_FFFF : UInt32(comp.count), &cd); le32(zip64 ? 0xFFFF_FFFF : UInt32(m.data.count), &cd)
            le16(UInt16(name.count), &cd); le16(UInt16(extra.count), &cd); le16(0, &cd); le16(0, &cd); le16(0, &cd)
            le32(m.mode << 16, &cd); le32(zip64 ? 0xFFFF_FFFF : UInt32(off), &cd)
            cd.append(name); cd.append(extra)
        }
        let cdOff = UInt64(out.count)
        out.append(cd)
        if zip64 {
            let eocd64 = UInt64(out.count)
            le32(0x0606_4B50, &out); le64(44, &out); le16(45, &out); le16(45, &out); le32(0, &out); le32(0, &out)
            le64(UInt64(members.count), &out); le64(UInt64(members.count), &out); le64(UInt64(cd.count), &out); le64(cdOff, &out)
            le32(0x0706_4B50, &out); le32(0, &out); le64(eocd64, &out); le32(1, &out)
            le32(0x0605_4B50, &out); le16(0, &out); le16(0, &out); le16(0xFFFF, &out); le16(0xFFFF, &out)
            le32(0xFFFF_FFFF, &out); le32(0xFFFF_FFFF, &out); le16(0, &out)
        } else {
            le32(0x0605_4B50, &out); le16(0, &out); le16(0, &out); le16(UInt16(members.count), &out); le16(UInt16(members.count), &out)
            le32(UInt32(cd.count), &out); le32(UInt32(cdOff), &out); le16(0, &out)
        }
        return out
    }
}

final class MemorySource: RangeSource {
    let data: Data
    var bytesFetched: UInt64 = 0
    var reads: [(UInt64, Int)] = []
    init(_ d: Data) { data = d }
    var size: UInt64 { UInt64(data.count) }
    func read(offset: UInt64, length: Int) throws -> Data {
        guard offset + UInt64(length) <= size else { throw StubError("past end") }
        reads.append((offset, length)); bytesFetched += UInt64(length)
        return data.subdata(in: Int(offset)..<Int(offset) + length)
    }
}

func plistXML(_ v: Any) -> Data { try! PropertyListSerialization.data(fromPropertyList: v, format: .xml, options: 0) }

func bytes(_ seed: String, _ n: Int) -> Data {
    var d = Data(); var i = 0
    while d.count < n { d.append(Data("\(seed)-\(i)|".utf8)); i += 1 }
    return d.prefix(n)
}

/// A synthetic restore image shaped like 13.5's, with made-up contents.
func fixtureIPSW(zip64: Bool = true, extraJ313: Bool = false, corrupt: String? = nil) -> (Data, StubProfile) {
    let identity: (String, String) -> [String: Any] = { board, cls in [
        "ApBoardID": board, "ApChipID": "0x8103",
        "Info": ["DeviceClass": cls, "RestoreBehavior": "Erase", "Variant": "macOS Customer", "BuildNumber": "22G74"],
        "Manifest": [
            "BaseSystem": ["Info": ["Path": "000-base.dmg"], "Digest": Data([1, 2, 3])],
            "OS": ["Info": ["Path": "000-os.dmg"]],
            "Cryptex1,SystemOS": ["Info": ["Path": "000-cryptex.dmg"]],
            "RestoreRamDisk": ["Info": ["Path": "000-ramdisk.dmg"]],
            "KernelCache": ["Info": ["Path": "kernelcache.release.fixture"], "Trusted": true],
            "iBoot": ["Info": ["Path": "Firmware/all_flash/iBoot.\(cls).im4p"]],
            "iBootData": ["Info": ["Path": "Firmware/all_flash/iBoot.\(cls).im4p"]],   // duplicate path: copied once
            "DeviceTree": ["Info": ["Path": "Firmware/all_flash/DeviceTree.\(cls).im4p"]],
        ]] }
    var ids = [identity("0x26", "j313ap"), identity("0x24", "j293ap")]
    if extraJ313 { ids.append(identity("0x26", "j313ap")) }
    let manifest: [String: Any] = ["BuildIdentities": ids, "ProductVersion": "13.5", "ProductBuildVersion": "22G74", "ManifestVersion": 1]
    var z = FixtureZip(); z.zip64 = zip64
    z.file("BuildManifest.plist", plistXML(manifest))
    z.dir("usr/"); z.dir("usr/standalone/")
    z.file("usr/standalone/bootcaches.plist", plistXML(["bless2": ["RestoreBundlePath": "./Restore", "SupportsPairedRecovery": true]]))
    z.file("SystemVersion.plist", plistXML(["ProductVersion": "13.5", "ProductBuildVersion": "22G74", "ProductUserVisibleVersion": "13.5", "ProductName": "macOS"]))
    z.file("RestoreVersion.plist", plistXML(["RestoreLongVersion": "fixture"]))
    z.file("PlatformSupport.plist", plistXML(["SupportedBoardIds": ["fixture"]]))
    z.dir("BootabilityBundle/"); z.dir("BootabilityBundle/Restore/"); z.dir("BootabilityBundle/Restore/Bootability/")
    z.dir("BootabilityBundle/Restore/Bootability/B.framework/")
    z.symlink("BootabilityBundle/Restore/Bootability/B.framework/B", to: "Versions/Current/B")
    z.dir("BootabilityBundle/Restore/Bootability/B.framework/Versions/")
    z.dir("BootabilityBundle/Restore/Bootability/B.framework/Versions/A/")
    z.file("BootabilityBundle/Restore/Bootability/B.framework/Versions/A/B", bytes("bootability", 5000))
    z.symlink("BootabilityBundle/Restore/Bootability/B.framework/Versions/Current", to: "A")
    z.dir("BootabilityBundle/Restore/Firmware/")
    z.file("BootabilityBundle/Restore/Firmware/Bootability.dmg.trustcache", bytes("tc", 300))
    z.dir("Firmware/"); z.dir("Firmware/Manifests/restore/macOS Customer/")
    z.file("Firmware/Manifests/restore/macOS Customer/apticket.j313ap.im4m", bytes("ticket313", 500))
    z.file("Firmware/Manifests/restore/macOS Customer/apticket.j293ap.im4m", bytes("ticket293", 500))
    z.file("kernelcache.release.fixture", bytes("kc", 70_000))
    for cls in ["j313ap", "j293ap"] {
        z.file("Firmware/all_flash/iBoot.\(cls).im4p", bytes("iboot\(cls)", 3000))
        z.file("Firmware/all_flash/DeviceTree.\(cls).im4p", bytes("dt\(cls)", 2000))
    }
    z.file("000-base.dmg", bytes("basesystem", 300_000), deflate: true)
    z.file("000-os.dmg", bytes("os-not-fetched", 200_000), deflate: false)  // > the 64 KiB end-of-file read
    if let c = corrupt, let i = z.members.firstIndex(where: { $0.name == c }) {
        // keep the directory's CRC but change the bytes
        let good = z.members[i].data
        var mutated = z.build()
        let r = mutated.range(of: FixtureZip.rawDeflate(good))!
        mutated[r.lowerBound + r.count / 2] ^= 0x55
        return (mutated, profile)
    }
    return (z.build(), profile)
}

let profile = StubProfile(version: "13.5", build: "22G74",
                          restore_image: .init(url: "https://example.invalid/fixture.ipsw", bytes: 0),
                          identity: .init(ap_board_id: "0x26", ap_chip_id: "0x8103", device_class: "j313ap", restore_behavior: "Erase", variant: "macOS Customer"),
                          partition_bytes: 2_499_805_184, skip_manifest_keys: StubProfile.upstreamSkip)

func tempDir(_ name: String) -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("sfstub-\(name)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

/// A payload like upstream's step2 bundle, synthetic.
func fixturePayload(_ dir: URL) throws -> StubPayload {
    let fm = FileManager.default
    let app = dir.appendingPathComponent("Payload/Setup.app/Contents")
    try fm.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
    try fm.createDirectory(at: app.appendingPathComponent("Resources/en.lproj"), withIntermediateDirectories: true)
    try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
    try Data("#!/bin/sh\nexec x\n".utf8).write(to: app.appendingPathComponent("MacOS/launch.sh"))
    chmod(app.appendingPathComponent("MacOS/launch.sh").path, 0o755)
    try Data("strings".utf8).write(to: app.appendingPathComponent("Resources/en.lproj/InfoPlist.strings"))
    let tpl = dir.appendingPathComponent("Payload/step2.sh")
    try Data("VGID=\"##VGID##\"\nPREBOOT=\"##PREBOOT##\"\nDISTRO=\"##DISTRO##\"\n".utf8).write(to: tpl)
    let icon = dir.appendingPathComponent("Payload/icon.icns"); try bytes("icon", 900).write(to: icon)
    let iapm = dir.appendingPathComponent("Payload/IAPhysicalMedia.plist"); try plistXML(["AppName": "Setup.app"]).write(to: iapm)
    let s1 = dir.appendingPathComponent("Payload/stage1.bin"); try bytes("m1n1", 4096).write(to: s1)
    return StubPayload(volumeIcon: icon, appSource: dir.appendingPathComponent("Payload/Setup.app"), appName: "Setup.app",
                       script: ("Contents/Resources/step2.sh", tpl, ["##VGID##": .vgid, "##PREBOOT##": .prebootVolumeUUID, "##DISTRO##": .literal("SiliconForest")]),
                       physicalMedia: iapm, bootObject: ("Contents/Resources/boot.bin", s1, ["chainload=X;sf/boot.bin"]))
}

@Suite("SFStub: range reads, zip, plists (no Apple bits)")
struct StubReaderTests {
    @Test func crc32KnownVectors() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
        var c = CRC32(); c.update(Data("1234".utf8)); c.update(Data("56789".utf8))
        #expect(c.value == 0xCBF4_3926)
        let big = bytes("crc", 1_000_003)
        var slow: UInt32 = 0xFFFF_FFFF
        for b in big { slow ^= UInt32(b); for _ in 0..<8 { slow = (slow & 1) != 0 ? 0xEDB8_8320 ^ (slow >> 1) : slow >> 1 } }
        #expect(CRC32.checksum(big) == ~slow)
    }

    @Test func rangeRuleAcceptsOnlyAnExact206() throws {
        try RangeRule.check(status: 206, contentRange: "bytes 10-19/100", offset: 10, length: 10, total: 100, bodyCount: 10)
        #expect(throws: StubError.self) { try RangeRule.check(status: 200, contentRange: nil, offset: 0, length: 100, total: 100, bodyCount: 100) }
        #expect(throws: StubError.self) { try RangeRule.check(status: 206, contentRange: "bytes 10-20/100", offset: 10, length: 10, total: 100, bodyCount: 10) }
        #expect(throws: StubError.self) { try RangeRule.check(status: 206, contentRange: "bytes 10-19/101", offset: 10, length: 10, total: 100, bodyCount: 10) }
        #expect(throws: StubError.self) { try RangeRule.check(status: 206, contentRange: "bytes 10-19/100", offset: 10, length: 10, total: 100, bodyCount: 9) }
        #expect(throws: StubError.self) { try RangeRule.check(status: 206, contentRange: nil, offset: 10, length: 10, total: 100, bodyCount: 10) }
    }

    struct FakeServer: HTTPTransport, @unchecked Sendable {
        let body: Data
        var headStatus = 200
        var ranges = true
        var mangle: (@Sendable (Int, String) -> (Int, String))? = nil
        let counter = Counter()
        final class Counter: @unchecked Sendable { var n = 0; var fail = 0 }
        func send(_ r: URLRequest) throws -> (Int, [String: String], Data) {
            if r.httpMethod == "HEAD" { return (headStatus, ["content-length": "\(body.count)", "accept-ranges": ranges ? "bytes" : "none"], Data()) }
            counter.n += 1
            if counter.fail > 0 { counter.fail -= 1; throw URLError(.timedOut) }
            let spec = r.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-").map { Int($0)! }
            var status = 206, cr = "bytes \(spec[0])-\(spec[1])/\(body.count)"
            if let mangle { (status, cr) = mangle(status, cr) }
            return (status, ["content-range": cr], body.subdata(in: spec[0]..<spec[1] + 1))
        }
    }

    @Test func httpSourceChecksSizeSchemeAndEveryResponse() throws {
        let body = bytes("remote", 10_000)
        let url = URL(string: "https://example.invalid/x.ipsw")!
        #expect(throws: StubError.self) { _ = try HTTPRangeSource(url: URL(string: "http://example.invalid/x.ipsw")!, expectedSize: nil, transport: FakeServer(body: body)) }
        #expect(throws: StubError.self) { _ = try HTTPRangeSource(url: url, expectedSize: 9_999, transport: FakeServer(body: body)) }
        #expect(throws: StubError.self) { _ = try HTTPRangeSource(url: url, expectedSize: nil, transport: FakeServer(body: body, ranges: false)) }
        let ok = try HTTPRangeSource(url: url, expectedSize: 10_000, transport: FakeServer(body: body), sleep: { _ in })
        #expect(try ok.read(offset: 100, length: 50) == body.subdata(in: 100..<150))
        // A server that answers 200 with the whole file, or a shifted range, is refused (no retry makes it right).
        let whole = try HTTPRangeSource(url: url, expectedSize: nil, transport: FakeServer(body: body, mangle: { _, c in (200, c) }), retries: 2, sleep: { _ in })
        #expect(throws: StubError.self) { _ = try whole.read(offset: 0, length: 10) }
        let shifted = try HTTPRangeSource(url: url, expectedSize: nil, transport: FakeServer(body: body, mangle: { s, _ in (s, "bytes 1-10/10000") }), retries: 1, sleep: { _ in })
        #expect(throws: StubError.self) { _ = try shifted.read(offset: 0, length: 10) }
        // Transient failures are retried.
        let flaky = FakeServer(body: body); flaky.counter.fail = 3
        let f = try HTTPRangeSource(url: url, expectedSize: nil, transport: flaky, sleep: { _ in })
        #expect(try f.read(offset: 5, length: 5) == body.subdata(in: 5..<10))
        #expect(flaky.counter.n == 4)
    }

    @Test func blockCacheIsBoundedAndExact() throws {
        let body = bytes("cache", 50_000)
        let mem = MemorySource(body)
        let c = BlockCache(mem, blockSize: 1000, capacity: 8, passThrough: 20_000)
        for (o, n) in [(0, 10), (995, 10), (3_500, 4_000), (49_990, 10), (12_345, 1)] {
            #expect(try c.read(offset: UInt64(o), length: n) == body.subdata(in: o..<o + n))
            #expect(c.cachedBlocks <= 8)
        }
        let before = mem.reads.count
        _ = try c.read(offset: 0, length: 25_000)       // pass-through
        #expect(mem.reads.count == before + 1)
        #expect(c.cachedBlocks <= 8)
    }

    @Test(arguments: [false, true]) func zipReadsMembersAndChecksCRC(zip64: Bool) throws {
        let (data, _) = fixtureIPSW(zip64: zip64)
        let z = try ZipReader(MemorySource(data))
        #expect(try z.read("000-base.dmg") == bytes("basesystem", 300_000))
        #expect(z.entry("BootabilityBundle/Restore/Bootability/B.framework/Versions/Current")?.isSymlink == true)
        #expect(z.entry("usr/standalone/")?.isDirectory == true)
        #expect(throws: StubError.self) { _ = try z.read("missing") }
        let (bad, _) = fixtureIPSW(zip64: zip64, corrupt: "000-base.dmg")
        let zb = try ZipReader(MemorySource(bad))
        #expect(throws: StubError.self) { _ = try zb.read("000-base.dmg") }
    }

    @Test func onlyTheNeededBytesAreRead() throws {
        let (data, profile) = fixtureIPSW()
        let mem = MemorySource(data)
        let z = try ZipReader(mem)
        let img = try RestoreImage(zip: z, profile: profile)
        _ = img
        // never touched the members the stub does not use
        let os = z.entry("000-os.dmg")!
        // (its local header and the start of its data sit before the 64 KiB tail read)
        #expect(!mem.reads.contains { $0.0 <= os.headerOffset + 40 && $0.0 + UInt64($0.1) > os.headerOffset + 30 })
        #expect(!mem.reads.contains { $0.0 <= os.headerOffset + 100_000 && $0.0 + UInt64($0.1) > os.headerOffset + 100 })
    }

    @Test func identitySelectionNeedsExactlyOne() throws {
        let (data, profile) = fixtureIPSW()
        let img = try RestoreImage(zip: try ZipReader(MemorySource(data)), profile: profile)
        #expect(img.identity["Info"]?["DeviceClass"]?.string == "j313ap")
        #expect(img.trimmedManifest["BuildIdentities"]?.array?.count == 1)
        let (two, _) = fixtureIPSW(extraJ313: true)
        #expect(throws: StubError.self) { _ = try RestoreImage(zip: try ZipReader(MemorySource(two)), profile: profile) }
        var other = profile; other.identity.device_class = "j999ap"
        #expect(throws: StubError.self) { _ = try RestoreImage(zip: try ZipReader(MemorySource(data)), profile: other) }
        var ver = profile; ver.build = "22G90"
        #expect(throws: StubError.self) { _ = try RestoreImage(zip: try ZipReader(MemorySource(data)), profile: ver) }
        var skip = profile; skip.skip_manifest_keys = ["OS"]
        #expect(throws: StubError.self) { _ = try RestoreImage(zip: try ZipReader(MemorySource(data)), profile: skip) }
    }

    @Test func plistWriterMatchesPythonPlistlibByteForByte() throws {
        // Expected bytes produced by Python 3.13 plistlib.dumps() for this value (generator: /workspace/notes/sfstub.md, "plist fixture").
        let expected = Data(base64Encoded: "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VOIiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+CjxwbGlzdCB2ZXJzaW9uPSIxLjAiPgo8ZGljdD4KCTxrZXk+Wjwva2V5PgoJPGRhdGE+Cgk8L2RhdGE+Cgk8a2V5PmE8L2tleT4KCTxzdHJpbmc+eDwvc3RyaW5nPgoJPGtleT5iPC9rZXk+Cgk8ZGljdD4KCQk8a2V5PkRpZ2VzdDwva2V5PgoJCTxkYXRhPgoJCUFBRUNBd1FGQmdjSUNRb0xEQTBPRHhBUkVoTVVGUllYR0JrYUd4d2RIaDhnSVNJakpDVW1KeWdwS2lzcwoJCUxTNHZNREV5TXpRMU5qYzRPVG83UEQwK1AwQkJRa05FUlVaSFNFbEtTMHhOVGs5UVVWSlRWRlZXVjFoWgoJCVdsdGNYVjVmWUdGaVkyUmxabWRvYVdwcmJHMXViM0J4Y25OMGRYWjNlSGw2ZTN4OWZuK0FnWUtEaElXRwoJCWg0aUppb3VNalk2UGtKR1NrNVNWbHBlWW1acWJuSjJlbjZDaG9xT2twYWFucUttcXE2eXRycSt3c2JLegoJCXRMVzJ0N2k1dXJ1OHZiNi93TUhDdzhURnhzYz0KCQk8L2RhdGE+CgkJPGtleT5UcnVzdGVkPC9rZXk+CgkJPHRydWUvPgoJCTxrZXk+ZTwva2V5PgoJCTxhcnJheS8+CgkJPGtleT5uPC9rZXk+CgkJPGFycmF5PgoJCQk8aW50ZWdlcj4xPC9pbnRlZ2VyPgoJCQk8aW50ZWdlcj4tNTwvaW50ZWdlcj4KCQkJPGRpY3QvPgoJCTwvYXJyYXk+CgkJPGtleT5zPC9rZXk+CgkJPHN0cmluZz5hJmFtcDtiJmx0O2MmZ3Q7ZAplPC9zdHJpbmc+Cgk8L2RpY3Q+Cgk8a2V5PmRlZXA8L2tleT4KCTxkaWN0PgoJCTxrZXk+ZDE8L2tleT4KCQk8ZGljdD4KCQkJPGtleT5kMjwva2V5PgoJCQk8ZGljdD4KCQkJCTxrZXk+ZDM8L2tleT4KCQkJCTxkaWN0PgoJCQkJCTxrZXk+ZDQ8L2tleT4KCQkJCQk8ZGljdD4KCQkJCQkJPGtleT5kNTwva2V5PgoJCQkJCQk8ZGljdD4KCQkJCQkJCTxrZXk+ZDY8L2tleT4KCQkJCQkJCTxkaWN0PgoJCQkJCQkJCTxrZXk+ZDc8L2tleT4KCQkJCQkJCQk8ZGljdD4KCQkJCQkJCQkJPGtleT5kODwva2V5PgoJCQkJCQkJCQk8ZGF0YT4KCQkJCQkJCQkJQUFFQ0F3UUZCZ2NJQ1FvTAoJCQkJCQkJCQlEQTBPRHhBUkVoTVVGUllYCgkJCQkJCQkJCUdCa2FHeHdkSGg4Z0lTSWoKCQkJCQkJCQkJSkNVbUp5Z3BLaXNzTFM0dgoJCQkJCQkJCQlNREV5TXpRMU5qYzRPVG83CgkJCQkJCQkJCVBEMCtQMEJCUWtORVJVWkgKCQkJCQkJCQkJU0VsS1MweE5UazlRVVZKVAoJCQkJCQkJCQlWRlZXVjFoWldsdGNYVjVmCgkJCQkJCQkJCVlHRmlZdz09CgkJCQkJCQkJCTwvZGF0YT4KCQkJCQkJCQk8L2RpY3Q+CgkJCQkJCQk8L2RpY3Q+CgkJCQkJCTwvZGljdD4KCQkJCQk8L2RpY3Q+CgkJCQk8L2RpY3Q+CgkJCTwvZGljdD4KCQk8L2RpY3Q+Cgk8L2RpY3Q+CjwvZGljdD4KPC9wbGlzdD4K")!
        let v: PValue = .dict([
            "b": .dict(["Digest": .data(Data(0..<200)), "Trusted": .bool(true), "n": .array([.int(1), .int(-5), .dict([:])]), "e": .array([]), "s": .string("a&b<c>d\r\ne")]),
            "a": .string("x"), "Z": .data(Data()),
            "deep": .dict(["d1": .dict(["d2": .dict(["d3": .dict(["d4": .dict(["d5": .dict(["d6": .dict(["d7": .dict(["d8": .data(Data(0..<100))])])])])])])])]),
        ])
        let got = try PythonPlistWriter.write(v)
        #expect(got == expected)
        #expect(try PValue.parse(got) == PValue.parse(expected))
    }
}

@Suite("SFStub: plan and write (synthetic image, plain directories)")
struct StubBuildTests {
    func build(_ dir: URL) throws -> (StubTarget, [StubAction], [String], [String], ZipReader) {
        let (data, profile) = fixtureIPSW()
        let z = try ZipReader(MemorySource(data))
        let img = try RestoreImage(zip: z, profile: profile)
        let payload = try fixturePayload(dir)
        let admin = dir.appendingPathComponent("admin.plist"); try plistXML(["u": ["GeneratedUID": "X", "RealName": "U"]]).write(to: admin)
        let vgid = "11111111-2222-3333-4444-555555555555"
        let plan = try StubPlanner.plan(image: img, target: vgid, payload: payload, adminUsers: admin)
        let staged = try StubStager(zip: z, work: dir.appendingPathComponent("work")).stage(try StubPlanner.members(of: plan, in: z))
        var roots: [StubVolume: URL] = [:]
        for v in StubVolume.allCases { roots[v] = dir.appendingPathComponent("vol-\(v.rawValue)"); try FileManager.default.createDirectory(at: roots[v]!, withIntermediateDirectories: true) }
        let target = StubTarget(roots: roots, vgid: vgid, prebootVolumeUUID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        var w = StubWriter(target: target, staged: staged)
        w.requireMountPoints = false
        var effects: [String] = [], bootable: [String] = []
        w.bootable = { bootable.append($0.lastPathComponent) }
        w.systemFlags = { p, f in effects.append("flags \((p as NSString).lastPathComponent) \(String(f, radix: 16))") }
        w.effect = { effects.append($0) }
        try w.run(plan)
        return (target, plan, effects, bootable, z)
    }

    @Test func planFollowsUpstreamOrderAndSkips() throws {
        let dir = tempDir("plan")
        let (data, profile) = fixtureIPSW()
        let z = try ZipReader(MemorySource(data))
        let img = try RestoreImage(zip: z, profile: profile)
        let plan = try StubPlanner.plan(image: img, target: "VGID", payload: try fixturePayload(dir), adminUsers: dir)
        let d = plan.map(\.description)
        #expect(d.first == "mkdir System:/usr/standalone")
        #expect(d[1] == "extract usr/standalone/bootcaches.plist -> System:/usr/standalone/bootcaches.plist")
        #expect(d.contains("compress(lzfse) 000-base.dmg -> Recovery:/VGID/usr/standalone/firmware/arm64eBaseSystem.dmg"))
        #expect(d.contains("fsctl APFSIOC_VOL_BOOTABLE System"))
        #expect(!d.contains { $0.contains("000-os.dmg") || $0.contains("cryptex") || $0.contains("ramdisk") })
        #expect(d.filter { $0.contains("iBoot.j313ap.im4p") }.count == 1)
        #expect(!d.contains { $0.contains("j293ap.im4p") })                  // the other identity's files
        #expect(d.contains("extract Firmware/Manifests/restore/macOS Customer/apticket.j293ap.im4m -> Preboot:/VGID/./Restore/apticket.j293ap.im4m"))   // as upstream: the whole variant tree
        let members = try StubPlanner.members(of: plan, in: z).map(\.name)
        #expect(members.contains("000-base.dmg") && !members.contains("000-os.dmg"))
        // upstream's order: System, Data, Preboot (restore bundle, admin users, the System/Restore link), Recovery, then the app
        func idx(_ s: String) -> Int { d.firstIndex { $0.hasPrefix(s) }! }
        #expect(idx("mkdir Data:/") < idx("mkdir Preboot:/VGID") && idx("chflags 0x20000 Preboot") < idx("symlink System:/./Restore"))
        #expect(idx("symlink System:/./Restore") < idx("compress(lzfse)") && idx("compress(lzfse)") < idx("copytree"))
    }

    @Test func writesTheTreeUpstreamWould() throws {
        let dir = tempDir("write")
        let (t, _, effects, bootable, z) = try build(dir)
        let r = t.roots
        func read(_ v: StubVolume, _ p: String) throws -> Data { try Data(contentsOf: r[v]!.appendingPathComponent(p)) }
        #expect(try read(.system, "usr/standalone/bootcaches.plist") == z.read("usr/standalone/bootcaches.plist"))
        #expect(try read(.system, "System/Library/CoreServices/PlatformSupport.plist") == z.read("PlatformSupport.plist"))
        let sv = try PValue.parse(read(.system, "System/Library/CoreServices/SystemVersion.plist"))
        #expect(sv["ProductUserVisibleVersion"]?.string == "13.5 (stub)")
        let rb = "\(t.vgid)/Restore"
        #expect(try PValue.parse(read(.preboot, "\(rb)/BuildManifest.plist"))["BuildIdentities"]?.array?.count == 1)
        #expect(try read(.preboot, "\(rb)/kernelcache.release.fixture") == bytes("kc", 70_000))
        #expect(try read(.preboot, "\(rb)/Firmware/all_flash/iBoot.j313ap.im4p") == bytes("ibootj313ap", 3000))
        #expect(try read(.preboot, "\(rb)/Bootability/Bootability.trustcache") == bytes("tc", 300))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: r[.preboot]!.path + "/\(rb)/Bootability/B.framework/Versions/Current") == "A")
        #expect(try read(.preboot, "\(rb)/Bootability/B.framework/B") == bytes("bootability", 5000))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: r[.system]!.path + "/Restore") == r[.preboot]!.path + "/\(t.vgid)/./Restore")
        #expect(FileManager.default.fileExists(atPath: r[.data]!.path + "/private/var/db/dslocal"))
        // BaseSystem: decmpfs LZFSE, reads back as the member's bytes
        let bs = r[.recovery]!.path + "/\(t.vgid)/usr/standalone/firmware/arm64eBaseSystem.dmg"
        #expect(try Data(contentsOf: URL(fileURLWithPath: bs)) == bytes("basesystem", 300_000))
        var st = stat(); stat(bs, &st)
        #expect(st.st_flags & UInt32(UF_COMPRESSED) != 0)
        #expect(st.st_size == 300_000)
        // the app, the script with its tokens, the boot object
        let app = r[.system]!.path + "/Setup.app/Contents"
        let script = try String(contentsOfFile: app + "/Resources/step2.sh", encoding: .utf8)
        #expect(script == "VGID=\"\(t.vgid)\"\nPREBOOT=\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\"\nDISTRO=\"SiliconForest\"\n")
        stat(app + "/Resources/step2.sh", &st); #expect(st.st_mode & 0o777 == 0o755)
        stat(app + "/MacOS/launch.sh", &st); #expect(st.st_mode & 0o777 == 0o755)
        #expect(try Data(contentsOf: URL(fileURLWithPath: app + "/Resources/boot.bin")) == bytes("m1n1", 4096) + Data("chainload=X;sf/boot.bin\n".utf8) + Data([0, 0, 0, 0]))
        #expect(FileManager.default.fileExists(atPath: r[.system]!.path + "/.IAPhysicalMedia"))
        #expect(FileManager.default.fileExists(atPath: r[.system]!.path + "/.VolumeIcon.icns"))
        // xattr, schg, bootable
        var fi = [UInt8](repeating: 0, count: 32)
        #expect(getxattr(r[.system]!.path, "com.apple.FinderInfo", &fi, 32, 0, 0) == 32 && fi[8] == 4)
        #expect(effects.contains("flags AdminUserRecoveryInfo.plist 20000"))
        #expect(effects.contains { $0.hasPrefix("xattr -wx com.apple.decmpfs 66706D630C000000e093040000000000 ") })
        #expect(bootable == ["vol-System"])
    }

    @Test func refusesUnmountedRootsAndEscapes() throws {
        let dir = tempDir("refuse")
        let t = StubTarget(roots: [.system: dir], vgid: "V", prebootVolumeUUID: "P")
        let w = StubWriter(target: t, staged: [:])
        #expect(throws: StubError.self) { try w.run([.mkdir(StubPath(.system, "x"))]) }   // not a mount point
        var w2 = w; w2.requireMountPoints = false
        #expect(throws: StubError.self) { try w2.run([.mkdir(StubPath(.system, "../escape"))]) }
        #expect(throws: StubError.self) { try w2.run([.mkdir(StubPath(.preboot, "x"))]) }  // no such volume
        #expect(throws: StubError.self) { _ = try StubStager(zip: try ZipReader(MemorySource(fixtureIPSW().0)), work: dir).stagedURL("../x") }
    }

    @Test func stagingIsCheckedAndReused() throws {
        let dir = tempDir("stage")
        let (data, _) = fixtureIPSW()
        let mem = MemorySource(data)
        let z = try ZipReader(mem)
        let e = try z.require("000-base.dmg")
        let s = StubStager(zip: z, work: dir)
        let u = try s.stage([e])["000-base.dmg"]!
        #expect(try Data(contentsOf: u) == bytes("basesystem", 300_000))
        let n = mem.reads.count
        _ = try s.stage([e])                         // complete stage: reused, nothing fetched
        #expect(mem.reads.count == n)
        let (bad, _) = fixtureIPSW(corrupt: "000-base.dmg")
        let zb = try ZipReader(MemorySource(bad))
        let dir2 = tempDir("stage-bad")
        #expect(throws: StubError.self) { _ = try StubStager(zip: zb, work: dir2).stage([try zb.require("000-base.dmg")]) }
        #expect(!FileManager.default.fileExists(atPath: dir2.appendingPathComponent("members/000-base.dmg").path))
    }

    @Test func decmpfsHeaderAndBootObjectFormats() {
        #expect(Decmpfs.header(size: 0x0102_0304) == Data([0x66, 0x70, 0x6D, 0x63, 0x0C, 0, 0, 0, 4, 3, 2, 1, 0, 0, 0, 0]))
        #expect(Decmpfs.upstreamHex(size: 1_815_115_416) == "66706D630C000000" + "9876306c00000000")
        #expect(M1n1.variablesBlob(["a=1", "b"]) == Data("a=1\nb\n".utf8) + Data([0, 0, 0, 0]))
    }

    @Test(.disabled("Needs Apple's 13.5 (22G74) restore image, root, and the pinned Asahi v0.9.2 oracle: run installer/mac/scripts/stub-differential.sh on the M5"))
    func differentialAgainstAsahiOnTheRealImage() {}
}
