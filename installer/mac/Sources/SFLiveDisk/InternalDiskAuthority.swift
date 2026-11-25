import Foundation
import SFEngine
import SFInstallKit

// The only type that can point the live backend at an internal disk. It exists only in a build that
// defines `SF_REAL_DISK_WRITES` (the compile key); `Package.swift` never does, CI refuses it, and
// `scripts/check-real-disk-gate.sh` fails if the symbol is in a shipped binary. Even then it is
// closed until the runtime key (RealDiskGate: root-owned, plan- and disk-bound, short-lived
// authorization) is open, and it re-checks that on every command, so an expired authorization stops a job.
#if SF_REAL_DISK_WRITES
public struct InternalDiskAuthority: TargetAuthority {
    public let diskUUID: String
    public let query: ToolRunner
    private let gate: @Sendable () -> Result<RealDiskGate.Authorization, RealDiskGate.Closed>
    public var kind: LiveTargetKind { .internalDisk(diskUUID: diskUUID) }
    public var label: String { "internal disk \(diskUUID)" }

    /// `gate` defaults to the real file-based runtime key. Tests (built with the compile key, fake runners
    /// only) inject their own.
    public init(planDigest: String, diskUUID: String, query: ToolRunner = ProcessToolRunner(),
                gate: (@Sendable () -> Result<RealDiskGate.Authorization, RealDiskGate.Closed>)? = nil) throws {
        let g = gate ?? { RealDiskGate.evaluate(planDigest: planDigest, diskUUID: diskUUID) }
        if case .failure(let closed) = g() { throw SafetyRefusal("the real-disk gate is closed: \(closed)") }
        self.diskUUID = diskUUID.uppercased(); self.query = query; self.gate = g
    }

    private func requireOpen() throws {
        if case .failure(let closed) = gate() { throw SafetyRefusal("the real-disk gate is closed: \(closed)") }
    }

    public func wholeDisk() throws -> String {
        try requireOpen()
        let list = try Query.dict(query, ["/usr/sbin/diskutil", "list", "-plist"])
        var found: [String] = []
        for e in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let id = e["DeviceIdentifier"] as? String, e["Content"] as? String == "GUID_partition_scheme",
                  id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { continue }
            let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", id])
            guard (try? WholeDiskIdentity.uuid(id, info: info)) == diskUUID.uppercased() else { continue }
            guard info["WholeDisk"] as? Bool == true, info["Internal"] as? Bool == true,
                  info["VirtualOrPhysical"] as? String != "Virtual", info["BusProtocol"] as? String != "Disk Image",
                  info["RemovableMediaOrExternalDevice"] as? Bool != true, info["Removable"] as? Bool != true else {
                throw SafetyRefusal("\(id) has the authorized UUID but isn't an internal physical whole disk")
            }
            found.append(id)
        }
        guard found.count == 1, let w = found.first else { throw SafetyRefusal("exactly one internal disk must match the authorized disk UUID (found \(found.count))") }
        return w
    }

    public func authorize(_ device: String) throws {
        try requireOpen()
        let (id, whole) = try ImageGuard.normalise(device)
        let target = try wholeDisk()
        let info = try Query.dict(query, ["/usr/sbin/diskutil", "info", "-plist", id])
        guard info["Internal"] as? Bool == true, info["BusProtocol"] as? String != "Disk Image" else { throw SafetyRefusal("\(id) is not an internal disk") }
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
            let ids = stores.compactMap { $0["APFSPhysicalStore"] as? String }
            guard !ids.isEmpty, try ids.allSatisfy({ try ImageGuard.normalise($0).whole == target }) else {
                throw SafetyRefusal("\(id) is an APFS disk whose store isn't on the authorized disk")
            }
            return
        }
        guard whole == target, info["ParentWholeDisk"] as? String == target else { throw SafetyRefusal("\(id) is not on the authorized disk \(target)") }
    }

    public func detach(force: Bool) throws { throw SafetyRefusal("a real disk can't be detached") }
    public func attach() throws { throw SafetyRefusal("a real disk can't be attached") }
}
#endif

/// What a build can say about itself, for the helper's status and the tests.
public enum LiveDiskBuild {
    /// True only in a build with the compile key. A shipped build must report false.
    public static var realDiskAuthorityCompiledIn: Bool { RealDiskGate.compiledIn }
}
