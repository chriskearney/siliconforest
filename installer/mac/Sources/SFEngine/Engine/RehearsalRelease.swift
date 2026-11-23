import Foundation
import Compression

/// A stand-in release for image rehearsals: every artifact the engine handles, made of our own
/// placeholder bytes (no Apple binaries, firmware or artwork, DESIGN §14.13), with real hashes, a
/// real xz (LZMA) root image and real slot offsets.
public enum RehearsalRelease {
    public static let rootImageBytes: Int64 = 16 << 20

    public static func make(in dir: URL, version: String = "0.0-rehearsal") throws -> ReleaseManifest {
        let fm = FileManager.default
        try fm.ensureDirectory(dir)
        var artifacts: [ReleaseManifest.Artifact] = []
        func put(_ name: String, _ data: Data) throws {
            let url = dir.appendingPathComponent(name)
            try fm.ensureDirectory(url.deletingLastPathComponent())
            try data.write(to: url)
            artifacts.append(.init(name: name, bytes: Int64(data.count), sha256: SHA256Hasher.hex(data)))
        }
        func filler(_ tag: String, _ n: Int) -> Data {
            var d = Data("SF-REHEARSAL \(tag)\n".utf8)
            var x: UInt32 = 2_463_534_242
            while d.count < n { x ^= x << 13; x ^= x >> 17; x ^= x << 5; withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
            return d.prefix(n)
        }
        // The stub's System volume contents (Apple's 13.5 files on a real install; placeholders here).
        let stubFiles = ["stub/System/Library/CoreServices/SystemVersion.plist", "stub/System/Library/CoreServices/boot.efi.placeholder",
                         "stub/usr/standalone/firmware/iBoot.placeholder", "stub/BaseSystem.placeholder"]
        try put(stubFiles[0], Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>ProductName</key><string>SiliconForest rehearsal stub</string><key>ProductVersion</key><string>13.5</string></dict></plist>

            """.utf8))
        try put(stubFiles[1], filler("boot", 96 << 10))
        try put(stubFiles[2], filler("iboot", 64 << 10))
        try put(stubFiles[3], filler("basesystem", 1 << 20))
        try put("sf-stage1.bin", filler("stage1", 256 << 10))
        try put("boot.bin", filler("stage2", 512 << 10))
        var kernel = filler("kernel", 1 << 20)
        kernel.append(Data("\nboot-args: rd=uuid boot-uuid=@SF_FSUUID@ sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@\n".utf8))
        try put("kernel.bin", kernel)
        try put("firmware.bin", filler("firmware", 256 << 10))

        // Root image: a recognisable header, then zeros (as a fresh ext4 image is mostly), xz-compressed.
        var root = Data("SFROOT1 rehearsal image\n".utf8)
        root.append(Data(count: Int(rootImageBytes) - root.count))
        root.replaceSubrange(4096..<(4096 + 65536), with: filler("rootdata", 65536))
        let rootSHA = SHA256Hasher.hex(root)
        var xz = Data()
        let filter = try OutputFilter(.compress, using: .lzma) { (d: Data?) in if let d { xz.append(d) } }
        try filter.write(root)
        try filter.finalize()
        try put("root.img.xz", xz)

        var sums = artifacts.map { "\($0.sha256)  \($0.name)" }.joined(separator: "\n")
        sums.append("\n")
        try sums.write(to: dir.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)

        return ReleaseManifest(version: version, artifacts: artifacts, rootImage: "root.img.xz", rootImageBytes: rootImageBytes,
                               rootImageSHA256: rootSHA, rootImageCompressed: true, rootMinBytes: 1 << 30,
                               firmwareSlotOffset: 8 << 20, firmwareSlotBytes: 1 << 20, receiptSlotOffset: 12 << 20, receiptSlotBytes: 64 << 10,
                               stubFiles: stubFiles, stage1: "sf-stage1.bin", stage2: "boot.bin", kernel: "kernel.bin", firmware: "firmware.bin")
    }
}
