import Foundation
import Compression

/// A stand-in release for image rehearsals: every artifact the engine handles, made of our own
/// placeholder bytes (no Apple binaries, firmware or artwork, DESIGN §14.13), with real hashes, a
/// real xz (LZMA) root image and real slot offsets.
public enum RehearsalRelease {
    public static let rootImageBytes: Int64 = 16 << 20

    /// The rehearsal kc-builder: links nothing; writes a header and the SHA-256 of every option and every
    /// input file (path and bytes) in link order, so any change to an input changes the "collection".
    /// Same idea as installer/payload/release/rehearsal_kc_builder.py. /bin/sh and shasum only.
    public static let standInKCBuilder = """
        #!/bin/sh
        # SiliconForest rehearsal stand-in for kc-builder (not a linker; rehearsals only)
        out=; prev=
        for a in "$@"; do [ "$prev" = -o ] && out=$a; prev=$a; done
        [ -n "$out" ] || exit 64
        {
          printf 'SFKC-REHEARSAL-STAND-IN 1\n'
          for a in "$@"; do [ "$a" = "$out" ] && a=@OUTPUT@; printf '%s\n' "$a"; done
          find kernel kexts codeless -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
            printf '%s ' "$f"; /usr/bin/shasum -a 256 < "$f"
          done
        } > "$out"

        """
    public static let rootFilesystemUUID = "5f0e3c2a-1b2c-4d3e-8f40-0000000000a1"

    /// Synthetic kernel-collection inputs (no kernel, no kexts, no Apple parts) and the stand-in tool, as
    /// artifacts; the expected hash comes from linking them once here, as make_release.py does.
    static func kernelCollection(put: (String, Data, Int?) throws -> Void, tool: Data = Data(standInKCBuilder.utf8)) throws -> KernelCollection {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("sf-kc-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        let tree = tmp.appendingPathComponent("inputs", isDirectory: true)
        var bundles: [KernelCollection.Bundle] = []
        var args = ["-kc-base", "fffffe0006000000", "-kernel", "kernel"]
        func file(_ rel: String, _ data: Data, artifact: String, mode: Int) throws {
            let u = tree.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: u)
            try put(artifact, data, mode)
        }
        try file("kernel", Data(String(repeating: "SF-REHEARSAL synthetic kernel\n", count: 64).utf8), artifact: "kc.kernel", mode: 0o644)
        for (kind, opt, name, withExe) in [("kexts", "-kext", "SFRehearsalA", true), ("kexts", "-kext", "SFRehearsalB", true),
                                           ("codeless", "-codeless", "SFRehearsalKPI", false)] {
            let dir = "\(kind)/\(name).kext"
            var files: [KernelCollection.File] = []
            let plistPath = withExe ? "Contents/Info.plist" : "Info.plist"
            let entries: [(String, Data, Int)] = [(plistPath, Data("<plist><dict><key>CFBundleIdentifier</key><string>org.siliconforest.rehearsal.\(name)</string></dict></plist>\n".utf8), 0o644)]
                + (withExe ? [("Contents/MacOS/\(name)", Data(String(repeating: "SF-REHEARSAL \(name) executable\n", count: 32).utf8), 0o755)] : [])
            for (path, data, mode) in entries {
                let art = KernelCollection.artifactName(dir, path)
                try file("\(dir)/\(path)", data, artifact: art, mode: mode)
                files.append(.init(path: path, artifact: art, mode: mode))
            }
            bundles.append(.init(dir: dir, files: files))
            args += [opt, dir]
        }
        args += ["-o", KernelCollection.output]
        try put("kc-builder", tool, 0o755)
        let toolURL = tmp.appendingPathComponent("kc-builder")
        try tool.write(to: toolURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)
        let out = tmp.appendingPathComponent("collection")
        let p = Process()
        p.executableURL = toolURL
        p.arguments = args.map { $0 == KernelCollection.output ? out.path : $0 }
        p.currentDirectoryURL = tree
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw EngineError(.internalError, "the rehearsal kc-builder failed") }
        let data = try Data(contentsOf: out)
        return KernelCollection(tool: "kc-builder", toolSigning: "rehearsal-stand-in", kernel: "kc.kernel", bundles: bundles, linkArgs: args,
                                collectionSHA256: SHA256Hasher.hex(data), collectionBytes: Int64(data.count), bootargsTemplate: "bootargs.template")
    }

    public static func make(in dir: URL, version: String = "0.0-rehearsal", kernelCollection withKC: Bool = true) throws -> ReleaseManifest {
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
        if !withKC {
            var kernel = filler("kernel", 1 << 20)
            kernel.append(Data("\nboot-args: rd=uuid boot-uuid=@SF_FSUUID@ sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@\n".utf8))
            try put("kernel.bin", kernel)
        }
        try put("firmware.bin", filler("firmware", 256 << 10))
        var kc: KernelCollection?
        if withKC {
            try put("bootargs.template", Data("rd=uuid boot-uuid=@SF_FSUUID@ sfnvme_part=@SF_PARTUUID@ sfnvme_part_lba=@SF_PART_LBA@\n".utf8))
            kc = try kernelCollection(put: { name, data, mode in
                try put(name, data)
                if let mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: dir.appendingPathComponent(name).path) }
            })
        }

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
                               stubFiles: stubFiles, stage1: "sf-stage1.bin", stage2: "boot.bin", kernel: withKC ? "kc.kernel" : "kernel.bin",
                               firmware: "firmware.bin", kernelCollection: kc, rootFilesystemUUID: withKC ? rootFilesystemUUID : nil)
    }

    /// A rehearsal release whose kernel collection is a real one: the kc artifacts, the boot-argument template
    /// and root.fs_uuid of a format-3 release directory (make_release.py), copied into `dir` over the
    /// synthetic ones. Every copied file is hashed against that release's install.json.
    public static func make(in dir: URL, kernelCollectionFrom real: URL, version: String = "0.0-rehearsal") throws -> ReleaseManifest {
        var m = try make(in: dir, version: version, kernelCollection: true)
        let fm = FileManager.default
        let installData = try Data(contentsOf: real.appendingPathComponent("install.json"))
        let (kc, fs) = try KernelCollection.fromInstallJSON(installData)
        guard let o = try JSONSerialization.jsonObject(with: installData) as? [String: Any], let list = o["artifacts"] as? [[String: Any]] else {
            throw EngineError(.inconsistent, "install.json has no artifacts")
        }
        var theirs: [String: ReleaseManifest.Artifact] = [:]
        for a in list {
            guard let n = a["name"] as? String, let h = a["sha256"] as? String, let b = (a["bytes"] as? NSNumber)?.int64Value else { continue }
            theirs[n] = .init(name: n, bytes: b, sha256: h)
        }
        let synthetic = Set(m.kernelCollection.map { k in [k.tool, k.kernel, k.bootargsTemplate] + k.bundles.flatMap { $0.files.map(\.artifact) } } ?? [])
        for n in synthetic where n != kc.bootargsTemplate { try? fm.removeItem(at: dir.appendingPathComponent(n)) }
        m.artifacts.removeAll { synthetic.contains($0.name) }
        let wanted = [kc.tool, kc.kernel, kc.bootargsTemplate] + kc.bundles.flatMap { $0.files.map(\.artifact) }
        for n in wanted {
            guard let a = theirs[n] else { throw EngineError(.inconsistent, "\(n) isn't listed in \(real.path)/install.json") }
            let dst = dir.appendingPathComponent(n)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: real.appendingPathComponent(n), to: dst)
            guard try SHA256Hasher.file(dst) == a.sha256 else { throw EngineError(.inconsistent, "\(n) doesn't match \(real.path)/install.json") }
            m.artifacts.append(a)
        }
        var sums = m.artifacts.map { "\($0.sha256)  \($0.name)" }.joined(separator: "\n")
        sums.append("\n")
        try sums.write(to: dir.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)
        m.kernelCollection = kc
        m.kernel = kc.kernel
        m.rootFilesystemUUID = fs
        return m
    }
}
