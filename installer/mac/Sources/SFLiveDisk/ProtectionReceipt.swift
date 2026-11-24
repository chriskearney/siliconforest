import Foundation
import SFEngine
import SFInstallKit

/// The protection receipt: what this job may never touch, and the one span it may write in, derived
/// from the approved plan and the partition table the journal saved before the first write. It is
/// derived again, identically, after a crash. The live backend checks every command against it, on a
/// fresh read of the disk, independently of the engine's gate.
///
/// Two rules, both enforced geometrically as well as by identity:
///  - every partition that existed before the job (Apple's own, the macOS container, and above all
///    the Linux stub, ESP and root) is **protected**, except that the macOS container may be resized,
///    only to a size the plan names (or, for a removal, to fill the freed space);
///  - the job may create, format, write and erase only partitions that lie entirely inside the
///    **span**: from the end of the (shrunk) macOS container to the start of the next existing partition.
public struct ProtectionReceipt: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case appleSystem, macOS, linuxStub, linuxESP, linuxRoot, other
    }

    public struct Entry: Codable, Sendable, Hashable {
        public var uuid: String
        public var content: String
        public var offset: Int64
        public var size: Int64
        public var kind: Kind
        public var end: Int64 { offset + size }
    }

    public var format = "siliconforest-protection/1"
    public var planDigest: String
    public var operation: EnginePlan.Operation
    public var wholeSize: Int64
    public var blockSize: Int64
    public var macOSStore: String
    public var macOSOffset: Int64
    public var macOSFrom: Int64
    public var macOSTo: Int64
    public var spanStart: Int64
    public var spanEnd: Int64
    /// Everything that existed before the job and is not the macOS container or ours: never touched.
    public var protected: [Entry]
    /// A removal: what the install's journal proved is ours, which may be erased.
    public var owned: [String]
    public var digest: String = ""

    public func computeDigest() -> String {
        var c = self; c.digest = ""
        return (try? Canonical.digest(c)) ?? ""
    }

    public func sealed() -> ProtectionReceipt { var r = self; r.digest = computeDigest(); return r }
    public var isSealed: Bool { !digest.isEmpty && digest == computeDigest() }

    public func isProtected(uuid: String) -> Bool { protected.contains { $0.uuid == uuid } }

    // MARK: derivation

    public static func classify(_ p: ImagePartition, macOSStore: String, macOSOffset: Int64) -> Kind {
        if p.uuid == macOSStore { return .macOS }
        switch p.content {
        case "EFI": return .linuxESP
        case "Linux Filesystem": return .linuxRoot
        case "Apple_APFS": return p.offset > macOSOffset ? .linuxStub : .appleSystem
        default:
            let c = p.content.uppercased()
            if c.contains("0FC63DAF-8483-4772-8E79-3D69D8477DE4") || c.contains("0657FD6D-A4AB-43C4-84E5-0933C84B4F4F") { return .linuxRoot }
            if c.contains("C12A7328-F81F-11D2-BA4B-00A0C93EC93B") { return .linuxESP }
            return p.offset < macOSOffset ? .appleSystem : .other
        }
    }

    /// `original` is the partition table saved before the job's first write.
    public static func derive(plan: EnginePlan, original: ImageTopology) throws -> ProtectionReceipt {
        guard plan.isSealed else { throw SafetyRefusal("protection receipt: the plan isn't sealed") }
        guard let mac = original.partition(uuid: plan.macOS.store) else { throw SafetyRefusal("protection receipt: the macOS container isn't in the saved table") }
        guard mac.content == "Apple_APFS" else { throw SafetyRefusal("protection receipt: the planned macOS partition isn't an APFS container") }
        let owned = plan.operation == .remove ? (plan.owned?.all ?? []) : []
        if plan.operation == .remove, owned.isEmpty { throw SafetyRefusal("protection receipt: a removal with nothing proved ours") }
        if plan.operation == .install, plan.macOS.from != mac.size { throw SafetyRefusal("protection receipt: the saved macOS size isn't the plan's") }
        let others = original.partitions.filter { $0.uuid != mac.uuid && !owned.contains($0.uuid) }
        let protected = others.map { Entry(uuid: $0.uuid, content: $0.content, offset: $0.offset, size: $0.size,
                                           kind: classify($0, macOSStore: mac.uuid, macOSOffset: mac.offset)) }
        // The span runs from the end of macOS (at its planned size) to the next partition that isn't ours.
        let spanStart = plan.operation == .install ? mac.offset + plan.macOS.to : mac.end
        let nextProtected = protected.filter { $0.offset >= mac.end }.map(\.offset).min()
        let spanEnd = nextProtected ?? (original.size - 20_480)
        guard spanEnd > spanStart else { throw SafetyRefusal("protection receipt: no space after the macOS container") }
        // Nothing protected may lie inside the span.
        if let bad = protected.first(where: { $0.offset < spanEnd && $0.end > spanStart }) {
            throw SafetyRefusal("protection receipt: a protected partition (\(bad.kind.rawValue)) lies inside the span")
        }
        return ProtectionReceipt(planDigest: plan.digest, operation: plan.operation, wholeSize: original.size, blockSize: original.blockSize,
                                 macOSStore: mac.uuid, macOSOffset: mac.offset, macOSFrom: plan.macOS.from, macOSTo: plan.macOS.to,
                                 spanStart: spanStart, spanEnd: spanEnd, protected: protected, owned: owned).sealed()
    }

    // MARK: checks against a fresh read

    /// The disk must be the disk the receipt was made for, and nothing protected may have moved.
    /// Returns a description of the first violation, or nil.
    public func violation(in now: ImageTopology) -> String? {
        if now.size != wholeSize || now.blockSize != blockSize { return "the target disk's size changed" }
        for e in protected {
            guard let p = now.partition(uuid: e.uuid) else { return "protected partition \(e.kind.rawValue) (\(e.uuid.prefix(8))…) vanished" }
            if p.offset != e.offset { return "protected partition \(e.kind.rawValue) moved" }
            if p.size != e.size { return "protected partition \(e.kind.rawValue) changed size" }
        }
        guard let mac = now.partition(uuid: macOSStore) else { return "the macOS container vanished" }
        if mac.offset != macOSOffset { return "the macOS container moved" }
        if operation == .install {
            if mac.size != macOSFrom && mac.size != macOSTo { return "the macOS container is \(mac.size) B, not a planned size" }
        } else if mac.size < macOSFrom || mac.end > spanEnd {
            // A removal only grows macOS, and only into the space the install had taken.
            return "the macOS container is \(mac.size) B, outside what a removal may give it"
        }
        for p in now.partitions where p.uuid != macOSStore && !isProtected(uuid: p.uuid) {
            if p.offset < spanStart || p.end > spanEnd { return "a new partition (\(p.content), \(p.size) B) lies outside the allowed span" }
        }
        return nil
    }

    /// A partition the job may create, format, write or erase: not protected, not macOS, inside the span.
    public func isWritable(_ p: ImagePartition) -> Bool {
        p.uuid != macOSStore && !isProtected(uuid: p.uuid) && p.offset >= spanStart && p.end <= spanEnd
    }
}
