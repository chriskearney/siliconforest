import Foundation

/// A partition reference in a plan: a real identifier ("disk0s2") or a slot ("@stub") that names a
/// partition the plan creates and is resolved when it exists.
public typealias PartRef = String

public extension PartRef {
    var isSlot: Bool { hasPrefix("@") }
}

public enum GUID {
    public static let efi = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    public static let linuxFilesystem = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
}

/// One thing the engine does to (or for) the disk. Every case renders as the exact commands a
/// privileged helper would run; the simulated backend applies it to a model instead, and the real
/// backend in this phase only records it.
public enum DiskOperation: Codable, Sendable, Hashable {
    /// `newSize == 0` grows the container to fill the free space after it.
    case resizeContainer(partition: PartRef, newSize: Int64)
    case addPartition(after: PartRef, slot: String, content: PartitionContent, name: String, size: Int64, metadata: [String: String])
    case deletePartition(PartRef)
    case deleteAPFSContainer(PartRef)
    /// Fetches something from the network (the stub's boot objects, the SiliconForest image).
    case download(item: String, url: String, bytes: Int64)
    /// Copies files onto a mounted volume of a partition.
    case writeFiles(target: PartRef, label: String, items: [String], bytes: Int64)
    /// Writes a filesystem image to a partition's raw device.
    case writeImage(target: PartRef, image: String, bytes: Int64)
    case verify(target: PartRef, label: String, bytes: Int64)
    /// Hashes downloaded files in the work directory (no disk object involved).
    case checkFiles(label: String, bytes: Int64)
    /// Sets the startup volume (`nextOnly`: just the next start, D5's one-shot first boot).
    case bless(target: PartRef, label: String, nextOnly: Bool)

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case resizeContainer, addPartition, deletePartition, deleteAPFSContainer, download, writeFiles, writeImage, verify, checkFiles, bless
    }

    public var kind: Kind {
        switch self {
        case .resizeContainer: return .resizeContainer
        case .addPartition: return .addPartition
        case .deletePartition: return .deletePartition
        case .deleteAPFSContainer: return .deleteAPFSContainer
        case .download: return .download
        case .writeFiles: return .writeFiles
        case .writeImage: return .writeImage
        case .verify: return .verify
        case .checkFiles: return .checkFiles
        case .bless: return .bless
        }
    }

    /// True for everything that changes the disk or boot state.
    public var isMutating: Bool {
        switch self {
        case .download, .verify, .checkFiles: return false
        default: return true
        }
    }

    public var summary: String {
        switch self {
        case .resizeContainer(let p, let size):
            return size == 0 ? "Grow \(p) to fill the free space" : "Resize APFS container \(p) to \(Bytes.format(size))"
        case .addPartition(_, _, let content, let name, let size, _):
            return "Create \(content == .appleAPFS ? "APFS container" : content == .efi ? "EFI partition" : "ext4 partition") “\(name)” (\(Bytes.format(size)))"
        case .deletePartition(let p): return "Remove partition \(p)"
        case .deleteAPFSContainer(let p): return "Delete APFS container on \(p)"
        case .download(let item, _, let bytes): return "Download \(item) (\(Bytes.format(bytes)))"
        case .writeFiles(_, let label, let items, _): return "Copy \(label) (\(items.count) item\(items.count == 1 ? "" : "s"))"
        case .writeImage(_, let image, let bytes): return "Write \(image) (\(Bytes.format(bytes)))"
        case .verify(_, let label, _): return "Verify \(label)"
        case .checkFiles(let label, _): return "Check \(label)"
        case .bless(_, let label, let next): return next ? "Start \(label) next time only" : "Make \(label) the startup disk"
        }
    }

    /// The commands a privileged helper would run, with slots resolved through `resolve`.
    public func commands(resolve: (PartRef) -> String = { $0 }) -> [[String]] {
        switch self {
        case .resizeContainer(let p, let size):
            return [["/usr/sbin/diskutil", "apfs", "resizeContainer", resolve(p), size == 0 ? "0" : "\(size)B"]]
        case .addPartition(let after, _, let content, let name, let size, _):
            switch content {
            case .appleAPFS:
                return [["/usr/sbin/diskutil", "addPartition", resolve(after), "APFS", name, "\(size)B"]]
            case .efi:
                return [["/usr/sbin/diskutil", "addPartition", resolve(after), "%\(GUID.efi)%", "%noformat%", "\(size)B"],
                        ["/sbin/newfs_msdos", "-F", "32", "-v", name, "/dev/r<new>"]]
            default:
                return [["/usr/sbin/diskutil", "addPartition", resolve(after), "%\(GUID.linuxFilesystem)%", "%noformat%", "\(size)B"]]
            }
        case .deletePartition(let p):
            return [["/usr/sbin/diskutil", "eraseVolume", "free", "free", resolve(p)]]
        case .deleteAPFSContainer(let p):
            return [["/usr/sbin/diskutil", "apfs", "deleteContainer", resolve(p)]]
        case .download(let item, let url, _):
            return [["/usr/bin/curl", "-fL", "--retry", "3", "-o", "<cache>/\(item)", url]]
        case .writeFiles(let target, _, let items, _):
            return items.map { ["/usr/bin/ditto", "<payload>/\($0)", "<mount:\(resolve(target))>/\($0)"] }
        case .writeImage(let target, let image, _):
            return [["/usr/bin/xz", "-dc", "<cache>/\(image).xz", "|", "<helper: stream to /dev/r\(resolve(target))>"]]
        case .verify(let target, let label, _):
            return [["/usr/bin/shasum", "-a", "256", "-c", "<payload>/\(label).sha256", "--", "/dev/r\(resolve(target))"]]
        case .checkFiles(let label, _):
            return [["/usr/bin/shasum", "-a", "256", "-c", "<cache>/SHA256SUMS", "# \(label)"]]
        case .bless(let target, _, let next):
            return [["/usr/sbin/bless", "--mount", "<mount:\(resolve(target))>", "--setBoot"] + (next ? ["--nextonly"] : [])]
        }
    }
}

/// Rendered command lines, for logs, journals and the "show commands" drawer.
public enum CommandRender {
    public static func render(_ argv: [String]) -> String {
        argv.map { arg in
            arg.contains(" ") || arg.contains("“") ? "'\(arg)'" : arg
        }.joined(separator: " ")
    }
}
