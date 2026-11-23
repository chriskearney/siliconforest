import Foundation

/// Builds sparse disk images laid out like real Macs, for the engine's rehearsals and tests. Files
/// live only under the allowed images directory, and every partitioning command goes through the
/// chokepoint like the engine's own.
public enum ImageFixtures {
    /// Bumped whenever a layout changes, so cached templates are rebuilt.
    public static let version = 1

    public enum Layout: String, Sendable, CaseIterable {
        /// 13-inch M1 MacBook Pro: Apple ISC, macOS container, Apple Recovery.
        case j293
        /// M1 MacBook Air as Chris has it: ISC, macOS, a Linux stub (APFS), an ESP, a Linux root, Recovery.
        case j313
    }

    static let isc = "%69646961-6700-11AA-AA11-00306543ECAC%"
    static let recovery = "%52637672-7900-11AA-AA11-00306543ECAC%"
    static let efi = "%C12A7328-F81F-11D2-BA4B-00A0C93EC93B%"
    static let linux = "%0FC63DAF-8483-4772-8E79-3D69D8477DE4%"

    /// Creates `<dir>/<name>.sparseimage`, partitions it and leaves it detached.
    @discardableResult
    public static func create(_ layout: Layout, in dir: URL, name: String, allowedRoot: URL = ImageGuard.defaultRoot) throws -> URL {
        try FileManager.default.ensureDirectory(dir)
        let url = dir.appendingPathComponent("\(name).sparseimage")
        let imageGuard = ImageGuard(allowedRoot: allowedRoot)
        guard imageGuard.isUnderAllowedRoot(dir.appendingPathComponent("x.sparseimage").path) else { throw SafetyRefusal("fixtures must live under \(allowedRoot.path)") }
        try? FileManager.default.removeItem(at: url)
        let size = layout == .j293 ? "64g" : "96g"
        let create = try ProcessToolRunner().run(["/usr/bin/hdiutil", "create", "-quiet", "-size", size, "-type", "SPARSE", "-layout", "GPTSPUD",
                                                  "-fs", "APFS", "-volname", "SFImage", url.path])
        guard create.ok else { throw EngineError(.appleTool, "hdiutil create failed", detail: create.err) }
        let backend = DiskImageBackend(imagePath: url, allowedRoot: allowedRoot)
        try backend.attach()
        do {
            let w = try backend.wholeDisk()
            switch layout {
            case .j293:
                try backend.diskutil(["partitionDisk", w, "3", "GPT", isc, "%noformat%", "524288000B", "APFS", "SFImage HD", "R", recovery, "%noformat%", "5368709120B"])
            case .j313:
                try backend.diskutil(["partitionDisk", w, "6", "GPT", isc, "%noformat%", "524288000B", "APFS", "SFImage HD", "R",
                                      "APFS", "Linux stub", "2499805184B", efi, "%noformat%", "524288000B", linux, "%noformat%", "21474836480B",
                                      recovery, "%noformat%", "5368709120B"])
            }
            // partitionDisk adds an EFI system partition first and, sometimes, an Apple_Boot helper.
            // Apple silicon Macs have neither: remove them so the table matches a real Mac's.
            var t = try backend.topology()
            for p in t.partitions where (p.offset < 600_000_000 && p.content == "EFI") || p.content == "Apple_Boot" {
                try backend.diskutil(["eraseVolume", "free", "none", p.identifier])
            }
            t = try backend.topology()
            // macOS: a System-role and a Data-role volume, like a real install's volume group.
            guard let mac = t.partitions.first(where: { $0.content == "Apple_APFS" && $0.apfs?.volumes.first?.name == "SFImage HD" }) else {
                throw EngineError(.internalError, "fixture: no macOS container")
            }
            try backend.addVolume(container: mac.uuid, name: "SFImage HD System", role: "S")
            try backend.addVolume(container: mac.uuid, name: "SFImage HD Data", role: "D")
            if layout == .j313 {
                // The Linux stub carries macOS 13.5's boot volumes on the real Air; one System volume stands in.
                if let stub = t.partitions.first(where: { $0.apfs?.volumes.first?.name == "Linux stub" }) {
                    try backend.addVolume(container: stub.uuid, name: "Linux stub System", role: "S")
                }
                if let esp = t.partitions.first(where: { $0.content == "EFI" }) {
                    try backend.formatFAT32(esp.uuid, label: "EFI")
                }
                if let root = t.partitions.first(where: { $0.content == "Linux Filesystem" }) {
                    // A recognisable pattern at the start of the Linux root: tests prove it is never touched.
                    try backend.writeRaw(root.uuid, offset: 0, data: Data(LinuxRootSentinel.bytes))
                }
            }
            try backend.detach(force: false)
        } catch {
            try? backend.detach(force: true)
            throw error
        }
        return url
    }

    /// Clones a template with APFS clonefile (instant, no extra space) and attaches the copy.
    public static func clone(_ template: URL, to url: URL) throws -> URL {
        try FileManager.default.ensureDirectory(url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: url)
        guard clonefile(template.path, url.path, 0) == 0 else {
            try FileManager.default.copyItem(at: template, to: url)
            return url
        }
        return url
    }

    /// Detaches every image attached from under the allowed directory and deletes `dir`.
    public static func cleanUp(_ dir: URL, allowedRoot: URL = ImageGuard.defaultRoot) {
        let g = ImageGuard(allowedRoot: allowedRoot)
        let prefix = ImageGuard.resolve(dir.path) + "/"
        for img in (try? g.attachedImages()) ?? [] where ImageGuard.resolve(img.imagePath).hasPrefix(prefix) {
            if let w = img.partitionMapDisk {
                _ = try? ImageChokepoint(imageGuard: g).run(["/usr/bin/hdiutil", "detach", w, "-force"])
            }
        }
        try? FileManager.default.removeItem(at: dir)
    }
}

public enum LinuxRootSentinel {
    public static let bytes: [UInt8] = Array("SF-TEST-LINUX-ROOT-DO-NOT-TOUCH\n".utf8) + [UInt8](repeating: 0x5A, count: 4096 - 32)
}
