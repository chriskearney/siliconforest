import Foundation
import Testing
@testable import SFEngine
@testable import SFLiveDisk
import SFInstallKit

// These run only in a build made with the compile key (`scripts/test-gate-compiled.sh`, never in CI and
// never in a shipped build). They use a fake runner that answers read-only queries from canned plists and
// records everything else: no real disk is read or written.
#if SF_REAL_DISK_WRITES

final class FakeDisks: ToolRunner, @unchecked Sendable {
    var list: [String: Any]
    var infos: [String: [String: Any]]
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    init(list: [String: Any], infos: [String: [String: Any]]) { self.list = list; self.infos = infos }
    func run(_ argv: [String], stdin: Data?) throws -> ToolResult {
        lock.lock(); calls.append(argv); lock.unlock()
        func plist(_ d: [String: Any]) -> ToolResult { ToolResult(status: 0, stdout: try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)) }
        if argv == ["/usr/sbin/diskutil", "list", "-plist"] { return plist(list) }
        if argv.count == 4, argv[1] == "info", let d = infos[argv[3]] { return plist(d) }
        return ToolResult(status: 1, stderr: Data("unexpected: \(argv)".utf8))
    }
}

final class GateSwitch: @unchecked Sendable { var open = true }

@Suite("Internal-disk authority (compile key on, fake disks only)")
struct InternalDiskAuthorityTests {
    static let uuid = "11111111-2222-3333-4444-555555555555"
    static func world(targetInternal: Bool = true, duplicate: Bool = false) -> FakeDisks {
        var entries: [[String: Any]] = [["DeviceIdentifier": "disk0", "Content": "GUID_partition_scheme"], ["DeviceIdentifier": "disk4", "Content": "GUID_partition_scheme"]]
        var infos: [String: [String: Any]] = [
            "disk0": ["DiskUUID": uuid, "WholeDisk": true, "ParentWholeDisk": "disk0", "Internal": targetInternal, "VirtualOrPhysical": "Physical", "BusProtocol": "Apple Fabric"],
            "disk0s2": ["Internal": true, "BusProtocol": "Apple Fabric", "ParentWholeDisk": "disk0"],
            "disk4": ["DiskUUID": "99999999-0000-0000-0000-000000000000", "WholeDisk": true, "ParentWholeDisk": "disk4", "Internal": false, "VirtualOrPhysical": "Virtual", "BusProtocol": "Disk Image"],
            "disk4s1": ["Internal": false, "BusProtocol": "Disk Image", "ParentWholeDisk": "disk4"],
            "disk3": ["Internal": true, "BusProtocol": "Apple Fabric", "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]]],
            "disk6": ["Internal": false, "BusProtocol": "Disk Image", "APFSPhysicalStores": [["APFSPhysicalStore": "disk4s1"]]],
        ]
        if duplicate {
            entries.append(["DeviceIdentifier": "disk7", "Content": "GUID_partition_scheme"])
            infos["disk7"] = infos["disk0"]
        }
        return FakeDisks(list: ["AllDisksAndPartitions": entries], infos: infos)
    }
    static let open: @Sendable () -> Result<RealDiskGate.Authorization, RealDiskGate.Closed> = {
        .success(RealDiskGate.Authorization(planDigest: "P", diskUUID: uuid, notBefore: Date(), notAfter: Date().addingTimeInterval(60)))
    }

    @Test func theCompileKeyIsOnInThisBuildOnly() {
        #expect(RealDiskGate.compiledIn && LiveDiskBuild.realDiskAuthorityCompiledIn)
        // Compile key on, runtime key off: the real file doesn't exist here, so the gate stays closed.
        #expect((try? InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid, query: Self.world())) == nil)
    }

    @Test func aClosedRuntimeKeyRefusesToEvenConstruct() {
        for closed in [RealDiskGate.Closed.noAuthorization, .expired, .planMismatch, .diskMismatch, .notRoot] {
            #expect(throws: SafetyRefusal.self) { _ = try InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid, query: Self.world(), gate: { .failure(closed) }) }
        }
    }

    @Test func findsExactlyTheAuthorizedInternalDiskAndNothingElse() throws {
        let a = try InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid.lowercased(), query: Self.world(), gate: Self.open)
        #expect(try a.wholeDisk() == "disk0")
        try a.authorize("disk0s2"); try a.authorize("disk0"); try a.authorize("disk3")          // disk3: APFS volume disk synthesised from disk0s2
        #expect(throws: SafetyRefusal.self) { try a.authorize("disk4s1") }                       // a disk image
        #expect(throws: SafetyRefusal.self) { try a.authorize("disk6") }                         // synthesised from a disk image
        #expect(throws: SafetyRefusal.self) { try a.authorize("/dev/rdisk4") }
        #expect(throws: SafetyRefusal.self) { try a.authorize("not-a-disk") }
        // The authorized UUID on a disk that isn't internal and physical: refused, not "found".
        let ext = try InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid, query: Self.world(targetInternal: false), gate: Self.open)
        #expect(throws: SafetyRefusal.self) { try ext.wholeDisk() }
        // Two disks claiming the UUID: refused.
        let dup = try InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid, query: Self.world(duplicate: true), gate: Self.open)
        #expect(throws: SafetyRefusal.self) { try dup.wholeDisk() }
        // No such disk.
        let none = try InternalDiskAuthority(planDigest: "P", diskUUID: "00000000-0000-0000-0000-000000000000", query: Self.world(), gate: { .success(RealDiskGate.Authorization(planDigest: "P", diskUUID: "00000000-0000-0000-0000-000000000000", notBefore: Date(), notAfter: Date().addingTimeInterval(60))) })
        #expect(throws: SafetyRefusal.self) { try none.wholeDisk() }
        #expect(throws: SafetyRefusal.self) { try a.detach(force: true) }
        #expect(throws: SafetyRefusal.self) { try a.attach() }
    }

    @Test func anExpiringAuthorizationStopsAJobMidway() throws {
        let flag = GateSwitch()
        let a = try InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid, query: Self.world(), gate: { flag.open ? Self.open() : .failure(.expired) })
        try a.authorize("disk0s2")
        flag.open = false
        #expect(throws: SafetyRefusal.self) { try a.authorize("disk0s2") }
        #expect(throws: SafetyRefusal.self) { _ = try a.wholeDisk() }
    }

    @Test func theLiveBackendRunsNothingUntilArmedEvenWithTheGateOpen() throws {
        let rec = RecordingRunner()
        let world = Self.world()
        let a = try InternalDiskAuthority(planDigest: "P", diskUUID: Self.uuid, query: world, gate: Self.open)
        let live = LiveDiskBackend(authority: a, runner: rec)
        for argv in [["/usr/sbin/diskutil", "eraseVolume", "free", "none", "disk0s2"], ["/usr/sbin/diskutil", "apfs", "resizeContainer", "disk0s2", "100000000B"]] {
            #expect(throws: SafetyRefusal.self) { try live.chokepoint.run(argv) }
        }
        #expect(throws: SafetyRefusal.self) { _ = try live.chokepoint.openRaw("disk0s2", write: true) }
        #expect(rec.calls.isEmpty)
        #expect(throws: SafetyRefusal.self) { try live.detach(force: true) }
    }
}
#endif
